#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# =============================================
# 1. AUTO-CONFIGURE SSHD (MAX SESSIONS = 1)
# =============================================
SSHD_CONF="/etc/ssh/sshd_config"
echo -e "\n\033[1;36m⚙️ Checking SSHD Configurations...\033[0m"
grep -q "^MaxSessions" "$SSHD_CONF" && sed -i 's/^MaxSessions.*/MaxSessions 1/' "$SSHD_CONF" || echo "MaxSessions 1" >> "$SSHD_CONF"
grep -q "^ClientAliveInterval" "$SSHD_CONF" && sed -i 's/^ClientAliveInterval.*/ClientAliveInterval 30/' "$SSHD_CONF" || echo "ClientAliveInterval 30" >> "$SSHD_CONF"
grep -q "^ClientAliveCountMax" "$SSHD_CONF" && sed -i 's/^ClientAliveCountMax.*/ClientAliveCountMax 2/' "$SSHD_CONF" || echo "ClientAliveCountMax 2" >> "$SSHD_CONF"
systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1

if [ -f /etc/os-release ]; then . /etc/os-release; OS=$ID; else OS="Unknown"; fi
if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS" == "kali" ]]; then CMD="apt-get update -y && apt-get install -y"
else CMD="yum install -y"; fi

USER_DB="/etc/xpanel/users_db.txt"
BOT_CONF="/etc/xpanel/bot.conf"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.py"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"
MIGRATION_FILE="/root/migration_users.txt"
VENV_DIR="/etc/xpanel/venv"
PYTHON_BIN="$VENV_DIR/bin/python3"
PIP_BIN="$VENV_DIR/bin/pip3"

RED=$'\033[1;31m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'; CYAN=$'\033[1;36m'; NC=$'\033[0m'; WHITE=$'\033[1;37m'
LINE="${BLUE}===============================================${NC}"

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"
[[ ! -f "$BOT_CONF" ]] && touch "$BOT_CONF"

if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null || ! command -v virtualenv &> /dev/null; then
    $CMD python3 python3-pip python3-venv systemd-logind > /dev/null 2>&1
fi

if [ ! -d "$VENV_DIR" ]; then python3 -m venv "$VENV_DIR"; fi

is_number() { [[ $1 =~ ^[0-9]+$ ]]; }

# =============================================
# 2. AUTO-BURN & EXPIRY MONITOR (PYTHON)
# =============================================
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/usr/bin/env python3
import datetime, subprocess, os, time, fcntl
import urllib.request, urllib.parse

DB_FILE = "/etc/xpanel/users_db.txt"
CONF_FILE = "/etc/xpanel/bot.conf"
LOG_FILE = "/var/log/kp_manager.log"

def log_event(msg):
    try:
        ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        with open(LOG_FILE, "a") as f: f.write(f"[{ts}] {msg}\n")
    except: pass

def kill_user(user):
    subprocess.run(["loginctl", "terminate-user", user], stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-KILL", "-u", user], stderr=subprocess.DEVNULL)

def check_loop():
    while True:
        try:
            if os.path.exists(DB_FILE):
                with open(DB_FILE, 'r+') as f:
                    fcntl.flock(f, fcntl.LOCK_EX)
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

                        # إصلاح مشكلة الأونلاين والأسماء الطويلة
                        try:
                            ssh_c = subprocess.getoutput(f"pgrep -c -u {user} sshd")
                            db_c = subprocess.getoutput(f"pgrep -c -u {user} dropbear")
                            total = (int(ssh_c) if ssh_c.isdigit() else 0) + (int(db_c) if db_c.isdigit() else 0)
                        except: total = 0

                        # ميزة التفعيل عند أول دخول
                        if "ACTIVATE" in exp_date and total > 0:
                            try: days_to_add = int(exp_date.split(":")[1])
                            except: days_to_add = 1
                            expiry_dt = now + datetime.timedelta(days=days_to_add)
                            exp_date = expiry_dt.strftime("%Y-%m-%d")
                            exp_time = expiry_dt.strftime("%H:%M")
                            line = f"{user}|{exp_date}|{exp_time}\n"
                            status_changed = True
                            log_event(f"⚡ ACTIVATED: {user} started connection. Set to {days_to_add} days.")

                        # ميزة الحرق التلقائي الصارم (>1)
                        if total > 1:
                            subprocess.run(["usermod", "-L", user], stderr=subprocess.DEVNULL)
                            kill_user(user)
                            line = f"{user}|BURNED|00:00\n"
                            status_changed = True
                            log_event(f"🔥 BURNED: {user} caught with {total} connections. Locked.")

                        # فحص انتهاء الاشتراك العادي
                        if exp_date not in ["NEVER", "EXPIRED", "BURNED"] and "ACTIVATE" not in exp_date:
                            try:
                                exp = datetime.datetime.strptime(f"{exp_date} {exp_time}", "%Y-%m-%d %H:%M")
                                if now >= exp:
                                    subprocess.run(["usermod", "-L", user], stderr=subprocess.DEVNULL)
                                    kill_user(user)
                                    line = f"{user}|EXPIRED|00:00\n"
                                    status_changed = True
                                    log_event(f"🔒 EXPIRED: {user} locked.")
                            except: pass
                        
                        new_lines.append(line)
                    
                    if status_changed:
                        f.seek(0)
                        f.writelines(new_lines)
                        f.truncate()
                    
                    fcntl.flock(f, fcntl.LOCK_UN)
        except: pass
        time.sleep(10)

if __name__ == "__main__":
    check_loop()
EOF
chmod +x "$MONITOR_SCRIPT"

cat > /etc/systemd/system/kp_monitor.service << EOF
[Unit]
Description=SSH Smart Monitor V15
After=network.target
[Service]
ExecStart=$PYTHON_BIN /usr/local/bin/kp_monitor.py
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
    echo -e "             ⚡ ${BLUE}SSH MANAGER V15 (ULTIMATE)${NC} ⚡"
    echo -e "${LINE}"
}

# =============================================
# 3. BASH MENU FUNCTIONS
# =============================================
fun_create() {
    draw_header
    echo -ne " ${BLUE}👤 Enter Username/Phone : ${NC}"
    read u
    if [[ -z "$u" ]]; then echo -e "\n${RED} ❌ Username cannot be empty!${NC}"; pause; return; fi
    if [[ ! "$u" =~ ^[a-zA-Z0-9_]+$ ]]; then echo -e "\n${RED} ❌ Invalid Username! Use only letters and numbers.${NC}"; pause; return; fi
    if id "$u" &>/dev/null || grep -q "^$u|" "$USER_DB"; then echo -e "\n${RED} ❌ USER ALREADY EXISTS!${NC}"; pause; return; fi

    echo -ne " ${BLUE}🔑 Enter Password : ${NC}"
    read p
    if [[ -z "$p" ]]; then echo -e "\n${RED} ❌ Password cannot be empty!${NC}"; pause; return; fi
    
    echo -ne " ${BLUE}📅 Enter Number of Days (e.g., 1, 7, 30): ${NC}"
    read days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then days=1; fi
    
    d="ACTIVATE:$days"
    t="00:00"
    
    useradd -M -s /bin/false "$u" >/dev/null 2>&1
    echo "$u:$p" | chpasswd >/dev/null 2>&1
    
    (
        flock -x 200
        echo "$u|$d|$t" >> "$USER_DB"
    ) 200>"/etc/xpanel/.db.lock"

    clear
    echo -e "${LINE}\n                 ${WHITE}ACCOUNT CREATED${NC}\n${LINE}\n"
    echo -e " ${BLUE}👤 Username :${NC} ${WHITE}$u${NC}\n ${BLUE}🔑 Password :${NC} ${WHITE}$p${NC}"
    echo -e " ${BLUE}📅 Status   :${NC} ${YELLOW}WAITING ($days Days)${NC}\n\n${LINE}"
    echo -e " ${BLUE}📋 Copy     :${NC} ${WHITE}$u:$p${NC}\n${LINE}"
    pause
}

fun_renew() {
    draw_header
    echo -e "               🔄 ${BLUE}RENEW ACCOUNT${NC}\n${LINE}"
    echo -ne " ${BLUE}👤 USERNAME : ${NC}"
    read u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "\n${RED} ❌ NOT FOUND!${NC}"; pause; return; fi
    
    echo -ne " ${BLUE}📅 Enter New Number of Days (e.g., 30): ${NC}"
    read days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then days=1; fi
    
    d="ACTIVATE:$days"
    t="00:00"
    
    (
        flock -x 200
        sed -i "/^$u|/d" "$USER_DB"
        echo "$u|$d|$t" >> "$USER_DB"
    ) 200>"/etc/xpanel/.db.lock"

    usermod -U "$u" >/dev/null 2>&1
    echo -e "\n${GREEN} ✅ RENEWED SUCCESSFULLY! Set to Waiting ($days Days)${NC}"; pause
}

fun_remove() {
    draw_header
    echo -e "               🗑️ ${BLUE}DELETE ACCOUNT${NC}\n${LINE}"
    echo -ne " ${BLUE}👤 USERNAME : ${NC}"
    read u
    echo -ne " ${BLUE}⚠️ CONFIRM? [Y/N]: ${NC}"
    read c
    if [[ "${c,,}" == "y" ]]; then
        loginctl terminate-user "$u" >/dev/null 2>&1
        pkill -KILL -u "$u" >/dev/null 2>&1
        userdel -f "$u" >/dev/null 2>&1
        ( flock -x 200; sed -i "/^$u|/d" "$USER_DB" ) 200>"/etc/xpanel/.db.lock"
        echo -e "\n${RED} 🗑️ DELETED SUCCESSFULLY${NC}"
    fi
    pause
}

fun_lock() {
    draw_header
    echo -e "               🔒 ${BLUE}LOCK ACCOUNT${NC}\n${LINE}"
    echo -ne " ${BLUE}👤 USERNAME : ${NC}"
    read u
    echo -e " ${BLUE}[1] LOCK ⛔${NC}\n ${BLUE}[2] UNLOCK 🔓${NC}"
    echo -ne " ${BLUE}SELECT: ${NC}"
    read s
    if [[ "$s" == "1" ]]; then
        usermod -L "$u" >/dev/null 2>&1; loginctl terminate-user "$u" >/dev/null 2>&1; pkill -KILL -u "$u" >/dev/null 2>&1; echo -e "\n${GREEN} ⛔ LOCKED${NC}"
    else
        usermod -U "$u" >/dev/null 2>&1; echo -e "\n${GREEN} 🔓 UNLOCKED${NC}"
    fi
    pause
}

fun_list() {
    clear
    echo -e "${LINE}\n               📋 ${BLUE}LIST ACCOUNTS${NC}\n${LINE}"
    SHADOW_CACHE=$(cat /etc/shadow 2>/dev/null)
    printf " ${BLUE}%-15s %-20s %-10s${NC}\n" "USERNAME" "EXPIRY/STATUS" "LOCK"
    echo -e "${LINE}"
    while IFS='|' read -r u d t rest; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             if [[ "$d" == *"ACTIVATE"* ]]; then 
                days_w=$(echo $d | cut -d: -f2); DATE_STR="${YELLOW}WAITING (${days_w}d)${NC}"
             elif [[ "$d" == "BURNED" ]]; then DATE_STR="${RED}🔥 BURNED${NC}"
             elif [[ "$d" == "EXPIRED" ]]; then DATE_STR="${RED}🔒 EXPIRED${NC}"
             else DATE_STR="${GREEN}$d $t${NC}"; fi
             
             if echo "$SHADOW_CACHE" | grep -q "^${u}:!"; then LOCK_STAT="⛔"; else LOCK_STAT="✅"; fi
             printf " %-15s %-20s %-10s\n" "$u" "$DATE_STR" "$LOCK_STAT"
        fi
    done < "$USER_DB"
    echo -e "${LINE}"
    pause
}

fun_monitor_view() {
    clear
    echo -e "${LINE}\n               👁 ${BLUE}LIVE MONITOR${NC}\n${LINE}"
    # إصلاح الأونلاين: استخراج الأسماء بدقة حتى 30 حرف (euser:30)
    ACTIVE_PROCS=$(ps -eo euser:30,comm 2>/dev/null | grep -E 'sshd|dropbear')
    while IFS='|' read -r u d t rest; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             # المطابقة الآمنة للاسم
             if echo "$ACTIVE_PROCS" | grep -qw "$u"; then
                 STATUS="${GREEN}🟢 ONLINE${NC}"
             else
                 STATUS="${RED}🔴 OFFLINE${NC}"
             fi
             printf " ${BLUE}👤 %-15s${NC}   %s\n" "$u" "$STATUS"
        fi
    done < "$USER_DB"
    echo -e "${LINE}"
    pause
}

fun_backup() {
    draw_header
    echo -e "               💾 ${BLUE}BACKUP DATA${NC}\n${LINE}"
    cp "$USER_DB" "$BACKUP_DIR/users_backup_$(date +%F).txt"
    echo -e "${GREEN} ✅ BACKUP SAVED IN $BACKUP_DIR${NC}"; pause
}

fun_export_users() {
    draw_header; echo -e "${BLUE} 📤 EXPORTING USERS...${NC}"
    cp "$USER_DB" "$MIGRATION_FILE"
    echo -e "${GREEN} ✅ EXPORT SUCCESSFUL!${NC}\n FILE: $MIGRATION_FILE"; pause
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
    echo -e "\n${GREEN} ✅ RESTORED: $count USERS${NC}"; pause
}

fun_violations() {
    clear
    echo -e "${LINE}\n         🔔 ${BLUE}ALERTS LOG (BURNED ACCOUNTS)${NC}\n${LINE}\n"
    if [ -f "$LOG_FILE" ]; then
        ALERTS=$(grep "BURNED" "$LOG_FILE" | tail -n 15)
        if [[ -z "$ALERTS" ]]; then echo -e " ${GREEN}✅ NO VIOLATIONS DETECTED YET.${NC}"
        else
            while read -r line; do echo -e " ${RED}⚠️  $line${NC}"; done <<< "$ALERTS"
        fi
    else
        echo -e " ${YELLOW}LOG FILE IS EMPTY.${NC}"
    fi
    echo -e "\n${LINE}"; pause
}

# =============================================
# 4. TELEGRAM BOT INSTALLER (UPDATED V15)
# =============================================
fun_install_bot() {
    clear; echo -e "${BLUE}INSTALLING SECURE BOT ENVIRONMENT...${NC}"
    echo -ne " ${BLUE}🤖 Enter your Telegram Bot Token: ${NC}"; read -r input_token
    [[ -z "$input_token" ]] && return
    echo -ne " ${BLUE}👤 Enter your Telegram Admin ID: ${NC}"; read -r input_id
    [[ -z "$input_id" ]] && return

    pkill -f ssh_bot.py 2>/dev/null; systemctl stop sshbot >/dev/null 2>&1
    echo -e "${YELLOW}⚙️ Installing Python dependencies...${NC}"
    $PIP_BIN install urllib3==1.26.15 python-telegram-bot==13.7 schedule requests >/dev/null 2>&1
    
    echo "BOT_TOKEN=\"$input_token\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$input_id\"" >> "$BOT_CONF"
    chmod 600 "$BOT_CONF"
    
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, re, fcntl
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(message)s')
CONF_FILE = "/etc/xpanel/bot.conf"
DB_FILE = "/etc/xpanel/users_db.txt"
LOG_FILE = "/var/log/kp_manager.log"
TLINE = "============================"

def load_config():
    c = {}
    try:
        for l in open(CONF_FILE):
            if "=" in l: k, v = l.strip().split("=", 1); c[k] = v.strip().replace('"', '')
    except: pass
    return c

cfg = load_config(); TOKEN = cfg.get("BOT_TOKEN"); ADMIN_ID = int(cfg.get("ADMIN_ID", 0))

def kill_user(user):
    subprocess.run(["loginctl", "terminate-user", user], stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-KILL", "-u", user], stderr=subprocess.DEVNULL)

def get_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 CREATE ACCOUNT", callback_data='add'), InlineKeyboardButton("🔄 RENEW ACCOUNT", callback_data='ren')],
        [InlineKeyboardButton("🗑 DELETE ACCOUNT", callback_data='del'), InlineKeyboardButton("🔒 LOCK ACCOUNT", callback_data='lock_menu')],
        [InlineKeyboardButton("📋 LIST ACCOUNTS", callback_data='list'), InlineKeyboardButton("👁 MONITOR ACCOUNT", callback_data='onl')],
        [InlineKeyboardButton("💾 BACKUP DATA", callback_data='bak'), InlineKeyboardButton("🔔 ALERTS LOG", callback_data='alerts')],
        [InlineKeyboardButton("⚙ SETTINGS", callback_data='bot_set'), InlineKeyboardButton("🚪 EXIT", callback_data='close')]
    ])

def get_settings_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("💻 Server Info", callback_data='set_info')],
        [InlineKeyboardButton("🔄 Restart Monitor", callback_data='set_mon')],
        [InlineKeyboardButton("🔙 BACK", callback_data='back')]
    ])

def get_back_btn(): return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]])

def start(u, c):
    if u.effective_user.id == ADMIN_ID: u.message.reply_text(f"⚡ <b>SSH MANAGER V15 ULTIMATE</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu())

def btn(u, c):
    q = u.callback_query; q.answer(); d = q.data
    if d == 'close':
        try: q.message.delete()
        except: pass
        return
    if d == 'back': c.user_data.clear(); q.edit_message_text(f"⚡ <b>SSH MANAGER V15 ULTIMATE</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu()); return
    try:
        if d == 'add':
            c.user_data['act'] = 'add_u'
            q.edit_message_text("👤 <b>Send the New Username (Phone) in chat:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'add_yes':
            c.user_data['act'] = 'a_datetime'
            q.edit_message_text(f"👤 Username : <code>{c.user_data['u']}</code>\n🔑 Password  : <code>{c.user_data['p']}</code>\n\n📅 <b>Enter Number of Days</b> (e.g., 1, 7, 30):", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'add_no':
            c.user_data.clear(); q.edit_message_text("❌ Cancelled.", reply_markup=get_back_btn())

        elif d == 'ren': 
            c.user_data['act']='r_user'
            q.edit_message_text("🔄 <b>Enter Username to Renew:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'ren_yes':
            c.user_data['act'] = 'r_val'
            q.edit_message_text("📅 <b>Enter New Number of Days</b> (e.g., 30):", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'del': 
            c.user_data['act']='d1'
            q.edit_message_text("🗑️ <b>Username to Delete:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'del_yes':
            usr = c.user_data.get('del_u')
            if usr:
                kill_user(usr)
                subprocess.run(["userdel", "-f", usr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if os.path.exists(DB_FILE):
                    with open(DB_FILE, 'r+') as f:
                        fcntl.flock(f, fcntl.LOCK_EX)
                        lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                        f.seek(0); f.writelines(lines); f.truncate()
                        fcntl.flock(f, fcntl.LOCK_UN)
                q.edit_message_text(f"🗑️ <b>DELETED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'lock_menu':
            c.user_data['act']='lu_user'
            q.edit_message_text("🔒/🔓 <b>Enter Username to Lock or Unlock:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d.startswith('do_lock_'):
            usr = d.split('_', 2)[2]
            subprocess.run(["usermod", "-L", usr], stdout=subprocess.DEVNULL); kill_user(usr)
            q.edit_message_text(f"⛔ <b>LOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d.startswith('do_unlock_'):
            usr = d.split('_', 2)[2]
            subprocess.run(["usermod", "-U", usr], stdout=subprocess.DEVNULL)
            q.edit_message_text(f"🔓 <b>UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'list':
            if os.path.exists(DB_FILE):
                try: shadow_data = open('/etc/shadow', 'r').read()
                except: shadow_data = ""
                
                valid_lines = [l.strip().split('|') for l in open(DB_FILE) if len(l.strip().split('|')) >= 3 and "root" not in l]
                if not valid_lines:
                    q.edit_message_text("No users found.", reply_markup=get_back_btn()); return
                
                chunk_size = 30
                chunks = [valid_lines[i:i + chunk_size] for i in range(0, len(valid_lines), chunk_size)]
                
                for idx, chunk in enumerate(chunks):
                    body = f"<b>{TLINE}</b>\n<b>📋 USERS ({idx+1}/{len(chunks)})</b>\n<b>{TLINE}</b>\n\n"
                    for p in chunk:
                        usr, date, tm = p[0], p[1], p[2]
                        if "ACTIVATE" in date: ds = f"⏳ WAITING ({date.split(':')[1]}d)"
                        elif date == "BURNED": ds = "🔥 BURNED"
                        elif date == "EXPIRED": ds = "🔒 EXPIRED"
                        else: ds = f"✅ {date} {tm}"
                        lock = " ⛔" if f"\n{usr}:!" in shadow_data or shadow_data.startswith(f"{usr}:!") else ""
                        body += f"👤 <code>{usr}</code>{lock}\n📅 {ds}\n\n"
                    
                    if idx == 0: q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if len(chunks) == 1 else None)
                    else: c.bot.send_message(chat_id=u.effective_chat.id, text=body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if idx == len(chunks) - 1 else None)

        elif d == 'onl':
            if os.path.exists(DB_FILE):
                try: active_users_raw = subprocess.getoutput("ps -eo euser:30,comm | grep -E 'sshd|dropbear' | awk '{print $1}'").split()
                except: active_users_raw = []
                active_set = set(active_users_raw)
                
                valid_lines = [l.strip().split('|')[0] for l in open(DB_FILE) if len(l.strip().split('|')) >= 3 and "root" not in l]
                
                chunk_size = 50
                chunks = [valid_lines[i:i + chunk_size] for i in range(0, len(valid_lines), chunk_size)]
                for idx, chunk in enumerate(chunks):
                    body = f"<b>{TLINE}</b>\n<b>👁 LIVE MONITOR</b>\n<b>{TLINE}</b>\n\n"
                    for usr in chunk:
                        st = "🟢 ONLINE" if usr in active_set else "🔴 OFFLINE"
                        body += f"👤 <code>{usr}</code> - {st}\n"
                    if idx == 0: q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if len(chunks) == 1 else None)
                    else: c.bot.send_message(chat_id=u.effective_chat.id, text=body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if idx == len(chunks) - 1 else None)

        elif d == 'alerts':
            if os.path.exists(LOG_FILE):
                try:
                    alerts_raw = subprocess.getoutput(f"grep 'BURNED' {LOG_FILE} | tail -n 15")
                    msg = "✅ <b>NO VIOLATIONS DETECTED.</b>" if not alerts_raw.strip() else f"🔔 <b>BURNED ACCOUNTS</b>\n\n{alerts_raw}"
                except: msg = "Error reading log."
            else: msg = "⚠️ <b>LOG FILE IS EMPTY.</b>"
            q.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'bak':
            if os.path.exists(DB_FILE): c.bot.send_document(ADMIN_ID, open(DB_FILE, 'rb'))
            q.edit_message_text("✅ <b>DATA SAVED & SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'bot_set': q.edit_message_text("⚙️ <b>SETTINGS</b>\nChoose an option:", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'set_info':
            try:
                up = subprocess.getoutput("uptime -p"); ram = subprocess.getoutput("free -m | awk 'NR==2{printf \"%.2f%%\", $3*100/$2 }'")
                msg = f"💻 <b>SERVER INFO</b>\n\n⏱ <b>Uptime:</b> {up}\n🧠 <b>RAM:</b> {ram}"
            except: msg = "💻 <b>Error fetching info.</b>"
            q.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'set_mon':
            subprocess.run(["systemctl", "restart", "kp_monitor"])
            q.edit_message_text("✅ <b>Monitor Restarted!</b>", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
    except: pass

def txt(u, c):
    if u.effective_user.id != ADMIN_ID: return
    msg = u.message.text; act = c.user_data.get('act')
    try:
        if act == 'add_u':
            usr = msg.strip()
            if not re.match(r"^[a-zA-Z0-9_]+$", usr):
                u.message.reply_text("❌ <b>Invalid Username! Use letters/numbers only.</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn()); return
            if subprocess.run(["id", usr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                u.message.reply_text("❌ <b>User already exists!</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            else:
                c.user_data['u'] = usr; c.user_data['act'] = 'add_p'
                u.message.reply_text(f"👤 Username: <code>{usr}</code>\n\n🔑 <b>Send the Password:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
                
        elif act == 'add_p':
            c.user_data['p'] = msg.strip()
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 PROCEED", callback_data='add_yes'), InlineKeyboardButton("🔴 CANCEL", callback_data='add_no')]])
            u.message.reply_text(f"👤 User: <code>{c.user_data['u']}</code>\n🔑 Pass: <code>{c.user_data['p']}</code>\n\n⏳ <b>Proceed to set Days?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''

        elif act == 'lu_user':
            usr = msg.strip()
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🔒 LOCK", callback_data=f"do_lock_{usr}"), InlineKeyboardButton("🔓 UNLOCK", callback_data=f"do_unlock_{usr}")],[InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"Select action for <b>{usr}</b>:", parse_mode=ParseMode.HTML, reply_markup=kb); c.user_data['act'] = ''
        
        elif act == 'r_user':
            c.user_data['ru'] = msg.strip()
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 PROCEED", callback_data='ren_yes'), InlineKeyboardButton("🔴 CANCEL", callback_data='back')]])
            u.message.reply_text(f"⏳ <b>Set New Days for {msg}?</b>", parse_mode=ParseMode.HTML, reply_markup=kb); c.user_data['act'] = ''

        elif act == 'a_datetime':
            usr = c.user_data['u']; pwd = c.user_data['p']; days = msg.strip()
            if not days.isdigit(): days = "1"
            
            subprocess.run(["useradd", "-M", "-s", "/bin/false", usr], stdout=subprocess.DEVNULL)
            subprocess.run(["chpasswd"], input=f"{usr}:{pwd}".encode(), stdout=subprocess.DEVNULL)
            with open(DB_FILE, 'a') as f:
                fcntl.flock(f, fcntl.LOCK_EX); f.write(f"{usr}|ACTIVATE:{days}|00:00\n"); fcntl.flock(f, fcntl.LOCK_UN)
                
            resp = (f"<b>{TLINE}</b>\n           <b>ACCOUNT CREATED</b>          \n<b>{TLINE}</b>\n\n👤 Username : <code>{usr}</code>\n🔑 Password : <code>{pwd}</code>\n📅 Status   : <b>WAITING ({days} Days)</b>\n\n📋 Copy     : <code>{usr}:{pwd}</code>")
            u.message.reply_text(resp, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            c.user_data.clear()
            
        elif act == 'r_val':
            usr = c.user_data.get('ru'); days = msg.strip()
            if not days.isdigit(): days = "1"
            
            with open(DB_FILE, 'r+') as f:
                fcntl.flock(f, fcntl.LOCK_EX)
                lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                lines.append(f"{usr}|ACTIVATE:{days}|00:00\n")
                f.seek(0); f.writelines(lines); f.truncate()
                fcntl.flock(f, fcntl.LOCK_UN)
                
            subprocess.run(["usermod", "-U", usr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            u.message.reply_text(f"✅ <b>RENEWED & UNLOCKED:</b> <code>{usr}</code> (Waiting {days} Days)", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif act == 'd1':
            usr_to_del = msg.strip(); c.user_data['del_u'] = usr_to_del
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='del_yes'), InlineKeyboardButton("🔴 NO", callback_data='back')]])
            u.message.reply_text(f"⚠️ <b>Delete</b> <code>{usr_to_del}</code><b>?</b>", parse_mode=ParseMode.HTML, reply_markup=kb); c.user_data['act'] = ''
    except: pass

def main():
    if not TOKEN: return
    up = Updater(TOKEN, use_context=True)
    up.dispatcher.add_handler(CommandHandler('start', start))
    up.dispatcher.add_handler(CallbackQueryHandler(btn)); up.dispatcher.add_handler(MessageHandler(Filters.text, txt))
    up.start_polling(); up.idle()
if __name__ == '__main__': main()
EOF
    cat > /etc/systemd/system/sshbot.service << EOF
[Unit]
Description=SSH Telegram Bot Service
[Service]
ExecStart=$PYTHON_BIN /root/ssh_bot.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable sshbot >/dev/null 2>&1; systemctl restart sshbot
    echo -e "\n${GREEN}✅ SECURE BOT INSTALLED!${NC}"; pause
}

# =============================================
# 5. SETTINGS & MAIN MENU
# =============================================
fun_settings() {
    while true; do
        draw_header
        echo -e "            ⚙️ ${BLUE}SETTINGS & TOOLS${NC}\n${LINE}"
        echo -e "  ${BLUE}[1] 🛠️ INSTALL TELEGRAM BOT${NC}"
        echo -e "  ${BLUE}[2] 🌍 SET TIMEZONE${NC}"
        echo -e "  ${BLUE}[3] 📤 EXPORT USERS${NC}"
        echo -e "  ${BLUE}[4] 📥 RESTORE USERS${NC}"
        echo -e "  ${BLUE}[0] 🔙 BACK${NC}\n${LINE}"
        echo -ne "  ${BLUE}SELECT: ${NC}"; read s
        case "$s" in
            1) fun_install_bot ;;
            2) echo -ne " ${BLUE}🌍 Enter Timezone (e.g., Africa/Tunis): ${NC}"; read tz
               if timedatectl set-timezone "$tz" 2>/dev/null; then echo -e "\n${GREEN} ✅ TIMEZONE SET${NC}"; else echo -e "\n${RED} ❌ INVALID!${NC}"; fi; pause ;;
            3) fun_export_users ;;
            4) fun_import_users ;;
            0) break ;;
        esac
    done
}

while true; do
    draw_header
    echo -e "  ${BLUE}[1] 👤 CREATE ACCOUNT${NC} (Auto-Activate)"
    echo -e "  ${BLUE}[2] 🔄 RENEW ACCOUNT${NC}"
    echo -e "  ${BLUE}[3] 🗑 DELETE ACCOUNT${NC}"
    echo -e "  ${BLUE}[4] ⛔ LOCK/UNLOCK ACCOUNT${NC}"
    echo -e "  ${BLUE}[5] 📋 LIST ACCOUNTS${NC}"
    echo -e "  ${BLUE}[6] 👁 LIVE MONITOR${NC} (Online Check)"
    echo -e "  ${BLUE}[7] 💾 BACKUP DATA${NC}"
    echo -e "  ${BLUE}[8] 🔔 BURNED LOG${NC} (Violations)"
    echo -e "  ${BLUE}[9] ⚙️ SETTINGS & BOT${NC}  "
    echo -e "  ${BLUE}[0] ↪️ EXIT${NC}\n${LINE}"
    echo -ne "  ${BLUE}SELECT:${NC} "
    read o
    case "$o" in
        1) fun_create ;; 2) fun_renew ;; 3) fun_remove ;; 4) fun_lock ;; 5) fun_list ;;
        6) fun_monitor_view ;; 7) fun_backup ;; 8) fun_violations ;; 9) fun_settings ;; 0) clear; exit 0 ;;
    esac
done
