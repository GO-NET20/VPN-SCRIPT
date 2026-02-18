#!/bin/bash
# ==================================================
#  SSH MANAGER V114 (THE MASTERPIECE) 💎
#  - CLI: ONLY DASHED LINES (--------------------)
#  - BOT: ZERO LINES, 100% CLEAN TEXT
#  - FIXED: USERDEL MAIL SPOOL ERRORS COMPLETELY MUTED
# ==================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- 1. SYSTEM SETUP ---
timedatectl set-timezone Africa/Tunis 2>/dev/null

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

# --- 2. CONFIGURATION ---
USER_DB="/etc/xpanel/users_db.txt"
BOT_CONF="/etc/xpanel/bot.conf"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.py"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"
MIGRATION_FILE="/root/migration_users.txt"

MY_TOKEN="8134717950:AAGj2wWaABBUWbPLa7jX6yEWHgwjgUelpwg"
MY_ID="7587310857"

# --- 3. COLORS & EXACT REQUESTED LINE ---
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
PURPLE='\033[1;35m'; CYAN='\033[1;36m'; NC='\033[0m'; WHITE='\033[1;37m'
# The EXACT line you requested:
LINE="${PURPLE}----------------------------------------${NC}"

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"

# ==================================================
#  🛡️ PYTHON PRECISION MONITOR (BACKGROUND)
# ==================================================
if ! command -v python3 &> /dev/null; then
    $CMD python3 python3-pip > /dev/null 2>&1
fi

pkill -f kp_monitor.py
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/usr/bin/env python3
import datetime, subprocess, os, time

DB_FILE = "/etc/xpanel/users_db.txt"
LOG_FILE = "/var/log/kp_manager.log"
MAX_LOGIN = 1

def check_loop():
    while True:
        if os.path.exists(DB_FILE):
            try:
                lines = open(DB_FILE, 'r').readlines()
                new_lines = []
                status_changed = False
                now = datetime.datetime.now()

                for line in lines:
                    parts = line.strip().split('|')
                    if len(parts) < 3: continue
                    user, exp_date, exp_time = parts[0], parts[1], parts[2]

                    if "V1" in user or "Turbo" in user or user == "root":
                        new_lines.append(line); continue

                    expired = False
                    if exp_date.lower() != "never":
                        try:
                            if not exp_time: exp_time = "23:59"
                            exp = datetime.datetime.strptime(f"{exp_date} {exp_time}", "%Y-%m-%d %H:%M")
                            if now >= exp:
                                subprocess.run(f"pkill -KILL -u {user}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                                # Removed -r to prevent mail spool errors completely
                                subprocess.run(f"userdel -f {user}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                                status_changed = True; expired = True
                        except: pass

                    if expired: continue

                    try:
                        c = int(subprocess.getoutput(f"pgrep -u {user} | grep -E 'sshd|dropbear' | wc -l"))
                        if c > MAX_LOGIN:
                            subprocess.run(f"pkill -KILL -u {user}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except: pass
                    new_lines.append(line)

                if status_changed: open(DB_FILE, 'w').writelines(new_lines)
            except: pass
        time.sleep(3)

if __name__ == "__main__": check_loop()
EOF
chmod +x "$MONITOR_SCRIPT"
if ! pgrep -f "kp_monitor.py" > /dev/null; then nohup python3 "$MONITOR_SCRIPT" >/dev/null 2>&1 & fi

# ==================================================
#  CLI FUNCTIONS (SERVER PANEL)
# ==================================================
pause() { echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"; read; }
draw_header() {
    clear
    echo -e "${LINE}"
    echo -e "          ${WHITE}SSH MANAGER V114${NC}"
    echo -e "${LINE}"
}

fun_create() {
    draw_header
    i=1
    while true; do
        u="USER${i}"
        if id "$u" &>/dev/null; then ((i++)); continue; fi
        if grep -q "^$u|" "$USER_DB"; then ((i++)); continue; fi
        break
    done
    p="12345"
    
    echo -e " 👤 Username : ${WHITE}$u${NC}"
    echo -e " 🔑 Password : ${WHITE}$p${NC}"
    read -p " 📅 Expiry Date & Time: " dt_input
    
    d=$(echo "$dt_input" | awk '{print $1}')
    t=$(echo "$dt_input" | awk '{print $2}')
    
    [[ -z "$d" ]] && d="NEVER"
    [[ -z "$t" ]] && t="00:00"
    
    useradd -M -s /bin/false "$u" >/dev/null 2>&1
    echo "$u:$p" | chpasswd >/dev/null 2>&1
    echo "$u|$d|$t|V114" >> "$USER_DB"
    
    clear
    echo -e "${LINE}"
    echo -e "        ✅ ${WHITE}ACCOUNT CREATED${NC}"
    echo -e "${LINE}"
    echo -e ""
    echo -e " 👤 Username  : ${WHITE}$u${NC}"
    echo -e " 🔑 Password  : ${WHITE}$p${NC}"
    echo -e " 📅 Expiry    : ${WHITE}$d${NC}"
    echo -e " ⏰ Time      : ${WHITE}$t${NC}"
    echo -e ""
    echo -e "${LINE}"
    echo -e " 📋 Copy: ${WHITE}$u:$p${NC}"
    echo -e "${LINE}"
    pause
}

fun_renew() {
    draw_header
    echo -e "             🔄 ${WHITE}RENEW USER${NC}"
    echo -e "${LINE}"
    read -p " 👤 Username : " u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "${RED} ❌ NOT FOUND!${NC}"; pause; return; fi
    read -p " 📅 New Date & Time : " dt_input
    d=$(echo "$dt_input" | awk '{print $1}')
    t=$(echo "$dt_input" | awk '{print $2}')
    [[ -z "$d" ]] && d="NEVER"
    [[ -z "$t" ]] && t="23:59"
    
    sed -i "/^$u|/d" "$USER_DB"
    echo "$u|$d|$t|Renew" >> "$USER_DB"
    usermod -U "$u" >/dev/null 2>&1
    echo -e "${GREEN} ✅ RENEWED SUCCESSFULLY${NC}"; pause
}

fun_remove() {
    draw_header
    echo -e "             🗑️ ${WHITE}DELETE USER${NC}"
    echo -e "${LINE}"
    read -p " 👤 Username : " u
    read -p " ⚠️ CONFIRM? [y/n]: " c
    if [[ "$c" == "y" ]]; then
        pkill -KILL -u "$u" >/dev/null 2>&1
        # Removed -r to stop "mail spool not found" error permanently
        userdel -f "$u" >/dev/null 2>&1
        sed -i "/^$u|/d" "$USER_DB"
        echo -e "${RED} 🗑️ DELETED SUCCESSFULLY${NC}"
    fi
    pause
}

fun_lock() {
    draw_header
    echo -e "             🔒 ${WHITE}LOCK/UNLOCK${NC}"
    echo -e "${LINE}"
    read -p " 👤 Username : " u
    echo " [1] LOCK ⛔"
    echo " [2] UNLOCK 🔓"
    read -p " Select: " s
    if [[ "$s" == "1" ]]; then
        usermod -L "$u" >/dev/null 2>&1; pkill -KILL -u "$u" >/dev/null 2>&1; echo -e "${GREEN} ⛔ LOCKED${NC}"
    else
        usermod -U "$u" >/dev/null 2>&1; echo -e "${GREEN} 🔓 UNLOCKED${NC}"
    fi
    pause
}

fun_list() {
    clear
    echo -e "${LINE}"
    echo -e "          📋 ${WHITE}LIST ACCOUNTS${NC}"
    echo -e "${LINE}"
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             [[ "$d" == "NEVER" ]] && DATE_STR="NEVER" || DATE_STR="$d $t"
             printf " 👤 ${WHITE}%-12s${NC}   📅 %s\n" "$u" "$DATE_STR"
        fi
    done < "$USER_DB"
    echo -e "${LINE}"
    pause
}

fun_monitor_view() {
    clear
    echo -e "${LINE}"
    echo -e "          ⚡ ${WHITE}LIVE MONITOR${NC}"
    echo -e "${LINE}"
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             if ps -ef | grep "sshd: $u" | grep -v grep > /dev/null 2>&1 || pgrep -u "$u" > /dev/null 2>&1; then
                STATUS="🟢 ONLINE "
             else
                STATUS="🔴 OFFLINE"
             fi
             printf " 👤 ${WHITE}%-12s${NC}   %s\n" "$u" "$STATUS"
        fi
    done < "$USER_DB"
    echo -e "${LINE}"
    pause
}

fun_backup() {
    draw_header
    echo -e "          📦 ${WHITE}LOCAL BACKUP${NC}"
    echo -e "${LINE}"
    cp "$USER_DB" "$BACKUP_DIR/users_backup_$(date +%F).txt"
    echo -e "${GREEN} ✅ Backup Saved in $BACKUP_DIR${NC}"
    pause
}

fun_export_users() {
    draw_header; echo -e "${YELLOW} 📤 EXPORTING USERS...${NC}"
    cp "$USER_DB" "$MIGRATION_FILE"
    echo -e "${GREEN} ✅ EXPORT SUCCESSFUL!${NC}\n File: $MIGRATION_FILE\n Upload this to new server."; pause
}

fun_import_users() {
    draw_header; echo -e "${YELLOW} 📥 RESTORING USERS...${NC}"
    if [[ ! -f "$MIGRATION_FILE" ]]; then echo -e "${RED} ❌ FILE NOT FOUND ($MIGRATION_FILE)${NC}"; pause; return; fi
    count=0
    while IFS='|' read -r u d t tag; do
        [[ -z "$u" ]] && continue
        if ! id "$u" &>/dev/null; then
            useradd -M -s /bin/false "$u" >/dev/null 2>&1; echo "$u:12345" | chpasswd >/dev/null 2>&1
            echo -e " Created: ${GREEN}$u${NC}"; ((count++))
        fi
    done < "$MIGRATION_FILE"
    cat "$MIGRATION_FILE" > "$USER_DB"
    echo -e "${GREEN} ✅ RESTORED: $count USERS${NC}"; pause
}

fun_settings() {
    while true; do
        draw_header
        echo -e "       ⚙️ ${WHITE}SETTINGS & MIGRATION${NC}"
        echo -e "${LINE}"
        echo -e " [1] 🤖 Install/Fix Bot"
        echo -e " [2] 🌍 Set Timezone (Tunis)"
        echo -e " [3] 📤 EXPORT Users (Backup)"
        echo -e " [4] 📥 RESTORE Users"
        echo -e " [5] 🔙 Back"
        echo -e "${LINE}"
        read -p " Select: " s
        case "$s" in
            1) fun_install_bot ;;
            2) timedatectl set-timezone Africa/Tunis; echo -e "${GREEN} ✅ Timezone set${NC}"; pause ;;
            3) fun_export_users ;;
            4) fun_import_users ;;
            5) break ;;
        esac
    done
}

# ==================================================
#  🤖 BOT INSTALLER (V114 - ZERO LINES IN TELEGRAM)
# ==================================================
fun_install_bot() {
    pkill -f ssh_bot.py
    systemctl stop sshbot >/dev/null 2>&1
    clear; echo -e "${YELLOW}INSTALLING BOT (REMOVING BOT LINES)...${NC}"
    
    pip3 uninstall -y python-telegram-bot telegram >/dev/null 2>&1
    
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        apt-get update -y >/dev/null 2>&1; apt-get install -y python3 python3-pip >/dev/null 2>&1
    else
        yum install -y python3 python3-pip >/dev/null 2>&1
    fi
    
    pip3 install python-telegram-bot==13.7 schedule requests --break-system-packages >/dev/null 2>&1 || \
    pip3 install python-telegram-bot==13.7 schedule requests >/dev/null 2>&1

    echo "BOT_TOKEN=\"$MY_TOKEN\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$MY_ID\"" >> "$BOT_CONF"
    chmod 600 "$BOT_CONF"

    # PYTHON BOT SCRIPT (NO LINES AT ALL, PURE CLEAN TEXT)
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(message)s')
CONF_FILE = "/etc/xpanel/bot.conf"
DB_FILE = "/etc/xpanel/users_db.txt"
MIGRATION_FILE = "/root/migration_users.txt"

def load_config():
    c = {}
    try:
        for l in open(CONF_FILE):
            if "=" in l: k, v = l.strip().split("=", 1); c[k] = v.strip().replace('"', '')
    except: pass
    return c

cfg = load_config(); TOKEN = cfg.get("BOT_TOKEN"); ADMIN_ID = int(cfg.get("ADMIN_ID", 0))

def get_status(u):
    try:
        if subprocess.getoutput(f"pgrep -u {u}"): return "🟢 ONLINE"
    except: pass
    return "🔴 OFFLINE"

def get_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 ADD", callback_data='add'), InlineKeyboardButton("🗑️ DEL", callback_data='del')],
        [InlineKeyboardButton("🔄 RENEW", callback_data='ren'), InlineKeyboardButton("📋 LIST", callback_data='list')],
        [InlineKeyboardButton("🔒 LOCK", callback_data='lock'), InlineKeyboardButton("🔓 UNLOCK", callback_data='unlock')],
        [InlineKeyboardButton("⚡ MONITOR", callback_data='onl'), InlineKeyboardButton("📦 BACKUP", callback_data='bak')],
        [InlineKeyboardButton("🚀 MIGRATION", callback_data='migrate')]
    ])

def start(u, c):
    if u.effective_user.id == ADMIN_ID: u.message.reply_text("💎 <b>X-PANEL V114</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu())

def btn(u, c):
    q = u.callback_query; q.answer(); d = q.data
    if d == 'back': c.user_data.clear(); q.edit_message_text("💎 <b>X-PANEL V114</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu()); return

    try:
        if d == 'add':
            i = 1
            while True:
                usr = f"USER{i}"
                if subprocess.run(f"id {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0 and f"{usr}|" not in (open(DB_FILE).read() if os.path.exists(DB_FILE) else ""): break
                i += 1
            c.user_data['u'] = usr; c.user_data['act'] = 'a_datetime'
            q.edit_message_text(f"👤 Username: <code>{usr}</code>\n📅 <b>Enter Date and time (YYYY-MM-DD HH:MM):</b>", parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙", callback_data='back')]]))

        elif d == 'ren': c.user_data['act']='r_datetime'; q.edit_message_text("🔄 <b>Username to Renew:</b>", parse_mode=ParseMode.HTML)
        elif d == 'del': c.user_data['act']='d1'; q.edit_message_text("🗑️ <b>Username to Delete:</b>", parse_mode=ParseMode.HTML)
        elif d == 'lock': c.user_data['act']='l1'; q.edit_message_text("🔒 <b>Username to Lock:</b>", parse_mode=ParseMode.HTML)
        elif d == 'unlock': c.user_data['act']='ul1'; q.edit_message_text("🔓 <b>Username to Unlock:</b>", parse_mode=ParseMode.HTML)

        # BOT LIST: ZERO LINES
        elif d == 'list':
            body = "📋 <b>LIST ACCOUNTS</b>\n\n"
            if os.path.exists(DB_FILE):
                for l in open(DB_FILE):
                    p = l.strip().split('|')
                    if len(p) < 3 or "V1" in p[0] or "root" in p[0]: continue
                    usr, date, time = p[0], p[1], p[2]
                    date_str = "NEVER" if date == "NEVER" else f"{date} {time}"
                    body += f"👤 <code>{usr}</code>\n📅 {date_str}\n\n"
            q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙", callback_data='back')]]))

        # BOT MONITOR: ZERO LINES
        elif d == 'onl':
            body = "⚡ <b>LIVE MONITOR</b>\n\n"
            if os.path.exists(DB_FILE):
                for l in open(DB_FILE):
                    usr = l.split('|')[0]
                    if not usr or "V1" in usr or "root" in usr: continue
                    if subprocess.run(f"id {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0: continue
                    st = get_status(usr)
                    body += f"👤 <code>{usr}</code>\n{st}\n\n"
            q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙", callback_data='back')]]))

        elif d == 'bak':
            if os.path.exists(DB_FILE): c.bot.send_document(ADMIN_ID, open(DB_FILE, 'rb'))
            q.edit_message_text("✅ <b>SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu())
            
        elif d == 'migrate':
            if os.path.exists(DB_FILE):
                subprocess.run(f"cp {DB_FILE} {MIGRATION_FILE}", shell=True)
                c.bot.send_document(ADMIN_ID, open(MIGRATION_FILE, 'rb'), caption="🚀 <b>MIGRATION FILE</b>", parse_mode=ParseMode.HTML)
                q.edit_message_text("✅ <b>SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu())

    except Exception as e: logging.error(e)

def txt(u, c):
    if u.effective_user.id != ADMIN_ID: return
    msg = u.message.text; act = c.user_data.get('act')
    
    try:
        if act == 'a_datetime':
            usr = c.user_data['u']; pwd = "12345"
            parts = msg.split()
            dt = parts[0] if len(parts) > 0 else "NEVER"
            tm = parts[1] if len(parts) > 1 else "00:00"
            
            subprocess.run(f"useradd -M -s /bin/false {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(f"echo '{usr}:{pwd}' | chpasswd", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            open(DB_FILE, 'a').write(f"{usr}|{dt}|{tm}|Bot\n")
            
            # BOT CREATE MSG: ZERO LINES
            resp = (
                "✅ <b>ACCOUNT CREATED</b>\n\n"
                f"👤 <b>Username :</b> <code>{usr}</code>\n"
                f"🔑 <b>Password :</b> <code>{pwd}</code>\n"
                f"📅 <b>Expiry   :</b> {dt}\n"
                f"⏰ <b>Time     :</b> {tm}\n\n"
                f"📋 <b>Copy     :</b> <code>{usr}:{pwd}</code>"
            )
            u.message.reply_text(resp, parse_mode=ParseMode.HTML, reply_markup=get_menu())

        elif act == 'r_datetime':
            c.user_data['ru'] = msg; c.user_data['act'] = 'r_datetime_val'
            u.message.reply_text("📅 <b>Enter New Date and time (YYYY-MM-DD HH:MM):</b>", parse_mode=ParseMode.HTML)

        elif act == 'r_datetime_val':
            usr = c.user_data.get('ru')
            parts = msg.split()
            dt = parts[0] if len(parts) > 0 else "NEVER"
            tm = parts[1] if len(parts) > 1 else "23:59"
            
            if os.path.exists(DB_FILE):
                lines = [l for l in open(DB_FILE) if not l.startswith(f"{usr}|")]
                lines.append(f"{usr}|{dt}|{tm}|Renew\n")
                open(DB_FILE, 'w').writelines(lines)
                u.message.reply_text(f"✅ <b>RENEWED: {usr}</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu())

        elif act == 'd1':
            subprocess.run(f"pkill -KILL -u {msg}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(f"userdel -f {msg}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            lines = [l for l in open(DB_FILE) if not l.startswith(f"{msg}|")]
            open(DB_FILE, 'w').writelines(lines)
            u.message.reply_text(f"🗑️ <b>DELETED:</b> <code>{msg}</code>", parse_mode=ParseMode.HTML, reply_markup=get_menu())

        elif act == 'l1':
            subprocess.run(f"usermod -L {msg}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(f"pkill -KILL -u {msg}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            u.message.reply_text(f"⛔ <b>LOCKED:</b> <code>{msg}</code>", parse_mode=ParseMode.HTML, reply_markup=get_menu())
            
        elif act == 'ul1':
            subprocess.run(f"usermod -U {msg}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            u.message.reply_text(f"🔓 <b>UNLOCKED:</b> <code>{msg}</code>", parse_mode=ParseMode.HTML, reply_markup=get_menu())
            
    except: pass

def main():
    if not TOKEN: return
    up = Updater(TOKEN, use_context=True)
    up.dispatcher.add_handler(CommandHandler('start', start))
    up.dispatcher.add_handler(CallbackQueryHandler(btn))
    up.dispatcher.add_handler(MessageHandler(Filters.text, txt))
    up.start_polling(); up.idle()

if __name__ == '__main__': main()
EOF

    cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Bot Service
After=network.target
[Service]
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sshbot >/dev/null 2>&1
    systemctl restart sshbot
    echo -e "${GREEN}✅ BOT INSTALLED SUCCESSFULLY!${NC}"; pause
}

# ==================================================
#  MAIN LOOP
# ==================================================
while true; do
    draw_header
    echo -e " ${GREEN}[01]${NC} 👤 ADD ACCOUNT"
    echo -e " ${GREEN}[02]${NC} 🔄 RENEW ACCOUNT"
    echo -e " ${GREEN}[03]${NC} 🗑️ REMOVE ACCOUNT"
    echo -e " ${GREEN}[04]${NC} 🔐 LOCK ACCOUNT"
    echo -e " ${GREEN}[05]${NC} 📋 LIST ACCOUNTS"
    echo -e " ${GREEN}[06]${NC} 🔘 MONITOR USERS"
    echo -e " ${GREEN}[07]${NC} 💾 BACKUP DATA"
    echo -e " ${GREEN}[08]${NC} ⚙️ SETTINGS"
    echo -e " ${GREEN}[00]${NC} 🚪 EXIT"
    echo ""
    echo -e "${LINE}"
        read -p " Select Option: " o
    case "$o" in
        1|01) fun_create ;; 
        2|02) fun_renew ;; 
        3|03) fun_remove ;; 
        4|04) fun_lock ;;
        5|05) fun_list ;; 
        6|06) fun_monitor_view ;; 
        7|07) fun_backup ;; 
        8|08) fun_settings ;; 
        0|00) exit 0 ;;
        *) echo -e "${RED} Invalid Option!${NC}" ; sleep 1 ;;
    esac
done
