#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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

USER_DB="/etc/xpanel/users_db.txt"
BOT_CONF="/etc/xpanel/bot.conf"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.py"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"
MIGRATION_FILE="/root/migration_users.txt"

MY_TOKEN="8134717950:AAGj2wWaABBUWbPLa7jX6yEWHgwjgUelpwg"
MY_ID="7587310857"

RED=$'\033[1;31m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'; NC=$'\033[0m'; WHITE=$'\033[1;37m'
LINE="${BLUE}===============================================${NC}"

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"
[[ ! -f "$BOT_CONF" ]] && touch "$BOT_CONF"

if ! command -v python3 &> /dev/null; then
    $CMD python3 > /dev/null 2>&1
fi

cat > "$MONITOR_SCRIPT" << 'EOF'
#!/usr/bin/env python3
import datetime, subprocess, os, time
import urllib.request, urllib.parse

DB_FILE = "/etc/xpanel/users_db.txt"
CONF_FILE = "/etc/xpanel/bot.conf"
LOG_FILE = "/var/log/kp_manager.log"
MAX_LOGIN = 1
alert_cache = {}

def load_config():
    c = {}
    try:
        for l in open(CONF_FILE):
            if "=" in l: k, v = l.strip().split("=", 1); c[k] = v.strip().replace('"', '')
    except: pass
    return c

def log_event(msg):
    try:
        timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        with open(LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {msg}\n")
    except: pass

def send_alert(msg, user_key):
    try:
        cfg = load_config()
        if cfg.get("ALERTS") != "ON": return 
        now = time.time()
        if user_key in alert_cache and now - alert_cache[user_key] < 60: return
        alert_cache[user_key] = now
        token = cfg.get("BOT_TOKEN")
        admin = cfg.get("ADMIN_ID")
        if token and admin:
            url = f"https://api.telegram.org/bot{token}/sendMessage"
            data = urllib.parse.urlencode({'chat_id': admin, 'text': msg, 'parse_mode': 'HTML'}).encode('utf-8')
            req = urllib.request.Request(url, data=data)
            urllib.request.urlopen(req, timeout=3)
    except: pass

def check_loop():
    while True:
        try:
            if os.path.exists(DB_FILE):
                with open(DB_FILE, 'r') as f:
                    lines = f.readlines()
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
                    if exp_date.upper() not in ["NEVER", "EXPIRED"]:
                        try:
                            exp = datetime.datetime.strptime(f"{exp_date} {exp_time}", "%Y-%m-%d %H:%M")
                            if now >= exp:
                                os.system(f"usermod -L {user} 2>/dev/null")
                                os.system(f"killall -9 -u {user} 2>/dev/null")
                                os.system(f"pkill -KILL -u {user} 2>/dev/null")
                                status_changed = True; expired = True
                                log_event(f"ACCOUNT EXPIRED: {user} locked.")
                                send_alert(f"🔒 <b>ACCOUNT EXPIRED</b>\n\n👤 User: <code>{user}</code>\n🛑 Account automatically locked.", f"{user}_exp")
                        except: pass
                    
                    if expired:
                        new_lines.append(f"{user}|EXPIRED|00:00|SSH\n")
                        continue

                    try:
                        ssh_procs = subprocess.getoutput(f"ps -u {user} -o comm= 2>/dev/null | grep -cE 'sshd|dropbear'")
                        total = int(ssh_procs) if ssh_procs.strip().isdigit() else 0
                        
                        if total > MAX_LOGIN:
                            os.system(f"killall -9 -u {user} 2>/dev/null")
                            os.system(f"pkill -KILL -u {user} 2>/dev/null")
                            log_event(f"MULTI-LOGIN KICK: {user} used {total} connections.")
                            send_alert(f"⚠️ <b>MULTI-LOGIN DETECTED</b>\n\n👤 User: <code>{user}</code>\n💻 Devices: {total}\n🛑 User has been kicked out.", f"{user}_multi")
                    except: pass
                    new_lines.append(line)
                
                if status_changed:
                    with open(DB_FILE, 'w') as f:
                        f.writelines(new_lines)
        except: pass
        time.sleep(3)

if __name__ == "__main__":
    check_loop()
EOF
chmod +x "$MONITOR_SCRIPT"

cat > /etc/systemd/system/kp_monitor.service << 'EOF'
[Unit]
Description=SSH Monitor & Alerts
After=network.target
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/kp_monitor.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kp_monitor >/dev/null 2>&1
systemctl restart kp_monitor

pause() { echo -e "\n${BLUE}PRESS [ENTER] TO RETURN...${NC}"; read; }

draw_header() {
    clear
    echo -e "${LINE}"
    echo -e "               ⚡ ${BLUE}SSH MANAGER${NC} ⚡"
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
    echo -e " ${BLUE}👤 USERNAME :${NC} ${WHITE}$u${NC}"
    echo -e " ${BLUE}🔑 PASSWORD :${NC} ${WHITE}$p${NC}"
    
    read -p " $(echo -e ${BLUE}⏳ Set Expiry Date? [Y/N] 🔴🟢 : ${NC})" exp_choice
    
    if [[ "${exp_choice,,}" == "y" ]]; then
        read -p " $(echo -e ${BLUE}📅 Enter Date and Time : ${NC})" dt_input
        d=$(echo "$dt_input" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
        t=$(echo "$dt_input" | grep -oE '[0-9]{2}:[0-9]{2}' | head -1)
        [[ -z "$d" ]] && d="NEVER"
        [[ -z "$t" ]] && t="00:00"
    else
        d="NEVER"
        t="00:00"
    fi
    
    useradd -M -s /bin/false "$u" >/dev/null 2>&1
    echo "$u:$p" | chpasswd >/dev/null 2>&1
    echo "$u|$d|$t|SSH" >> "$USER_DB"
    clear
    echo -e "${LINE}"
    echo -e "                    ${WHITE}ACCOUNT${NC} "
    echo -e "${LINE}"
    echo -e ""
    echo -e " ${BLUE}👤 Username :${NC} ${WHITE}$u${NC}"
    echo -e " ${BLUE}🔑 Password :${NC} ${WHITE}$p${NC}"
    echo -e " ${BLUE}📅 Expiry   :${NC} ${WHITE}$d${NC}"
    echo -e " ${BLUE}⏰ Time     :${NC} ${WHITE}$t${NC}"
    echo -e ""
    echo -e "${LINE}"
    echo -e " ${BLUE}📋 Copy     :${NC} ${WHITE}$u:$p${NC}"
    echo -e "${LINE}"
    pause
}

fun_renew() {
    draw_header
    echo -e "               🔄 ${BLUE}RENEW ACCOUNT${NC}"
    echo -e "${LINE}"
    read -p " $(echo -e ${BLUE}👤 USERNAME : ${NC})" u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "${RED} ❌ NOT FOUND!${NC}"; pause; return; fi
    
    read -p " $(echo -e ${BLUE}⏳ Set Expiry Date? [Y/N] 🔴🟢 : ${NC})" exp_choice
    if [[ "${exp_choice,,}" == "y" ]]; then
        read -p " $(echo -e ${BLUE}📅 Enter New Date and Time : ${NC})" dt_input
        d=$(echo "$dt_input" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
        t=$(echo "$dt_input" | grep -oE '[0-9]{2}:[0-9]{2}' | head -1)
        [[ -z "$d" ]] && d="NEVER"
        [[ -z "$t" ]] && t="23:59"
    else
        d="NEVER"
        t="00:00"
    fi
    
    sed -i "/^$u|/d" "$USER_DB"
    echo "$u|$d|$t|Renew" >> "$USER_DB"
    usermod -U "$u" >/dev/null 2>&1
    echo -e "${GREEN} ✅ RENEWED SUCCESSFULLY${NC}"; pause
}

fun_remove() {
    draw_header
    echo -e "               🗑️ ${BLUE}REMOVE USER${NC}"
    echo -e "${LINE}"
    read -p " $(echo -e ${BLUE}👤 USERNAME : ${NC})" u
    read -p " $(echo -e ${BLUE}⚠️ CONFIRM? [Y/N]: ${NC})" c
    if [[ "${c,,}" == "y" ]]; then
        pkill -KILL -u "$u" >/dev/null 2>&1
        userdel -f "$u" >/dev/null 2>&1
        sed -i "/^$u|/d" "$USER_DB"
        echo -e "${RED} 🗑️ DELETED SUCCESSFULLY${NC}"
    fi
    pause
}

fun_lock() {
    draw_header
    echo -e "               🔒 ${BLUE}LOCK/UNLOCK${NC}"
    echo -e "${LINE}"
    read -p " $(echo -e ${BLUE}👤 USERNAME : ${NC})" u
    echo -e " ${BLUE}[1] LOCK ⛔${NC}"
    echo -e " ${BLUE}[2] UNLOCK 🔓${NC}"
    read -p " $(echo -e ${BLUE}SELECT: ${NC})" s
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
    echo -e "               📋 ${BLUE}ALL USERS${NC}"
    echo -e "${LINE}"
    SHADOW_CACHE=$(cat /etc/shadow 2>/dev/null)
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             if [[ "$d" == "NEVER" || "$d" == "EXPIRED" ]]; then DATE_STR="$d"; else DATE_STR="$d $t"; fi
             if echo "$SHADOW_CACHE" | grep -q "^${u}:!"; then LOCK_STAT="⛔"; else LOCK_STAT="  "; fi
             printf " ${BLUE}👤 %-12s${NC} %s ${BLUE}📅 %s${NC}\n" "$u" "$LOCK_STAT" "$DATE_STR"
        fi
    done < "$USER_DB"
    echo -e "${LINE}"
    pause
}

fun_monitor_view() {
    clear
    echo -e "${LINE}"
    echo -e "               🔘 ${BLUE}LIVE MONITOR${NC}"
    echo -e "${LINE}"
    ACTIVE_PROCS=$(ps -eo user,comm 2>/dev/null | grep -E 'sshd|dropbear')
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             if echo "$ACTIVE_PROCS" | grep -q "^${u} "; then
                STATUS="${GREEN}🟢 ONLINE${NC}"
             else
                STATUS="${RED}🔴 OFFLINE${NC}"
             fi
             printf " ${BLUE}👤 %-12s${NC}   %s\n" "$u" "$STATUS"
        fi
    done < "$USER_DB"
    echo -e "${LINE}"
    pause
}

fun_backup() {
    draw_header
    echo -e "               💾 ${BLUE}SAVE DATA${NC}"
    echo -e "${LINE}"
    cp "$USER_DB" "$BACKUP_DIR/users_backup_$(date +%F).txt"
    echo -e "${GREEN} ✅ BACKUP SAVED IN $BACKUP_DIR${NC}"
    pause
}

fun_export_users() {
    draw_header; echo -e "${BLUE} 📤 EXPORTING USERS...${NC}"
    cp "$USER_DB" "$MIGRATION_FILE"
    echo -e "${GREEN} ✅ EXPORT SUCCESSFUL!${NC}\n FILE: $MIGRATION_FILE\n UPLOAD THIS TO NEW SERVER."; pause
}

fun_import_users() {
    draw_header; echo -e "${BLUE} 📥 RESTORING USERS...${NC}"
    if [[ ! -f "$MIGRATION_FILE" ]]; then echo -e "${RED} ❌ FILE NOT FOUND ($MIGRATION_FILE)${NC}"; pause; return; fi
    count=0
    while IFS='|' read -r u d t tag; do
        [[ -z "$u" ]] && continue
        if ! id "$u" &>/dev/null; then
            useradd -M -s /bin/false "$u" >/dev/null 2>&1; echo "$u:12345" | chpasswd >/dev/null 2>&1
            echo -e " CREATED: ${GREEN}$u${NC}"; ((count++))
        fi
    done < "$MIGRATION_FILE"
    cat "$MIGRATION_FILE" > "$USER_DB"
    echo -e "${GREEN} ✅ RESTORED: $count USERS${NC}"; pause
}

fun_settings() {
    while true; do
        draw_header
        echo -e "            ⚙️ ${BLUE}SETTINGS & MIGRATION${NC}"
        echo -e "${LINE}"
        echo -e " ${BLUE}[1] 🛠️ INSTALL BOT${NC}"
        echo -e " ${BLUE}[2] 🌍 SET TIMEZONE${NC}"
        echo -e " ${BLUE}[3] 📤 EXPORT USERS${NC}"
        echo -e " ${BLUE}[4] 📥 RESTORE USERS${NC}"
        echo -e " ${BLUE}[5] 🔙 BACK${NC}"
        echo -e "${LINE}"
        read -p " $(echo -e ${BLUE}SELECT: ${NC})" s
        case "$s" in
            1) fun_install_bot ;;
            2) timedatectl set-timezone Africa/Tunis; echo -e "${GREEN} ✅ TIMEZONE SET TO TUNIS${NC}"; pause ;;
            3) fun_export_users ;;
            4) fun_import_users ;;
            5) break ;;
        esac
    done
}

fun_violations() {
    clear
    echo -e "${LINE}"
    echo -e "         🔔 ${BLUE}ALERTS LOG (VIOLATIONS)${NC}"
    echo -e "${LINE}"
    echo -e ""
    if [ -f "$LOG_FILE" ]; then
        ALERTS=$(grep "MULTI-LOGIN KICK" "$LOG_FILE" | tail -n 15)
        if [[ -z "$ALERTS" ]]; then
            echo -e " ${GREEN}✅ NO VIOLATIONS DETECTED YET.${NC}"
        else
            while read -r line; do
                echo -e " ${RED}⚠️  $line${NC}"
            done <<< "$ALERTS"
        fi
    else
        echo -e " ${YELLOW}LOG FILE IS EMPTY.${NC}"
    fi
    echo -e ""
    echo -e "${LINE}"
    pause
}

fun_bulk_create() {
    draw_header
    echo -e "               📦 ${BLUE}BULK CREATE${NC}"
    echo -e "${LINE}"
    read -p " $(echo -e ${BLUE}🔢 How many accounts? : ${NC})" count
    if ! [[ "$count" =~ ^[0-9]+$ ]]; then echo -e "${RED} INVALID NUMBER!${NC}"; pause; return; fi
    echo -e " ${YELLOW}Creating $count accounts... Please wait...${NC}"
    created=0
    i=1
    while [ $created -lt "$count" ]; do
        u="USER${i}"
        if ! id "$u" &>/dev/null && ! grep -q "^$u|" "$USER_DB"; then
            useradd -M -s /bin/false "$u" >/dev/null 2>&1
            echo "$u:12345" | chpasswd >/dev/null 2>&1
            echo "$u|NEVER|00:00|SSH" >> "$USER_DB"
            ((created++))
            echo -e " ✅ Created: ${WHITE}$u${NC} (Pass: 12345)"
        fi
        ((i++))
    done
    echo -e "${LINE}"
    echo -e "${GREEN} ✅ $count ACCOUNTS CREATED SUCCESSFULLY!${NC}"
    pause
}

fun_install_bot() {
    pkill -f ssh_bot.py
    systemctl stop sshbot >/dev/null 2>&1
    clear; echo -e "${BLUE}INSTALLING BOT WITH SMART LOCK & BULK FEATURE...${NC}"
    pip3 install python-telegram-bot==13.7 schedule requests --break-system-packages >/dev/null 2>&1 || \
    pip3 install python-telegram-bot==13.7 schedule requests >/dev/null 2>&1
    echo "BOT_TOKEN=\"$MY_TOKEN\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$MY_ID\"" >> "$BOT_CONF"
    echo "ALERTS=\"ON\"" >> "$BOT_CONF"
    chmod 600 "$BOT_CONF"
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, re
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(message)s')
CONF_FILE = "/etc/xpanel/bot.conf"
DB_FILE = "/etc/xpanel/users_db.txt"
TLINE = "============================"

def load_config():
    c = {}
    try:
        for l in open(CONF_FILE):
            if "=" in l: k, v = l.strip().split("=", 1); c[k] = v.strip().replace('"', '')
    except: pass
    return c

cfg = load_config(); TOKEN = cfg.get("BOT_TOKEN"); ADMIN_ID = int(cfg.get("ADMIN_ID", 0))

def get_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 ADD USER", callback_data='add'), InlineKeyboardButton("📦 BULK CREATE", callback_data='bulk')],
        [InlineKeyboardButton("🔄 RENEW", callback_data='ren'), InlineKeyboardButton("🗑️ REMOVE", callback_data='del')],
        [InlineKeyboardButton("🔒 LOCK / UNLOCK", callback_data='lock_menu')],
        [InlineKeyboardButton("📋 ALL USERS", callback_data='list')],
        [InlineKeyboardButton("🔘 MONITOR", callback_data='onl')],
        [InlineKeyboardButton("💾 SAVE DATA", callback_data='bak')],
        [InlineKeyboardButton("⚙️ SETTINGS", callback_data='bot_set')]
    ])

def get_settings_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("💻 Server Info", callback_data='set_info')],
        [InlineKeyboardButton("🔄 Restart Monitor", callback_data='set_mon')],
        [InlineKeyboardButton("🚀 Migration", callback_data='migrate')],
        [InlineKeyboardButton("🔙 BACK", callback_data='back')]
    ])

def get_back_btn():
    return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]])

def start(u, c):
    if u.effective_user.id == ADMIN_ID: u.message.reply_text(f"⚡ <b>SSH MANAGER</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu())

def btn(u, c):
    q = u.callback_query; q.answer(); d = q.data
    if d == 'back': c.user_data.clear(); q.edit_message_text(f"⚡ <b>SSH MANAGER</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu()); return
    try:
        if d == 'add':
            i = 1
            while True:
                usr = f"USER{i}"
                if subprocess.run(f"id {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0: break
                i += 1
            c.user_data['u'] = usr
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='add_yes'), InlineKeyboardButton("🔴 NO", callback_data='add_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            q.edit_message_text(f"👤 Username: <code>{usr}</code>\n\n⏳ <b>Set Expiry Date?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
            
        elif d == 'add_yes':
            c.user_data['act'] = 'a_datetime'
            q.edit_message_text(f"👤 Username : <code>{c.user_data['u']}</code>\n🔑 Password  : <code>12345</code>\n\n📅 <b>Enter Date and Time :</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'add_no':
            usr = c.user_data['u']; pwd = "12345"; dt = "NEVER"; tm = "00:00"
            subprocess.run(f"useradd -M -s /bin/false {usr}", shell=True, stdout=subprocess.DEVNULL); subprocess.run(f"echo '{usr}:{pwd}' | chpasswd", shell=True, stdout=subprocess.DEVNULL)
            open(DB_FILE, 'a').write(f"{usr}|{dt}|{tm}|SSH\n")
            resp = (f"<b>{TLINE}</b>\n           <b>ACCOUNT</b>          \n<b>{TLINE}</b>\n\n👤 Username : <code>{usr}</code>\n🔑 Password : <code>{pwd}</code>\n📅 Expiry   : <code>{dt}</code>\n⏰ Time     : <code>{tm}</code>\n\n<b>{TLINE}</b>\n📋 Copy     : <code>{usr}:{pwd}</code>\n<b>{TLINE}</b>")
            q.edit_message_text(resp, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'bulk':
            c.user_data['act'] = 'bulk_amt'
            q.edit_message_text("📦 <b>Enter the number of accounts to create:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'ren': 
            c.user_data['act']='r_user'
            q.edit_message_text("🔄 <b>Enter Username to Renew:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'ren_yes':
            c.user_data['act'] = 'r_val'
            q.edit_message_text("📅 <b>Enter New Date and Time :</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'ren_no':
            usr = c.user_data.get('ru')
            lines = [l for l in open(DB_FILE) if not l.startswith(f"{usr}|")]
            lines.append(f"{usr}|NEVER|00:00|Renew\n")
            open(DB_FILE, 'w').writelines(lines)
            subprocess.run(f"usermod -U {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            q.edit_message_text(f"✅ <b>RENEWED & UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'del': 
            c.user_data['act']='d1'
            q.edit_message_text("🗑️ <b>Username to Delete:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'del_yes':
            usr = c.user_data.get('del_u')
            if usr:
                os.system(f"killall -9 -u {usr} 2>/dev/null; pkill -KILL -u {usr} 2>/dev/null")
                subprocess.run(f"userdel -f {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if os.path.exists(DB_FILE):
                    lines = [l for l in open(DB_FILE) if not l.startswith(f"{usr}|")]
                    open(DB_FILE, 'w').writelines(lines)
                q.edit_message_text(f"🗑️ <b>DELETED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
                
        elif d == 'del_no':
            q.edit_message_text("❌ <b>Deletion Cancelled.</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'lock_menu':
            c.user_data['act']='lu_user'
            q.edit_message_text("🔒/🔓 <b>Enter Username to Lock or Unlock:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d.startswith('do_lock_'):
            usr = d.split('_', 2)[2]
            subprocess.run(f"usermod -L {usr}", shell=True, stdout=subprocess.DEVNULL)
            os.system(f"killall -9 -u {usr} 2>/dev/null; pkill -KILL -u {usr} 2>/dev/null")
            q.edit_message_text(f"⛔ <b>LOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d.startswith('do_unlock_'):
            usr = d.split('_', 2)[2]
            subprocess.run(f"usermod -U {usr}", shell=True, stdout=subprocess.DEVNULL)
            q.edit_message_text(f"🔓 <b>UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'list':
            if os.path.exists(DB_FILE):
                try: shadow_data = open('/etc/shadow', 'r').read()
                except: shadow_data = ""
                
                valid_lines = [l.strip().split('|') for l in open(DB_FILE) if len(l.strip().split('|')) >= 3 and "root" not in l]
                if not valid_lines:
                    q.edit_message_text("No users found.", reply_markup=get_back_btn())
                    return
                
                chunk_size = 100
                chunks = [valid_lines[i:i + chunk_size] for i in range(0, len(valid_lines), chunk_size)]
                
                for idx, chunk in enumerate(chunks):
                    total_pages = len(chunks)
                    if total_pages > 1:
                        pg_str = f"ALL USERS (Page {idx+1}/{total_pages})"
                        sp_l = max(0, (28 - len(pg_str)) // 2)
                        sp_r = max(0, 28 - len(pg_str) - sp_l)
                        header = f"<b>{TLINE}</b>\n{' '*sp_l}<b>{pg_str}</b>{' '*sp_r}\n<b>{TLINE}</b>\n\n"
                    else:
                        header = f"<b>{TLINE}</b>\n         <b>ALL USERS</b>         \n<b>{TLINE}</b>\n\n"
                        
                    body = header
                    for p in chunk:
                        usr, date, tm = p[0], p[1], p[2]
                        date_str = date if date in ["NEVER", "EXPIRED"] else f"{date} {tm}"
                        lock_icon = " ⛔" if f"\n{usr}:!" in shadow_data or shadow_data.startswith(f"{usr}:!") else ""
                        body += f"👤 <code>{usr}</code>{lock_icon}\n📅 <code>{date_str}</code>\n\n"
                    
                    if idx == 0:
                        q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if total_pages == 1 else None)
                    else:
                        c.bot.send_message(chat_id=u.effective_chat.id, text=body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if idx == total_pages - 1 else None)
            else:
                q.edit_message_text("No users found.", reply_markup=get_back_btn())

        elif d == 'onl':
            if os.path.exists(DB_FILE):
                try:
                    active_users_raw = subprocess.getoutput("ps -eo user,comm | grep -E 'sshd|dropbear' | awk '{print $1}'").split()
                    active_set = set(active_users_raw)
                except: active_set = set()
                
                valid_lines = [l.strip().split('|')[0] for l in open(DB_FILE) if len(l.strip().split('|')) >= 3 and "root" not in l]
                if not valid_lines:
                    q.edit_message_text("No users found.", reply_markup=get_back_btn())
                    return
                
                chunk_size = 100
                chunks = [valid_lines[i:i + chunk_size] for i in range(0, len(valid_lines), chunk_size)]
                
                for idx, chunk in enumerate(chunks):
                    total_pages = len(chunks)
                    if total_pages > 1:
                        pg_str = f"LIVE MONITOR (Page {idx+1}/{total_pages})"
                        sp_l = max(0, (28 - len(pg_str)) // 2)
                        sp_r = max(0, 28 - len(pg_str) - sp_l)
                        header = f"<b>{TLINE}</b>\n{' '*sp_l}<b>{pg_str}</b>{' '*sp_r}\n<b>{TLINE}</b>\n\n"
                    else:
                        header = f"<b>{TLINE}</b>\n        <b>LIVE MONITOR</b>        \n<b>{TLINE}</b>\n\n"
                        
                    body = header
                    for usr in chunk:
                        st = "🟢 ONLINE" if usr in active_set else "🔴 OFFLINE"
                        body += f"👤 <code>{usr}</code>\n{st}\n\n"
                    
                    if idx == 0:
                        q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if total_pages == 1 else None)
                    else:
                        c.bot.send_message(chat_id=u.effective_chat.id, text=body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if idx == total_pages - 1 else None)
            else:
                q.edit_message_text("No users found.", reply_markup=get_back_btn())

        elif d == 'bak':
            if os.path.exists(DB_FILE): c.bot.send_document(ADMIN_ID, open(DB_FILE, 'rb'))
            q.edit_message_text("✅ <b>DATA SAVED & SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'bot_set':
            q.edit_message_text("⚙️ <b>SETTINGS</b>\nChoose an option:", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'set_info':
            try:
                up = subprocess.getoutput("uptime -p")
                ram = subprocess.getoutput("free -m | awk 'NR==2{printf \"%.2f%%\", $3*100/$2 }'")
                cpu = subprocess.getoutput("top -bn1 | grep load | awk '{printf \"%.2f%%\", $(NF-2)}'")
                msg = f"💻 <b>SERVER INFO</b>\n\n⏱ <b>Uptime:</b> {up}\n🧠 <b>RAM:</b> {ram}\n⚙️ <b>CPU Load:</b> {cpu}"
            except: msg = "💻 <b>SERVER INFO</b>\nError fetching info."
            q.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'set_mon':
            subprocess.run("systemctl restart kp_monitor", shell=True)
            q.edit_message_text("✅ <b>Monitor Restarted!</b>", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'migrate':
            if os.path.exists(DB_FILE):
                subprocess.run(f"cp {DB_FILE} {MIGRATION_FILE}", shell=True)
                c.bot.send_document(ADMIN_ID, open(MIGRATION_FILE, 'rb'), caption="🚀 <b>MIGRATION FILE</b>", parse_mode=ParseMode.HTML)
                q.edit_message_text("✅ <b>MIGRATION FILE SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
    except: pass

def txt(u, c):
    if u.effective_user.id != ADMIN_ID: return
    msg = u.message.text; act = c.user_data.get('act')
    try:
        if act == 'bulk_amt':
            if not msg.isdigit():
                u.message.reply_text("❌ <b>Invalid Number.</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
                return
            count = int(msg)
            if count > 150: count = 150
            u.message.reply_text(f"⏳ <b>Creating {count} accounts... Please wait.</b>", parse_mode=ParseMode.HTML)
            created = 0
            i = 1
            db_content = open(DB_FILE, 'r').read() if os.path.exists(DB_FILE) else ""
            new_entries = []
            while created < count:
                usr = f"USER{i}"
                if subprocess.run(f"id {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0 and f"{usr}|" not in db_content:
                    subprocess.run(f"useradd -M -s /bin/false {usr}", shell=True, stdout=subprocess.DEVNULL)
                    subprocess.run(f"echo '{usr}:12345' | chpasswd", shell=True, stdout=subprocess.DEVNULL)
                    new_entries.append(f"{usr}|NEVER|00:00|SSH\n")
                    created += 1
                i += 1
            open(DB_FILE, 'a').writelines(new_entries)
            u.message.reply_text(f"✅ <b>Successfully created {count} accounts!</b>\nAll set to <b>NEVER</b> expiry.", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            c.user_data['act'] = ''

        elif act == 'lu_user':
            usr = msg
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🔒 LOCK", callback_data=f"do_lock_{usr}"), InlineKeyboardButton("🔓 UNLOCK", callback_data=f"do_unlock_{usr}")],[InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"Select action for <b>{usr}</b>:", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''
        
        elif act == 'r_user':
            c.user_data['ru'] = msg
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='ren_yes'), InlineKeyboardButton("🔴 NO", callback_data='ren_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"⏳ <b>Set Expiry Date for {msg}?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''

        elif act == 'a_datetime':
            usr = c.user_data['u']; pwd = "12345"
            dm = re.search(r'\d{4}-\d{2}-\d{2}', msg); tm = re.search(r'\d{2}:\d{2}', msg)
            d = dm.group(0) if dm else "NEVER"; t = tm.group(0) if tm else "00:00"
            subprocess.run(f"useradd -M -s /bin/false {usr}", shell=True, stdout=subprocess.DEVNULL); subprocess.run(f"echo '{usr}:{pwd}' | chpasswd", shell=True, stdout=subprocess.DEVNULL)
            open(DB_FILE, 'a').write(f"{usr}|{d}|{t}|SSH\n")
            resp = (f"<b>{TLINE}</b>\n           <b>ACCOUNT</b>          \n<b>{TLINE}</b>\n\n👤 Username : <code>{usr}</code>\n🔑 Password : <code>{pwd}</code>\n📅 Expiry   : <code>{d}</code>\n⏰ Time     : <code>{t}</code>\n\n<b>{TLINE}</b>\n📋 Copy     : <code>{usr}:{pwd}</code>\n<b>{TLINE}</b>")
            u.message.reply_text(resp, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif act == 'r_val':
            usr = c.user_data.get('ru'); dm = re.search(r'\d{4}-\d{2}-\d{2}', msg); tm = re.search(r'\d{2}:\d{2}', msg)
            d = dm.group(0) if dm else "NEVER"; t = tm.group(0) if tm else "23:59"
            lines = [l for l in open(DB_FILE) if not l.startswith(f"{usr}|")]
            lines.append(f"{usr}|{d}|{t}|Renew\n")
            open(DB_FILE, 'w').writelines(lines)
            subprocess.run(f"usermod -U {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            u.message.reply_text(f"✅ <b>RENEWED & UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif act == 'd1':
            usr_to_del = msg
            c.user_data['del_u'] = usr_to_del
            kb = InlineKeyboardMarkup([
                [InlineKeyboardButton("🟢 YES", callback_data='del_yes'), InlineKeyboardButton("🔴 NO", callback_data='del_no')],
                [InlineKeyboardButton("🔙 BACK", callback_data='back')]
            ])
            u.message.reply_text(f"⚠️ <b>Are you sure you want to delete</b> <code>{usr_to_del}</code><b>?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''
            
    except: pass

def main():
    if not TOKEN: return
    up = Updater(TOKEN, use_context=True)
    up.dispatcher.add_handler(CommandHandler('start', start))
    up.dispatcher.add_handler(CallbackQueryHandler(btn)); up.dispatcher.add_handler(MessageHandler(Filters.text, txt))
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
    systemctl daemon-reload; systemctl enable sshbot >/dev/null 2>&1; systemctl restart sshbot
    echo -e "${GREEN}✅ BOT INSTALLED SUCCESSFULLY!${NC}"; pause
}

while true; do
    draw_header
    echo -e " ${BLUE}[1] 👤 ADD ACCOUNT${NC}"
    echo -e " ${BLUE}[2] 🔄 RENEW ACCOUNT${NC}"
    echo -e " ${BLUE}[3] 🗑️ REMOVE ACCOUNT${NC}"
    echo -e " ${BLUE}[4] 🔐 LOCK ACCOUNT${NC}"
    echo -e " ${BLUE}[5] 📋 LIST ACCOUNTS${NC}"
    echo -e " ${BLUE}[6] 🔘 MONITOR USERS${NC}"
    echo -e " ${BLUE}[7] 💾 BACKUP DATA${NC}"
    echo -e " ${BLUE}[8] 🔔 ALERTS LOG${NC}"
    echo -e " ${BLUE}[9] ⚙️ SETTINGS${NC}"
    echo -e " ${BLUE}[10] 📦 BULK CREATE${NC}"
    echo -e " ${BLUE}[0] 🚪 EXIT${NC}"
    echo -e "${LINE}"
    echo -e " ${BLUE}SELECT:${NC}"
    echo -e "${LINE}"
    read o
    case "$o" in
        1|01) fun_create ;; 
        2|02) fun_renew ;; 
        3|03) fun_remove ;; 
        4|04) fun_lock ;;
        5|05) fun_list ;; 
        6|06) fun_monitor_view ;; 
        7|07) fun_backup ;; 
        8|08) fun_violations ;; 
        9|09) fun_settings ;; 
        10) fun_bulk_create ;; 
        0|00) exit 0 ;;
        *) echo -e "${RED} INVALID OPTION!${NC}" ; sleep 1 ;;
    esac
done
