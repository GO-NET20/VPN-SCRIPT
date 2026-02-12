#!/bin/bash
# ==================================================
#  SSH MANAGER V81 (ACCURATE MONITOR) 💎
#  - FIX: Fixed Status Icons (🟢/🔴) in Bot
#  - LOGIC: Dual check method (Process name + User PID)
# ==================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- 1. OS DETECTION ---
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
#  CLI FUNCTIONS
# ==================================================

pause() { echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"; read; }

# --- CLI STATUS CHECKER ---
check_status_cli() {
    local u=$1
    # Check if locked
    if grep -q "^$u:!:" /etc/shadow || grep -q "^$u:*:" /etc/shadow; then
        echo -e "${RED}LOCKED${NC}"
        return
    fi
    # Check SSH (Greps for 'sshd: user' with word boundary or space to avoid partial match)
    if ps -ef | grep "sshd: $u" | grep -v grep > /dev/null 2>&1; then
        echo -e "${GREEN}ONLINE${NC}"
    elif pgrep -u "$u" > /dev/null 2>&1; then
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
    if [[ ! "$u" =~ ^[a-zA-Z0-9]+$ ]]; then echo -e "${RED}❌ INVALID!${NC}"; pause; return; fi
    if id "$u" &>/dev/null; then echo -e "${RED}❌ EXISTS!${NC}"; pause; return; fi
    read -p " 🔑 PASSWORD : " p
    read -p " 📅 SET EXPIRY? [y/n]: " ch
    if [[ "$ch" == "y" || "$ch" == "Y" ]]; then
        read -p " DATE (YYYY-MM-DD): " d
        read -p " TIME (HH:MM): " t; [[ -z "$t" ]] && t="00:00"
    else d="NEVER"; t="00:00"; fi
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    echo "$u|$d|$t|V81" >> "$USER_DB"
    echo -e "${GREEN}✅ SUCCESS${NC}"; pause
}

fun_list() {
    draw_header
    echo -e "                ${WHITE}USER LIST${NC}"
    echo -e "${CYAN}==================================================${NC}"
    printf "${PURPLE}%-12s | %-12s | %-8s${NC}\n" "USER" "DATE" "STATUS"
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
    echo -e "                ${WHITE}MONITOR${NC}"
    echo -e "${CYAN}==================================================${NC}"
    count=0
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        # CLI Monitor Logic
        if ps -ef | grep "sshd: $u" | grep -v grep > /dev/null 2>&1 || pgrep -u "$u" >/dev/null 2>&1; then
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
    echo -e " ${GREEN}[01]${NC} UPDATE BOT (V81)"
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
#  🤖 BOT INSTALLER (V81 - ACCURATE ICONS)
# ==================================================
fun_install_bot() {
    pkill -f ssh_bot.py
    systemctl stop sshbot >/dev/null 2>&1

    clear; echo -e "${YELLOW}INSTALLING BOT V81 (ACCURATE MODE)...${NC}"
    echo "BOT_TOKEN=\"$MY_TOKEN\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$MY_ID\"" >> "$BOT_CONF"
    chmod 600 "$BOT_CONF"
    
    # Install dependencies
    eval "$CMD python3 python3-pip" >/dev/null 2>&1
    pip3 install python-telegram-bot==13.7 schedule --break-system-packages --force-reinstall >/dev/null 2>&1
    
    # Systemd Service
    cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Bot V81
After=network.target network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
RestartSec=5
StartLimitInterval=0
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Python Bot Script
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, time, re
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    filename='/var/log/ssh_bot.log'
)

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
        # 1. Check Locked (Shadow File)
        shadow_cmd = f"grep '^{u}:' /etc/shadow"
        shadow = subprocess.getoutput(shadow_cmd)
        if "!" in shadow.split(":")[1] or "*" in shadow.split(":")[1]:
            return "⛔" # Locked

        # 2. Check Connection (Dual Method)
        # Method A: Check for sshd process with username
        cmd_ps = f"ps -ef | grep 'sshd: {u}' | grep -v grep"
        out_ps = subprocess.getoutput(cmd_ps)
        
        # Method B: Check for any process owned by user (fallback)
        cmd_pgrep = f"pgrep -u {u}"
        out_pgrep = subprocess.getoutput(cmd_pgrep)

        if out_ps or out_pgrep:
            return "🟢" # Connected
            
    except Exception as e:
        logging.error(f"Status Check Error: {e}")
        
    return "🔴" # Disconnected

def get_back_btn():
    return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]])

def get_main_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 ADD USER", callback_data='add')],
        [InlineKeyboardButton("🔄 RENEW", callback_data='ren'), InlineKeyboardButton("🗑️ REMOVE", callback_data='del')],
        [InlineKeyboardButton("🔒 LOCK / UNLOCK", callback_data='lock')],
        [InlineKeyboardButton("📋 ALL USERS", callback_data='list'), InlineKeyboardButton("🟢 MONITOR", callback_data='onl')],
        [InlineKeyboardButton("💾 SAVE DATA", callback_data='bak')],
        [InlineKeyboardButton("⚙️ SETTINGS", callback_data='set')]
    ])

def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    try: update.message.reply_text("⚡ *SSH MANAGER V81*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_menu())
    except: pass

def btn(update: Update, context: CallbackContext):
    q = update.callback_query; 
    try: q.answer()
    except: pass
    data = q.data
    
    if data == 'back': 
        context.user_data.clear()
        q.edit_message_text("⚡ *SSH MANAGER V81*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_menu())
        return

    try:
        if data == 'add': 
            context.user_data['act']='a1'
            q.edit_message_text("👤 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'ren': 
            context.user_data['act']='r1'
            q.edit_message_text("🔄 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'del': 
            context.user_data['act']='d1'
            q.edit_message_text("🗑️ *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'del_yes':
            u = context.user_data.get('del_u')
            subprocess.run(f"pkill -u {u}", shell=True); subprocess.run(f"userdel -f -r {u}", shell=True)
            lines = [l for l in open(DB_FILE) if not l.startswith(f"{u}|")]
            with open(DB_FILE, 'w') as f: f.writelines(lines)
            q.edit_message_text(f"✅ *USER {u} DELETED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'lock': 
            context.user_data['act']='l1'
            q.edit_message_text("🔒 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'do_lock':
            u = context.user_data.get('lock_u'); subprocess.run(f"usermod -L {u}", shell=True); subprocess.run(f"pkill -KILL -u {u}", shell=True)
            q.edit_message_text(f"⛔ *USER {u} LOCKED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'do_unlock':
            u = context.user_data.get('lock_u'); subprocess.run(f"usermod -U {u}", shell=True)
            q.edit_message_text(f"🟢 *USER {u} UNLOCKED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'list':
            header = "➖➖➖➖➖➖➖➖➖➖➖➖\n       ALL USERS LIST\n➖➖➖➖➖➖➖➖➖➖➖➖\n"; body = ""
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        p = l.split('|')
                        if len(p)<2: continue
                        u=p[0][:10]; d=p[1]; st=get_status(p[0]); exp="No Expiry" if d=="NEVER" else d
                        body += f"{u:<10} | {st} | {exp}\n"
            msg = header + f"```\n{body}```" + "➖➖➖➖➖➖➖➖➖➖➖➖"
            q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'onl':
            header = "➖➖➖➖➖➖➖➖➖➖➖➖\n       ONLINE MONITOR\n➖➖➖➖➖➖➖➖➖➖➖➖\n"; body = ""
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        u=l.split('|')[0]; st=get_status(u)
                        if st == "🟢":
                            body += f"{u:<10} :    {st}\n"
            if body == "": body = "🔴 NO USERS ONLINE"
            msg = header + f"```\n{body}```" + "➖➖➖➖➖➖➖➖➖➖➖➖"
            q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'bak':
            if os.path.exists(DB_FILE): context.bot.send_document(chat_id=ADMIN_ID, document=open(DB_FILE, 'rb'))
            q.edit_message_text("✅ *SAVED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'set': 
            q.edit_message_text("⚙️ *SETTINGS*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("UPDATE BOT", callback_data='ins'), InlineKeyboardButton("FIX TIMEZONE", callback_data='tz')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]]))
        elif data == 'tz': 
            subprocess.run("timedatectl set-timezone Africa/Tunis", shell=True)
            q.edit_message_text("🌍 DONE", reply_markup=get_back_btn())
        elif data == 'exp_yes': 
            context.user_data['act']='a_date'
            q.edit_message_text("📅 *DATE (YYYY-MM-DD):*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'exp_no': 
            create_user_final(update, context, "NEVER", "00:00")
    except Exception as e: logging.error(f"Btn error: {e}")

def create_user_final(update, context, d, t):
    try:
        u = context.user_data.get('nu'); p = context.user_data.get('np')
        if subprocess.run(f"useradd -M -s /bin/false {u}", shell=True).returncode == 0:
            subprocess.run(f"echo '{u}:{p}' | chpasswd", shell=True)
            with open(DB_FILE, 'a') as f: f.write(f"{u}|{d}|{t}|Bot\n")
            if d == "NEVER":
                msg = f"━━━━━━━━━━━━━━━━━━━━━━━━━━━\n🆕 NEW ACCOUNT \n━━━━━━━━━━━━━━━━━━━━━━━━━━━\n👤 User : `{u}`\n🔐 Pass : `{p}`\n📅 Date : Unlimited\n━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📋 `{u}:{p}`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            else:
                msg = f"━━━━━━━━━━━━━━━━━━━━━━━━━━━\n🆕 NEW ACCOUNT \n━━━━━━━━━━━━━━━━━━━━━━━━━━━\n👤 User : `{u}`\n🔐 Pass : `{p}`\n📅 Date : {d}\n⏰ Time : {t}\n━━━━━━━━━━━━━━━━━━━━━━━━━━━\n📋 `{u}:{p}`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            
            kb = get_back_btn()
            if update.callback_query: update.callback_query.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=kb)
            else: update.message.reply_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=kb)
    except Exception as e: logging.error(f"Create error: {e}")

def txt(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    msg = update.message.text
    act = context.user_data.get('act')
    try:
        if act == 'a1': 
            context.user_data.update({'nu':msg,'act':'a2'})
            update.message.reply_text("🔑 *ENTER PASSWORD:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif act == 'a2': 
            context.user_data.update({'np':msg})
            kb = [[InlineKeyboardButton("🟢 YES", callback_data='exp_yes'), InlineKeyboardButton("🔴 NO", callback_data='exp_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]]
            update.message.reply_text("📅 *SET EXPIRY?*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
        elif act == 'a_date': 
            context.user_data.update({'nd':msg,'act':'a_time'})
            update.message.reply_text("⏰ *TIME (HH:MM):*", reply_markup=get_back_btn())
        elif act == 'a_time': 
            create_user_final(update, context, context.user_data['nd'], msg)
        elif act == 'r1': 
            context.user_data.update({'ru':msg,'act':'r2'})
            update.message.reply_text("📅 *NEW DATE:*", reply_markup=get_back_btn())
        elif act == 'r2': 
            context.user_data.update({'rd':msg,'act':'r3'})
            update.message.reply_text("⏰ *NEW TIME:*", reply_markup=get_back_btn())
        elif act == 'r3':
            u=context.user_data['ru']; lines=[l for l in open(DB_FILE) if not l.startswith(f"{u}|")]; lines.append(f"{u}|{context.user_data['rd']}|{msg}|Renew\n")
            with open(DB_FILE, 'w') as f: f.writelines(lines)
            update.message.reply_text("✅ RENEWED!", reply_markup=get_back_btn())
        elif act == 'd1': 
            context.user_data['del_u']=msg
            kb=[[InlineKeyboardButton("🗑️ YES, DELETE", callback_data='del_yes'), InlineKeyboardButton("🔙 CANCEL", callback_data='back')]]
            update.message.reply_text(f"⚠️ *DELETE {msg}?*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
        elif act == 'l1': 
            context.user_data['lock_u']=msg
            kb=[[InlineKeyboardButton("🔒 LOCK", callback_data='do_lock'), InlineKeyboardButton("🔓 UNLOCK", callback_data='do_unlock')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]]
            update.message.reply_text(f"⚙️ *MANAGE {msg}*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
    except Exception as e: logging.error(f"Txt error: {e}")

def main():
    up = Updater(TOKEN, use_context=True, request_kwargs={'read_timeout': 10, 'connect_timeout': 10})
    dp = up.dispatcher
    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CallbackQueryHandler(btn))
    dp.add_handler(MessageHandler(Filters.text, txt))
    
    while True:
        try:
            up.start_polling()
            up.idle()
        except Exception as e:
            logging.error(f"Crash: {e}")
            time.sleep(5)

if __name__ == '__main__': main()
EOF
    systemctl daemon-reload; systemctl enable sshbot; systemctl start sshbot
    echo -e "${GREEN}✅ BOT V81 INSTALLED!${NC}"; pause
}

# --- MAIN LOOP ---
while true; do
    draw_header
    echo -e " ${GREEN}[01]${NC} 👤 ADD ACCOUNT"
    echo -e " ${GREEN}[02]${NC} 🔄 RENEW ACCOUNT"
    echo -e " ${GREEN}[03]${NC} 🗑️ REMOVE ACCOUNT"
    echo -e " ${GREEN}[04]${NC} 🔐 LOCK ACCOUNT"
    echo -e " ${GREEN}[05]${NC} 📋 LIST ACCOUNTS"
    echo -e " ${GREEN}[06]${NC} 🟢 CHECK STATUS"
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
