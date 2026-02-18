#!/bin/bash
# ==================================================
#  SSH MANAGER V99 (FULL SYNC - FIXED) 💎
#  - BOT & CLI ARE NOW 100% IDENTICAL
#  - FIXED: Python Library Installation (Break System Packages)
#  - FIXED: Monitor Option in Menu
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
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.py"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"
MIGRATION_FILE="/root/migration_users.txt"

# --- CREDENTIALS ---
MY_TOKEN="8134717950:AAGj2wWaABBUWbPLa7jX6yEWHgwjgUelpwg"
MY_ID="7587310857"

# --- COLORS ---
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; PURPLE='\033[1;35m'; CYAN='\033[1;36m'; NC='\033[0m'; WHITE='\033[1;37m'

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"

# ==================================================
#  🛡️ PYTHON PRECISION MONITOR
# ==================================================
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}Installing Python3...${NC}"
    $CMD python3 python3-pip > /dev/null 2>&1
fi

pkill -f kp_monitor.py
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/usr/bin/env python3
import datetime
import subprocess
import os
import time

DB_FILE = "/etc/xpanel/users_db.txt"
LOG_FILE = "/var/log/kp_manager.log"
MAX_LOGIN = 1

def log_event(message):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{datetime.datetime.now()} - {message}\n")
    except: pass

def check_loop():
    while True:
        if os.path.exists(DB_FILE):
            try:
                with open(DB_FILE, 'r') as f:
                    lines = f.readlines()
                
                new_lines = []
                status_changed = False
                now = datetime.datetime.now()

                for line in lines:
                    parts = line.strip().split('|')
                    if len(parts) < 3: 
                        continue
                    
                    user = parts[0]
                    exp_date = parts[1]
                    exp_time = parts[2]

                    if "V9" in user or "Turbo" in user or user == "root":
                        new_lines.append(line)
                        continue

                    # --- EXPIRY CHECK ---
                    expired = False
                    if exp_date.lower() != "never":
                        try:
                            if not exp_time: exp_time = "23:59"
                            expiry_str = f"{exp_date} {exp_time}"
                            expiry_moment = datetime.datetime.strptime(expiry_str, "%Y-%m-%d %H:%M")
                            
                            if now >= expiry_moment:
                                subprocess.run(f"pkill -KILL -u {user}", shell=True)
                                subprocess.run(f"userdel -f -r {user}", shell=True)
                                log_event(f"EXPIRED: User {user} deleted automatically.")
                                status_changed = True
                                expired = True
                        except Exception as e:
                            log_event(f"Date Error for {user}: {e}")

                    if expired: continue

                    # --- MULTI-LOGIN CHECK ---
                    try:
                        p1 = subprocess.getoutput(f"pgrep -u {user} sshd | wc -l")
                        p2 = subprocess.getoutput(f"pgrep -u {user} dropbear | wc -l")
                        total = int(p1) + int(p2)
                        
                        if total > MAX_LOGIN:
                            subprocess.run(f"pkill -KILL -u {user}", shell=True)
                            log_event(f"KICK: User {user} exceeded max logins ({total})")
                    except: pass

                    new_lines.append(line)

                if status_changed:
                    with open(DB_FILE, 'w') as f:
                        f.writelines(new_lines)

            except Exception as e:
                log_event(f"Monitor Loop Error: {e}")
        
        time.sleep(3)

if __name__ == "__main__":
    check_loop()
EOF

chmod +x "$MONITOR_SCRIPT"
if ! pgrep -f "kp_monitor.py" > /dev/null; then nohup python3 "$MONITOR_SCRIPT" >/dev/null 2>&1 & fi

# ==================================================
#  CLI FUNCTIONS
# ==================================================

pause() { echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"; read; }
draw_header() {
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "           ${WHITE}SSH MANAGER V99 (FULL SYNC)${NC}"
    echo -e "${CYAN}==================================================${NC}"
}

fun_create() {
    draw_header
    echo -e "                ${WHITE}AUTO-SEQUENCE USER${NC}"
    echo -e "${CYAN}==================================================${NC}"
    i=1
    while true; do
        u="USER${i}"
        # Robust check: System OR DB
        if id "$u" &>/dev/null; then ((i++)); continue; fi
        if grep -q "^$u|" "$USER_DB"; then ((i++)); continue; fi
        break
    done
    p="12345"
    echo -e " 👤 USER : ${GREEN}$u${NC}"
    echo -e " 🔑 PASS : ${GREEN}$p${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    read -p " 📅 DATE (YYYY-MM-DD): " d
    if [[ -z "$d" ]]; then d="NEVER"; t="00:00"; else
        read -p " ⏰ TIME (HH:MM)     : " t
        [[ -z "$t" ]] && t="00:00"
    fi
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    echo "$u|$d|$t|V99" >> "$USER_DB"
    echo -e "${GREEN}✅ CREATED: $u${NC}"; pause
}

fun_renew() {
    draw_header; echo -e "                ${WHITE}RENEW USER${NC}"; echo -e "${CYAN}==================================================${NC}"
    read -p " 👤 USERNAME : " u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "${RED}❌ NOT FOUND!${NC}"; pause; return; fi
    read -p " 📅 NEW DATE (YYYY-MM-DD): " d
    read -p " ⏰ NEW TIME (HH:MM)     : " t
    [[ -z "$t" ]] && t="23:59"
    sed -i "/^$u|/d" "$USER_DB"
    echo "$u|$d|$t|Renew" >> "$USER_DB"
    usermod -U "$u"
    echo -e "${GREEN}✅ RENEWED${NC}"; pause
}

fun_remove() {
    draw_header; echo -e "                ${WHITE}REMOVE USER${NC}"; echo -e "${CYAN}==================================================${NC}"
    read -p " 👤 USERNAME : " u
    read -p " ⚠️ CONFIRM? [y/n]: " c
    if [[ "$c" == "y" ]]; then
        pkill -u "$u"
        userdel -f -r "$u" 2>/dev/null
        sed -i "/^$u|/d" "$USER_DB"
        echo -e "${RED}🗑️ DELETED${NC}"
    fi
    pause
}

fun_lock() {
    draw_header; echo -e "                ${WHITE}LOCK/UNLOCK${NC}"; echo -e "${CYAN}==================================================${NC}"
    read -p " 👤 USERNAME : " u
    echo " [1] LOCK ⛔"; echo " [2] UNLOCK 🔓"
    read -p " SELECT: " s
    if [[ "$s" == "1" ]]; then usermod -L "$u"; pkill -KILL -u "$u"; echo "LOCKED"; 
    else usermod -U "$u"; echo "UNLOCKED"; fi
    pause
}

fun_list() {
    draw_header; echo -e "                ${WHITE}USER LIST${NC}"; echo -e "${CYAN}==================================================${NC}"
    printf "%-12s | %-18s | %-10s\n" "USER" "EXPIRY DATE" "STATUS"
    echo "------------------------------------------------"
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             if ps -ef | grep "sshd: $u" | grep -v grep > /dev/null 2>&1 || pgrep -u "$u" > /dev/null 2>&1; then
                STATUS="${GREEN}ON${NC}"
             else
                STATUS="${RED}OFF${NC}"
             fi
             [[ "$d" == "NEVER" ]] && DATE_STR="NEVER" || DATE_STR="$d $t"
             printf "%-12s | %-18s | ${STATUS}\n" "$u" "$DATE_STR"
        fi
    done < "$USER_DB"
    echo ""; pause
}

fun_monitor_view() {
    draw_header; echo -e "                ${WHITE}LIVE MONITOR${NC}"; echo -e "${CYAN}==================================================${NC}"
    echo -e "Monitor is running in background (kp_monitor.py)."
    echo -e "Checking log file: $LOG_FILE"
    echo -e "------------------------------------------------"
    if [ -f "$LOG_FILE" ]; then
        tail -n 10 "$LOG_FILE"
    else
        echo "No logs yet."
    fi
    pause
}

fun_backup() {
    draw_header; echo -e "                ${WHITE}LOCAL BACKUP${NC}"; echo -e "${CYAN}==================================================${NC}"
    echo -e "${YELLOW}Creating Backup...${NC}"
    cp "$USER_DB" "$BACKUP_DIR/users_backup_$(date +%F).txt"
    echo -e "${GREEN}✅ Backup Saved in $BACKUP_DIR${NC}"
    pause
}

# --- 🚀 MIGRATION FUNCTIONS ---
fun_export_users() {
    draw_header
    echo -e "${YELLOW}EXPORTING USERS...${NC}"
    cp "$USER_DB" "$MIGRATION_FILE"
    echo -e "${GREEN}✅ EXPORT SUCCESSFUL!${NC} File: $MIGRATION_FILE"
    pause
}

fun_import_users() {
    draw_header
    echo -e "${YELLOW}RESTORING USERS...${NC}"
    if [[ ! -f "$MIGRATION_FILE" ]]; then echo -e "${RED}❌ FILE NOT FOUND${NC}"; pause; return; fi
    count=0
    while IFS='|' read -r u d t tag; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then echo -e "User $u exists... ${YELLOW}Skipping${NC}"; else
            useradd -M -s /bin/false "$u"; echo "$u:12345" | chpasswd
            echo -e "Created: ${GREEN}$u${NC}"; ((count++))
        fi
    done < "$MIGRATION_FILE"
    cat "$MIGRATION_FILE" > "$USER_DB"
    echo -e "${GREEN}✅ RESTORED: $count${NC}"; pause
}

fun_settings() {
    while true; do
        draw_header; echo -e "                ${WHITE}SETTINGS${NC}"; echo -e "${CYAN}==================================================${NC}"
        echo -e " [1] Install/Update Bot (FIX LIBRARIES)"
        echo -e " [2] Set Timezone (Africa/Tunis)"
        echo -e " [3] 📤 EXPORT USERS (Backup)"
        echo -e " [4] 📥 RESTORE USERS (Restore)"
        echo -e " [5] Back"
        echo -e "${CYAN}--------------------------------------------------${NC}"
        read -p " SELECT: " s
        case "$s" in
            1) fun_install_bot ;;
            2) timedatectl set-timezone Africa/Tunis; echo -e "${GREEN}✅ Timezone set to Tunis${NC}"; pause ;;
            3) fun_export_users ;;
            4) fun_import_users ;;
            5) break ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# ==================================================
#  🤖 BOT INSTALLER (V99 FULL SYNC)
# ==================================================
fun_install_bot() {
    pkill -f ssh_bot.py
    systemctl stop sshbot >/dev/null 2>&1
    clear; echo -e "${YELLOW}INSTALLING BOT V99 (FIXING LIBS)...${NC}"
    
    # 1. REMOVE OLD LIBS
    echo -e "${BLUE}Cleaning old libraries...${NC}"
    pip3 uninstall -y python-telegram-bot telegram >/dev/null 2>&1
    
    # 2. INSTALL DEPENDENCIES (FORCE BREAK SYSTEM PACKAGES)
    echo -e "${BLUE}Installing correct libraries (v13.7)...${NC}"
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        apt-get update -y >/dev/null 2>&1; apt-get install -y python3 python3-pip >/dev/null 2>&1
    else
        yum install -y python3 python3-pip >/dev/null 2>&1
    fi
    
    # FORCE INSTALL v13.7 even on new systems
    pip3 install python-telegram-bot==13.7 schedule requests --break-system-packages >/dev/null 2>&1
    # Fallback if flag fails
    if [ $? -ne 0 ]; then
        pip3 install python-telegram-bot==13.7 schedule requests >/dev/null 2>&1
    fi

    echo "BOT_TOKEN=\"$MY_TOKEN\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$MY_ID\"" >> "$BOT_CONF"
    chmod 600 "$BOT_CONF"
    
    cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Bot V99
After=network.target network-online.target
[Service]
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

    # PYTHON BOT SCRIPT (FULL FEATURES)
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(filename='/var/log/sshbot.log', level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
CONF_FILE = "/etc/xpanel/bot.conf"
DB_FILE = "/etc/xpanel/users_db.txt"
MIGRATION_FILE = "/root/migration_users.txt"

def load_config():
    config = {}
    try:
        with open(CONF_FILE) as f:
            for line in f:
                if "=" in line: k, v = line.strip().split("=", 1); config[k] = v.strip().replace('"', '')
    except: pass
    return config

cfg = load_config(); TOKEN = cfg.get("BOT_TOKEN"); ADMIN_ID = int(cfg.get("ADMIN_ID", 0))

def get_status(u):
    try:
        if subprocess.getoutput(f"pgrep -u {u}"): return "🟢 ON "
    except: pass
    return "🔴 OFF"

def get_back_btn(): return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]])

def get_main_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 ADD USER (AUTO)", callback_data='add')],
        [InlineKeyboardButton("🔄 RENEW", callback_data='ren'), InlineKeyboardButton("🗑️ DELETE", callback_data='del')],
        [InlineKeyboardButton("🔒 LOCK", callback_data='lock'), InlineKeyboardButton("🔓 UNLOCK", callback_data='unlock_menu')],
        [InlineKeyboardButton("📋 LIST", callback_data='list'), InlineKeyboardButton("⚡ MONITOR", callback_data='onl')],
        [InlineKeyboardButton("📦 BACKUP", callback_data='bak'), InlineKeyboardButton("🚀 MIGRATION", callback_data='migrate')]
    ])

def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    update.message.reply_text("💎 *SSH MANAGER V99*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_menu())

def button_handler(update: Update, context: CallbackContext):
    q = update.callback_query; q.answer(); data = q.data
    if data == 'back': context.user_data.clear(); q.edit_message_text("💎 *SSH MANAGER V99*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_menu()); return

    try:
        if data == 'add':
            i = 1
            while True:
                u = f"USER{i}"
                # Check System AND File
                sys_check = subprocess.run(f"id {u}", shell=True).returncode
                file_check = False
                if os.path.exists(DB_FILE):
                     if f"{u}|" in open(DB_FILE).read(): file_check = True
                
                if sys_check != 0 and not file_check: break
                i += 1
            context.user_data['nu'] = u; context.user_data['np'] = "12345"; context.user_data['act'] = 'a_date'
            q.edit_message_text(f"👤 *NEW USER:* `{u}`\n🔑 *PASS:* `12345`\n\n📅 *ENTER DATE (YYYY-MM-DD):*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

        elif data == 'ren': context.user_data['act'] = 'r1'; q.edit_message_text("🔄 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'del': context.user_data['act'] = 'd1'; q.edit_message_text("🗑️ *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'del_yes':
            u = context.user_data.get('del_u')
            if u:
                subprocess.run(f"pkill -u {u}", shell=True); subprocess.run(f"userdel -f -r {u}", shell=True)
                if os.path.exists(DB_FILE):
                    lines = open(DB_FILE).readlines()
                    with open(DB_FILE, 'w') as f:
                        for l in lines: 
                            if not l.startswith(f"{u}|"): f.write(l)
                q.edit_message_text(f"✅ *USER {u} DELETED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

        elif data == 'lock': context.user_data['act'] = 'l1'; q.edit_message_text("🔒 *ENTER USERNAME TO LOCK:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'unlock_menu': context.user_data['act'] = 'ul1'; q.edit_message_text("🔓 *ENTER USERNAME TO UNLOCK:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        
        elif data == 'do_lock': u = context.user_data.get('lock_u'); subprocess.run(f"usermod -L {u}", shell=True); subprocess.run(f"pkill -KILL -u {u}", shell=True); q.edit_message_text(f"⛔ *USER {u} LOCKED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'do_unlock': u = context.user_data.get('lock_u'); subprocess.run(f"usermod -U {u}", shell=True); q.edit_message_text(f"🟢 *USER {u} UNLOCKED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

        elif data == 'list':
            body = "👤 *USER* | 📅 *EXPIRY* | *ST*\n-----------------------------------\n"
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        parts = l.strip().split('|')
                        if len(parts) < 3 or "Turbo" in l: continue
                        # Format: User | Date Time | Status
                        st = "🟢" if "🟢" in get_status(parts[0]) else "🔴"
                        body += f"`{parts[0]:<10}` | {parts[1]} {parts[2]} | {st}\n"
            q.edit_message_text(body, parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

        elif data == 'onl':
            body = "👤 *USER* | ⚡ *STATUS*\n---------------------------\n"
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        u = l.split('|')[0]
                        if not u or "Turbo" in u: continue
                        if subprocess.run(f"id {u}", shell=True).returncode != 0: continue
                        body += f"`{u:<12}` | {get_status(u)}\n"
            q.edit_message_text(body, parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

        elif data == 'bak':
            if os.path.exists(DB_FILE): context.bot.send_document(chat_id=ADMIN_ID, document=open(DB_FILE, 'rb'))
            q.edit_message_text("✅ *DATABASE BACKUP SENT!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

        elif data == 'migrate':
            # Create the migration file
            if os.path.exists(DB_FILE):
                subprocess.run(f"cp {DB_FILE} {MIGRATION_FILE}", shell=True)
                context.bot.send_document(chat_id=ADMIN_ID, document=open(MIGRATION_FILE, 'rb'), caption="🚀 *MIGRATION FILE*\n\n1. Download file\n2. Upload to new server at `/root/migration_users.txt`\n3. Run Restore in CLI.", parse_mode=ParseMode.MARKDOWN)
                q.edit_message_text("✅ *MIGRATION FILE SENT!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
            else:
                 q.edit_message_text("❌ *NO DATABASE FOUND!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

    except Exception as e: logging.error(f"Btn: {e}")

def txt(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    msg = update.message.text; act = context.user_data.get('act')
    try:
        if act == 'a_date': context.user_data.update({'nd': msg, 'act': 'a_time'}); update.message.reply_text("⏰ *ENTER TIME (HH:MM):*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif act == 'a_time':
            u = context.user_data.get('nu'); p = context.user_data.get('np'); d = context.user_data['nd']
            if u:
                subprocess.run(f"useradd -M -s /bin/false {u}", shell=True); subprocess.run(f"echo '{u}:{p}' | chpasswd", shell=True)
                with open(DB_FILE, 'a') as f: f.write(f"{u}|{d}|{msg}|Bot\n")
                update.message.reply_text(f"✅ *CREATED:*\n👤 `{u}`\n🔑 `{p}`\n📅 {d} {msg}", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        
        elif act == 'r1': context.user_data.update({'ru': msg, 'act': 'r2'}); update.message.reply_text("📅 *NEW DATE:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif act == 'r2': context.user_data.update({'rd': msg, 'act': 'r3'}); update.message.reply_text("⏰ *NEW TIME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif act == 'r3':
            u = context.user_data.get('ru')
            if u and os.path.exists(DB_FILE):
                lines = open(DB_FILE).readlines()
                with open(DB_FILE, 'w') as f:
                    for l in lines:
                        if not l.startswith(f"{u}|"): f.write(l)
                    f.write(f"{u}|{context.user_data['rd']}|{msg}|Renew\n")
                update.message.reply_text(f"✅ *RENEWED: {u}*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        
        elif act == 'd1': context.user_data['del_u'] = msg; update.message.reply_text(f"⚠️ *DELETE {msg}?*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("YES", callback_data='del_yes'), InlineKeyboardButton("NO", callback_data='back')]]))
        elif act == 'l1': context.user_data['lock_u'] = msg; update.message.reply_text(f"⚙️ *LOCK {msg}?*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("CONFIRM LOCK", callback_data='do_lock'), InlineKeyboardButton("BACK", callback_data='back')]]))
        elif act == 'ul1': context.user_data['lock_u'] = msg; update.message.reply_text(f"⚙️ *UNLOCK {msg}?*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("CONFIRM UNLOCK", callback_data='do_unlock'), InlineKeyboardButton("BACK", callback_data='back')]]))

    except: pass

def main():
    if not TOKEN: return
    try:
        up = Updater(TOKEN, use_context=True); dp = up.dispatcher
        dp.add_handler(CommandHandler("start", start))
        dp.add_handler(CallbackQueryHandler(button_handler))
        dp.add_handler(MessageHandler(Filters.text, txt))
        up.start_polling()
        up.idle()
    except Exception as e: logging.error(f"Main: {e}")

if __name__ == '__main__': main()
EOF
    systemctl daemon-reload; systemctl enable sshbot; systemctl restart sshbot
    echo -e "${GREEN}✅ BOT V99 INSTALLED!${NC}"; pause
}

# --- MAIN LOOP ---
while true; do
    draw_header
    echo -e " ${GREEN}[01]${NC} 👤 ADD ACCOUNT (AUTO)"
    echo -e " ${GREEN}[02]${NC} 🔄 RENEW ACCOUNT"
    echo -e " ${GREEN}[03]${NC} 🗑️ REMOVE ACCOUNT"
    echo -e " ${GREEN}[04]${NC} 🔐 LOCK ACCOUNT"
    echo -e " ${GREEN}[05]${NC} 📋 LIST ACCOUNTS"
    echo -e " ${GREEN}[06]${NC} 🔘 MONITOR USERS"
    echo -e " ${GREEN}[07]${NC} 💾 BACKUP DATA"
    echo -e " ${GREEN}[08]${NC} ⚙️ SETTINGS (MIGRATION/BOT)"
    echo -e " ${GREEN}[00]${NC} 🚪 EXIT"
    echo ""
    echo -e "${CYAN}==================================================${NC}"
        read -p " SELECT OPTION: " o
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
