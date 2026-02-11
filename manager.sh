cat > manager.sh << 'EOF'
#!/bin/bash
# ==================================================
#  SSH MANAGER V58 (ELEGANT DESIGN EDITION) 💎
#  - UI: FULL BORDER LINES & PERFECT ALIGNMENT ✅
#  - BOT: ELEGANT VERTICAL LAYOUT & COMPACT BUTTONS ✅
#  - STATUS: ICONS ONLY (🟢/🔴/⛔) NO TEXT 🚫
# ==================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- 1. DETECT OS ---
if [[ -f /etc/debian_version ]]; then
    OS="debian"; SSH_SERVICE="ssh"
elif [[ -f /etc/redhat-release ]]; then
    OS="centos"; SSH_SERVICE="sshd"
else
    OS="unknown"; SSH_SERVICE="sshd"
fi

# --- CONFIG ---
USER_DB="/etc/xpanel/users_db.txt"
BOT_CONF="/etc/xpanel/bot.conf"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"

# --- YOUR CREDENTIALS ---
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

# ==================================================
#  CLI FUNCTIONS
# ==================================================

pause() { echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"; read; }

check_status_cli() {
    local u=$1
    if ps -ef | grep "sshd: $u" | grep -v grep | grep -qE "@| "; then echo -e "🟢"
    elif pgrep -u "$u" dropbear >/dev/null; then echo -e "🟢"
    elif passwd -S "$u" | grep -q " L "; then echo -e "⛔"
    else echo -e "🔴"
    fi
}

fun_create() {
    clear; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}               ADD NEW USER               ${NC}"
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
    echo "$u|$d|$t|V58" >> "$USER_DB"
    clear; echo -e "${GREEN}✅ CREATED${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " User : $u"
    echo " Pass : $p"
    echo " Date : $d"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$u:$p"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; pause
}

fun_list() {
    clear; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}              USER LIST                   ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "${PURPLE}%-15s | %-12s | %-5s${NC}\n" "USER" "DATE" "ST"
    echo "------------------------------------------"
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        st=$(check_status_cli "$u"); printf "%-15s | %-12s | %b\n" "$u" "$d" "$st"
    done < "$USER_DB"; pause
}

fun_online() {
    clear; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}           🟢 LIVE MONITOR                ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if ps -ef | grep "sshd: $u" | grep -v grep | grep -qE "@| "; then
             echo -e "$u : 🟢"
        fi
    done < "$USER_DB"; pause
}

fun_renew() { clear; echo "=== RENEW ==="; read -p " USER: " u; read -p " DATE: " d; sed -i "/^$u|/d" "$USER_DB"; echo "$u|$d|23:59|Renew" >> "$USER_DB"; usermod -U "$u"; echo "DONE"; pause; }
fun_remove() { clear; echo "=== DELETE ==="; read -p " USER: " u; pkill -u "$u"; userdel -f -r "$u"; sed -i "/^$u|/d" "$USER_DB"; echo "DELETED"; pause; }
fun_lock() { clear; echo "=== LOCK ==="; read -p " USER: " u; read -p " 1=LOCK, 2=UNLOCK: " s; if [[ "$s" == "1" ]]; then usermod -L "$u"; pkill -KILL -u "$u"; echo "LOCKED"; else usermod -U "$u"; echo "UNLOCKED"; fi; pause; }
fun_backup() { cp "$USER_DB" "$BACKUP_DIR/backup.txt"; echo "BACKUP SAVED"; pause; }

fun_settings() {
    clear; echo -e "${BLUE}=== SETTINGS ===${NC}"
    echo " [1] INSTALL / UPDATE BOT"
    echo " [2] FIX TIMEZONE"
    echo " [0] BACK"
    read -p " OPTION: " s
    case "$s" in
        1) fun_install_bot ;;
        2) timedatectl set-timezone Africa/Tunis; echo -e "${GREEN}DONE${NC}"; pause ;;
        *) return ;;
    esac
}

# ==================================================
#  🤖 BOT INSTALLER (V58)
# ==================================================
fun_install_bot() {
    clear; echo -e "${YELLOW}INSTALLING DESIGNED BOT V58...${NC}"
    echo "BOT_TOKEN=\"$MY_TOKEN\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$MY_ID\"" >> "$BOT_CONF"
    
    if [[ "$OS" == "debian" ]]; then apt-get update -y; apt-get install python3-pip -y; else yum install python3-pip -y; fi
    pip3 install python-telegram-bot==13.7 schedule --force-reinstall --break-system-packages >/dev/null 2>&1

    cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Bot V58
After=network.target
[Service]
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, re
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

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
        if out and (re.search(f"sshd: {u}\\b", out) or re.search(f"sshd: {u}@", out)): return "🟢"
        if subprocess.getoutput(f"pgrep -u {u} dropbear"): return "🟢"
        if " L " in subprocess.getoutput(f"passwd -S {u}"): return "⛔"
    except: pass
    return "🔴"

def get_main_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 ADD USER", callback_data='add')],
        [InlineKeyboardButton("🔄 RENEW USER", callback_data='ren')],
        [InlineKeyboardButton("🗑️ REMOVE USER", callback_data='del')],
        [InlineKeyboardButton("🔒 LOCK / UNLOCK", callback_data='lock')],
        [InlineKeyboardButton("📋 SHOW ALL USERS", callback_data='list')],
        [InlineKeyboardButton("🟢 CHECK ONLINE", callback_data='onl')],
        [InlineKeyboardButton("💾 SAVE DATA", callback_data='bak')],
        [InlineKeyboardButton("⚙️ SETTINGS", callback_data='set')]
    ])

def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    update.message.reply_text("Panel SSH MANAGER", reply_markup=get_main_menu())

def btn(update: Update, context: CallbackContext):
    try:
        q = update.callback_query; q.answer()
        data = q.data
        if data == 'back': q.edit_message_text("Panel SSH MANAGER", reply_markup=get_main_menu()); return

        if data == 'add': context.user_data['act']='a1'; q.edit_message_text("👤 ENTER USERNAME:", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data == 'ren': context.user_data['act']='r1'; q.edit_message_text("🔄 ENTER USERNAME:", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data == 'del': context.user_data['act']='d1'; q.edit_message_text("🗑️ ENTER USERNAME:", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data == 'lock': context.user_data['act']='l1'; q.edit_message_text("🔒 ENTER USERNAME:", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        
        elif data == 'list':
            header = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n      📋 ALL USERS LIST\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\nUsername       | Status | Expiry\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            body = ""
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        p = l.split('|'); u = p[0]; d = p[1]
                        if not u.strip(): continue
                        body += f"{u:<14} |   {get_status(u)}  | {d}\n"
            msg = header + f"```\n{body}```" + "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            
        elif data == 'onl':
            header = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n      📊 LIVE STATUS MONITOR\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\nUsername            Status\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            body = ""
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        u = l.split('|')[0]
                        if not u.strip(): continue
                        body += f"{u:<15} :    {get_status(u)}\n"
            msg = header + f"```\n{body}```" + "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))

        elif data == 'bak': context.bot.send_document(chat_id=ADMIN_ID, document=open(DB_FILE, 'rb')); q.edit_message_text("✅ DATABASE SAVED", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data == 'set': q.edit_message_text("SETTINGS MENU", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("FIX TIMEZONE", callback_data='tz')], [InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data == 'tz': subprocess.run("timedatectl set-timezone Africa/Tunis", shell=True); q.edit_message_text("🌍 DONE", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data == 'exp_yes': context.user_data['act']='a_date'; q.edit_message_text("📅 ENTER DATE (YYYY-MM-DD):", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data == 'exp_no': create_user_final(update, context, "NEVER", "00:00")
    except: pass

def create_user_final(update, context, d, t):
    try:
        u = context.user_data.get('nu'); p = context.user_data.get('np')
        if subprocess.run(f"useradd -M -s /bin/false {u}", shell=True).returncode == 0:
            subprocess.run(f"echo '{u}:{p}' | chpasswd", shell=True)
            with open(DB_FILE, 'a') as f: f.write(f"{u}|{d}|{t}|Bot\n")
            exp_info = f"Expiry date : `{d}`\ntime : `{t}`" if d != "NEVER" else "No date or time"
            msg = f"""✅ *USER CREATED!*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
👤 User : `{u}`
🔑 Pass : `{p}`
📅 {exp_info}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
`{u}:{p}`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━"""
            try: update.callback_query.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            except: update.message.reply_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        else:
            update.message.reply_text("❌ EXISTS", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
    except: pass

def txt(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    msg = update.message.text; act = context.user_data.get('act')
    if act == 'a1':
        if not msg.isalnum(): update.message.reply_text("❌ A-Z, 0-9 ONLY"); return
        context.user_data.update({'nu': msg, 'act': 'a2'}); update.message.reply_text("🔑 ENTER PASSWORD:", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
    elif act == 'a2':
        context.user_data.update({'np': msg})
        kb = [[InlineKeyboardButton("YES", callback_data='exp_yes'), InlineKeyboardButton("NO", callback_data='exp_no')], [InlineKeyboardButton("BACK", callback_data='back')]]
        update.message.reply_text("📅 SET EXPIRY DATE?", reply_markup=InlineKeyboardMarkup(kb))
    elif act == 'a_date': context.user_data.update({'nd': msg, 'act': 'a_time'}); update.message.reply_text("⏰ ENTER TIME (HH:MM):", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
    elif act == 'a_time': d = context.user_data['nd']; t = msg if msg else "00:00"; create_user_final(update, context, d, t)
    elif act == 'r1': u=msg; context.user_data.update({'ru':u,'act':'r2'}); update.message.reply_text("📅 NEW DATE (YYYY-MM-DD):", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
    elif act == 'r2':
        u = context.user_data['ru']; d = msg; subprocess.run(f"usermod -U {u}", shell=True)
        lines = [l for l in open(DB_FILE) if not l.startswith(f"{u}|")]; lines.append(f"{u}|{d}|23:59|Renew\n")
        with open(DB_FILE, 'w') as f: f.writelines(lines)
        update.message.reply_text("✅ RENEWED", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
    elif act == 'd1':
        u=msg; subprocess.run(f"pkill -u {u}", shell=True); subprocess.run(f"userdel -f -r {u}", shell=True)
        lines = [l for l in open(DB_FILE) if not l.startswith(f"{u}|")]
        with open(DB_FILE, 'w') as f: f.writelines(lines)
        update.message.reply_text("🗑 DELETED", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
    elif act == 'l1':
        u=msg; subprocess.run(f"usermod -L {u}", shell=True); subprocess.run(f"pkill -KILL -u {u}", shell=True)
        update.message.reply_text("⛔ LOCKED", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))

def main():
    up = Updater(TOKEN, use_context=True)
    up.dispatcher.add_handler(CommandHandler("start", start))
    up.dispatcher.add_handler(CallbackQueryHandler(btn, run_async=True))
    up.dispatcher.add_handler(MessageHandler(Filters.text, txt))
    up.start_polling(); up.idle()

if __name__ == '__main__': main()
EOF

    systemctl daemon-reload; systemctl enable sshbot; systemctl start sshbot
    echo -e "${GREEN}✅ BOT V58 INSTALLED!${NC}"; pause
}

# --- MAIN LOOP ---
while true; do
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}      SSH MANAGER V58 (DESIGNED)💎        ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ${GREEN}[01]${NC} ADD USER"
    echo -e " ${GREEN}[02]${NC} RENEW USER"
    echo -e " ${GREEN}[03]${NC} REMOVE USER"
    echo -e " ${GREEN}[04]${NC} LOCK/UNLOCK"
    echo -e " ${GREEN}[05]${NC} LIST USERS"
    echo -e " ${GREEN}[06]${NC} ONLINE MONITOR"
    echo -e " ${GREEN}[07]${NC} BACKUP"
    echo -e " ${GREEN}[08]${NC} SETTINGS ⚙️"
    echo -e " ${GREEN}[00]${NC} EXIT"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p " SELECT: " o
    case "$o" in
        1) fun_create ;; 2) fun_renew ;; 3) fun_remove ;; 4) fun_lock ;;
        5) fun_list ;; 6) fun_online ;; 7) fun_backup ;; 8) fun_settings ;; 0) exit 0 ;;
    esac
done
EOF
bash manager.sh
