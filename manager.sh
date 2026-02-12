#!/bin/bash
# ==================================================
#  SSH MANAGER V72 (EXACT DESIGN) 🎨
#  - UI: Exact match to your requested layout ✅
#  - LOGIC: Auto-hides Time if Unlimited ✅
#  - COPY: User, Pass, and Combo are copyable ✅
# ==================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- 1. SMART OS DETECTION ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "❌ UNSUPPORTED OS"; exit 1
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

# --- CREDENTIALS (AUTO) ---
MY_TOKEN="8275679858:AAGCTP9tsJzCgzXXzgA9hJQ8ooqhlFY8BcA"
MY_ID="7587310857"

# --- COLORS ---
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; PURPLE='\033[1;35m'; CYAN='\033[1;36m'; NC='\033[0m'

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"

# ==================================================
#  🚫 CLEANUP
# ==================================================
pkill -f ssh_bot.py
systemctl stop sshbot >/dev/null 2>&1
rm -f /etc/systemd/system/sshbot.service

# ==================================================
#  CLI FUNCTIONS
# ==================================================

pause() { echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"; read; }

check_status_cli() {
    local u=$1
    if passwd -S "$u" 2>/dev/null | grep -q " L "; then echo -e "⛔"
    elif w -h | grep -q "^$u "; then echo -e "🟢"
    else echo -e "🔴"
    fi
}

fun_create() {
    clear; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}           👤 ADD NEW USER                ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p " 👤 USERNAME : " u
    if [[ ! "$u" =~ ^[a-zA-Z0-9]+$ ]]; then echo -e "${RED}❌ INVALID CHARS!${NC}"; pause; return; fi
    if id "$u" &>/dev/null; then echo -e "${RED}❌ EXISTS!${NC}"; pause; return; fi
    read -p " 🔑 PASSWORD : " p
    read -p " 📅 SET EXPIRY? [y/n]: " ch
    if [[ "$ch" == "y" || "$ch" == "Y" ]]; then
        read -p " DATE (YYYY-MM-DD): " d
        read -p " TIME (HH:MM): " t; [[ -z "$t" ]] && t="00:00"
    else d="NEVER"; t="00:00"; fi
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    echo "$u|$d|$t|V72" >> "$USER_DB"
    clear; echo -e "${GREEN}✅ CREATED SUCCESSFULLY${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " User : $u"
    echo " Pass : $p"
    echo " Date : $d"
    echo " Time : $t"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$u:$p"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; pause
}

fun_renew() {
    clear; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}           🔄 RENEW USER                  ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p " 👤 ENTER USERNAME: " u
    if ! id "$u" &>/dev/null; then echo -e "${RED}❌ USER NOT FOUND!${NC}"; pause; return; fi
    
    read -p " 📅 NEW DATE (YYYY-MM-DD): " d
    read -p " ⏰ NEW TIME (HH:MM): " t
    [[ -z "$t" ]] && t="00:00"
    
    usermod -U "$u"
    grep -v "^$u|" "$USER_DB" > "${USER_DB}.tmp" && mv "${USER_DB}.tmp" "$USER_DB"
    echo "$u|$d|$t|Renew" >> "$USER_DB"
    echo -e "${GREEN}✅ RENEWED SUCCESSFULLY!${NC}"; pause
}

fun_remove() {
    clear; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}           🗑️ REMOVE USER                 ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p " 👤 ENTER USERNAME: " u
    if ! id "$u" &>/dev/null; then echo -e "${RED}❌ USER NOT FOUND!${NC}"; pause; return; fi
    echo -e "${YELLOW}⚠️ ARE YOU SURE? [y/n]${NC}"; read -p " > " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        pkill -u "$u"; userdel -f -r "$u"
        grep -v "^$u|" "$USER_DB" > "${USER_DB}.tmp" && mv "${USER_DB}.tmp" "$USER_DB"
        echo -e "${GREEN}✅ DELETED!${NC}"
    else echo -e "${RED}❌ CANCELLED${NC}"; fi; pause
}

fun_lock() {
    clear; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}          🔒 LOCK / UNLOCK USER           ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p " 👤 ENTER USERNAME: " u
    if ! id "$u" &>/dev/null; then echo -e "${RED}❌ USER NOT FOUND!${NC}"; pause; return; fi
    echo ""; echo -e " [1] 🔒 LOCK USER"; echo -e " [2] 🔓 UNLOCK USER"; echo ""; read -p " SELECT: " op
    if [[ "$op" == "1" ]]; then usermod -L "$u"; pkill -KILL -u "$u"; echo -e "${RED}⛔ LOCKED!${NC}"; 
    elif [[ "$op" == "2" ]]; then usermod -U "$u"; echo -e "${GREEN}🟢 UNLOCKED!${NC}"; 
    else echo "❌ INVALID"; fi; pause
}

fun_list() {
    clear; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}              📋 USER LIST                ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "${PURPLE}%-12s | %-12s | %-5s${NC}\n" "USER" "DATE" "ST"
    echo "------------------------------------------"
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        st=$(check_status_cli "$u"); printf "%-12s | %-12s | %b\n" "$u" "$d" "$st"
    done < "$USER_DB"; pause
}

fun_settings() {
    clear; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}             ⚙️ SETTINGS MENU             ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " SYSTEM: ${GREEN}$OS${NC}"
    echo "------------------------------------------"
    echo " [1] 🔄 UPDATE / REINSTALL BOT"
    echo " [2] 🌍 FIX TIMEZONE"
    echo " [0] 🔙 BACK"
    echo "------------------------------------------"
    read -p " OPTION: " s
    case "$s" in
        1) fun_install_bot ;;
        2) timedatectl set-timezone Africa/Tunis; echo -e "${GREEN}✅ DONE${NC}"; pause ;;
        *) return ;;
    esac
}

# ==================================================
#  🤖 BOT INSTALLER (V72)
# ==================================================
fun_install_bot() {
    clear; echo -e "${YELLOW}INSTALLING BOT V72 (EXACT DESIGN)...${NC}"
    
    echo "BOT_TOKEN=\"$MY_TOKEN\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$MY_ID\"" >> "$BOT_CONF"
    chmod 600 "$BOT_CONF"

    # Install Libs
    eval "$CMD python3 python3-pip" >/dev/null 2>&1
    if pip3 install python-telegram-bot==13.15 schedule >/dev/null 2>&1; then
        echo -e "${GREEN}✔ Libs Installed.${NC}"
    else
        echo -e "${YELLOW}⚠ Force Installing...${NC}"
        pip3 install python-telegram-bot==13.15 schedule --break-system-packages --force-reinstall >/dev/null 2>&1
    fi

    # Create Service
    cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Bot V72
After=network.target
[Service]
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

    # Bot Code
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, re
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(level=logging.INFO)

CONF_FILE = "/etc/xpanel/bot.conf"
config = {}
try:
    with open(CONF_FILE) as f:
        for line in f:
            if "=" in line: k, v = line.strip().split("=", 1); config[k] = v.strip().replace('"', '')
except: exit(1)

TOKEN = config.get("BOT_TOKEN")
try: ADMIN_ID = int(config.get("ADMIN_ID"))
except: ADMIN_ID = 0
DB_FILE = "/etc/xpanel/users_db.txt"

def get_status(u):
    try:
        cmd = f"ps -ef | grep 'sshd: {u}' | grep -v grep"
        out = subprocess.getoutput(cmd)
        if out and "sshd:" in out: return "🟢"
        if subprocess.getoutput(f"pgrep -u {u} dropbear"): return "🟢"
        if " L " in subprocess.getoutput(f"passwd -S {u}"): return "⛔"
    except: pass
    return "🔴"

def get_main_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 ADD USER", callback_data='add')],
        [InlineKeyboardButton("🔄 RENEW", callback_data='ren'), InlineKeyboardButton("🗑️ REMOVE", callback_data='del')],
        [InlineKeyboardButton("🔒 LOCK / UNLOCK", callback_data='lock')],
        [InlineKeyboardButton("📋 ALL USERS", callback_data='list'), InlineKeyboardButton("🟢 MONITOR", callback_data='onl')],
        [InlineKeyboardButton("💾 BACKUP", callback_data='bak')],
        [InlineKeyboardButton("⚙️ SETTINGS", callback_data='set')]
    ])

def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    update.message.reply_text("⚡ *SSH MANAGER V72*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_menu())

def btn(update: Update, context: CallbackContext):
    query = update.callback_query
    query.answer()
    data = query.data
    
    try:
        if data == 'back':
            query.edit_message_text("⚡ *SSH MANAGER V72*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_menu())
            return

        if data == 'add':
            context.user_data['act'] = 'a1'
            query.edit_message_text("👤 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            
        elif data == 'ren':
            context.user_data['act'] = 'r1'
            query.edit_message_text("🔄 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            
        elif data == 'del':
            context.user_data['act'] = 'd1'
            query.edit_message_text("🗑️ *ENTER USERNAME TO DELETE:*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            
        elif data == 'del_yes':
            u = context.user_data.get('del_u')
            if u:
                subprocess.run(f"pkill -u {u}", shell=True)
                subprocess.run(f"userdel -f -r {u}", shell=True)
                lines = []
                if os.path.exists(DB_FILE):
                    with open(DB_FILE, 'r') as f:
                        for line in f:
                            if not line.startswith(f"{u}|"): lines.append(line)
                with open(DB_FILE, 'w') as f: f.writelines(lines)
                query.edit_message_text(f"✅ *USER {u} DELETED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            else:
                query.edit_message_text("❌ ERROR", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))

        elif data == 'lock':
            context.user_data['act'] = 'l1'
            query.edit_message_text("🔒 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        
        elif data == 'do_lock':
            u = context.user_data.get('lock_u')
            subprocess.run(f"usermod -L {u}", shell=True)
            subprocess.run(f"pkill -KILL -u {u}", shell=True)
            query.edit_message_text(f"⛔ *USER {u} LOCKED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))

        elif data == 'do_unlock':
            u = context.user_data.get('lock_u')
            subprocess.run(f"usermod -U {u}", shell=True)
            query.edit_message_text(f"🟢 *USER {u} UNLOCKED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))

        elif data == 'list':
            header = "➖➖➖➖➖➖➖➖➖➖➖➖\n       ALL USERS LIST\n➖➖➖➖➖➖➖➖➖➖➖➖\n"
            body = ""
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        parts = l.split('|')
                        if len(parts) < 2: continue
                        u = parts[0][:10]; d = parts[1]
                        exp = "No Expiry" if d == "NEVER" else d
                        st = get_status(u)
                        body += f"{u:<10} | {st} | {exp}\n"
            if not body: body = "No Users Found"
            msg = header + f"```\n{body}```" + "➖➖➖➖➖➖➖➖➖➖➖➖"
            query.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            
        elif data == 'onl':
            header = "➖➖➖➖➖➖➖➖➖➖➖➖\n       ONLINE MONITOR\n➖➖➖➖➖➖➖➖➖➖➖➖\n"
            body = ""
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        u = l.split('|')[0]
                        st = get_status(u)
                        body += f"{u:<10} :    {st}\n"
            msg = header + f"```\n{body}```" + "➖➖➖➖➖➖➖➖➖➖➖➖"
            query.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))

        elif data == 'bak':
            if os.path.exists(DB_FILE):
                context.bot.send_document(chat_id=ADMIN_ID, document=open(DB_FILE, 'rb'))
            query.edit_message_text("✅ *SAVED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))

        elif data == 'set':
            kb = [[InlineKeyboardButton("UPDATE BOT", callback_data='ins'), InlineKeyboardButton("FIX TIMEZONE", callback_data='tz')], [InlineKeyboardButton("BACK", callback_data='back')]]
            query.edit_message_text("⚙️ *SETTINGS*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
        
        elif data == 'ins':
            query.edit_message_text("⚠️ USE OPTION [8] IN TERMINAL", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        
        elif data == 'tz':
            subprocess.run("timedatectl set-timezone Africa/Tunis", shell=True)
            query.edit_message_text("🌍 TIMEZONE FIXED", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        
        elif data == 'exp_yes':
            context.user_data['act'] = 'a_date'
            query.edit_message_text("📅 *DATE (YYYY-MM-DD):*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        
        elif data == 'exp_no':
            create_user_final(update, context, "NEVER", "00:00")

    except Exception as e: print(e)

def create_user_final(update, context, d, t):
    try:
        u = context.user_data.get('nu'); p = context.user_data.get('np')
        if subprocess.run(f"useradd -M -s /bin/false {u}", shell=True).returncode == 0:
            subprocess.run(f"echo '{u}:{p}' | chpasswd", shell=True)
            with open(DB_FILE, 'a') as f: f.write(f"{u}|{d}|{t}|Bot\n")
            
            # --- CUSTOM DESIGN LOGIC ---
            if d == "NEVER":
                msg = f"""━━━━━━━━━━━━━━━━━━━━━━━━━━━
🆕 NEW ACCOUNT 
━━━━━━━━━━━━━━━━━━━━━━━━━━━
👤  User : `{u}`
🔐 Pass : `{p}`
📅 Date : Unlimited
━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 `{u}:{p}`
━━━━━━━━━━━━━━━━━━━━━━━━━━━"""
            else:
                msg = f"""━━━━━━━━━━━━━━━━━━━━━━━━━━━
🆕 NEW ACCOUNT 
━━━━━━━━━━━━━━━━━━━━━━━━━━━
👤  User : `{u}`
🔐 Pass : `{p}`
📅 Date : {d}
⏰ Time : {t}
━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 `{u}:{p}`
━━━━━━━━━━━━━━━━━━━━━━━━━━━"""
            
            if update.callback_query: update.callback_query.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            else: update.message.reply_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        else:
            msg = "❌ USER ALREADY EXISTS"
            if update.callback_query: update.callback_query.edit_message_text(msg, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            else: update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
    except: pass

def txt(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    msg = update.message.text; act = context.user_data.get('act')
    try:
        if act == 'a1':
            if not msg.isalnum(): update.message.reply_text("❌ LETTERS/NUMBERS ONLY"); return
            context.user_data.update({'nu': msg, 'act': 'a2'})
            update.message.reply_text("🔑 *PASSWORD:*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        
        elif act == 'a2':
            context.user_data.update({'np': msg})
            kb = [[InlineKeyboardButton("🟢 YES", callback_data='exp_yes'), InlineKeyboardButton("🔴 NO", callback_data='exp_no')], [InlineKeyboardButton("BACK", callback_data='back')]]
            update.message.reply_text("📅 *SET EXPIRY?*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
        
        elif act == 'a_date':
            context.user_data.update({'nd': msg, 'act': 'a_time'})
            update.message.reply_text("⏰ *TIME (HH:MM):*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        
        elif act == 'a_time':
            d = context.user_data['nd']; t = msg if msg else "00:00"
            create_user_final(update, context, d, t)
            
        elif act == 'r1': context.user_data.update({'ru': msg, 'act': 'r2'}); update.message.reply_text("📅 *NEW DATE:*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif act == 'r2': context.user_data.update({'rd': msg, 'act': 'r3'}); update.message.reply_text("⏰ *NEW TIME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif act == 'r3':
            u = context.user_data['ru']; d = context.user_data['rd']; t = msg
            subprocess.run(f"usermod -U {u}", shell=True)
            lines = []
            if os.path.exists(DB_FILE):
                with open(DB_FILE, 'r') as f:
                    for line in f:
                        if not line.startswith(f"{u}|"): lines.append(line)
            lines.append(f"{u}|{d}|{t}|Renew\n")
            with open(DB_FILE, 'w') as f: f.writelines(lines)
            update.message.reply_text(f"✅ *RENEWED: {u}*\n📅 {d} | ⏰ {t}", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        
        elif act == 'd1':
            u = msg
            if subprocess.run(f"id {u}", shell=True, stdout=subprocess.DEVNULL).returncode != 0:
                update.message.reply_text("❌ USER NOT FOUND", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
                return
            context.user_data['del_u'] = u
            kb = [[InlineKeyboardButton("🗑️ YES, DELETE", callback_data='del_yes'), InlineKeyboardButton("🔙 CANCEL", callback_data='back')]]
            update.message.reply_text(f"⚠️ *ARE YOU SURE YOU WANT TO DELETE {u}?*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
            
        elif act == 'l1':
            u = msg
            if subprocess.run(f"id {u}", shell=True, stdout=subprocess.DEVNULL).returncode != 0:
                update.message.reply_text("❌ USER NOT FOUND", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
                return
            context.user_data['lock_u'] = u
            kb = [[InlineKeyboardButton("🔒 LOCK", callback_data='do_lock'), InlineKeyboardButton("🔓 UNLOCK", callback_data='do_unlock')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]]
            update.message.reply_text(f"⚙️ *MANAGE USER: {u}*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))

    except: pass

def main():
    up = Updater(TOKEN, use_context=True)
    dp = up.dispatcher
    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CallbackQueryHandler(btn))
    dp.add_handler(MessageHandler(Filters.text, txt))
    up.start_polling(); up.idle()

if __name__ == '__main__': main()
EOF

    systemctl daemon-reload; systemctl enable sshbot; systemctl start sshbot
    echo -e "${GREEN}✅ BOT V72 INSTALLED!${NC}"; pause
}

# --- MAIN LOOP ---
while true; do
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e " ${WHITE}SSH MANAGER (V72) ${NC}"
    echo -e " ${YELLOW}OS: ${OS_NAME^^} ${OS_VERSION}${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo ""
    echo -e " ${GREEN}[01]${NC} ADD ACCOUNT 👤"
    echo -e " ${GREEN}[02]${NC} RENEW ACCOUNT 🔄"
    echo -e " ${GREEN}[03]${NC} REMOVE ACCOUNT 🗑️"
    echo -e " ${GREEN}[04]${NC} LOCK ACCOUNT 🔐"
    echo -e " ${GREEN}[05]${NC} LIST ACCOUNTS 📋"
    echo -e " ${GREEN}[06]${NC} CHECK STATUS 🟢"
    echo -e " ${GREEN}[07]${NC} BACKUP DATA 💾"
    echo -e " ${GREEN}[08]${NC} SETTINGS ⚙️"
    echo -e " ${GREEN}[00]${NC} EXIT 🚪"
    echo ""
    echo -e "${CYAN}==================================================${NC}"
    read -p " SELECT OPTION: " o
    case "$o" in
        1) fun_create ;; 2) fun_renew ;; 3) fun_remove ;; 4) fun_lock ;;
        5) fun_list ;; 6) fun_online ;; 7) fun_backup ;; 8) fun_settings ;; 0) exit 0 ;;
    esac
done
