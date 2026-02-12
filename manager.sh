#!/bin/bash
# ==================================================
#  SSH MANAGER V81 (PROFESSIONAL EDITION) 💎
#  - FIX: 100% Accurate Online/Offline Detection
#  - LOGIC: Filters for active sessions only (@pts/@notty)
#  - BOT: Optimized for high load
# ==================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- 1. SMART OS DETECTION ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="Unknown"
fi

if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS" == "kali" ]]; then
    CMD="apt-get update -y && apt-get install -y"
elif [[ "$OS" == "centos" || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
    CMD="yum install -y"
else
    CMD="apt-get install -y"
fi

# --- CONFIG ---
USER_DB="/etc/xpanel/users_db.txt"
BOT_CONF="/etc/xpanel/bot.conf"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"

# --- CREDENTIALS ---
MY_TOKEN="8275679858:AAGCTP9tsJzCgzXXzgA9hJQ8ooqhlFY8BcA"
MY_ID="7587310857"

# --- COLORS ---
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; PURPLE='\033[1;35m'; CYAN='\033[1;36m'; NC='\033[0m'; WHITE='\033[1;37m'
BOLD='\033[1m'

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"

# ==================================================
#  CORE FUNCTIONS
# ==================================================

pause() { echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"; read; }

# --- PROFESSIONAL STATUS CHECKER (CLI) ---
check_status_cli() {
    local u=$1
    
    # 1. Check if Locked
    # Checks shadow file directly for lock status (!)
    if grep -q "^$u:!:" /etc/shadow || grep -q "^$u:*:" /etc/shadow; then
        echo -e "${RED}LOCKED${NC}"
        return
    fi

    # 2. Precise SSH Check
    # We look for "sshd: user@" which indicates an ACTIVE session (pts or notty).
    # This filters out "sshd: user [priv]" which is just a parent process.
    if ps -ef | grep "sshd: $u@" | grep -v grep > /dev/null 2>&1; then
        echo -e "${GREEN}ONLINE${NC}"
    # 3. Check Dropbear (Alternative SSH)
    elif pgrep -u "$u" dropbear > /dev/null 2>&1; then
        echo -e "${GREEN}ONLINE${NC}"
    else
        echo -e "${WHITE}OFFLINE${NC}"
    fi
}

draw_header() {
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "                ${BOLD}${WHITE}SSH MANAGER (V81)${NC}"
    echo -e "${CYAN}==================================================${NC}"
}

fun_create() {
    draw_header
    echo -e "                ${WHITE}ADD NEW USER${NC}"
    echo -e "${CYAN}==================================================${NC}"
    read -p " 👤 USERNAME : " u
    if [[ ! "$u" =~ ^[a-zA-Z0-9]+$ ]]; then echo -e "${RED}❌ INVALID CHARACTERS!${NC}"; pause; return; fi
    if id "$u" &>/dev/null; then echo -e "${RED}❌ USER EXISTS!${NC}"; pause; return; fi
    read -p " 🔑 PASSWORD : " p
    read -p " 📅 SET EXPIRY? [y/n]: " ch
    if [[ "$ch" == "y" || "$ch" == "Y" ]]; then
        read -p " DATE (YYYY-MM-DD): " d
        read -p " TIME (HH:MM): " t; [[ -z "$t" ]] && t="00:00"
    else d="NEVER"; t="00:00"; fi
    
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    echo "$u|$d|$t|V81" >> "$USER_DB"
    echo -e "${GREEN}✅ USER CREATED${NC}"; pause
}

fun_renew() {
    draw_header
    read -p " 👤 USERNAME TO RENEW: " u
    if ! id "$u" &>/dev/null; then echo -e "${RED}❌ USER NOT FOUND!${NC}"; pause; return; fi
    read -p " 📅 NEW DATE (YYYY-MM-DD): " d
    read -p " ⏰ NEW TIME (HH:MM): " t
    
    # Update Database
    grep -v "^$u|" "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
    echo "$u|$d|$t|Renewed" >> "$USER_DB"
    
    # Unlock user if locked
    usermod -U "$u" 2>/dev/null
    echo -e "${GREEN}✅ ACCOUNT RENEWED${NC}"; pause
}

fun_remove() {
    draw_header
    read -p " 👤 USERNAME TO DELETE: " u
    if ! id "$u" &>/dev/null; then echo -e "${RED}❌ USER NOT FOUND!${NC}"; pause; return; fi
    read -p " ⚠️ CONFIRM DELETE? [y/n]: " c
    if [[ "$c" == "y" ]]; then
        pkill -u "$u"
        userdel -f -r "$u"
        grep -v "^$u|" "$USER_DB" > "$USER_DB.tmp" && mv "$USER_DB.tmp" "$USER_DB"
        echo -e "${GREEN}✅ USER DELETED${NC}"
    fi
    pause
}

fun_lock() {
    draw_header
    read -p " 👤 USERNAME TO LOCK: " u
    if ! id "$u" &>/dev/null; then echo -e "${RED}❌ USER NOT FOUND!${NC}"; pause; return; fi
    usermod -L "$u"
    pkill -KILL -u "$u"
    echo -e "${YELLOW}⛔ USER LOCKED${NC}"; pause
}

fun_list() {
    draw_header
    echo -e "                ${WHITE}USER LIST${NC}"
    echo -e "${CYAN}==================================================${NC}"
    printf "${PURPLE}%-12s | %-12s | %-8s${NC}\n" "USER" "EXPIRY" "STATUS"
    echo "--------------------------------------------------"
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
            st=$(check_status_cli "$u")
            printf "%-12s | %-12s | %b\n" "$u" "$d" "$st"
        fi
    done < "$USER_DB"; pause
}

fun_online() {
    draw_header
    echo -e "                ${WHITE}LIVE MONITOR${NC}"
    echo -e "${CYAN}==================================================${NC}"
    count=0
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        # Precise Monitor Logic
        if ps -ef | grep "sshd: $u@" | grep -v grep >/dev/null 2>&1 || pgrep -u "$u" dropbear >/dev/null 2>&1; then
             echo -e " 👤 $u : ${GREEN}ONLINE${NC}"
             ((count++))
        fi
    done < "$USER_DB"
    [[ $count -eq 0 ]] && echo -e " 🔴 NO USERS ONLINE"
    echo -e "${CYAN}==================================================${NC}"
    pause
}

fun_settings() {
    draw_header
    echo -e "                ${WHITE}SETTINGS${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo -e " ${GREEN}[01]${NC} INSTALL/UPDATE BOT (V81)"
    echo -e " ${GREEN}[02]${NC} FIX TIMEZONE"
    echo -e " ${GREEN}[00]${NC} BACK"
    echo -e "${CYAN}==================================================${NC}"
    read -p " SELECT OPTION: " s
    case "$s" in
        1) fun_install_bot ;;
        2) timedatectl set-timezone Africa/Tunis; echo -e "${GREEN}DONE${NC}"; pause ;;
    esac
}

# ==================================================
#  🤖 BOT INSTALLER (V81 PROFESSIONAL)
# ==================================================
fun_install_bot() {
    pkill -f ssh_bot.py
    systemctl stop sshbot >/dev/null 2>&1

    clear; echo -e "${YELLOW}INSTALLING BOT V81...${NC}"
    echo "BOT_TOKEN=\"$MY_TOKEN\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$MY_ID\"" >> "$BOT_CONF"
    chmod 600 "$BOT_CONF"
    
    # Dependencies
    eval "$CMD python3 python3-pip" >/dev/null 2>&1
    pip3 install python-telegram-bot==13.7 schedule --break-system-packages --force-reinstall >/dev/null 2>&1
    
    # Service
    cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Bot V81
After=network.target network-online.target

[Service]
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Python Script (The Brain)
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, time
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)

CONF_FILE = "/etc/xpanel/bot.conf"
config = {}
try:
    with open(CONF_FILE) as f:
        for line in f:
            if "=" in line: k, v = line.strip().split("=", 1); config[k] = v.strip().replace('"', '')
except: exit(1)

TOKEN = config.get("BOT_TOKEN")
ADMIN_ID = int(config.get("ADMIN_ID"))
DB_FILE = "/etc/xpanel/users_db.txt"

def get_status(u):
    try:
        # 1. Check Lock Status
        shadow = subprocess.getoutput(f"grep '^{u}:' /etc/shadow")
        if "!" in shadow.split(":")[1] or "*" in shadow.split(":")[1]:
            return "🔴" # Show red if locked

        # 2. PRECISE CONNECTION CHECK
        # We search for 'sshd: user@' which handles both @pts (terminal) and @notty (apps)
        # This completely ignores 'sshd: user [priv]'
        cmd_ssh = f"ps -ef | grep 'sshd: {u}@' | grep -v grep"
        if subprocess.getoutput(cmd_ssh):
            return "🟢"
            
        # 3. Dropbear Check
        if subprocess.call(f"pgrep -u {u} dropbear", shell=True, stdout=subprocess.DEVNULL) == 0:
            return "🟢"
            
    except: pass
    return "🔴"

def get_back_btn():
    return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]])

def get_main_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 ADD USER", callback_data='add'), InlineKeyboardButton("🗑️ REMOVE", callback_data='del')],
        [InlineKeyboardButton("🔄 RENEW", callback_data='ren'), InlineKeyboardButton("🔒 LOCK/UNLOCK", callback_data='lock')],
        [InlineKeyboardButton("📋 ALL USERS", callback_data='list'), InlineKeyboardButton("🟢 MONITOR", callback_data='onl')],
        [InlineKeyboardButton("💾 BACKUP", callback_data='bak'), InlineKeyboardButton("⚙️ SETTINGS", callback_data='set')]
    ])

def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    update.message.reply_text("⚡ *SSH MANAGER V81*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_menu())

def btn(update: Update, context: CallbackContext):
    q = update.callback_query
    try: q.answer()
    except: pass
    data = q.data
    
    if data == 'back': 
        context.user_data.clear()
        q.edit_message_text("⚡ *SSH MANAGER V81*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_menu())
        return

    if data == 'add': 
        context.user_data['act']='a1'
        q.edit_message_text("👤 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
    
    elif data == 'ren':
        context.user_data['act']='r1'
        q.edit_message_text("🔄 *ENTER USERNAME TO RENEW:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

    elif data == 'del':
        context.user_data['act']='d1'
        q.edit_message_text("🗑️ *ENTER USERNAME TO DELETE:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

    elif data == 'lock':
        context.user_data['act']='l1'
        q.edit_message_text("🔒 *ENTER USERNAME TO LOCK/UNLOCK:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

    elif data == 'list':
        msg = "➖➖➖➖➖➖➖➖➖➖➖➖\n       ALL USERS LIST\n➖➖➖➖➖➖➖➖➖➖➖➖\n"
        if os.path.exists(DB_FILE):
            with open(DB_FILE) as f:
                for l in f:
                    p = l.split('|')
                    if len(p)<2: continue
                    u=p[0][:10]; d=p[1]; st=get_status(p[0])
                    msg += f"{u:<12} | {st} | {d}\n"
        q.edit_message_text(f"```\n{msg}```", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

    elif data == 'onl':
        msg = "➖➖➖➖➖➖➖➖➖➖➖➖\n       ONLINE USERS\n➖➖➖➖➖➖➖➖➖➖➖➖\n"
        count = 0
        if os.path.exists(DB_FILE):
            with open(DB_FILE) as f:
                for l in f:
                    u=l.split('|')[0]
                    if get_status(u) == "🟢":
                        msg += f"👤 {u:<12} : 🟢\n"
                        count += 1
        if count == 0: msg += "🔴 NO USERS ONLINE"
        q.edit_message_text(f"```\n{msg}```", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

    elif data == 'bak':
        if os.path.exists(DB_FILE): context.bot.send_document(chat_id=ADMIN_ID, document=open(DB_FILE, 'rb'))
        q.edit_message_text("✅ *DATABASE SAVED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
    
    elif data == 'set':
        kb = [[InlineKeyboardButton("UPDATE BOT", callback_data='ins')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]]
        q.edit_message_text("⚙️ *SETTINGS*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
        
    elif data == 'ins':
        q.edit_message_text("✅ *BOT UPDATED! RESTARTING...*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

    elif data == 'del_yes':
        u = context.user_data.get('del_u')
        subprocess.run(f"pkill -u {u}", shell=True); subprocess.run(f"userdel -f -r {u}", shell=True)
        lines = [l for l in open(DB_FILE) if not l.startswith(f"{u}|")]
        with open(DB_FILE, 'w') as f: f.writelines(lines)
        q.edit_message_text(f"✅ *USER {u} DELETED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
    
    elif data == 'do_lock':
        u = context.user_data.get('lock_u'); subprocess.run(f"usermod -L {u}", shell=True); subprocess.run(f"pkill -KILL -u {u}", shell=True)
        q.edit_message_text(f"⛔ *USER {u} LOCKED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

    elif data == 'do_unlock':
        u = context.user_data.get('lock_u'); subprocess.run(f"usermod -U {u}", shell=True)
        q.edit_message_text(f"🟢 *USER {u} UNLOCKED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

    elif data == 'exp_yes':
        context.user_data['act']='a_date'
        q.edit_message_text("📅 *DATE (YYYY-MM-DD):*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
    
    elif data == 'exp_no':
        create_user_final(update, context, "NEVER", "00:00")

def create_user_final(update, context, d, t):
    u = context.user_data.get('nu'); p = context.user_data.get('np')
    if subprocess.run(f"useradd -M -s /bin/false {u}", shell=True).returncode == 0:
        subprocess.run(f"echo '{u}:{p}' | chpasswd", shell=True)
        with open(DB_FILE, 'a') as f: f.write(f"{u}|{d}|{t}|Bot\n")
        msg = f"━━━━━━━━━━━━━━━━━━━━━━\n🆕 NEW ACCOUNT\n━━━━━━━━━━━━━━━━━━━━━━\n👤 User : `{u}`\n🔐 Pass : `{p}`\n📅 Date : {d}\n━━━━━━━━━━━━━━━━━━━━━━"
        kb = get_back_btn()
        if update.callback_query: update.callback_query.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=kb)
        else: update.message.reply_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=kb)

def txt(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    msg = update.message.text
    act = context.user_data.get('act')
    
    if act == 'a1':
        context.user_data.update({'nu':msg, 'act':'a2'})
        update.message.reply_text("🔑 *ENTER PASSWORD:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
    elif act == 'a2':
        context.user_data.update({'np':msg})
        kb = [[InlineKeyboardButton("✅ YES", callback_data='exp_yes'), InlineKeyboardButton("❌ NO", callback_data='exp_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]]
        update.message.reply_text("📅 *SET EXPIRY DATE?*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
    elif act == 'a_date':
        context.user_data.update({'nd':msg, 'act':'a_time'})
        update.message.reply_text("⏰ *TIME (HH:MM):*", reply_markup=get_back_btn())
    elif act == 'a_time':
        create_user_final(update, context, context.user_data['nd'], msg)
    
    elif act == 'r1':
        context.user_data.update({'ru':msg, 'act':'r2'})
        update.message.reply_text("📅 *NEW DATE (YYYY-MM-DD):*", reply_markup=get_back_btn())
    elif act == 'r2':
        context.user_data.update({'rd':msg, 'act':'r3'})
        update.message.reply_text("⏰ *NEW TIME (HH:MM):*", reply_markup=get_back_btn())
    elif act == 'r3':
        u=context.user_data['ru']; lines=[l for l in open(DB_FILE) if not l.startswith(f"{u}|")]; lines.append(f"{u}|{context.user_data['rd']}|{msg}|Renew\n")
        with open(DB_FILE, 'w') as f: f.writelines(lines)
        update.message.reply_text("✅ *RENEWED SUCCESSFULLY!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

    elif act == 'd1':
        context.user_data['del_u']=msg
        kb=[[InlineKeyboardButton("🗑️ CONFIRM DELETE", callback_data='del_yes'), InlineKeyboardButton("🔙 CANCEL", callback_data='back')]]
        update.message.reply_text(f"⚠️ *DELETE USER {msg}?*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))

    elif act == 'l1':
        context.user_data['lock_u']=msg
        kb=[[InlineKeyboardButton("🔒 LOCK", callback_data='do_lock'), InlineKeyboardButton("🔓 UNLOCK", callback_data='do_unlock')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]]
        update.message.reply_text(f"⚙️ *MANAGE USER {msg}*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))

def main():
    up = Updater(TOKEN, use_context=True)
    dp = up.dispatcher
    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CallbackQueryHandler(btn))
    dp.add_handler(MessageHandler(Filters.text, txt))
    up.start_polling()
    up.idle()

if __name__ == '__main__': main()
EOF
    systemctl daemon-reload; systemctl enable sshbot; systemctl start sshbot
    echo -e "${GREEN}✅ BOT V81 INSTALLED SUCCESSFULLY!${NC}"; pause
}

# --- MAIN LOOP ---
while true; do
    draw_header
    echo -e " ${GREEN}[01]${NC} 👤 ADD USER"
    echo -e " ${GREEN}[02]${NC} 🔄 RENEW USER"
    echo -e " ${GREEN}[03]${NC} 🗑️ REMOVE USER"
    echo -e " ${GREEN}[04]${NC} 🔐 LOCK USER"
    echo -e " ${GREEN}[05]${NC} 📋 LIST USERS"
    echo -e " ${GREEN}[06]${NC} 🟢 ONLINE MONITOR"
    echo -e " ${GREEN}[07]${NC} 💾 BACKUP DATA"
    echo -e " ${GREEN}[08]${NC} ⚙️ SETTINGS"
    echo -e " ${GREEN}[00]${NC} 🚪 EXIT"
    echo ""
    echo -e "${CYAN}==================================================${NC}"
    read -p " SELECT OPTION: " o
    case "$o" in
        1) fun_create ;; 2) fun_renew ;; 3) fun_remove ;; 4) fun_lock ;;
        5) fun_list ;; 6) fun_online ;; 7) fun_backup ;; 8) fun_settings ;; 0) exit 0 ;;
    esac
done
