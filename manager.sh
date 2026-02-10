#!/bin/bash
# ==================================================
#  SSH MANAGER V42 (PRIVATE EDITION) 🔒
#  - ID & TOKEN: HARDCODED (READY TO USE)
#  - BOT: ANTI-FREEZE + AUTO RESTART
#  - MONITOR: STRICT (60s -> DELETE)
# ==================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- 1. DETECT OS ---
if [[ -f /etc/debian_version ]]; then
    OS="debian"
elif [[ -f /etc/redhat-release ]]; then
    OS="centos"
else
    OS="unknown"
fi

# --- CONFIG ---
USER_DB="/etc/xpanel/users_db.txt"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.sh"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"
MAX_LOGIN=1

# --- COLORS ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"

# ==================================================
#  🛡️ MONITOR ENGINE
# ==================================================
pkill -f kp_monitor.sh
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
DB="/etc/xpanel/users_db.txt"
LOG="/var/log/kp_manager.log"
MAX_LOGIN=1

while true; do
    sleep 5
    if [[ -f "$DB" ]]; then
        NOW=$(date +%s)
        while IFS='|' read -r user date time note; do
            [[ -z "$user" || -z "$date" ]] && continue
            
            # 1. Expiry
            if [[ "$date" != "NEVER" ]]; then
                [[ -z "$time" ]] && time="23:59"
                EXP_TS=$(date -d "$date $time" +%s 2>/dev/null)
                if [[ -n "$EXP_TS" && "$NOW" -ge "$EXP_TS" ]]; then
                    pkill -KILL -u "$user"
                    userdel -f -r "$user" 2>/dev/null
                    sed -i "/^$user|/d" "$DB"
                    echo "$(date) | EXPIRED | DELETED $user" >> "$LOG"
                    continue
                fi
            fi

            # 2. Multi-Login
            if [[ "$user" == "root" ]]; then continue; fi
            c1=$(pgrep -f "sshd: $user " | wc -l)
            c2=$(pgrep -u "$user" "sshd" | wc -l)
            c3=$(pgrep -u "$user" "dropbear" | wc -l)
            
            if [[ "$c1" -gt "$c2" ]]; then COUNT=$((c1 + c3)); else COUNT=$((c2 + c3)); fi
            
            if [[ "$COUNT" -gt "$MAX_LOGIN" ]]; then
                sleep 60
                c1=$(pgrep -f "sshd: $user " | wc -l)
                c2=$(pgrep -u "$user" "sshd" | wc -l)
                c3=$(pgrep -u "$user" "dropbear" | wc -l)
                if [[ "$c1" -gt "$c2" ]]; then COUNT_AGAIN=$((c1 + c3)); else COUNT_AGAIN=$((c2 + c3)); fi
                
                if [[ "$COUNT_AGAIN" -gt "$MAX_LOGIN" ]]; then
                    pkill -KILL -u "$user"
                    userdel -f -r "$user" 2>/dev/null
                    sed -i "/^$user|/d" "$DB"
                    echo "$(date) | CHEATER | DELETED $user" >> "$LOG"
                fi
            fi
        done < "$DB"
    fi
done
EOF
chmod +x "$MONITOR_SCRIPT"
if ! pgrep -f "kp_monitor.sh" > /dev/null; then nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 & fi

# ==================================================
#  FUNCTIONS
# ==================================================

pause() { echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"; read; }

fun_create() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}                 [01] ADD ACCOUNT                 ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    read -p " ENTER USERNAME : " u
    if id "$u" &>/dev/null; then echo -e "${RED}❌ ERROR: ACCOUNT ALREADY EXISTS!${NC}"; pause; return; fi
    read -p " ENTER PASSWORD : " p
    echo -e "${CYAN}--------------------------------------------------${NC}"
    read -p " SET EXPIRY DATE? (Y/N) : " choice
    if [[ "$choice" == "Y" || "$choice" == "y" ]]; then
        read -p " ENTER DATE (YYYY-MM-DD): " d
        read -p " ENTER TIME (HH:MM)     : " t
        [[ -z "$t" ]] && t="23:59"
    else d="NEVER"; t="00:00"; echo -e "${GREEN}ℹ️  SET TO UNLIMITED${NC}"; fi
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    echo "$u|$d|$t|V42" >> "$USER_DB"
    echo -e "${GREEN}✔ ACCOUNT CREATED!${NC}"; pause
}

fun_renew() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}                [02] RENEW ACCOUNT                ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    read -p " ENTER USERNAME  : " u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "${RED}❌ NOT FOUND!${NC}"; pause; return; fi
    read -p " ENTER NEW DATE (YYYY-MM-DD) : " d
    sed -i "/^$u|/d" "$USER_DB"
    echo "$u|$d|23:59|Renew" >> "$USER_DB"
    usermod -U "$u"
    echo -e "${GREEN}✔ RENEWED SUCCESSFULLY!${NC}"; pause
}

fun_remove() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${RED}                [03] REMOVE ACCOUNT               ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    read -p " ENTER USERNAME: " u
    read -p " CONFIRM DELETE? (Y/N): " c
    if [[ "$c" == "Y" || "$c" == "y" ]]; then
        pkill -u "$u"; userdel -f -r "$u"; sed -i "/^$u|/d" "$USER_DB"
        echo -e "${RED}🗑️ DELETED.${NC}"
    else echo "CANCELLED."; fi
    pause
}

fun_lock() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}                 [04] LOCK ACCOUNT                ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    read -p " ENTER USERNAME: " u
    echo " [1] LOCK ⛔"; echo " [2] UNLOCK 🔓"
    read -p " SELECT: " s
    if [[ "$s" == "1" ]]; then usermod -L "$u"; pkill -KILL -u "$u"; echo -e "${RED}LOCKED${NC}"; 
    else usermod -U "$u"; echo -e "${GREEN}UNLOCKED${NC}"; fi
    pause
}

fun_list() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}               [05] LIST ACCOUNTS                 ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${WHITE}USER           | DATE       | TIME  | STATUS${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        is_on=0
        if pgrep -f "sshd: $u " >/dev/null; then is_on=1; fi
        if pgrep -u "$u" "dropbear" >/dev/null; then is_on=1; fi
        if [[ $is_on -eq 1 ]]; then st="${GREEN}ONLINE 🟢${NC}"
        elif passwd -S "$u" | grep -q " L "; then st="${RED}LOCKED ⛔${NC}"
        else st="${RED}OFFLINE${NC}"; fi
        printf "${YELLOW}%-14s ${NC}| %-10s | %-5s | %b\n" "$u" "$d" "$t" "$st"
    done < "$USER_DB"
    pause
}

fun_online() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}               [06] CHECK STATUS                  ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${WHITE}USER           | STATUS${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    count=0
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        is_on=0
        if pgrep -f "sshd: $u " >/dev/null; then is_on=1; fi
        if pgrep -u "$u" "dropbear" >/dev/null; then is_on=1; fi
        if [[ $is_on -eq 1 ]]; then
            printf "${YELLOW}%-14s ${NC}| ${GREEN}ONLINE 🟢${NC}\n" "$u"
            ((count++))
        fi
    done < "$USER_DB"
    if [[ $count -eq 0 ]]; then echo "NO USERS ONLINE."; fi
    pause
}

fun_save() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}                 [07] BACKUP DATA                 ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    B_NAME="BACKUP_$(date '+%Y%m%d').txt"
    cp "$USER_DB" "$BACKUP_DIR/$B_NAME"
    echo -e "${GREEN}✅ DATA BACKED UP!${NC}"; echo -e "PATH: $BACKUP_DIR/$B_NAME"; pause
}

# --- 🤖 BOT INSTALLER (PERSONALIZED) ---
fun_install_bot() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}           INSTALLING YOUR PRIVATE BOT...         ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    
    # 1. Install Dependencies
    echo -e ">> INSTALLING PYTHON..."
    if [[ "$OS" == "debian" ]]; then
        apt-get update -y >/dev/null; apt-get install python3 python3-pip -y >/dev/null
    else
        yum install epel-release -y >/dev/null; yum install python3 python3-pip -y >/dev/null
    fi
    # Force Correct Version
    pip3 install --upgrade --force-reinstall python-telegram-bot==13.7 schedule >/dev/null 2>&1

    # 2. Stop Old
    systemctl stop sshbot >/dev/null 2>&1; rm -f /root/ssh_bot.py

    # 3. Write Bot Code (HARDCODED CREDENTIALS)
    echo -e ">> WRITING BOT CODE..."
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, threading, time
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext
from telegram.utils.request import Request

# --- YOUR CREDENTIALS ---
TOKEN = "7867550558:AAHqNQ6s6lveMXs9CS51g_ZSbcga63sfacE"
ADMIN_ID = 7587310857
DB_FILE = "/etc/xpanel/users_db.txt"

logging.basicConfig(level=logging.ERROR)

def run_cmd(cmd):
    try: subprocess.run(cmd, shell=True, check=True); return True
    except: return False

def get_status(u):
    try:
        if subprocess.getoutput(f"pgrep -f 'sshd: {u} '") or subprocess.getoutput(f"pgrep -u {u} dropbear"): return "ONLINE 🟢"
        if " L " in subprocess.getoutput(f"passwd -S {u}"): return "LOCKED ⛔"
    except: pass
    return "OFFLINE 🔴"

def start(update: Update, context: CallbackContext):
    try:
        if update.effective_user.id != ADMIN_ID: return
        kb = [[InlineKeyboardButton("👤 ADD ACCOUNT", callback_data='add'), InlineKeyboardButton("🔄 RENEW", callback_data='ren')],
              [InlineKeyboardButton("🗑️ REMOVE", callback_data='del'), InlineKeyboardButton("🔒 LOCK/UNLOCK", callback_data='lock')],
              [InlineKeyboardButton("📋 LIST", callback_data='list'), InlineKeyboardButton("🟢 ONLINE", callback_data='onl')],
              [InlineKeyboardButton("💾 BACKUP", callback_data='bak'), InlineKeyboardButton("⚙️ SETTINGS", callback_data='set')]]
        update.message.reply_text("*🤖 SSH MANAGER V42*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
    except: pass

def btn(update: Update, context: CallbackContext):
    try:
        q = update.callback_query
        try: q.answer() 
        except: pass
        
        data = q.data
        if data == 'add': context.user_data['act']='a1'; q.edit_message_text("ENTER USERNAME:")
        elif data == 'ren': context.user_data['act']='r1'; q.edit_message_text("ENTER USERNAME:")
        elif data == 'del': context.user_data['act']='d1'; q.edit_message_text("ENTER USERNAME:")
        elif data == 'lock': context.user_data['act']='l1'; q.edit_message_text("ENTER USERNAME:")
        
        elif data == 'list':
            msg = "USER | EXPIRY\n------------------\n"
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        p = l.strip().split('|')
                        if len(p)>=2: msg += f"{p[0]:<10} | {p[1]}\n"
            q.edit_message_text(f"```\n{msg}```", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        
        elif data == 'onl':
            msg = "USER | STATUS\n------------------\n"
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        u = l.strip().split('|')[0]
                        st = get_status(u)
                        if "ONLINE" in st: msg += f"{u:<10} | {st}\n"
            q.edit_message_text(f"```\n{msg}```", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            
        elif data == 'bak':
            if os.path.exists(DB_FILE): context.bot.send_document(chat_id=ADMIN_ID, document=open(DB_FILE, 'rb'), filename="users_db.txt")
            q.edit_message_text("✅ DONE!", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            
        elif data == 'set':
            kb = [[InlineKeyboardButton("🌍 FIX TIMEZONE", callback_data='tz')], [InlineKeyboardButton("BACK", callback_data='back')]]
            q.edit_message_text("⚙️ SETTINGS:", reply_markup=InlineKeyboardMarkup(kb))
        
        elif data == 'tz': run_cmd("timedatectl set-timezone Africa/Tunis"); q.edit_message_text("🌍 DONE.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data == 'back': start(update, context)
        
        elif data == 'a_unlim': create_user(update, context, "NEVER", "00:00")
        elif data == 'a_date': context.user_data['act']='a_date_input'; q.edit_message_text("ENTER DATE (YYYY-MM-DD):")
        
        elif data.startswith('LK_'): u = data.split('_')[1]; run_cmd(f"usermod -L {u}"); run_cmd(f"pkill -KILL -u {u}"); q.edit_message_text(f"⛔ LOCKED {u}", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data.startswith('UL_'): u = data.split('_')[1]; run_cmd(f"usermod -U {u}"); q.edit_message_text(f"🔓 UNLOCKED {u}", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data.startswith('DEL_YES_'):
            u = data.split('_')[2]; run_cmd(f"pkill -u {u}"); run_cmd(f"userdel -f -r {u}")
            lines = [l for l in open(DB_FILE) if not l.startswith(f"{u}|")]
            with open(DB_FILE, 'w') as f: f.writelines(lines)
            q.edit_message_text("🗑️ DELETED.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
        elif data == 'DEL_NO': q.edit_message_text("❌ CANCELLED.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
    except: pass

def create_user(update, context, d, t):
    try:
        u = context.user_data.get('nu'); p = context.user_data.get('np')
        if run_cmd(f"useradd -M -s /bin/false {u}"):
            run_cmd(f"echo '{u}:{p}' | chpasswd")
            with open(DB_FILE, 'a') as f: f.write(f"{u}|{d}|{t}|Bot\n")
            exp = "UNLIMITED ♾️" if d == "NEVER" else d
            res = f"━━━━━━━━━━━━━━━━━━\nACCOUNT\n━━━━━━━━━━━━━━━━━━\n👤 USER : `{u}`\n🔑 PASS : `{p}`\n📅 EXPIRY : {exp}\n━━━━━━━━━━━━━━━━━━\n`{u}:{p}`\n━━━━━━━━━━━━━━━━━━"
            try: update.callback_query.edit_message_text(res, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("MENU", callback_data='back')]]))
            except: update.message.reply_text(res, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("MENU", callback_data='back')]]))
        else:
            try: update.callback_query.edit_message_text("❌ EXISTS!", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
            except: update.message.reply_text("❌ EXISTS!", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]]))
    except: pass
    context.user_data['act'] = None

def txt(update: Update, context: CallbackContext):
    try:
        if update.effective_user.id != ADMIN_ID: return
        msg = update.message.text; act = context.user_data.get('act')
        
        if act == 'a1': context.user_data.update({'nu': msg, 'act': 'a2'}); update.message.reply_text("ENTER PASSWORD :")
        elif act == 'a2': context.user_data.update({'np': msg}); kb = [[InlineKeyboardButton("♾️ UNLIMITED", callback_data='a_unlim')], [InlineKeyboardButton("📅 CUSTOM", callback_data='a_date')]]; update.message.reply_text("EXPIRY:", reply_markup=InlineKeyboardMarkup(kb))
        elif act == 'a_date_input': context.user_data.update({'nd': msg, 'act': 'a_time_input'}); update.message.reply_text("TIME (HH:MM):")
        elif act == 'a_time_input': t = msg if msg else "23:59"; d = context.user_data['nd']; create_user(update, context, d, t)
        
        elif act == 'r1': context.user_data.update({'ru': msg, 'act': 'r2'}); update.message.reply_text("NEW DATE:")
        elif act == 'r2': context.user_data.update({'rd': msg, 'act': 'r3'}); update.message.reply_text("TIME:")
        elif act == 'r3':
            t = msg if msg else "23:59"; u, d = context.user_data['ru'], context.user_data['rd']
            lines = [l for l in open(DB_FILE) if not l.startswith(f"{u}|")]
            with open(DB_FILE, 'w') as f: f.writelines(lines)
            with open(DB_FILE, 'a') as f: f.write(f"{u}|{d}|{t}|Renew\n"); run_cmd(f"usermod -U {u}")
            update.message.reply_text("✅ RENEWED!", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("BACK", callback_data='back')]])); context.user_data['act'] = None
        
        elif act == 'd1': u = msg; kb = [[InlineKeyboardButton("YES", callback_data=f'DEL_YES_{u}'), InlineKeyboardButton("NO", callback_data='DEL_NO')]]; update.message.reply_text(f"DELETE {u}?", reply_markup=InlineKeyboardMarkup(kb)); context.user_data['act'] = None
        elif act == 'l1': u = msg; kb = [[InlineKeyboardButton("LOCK", callback_data=f'LK_{u}'), InlineKeyboardButton("UNLOCK", callback_data=f'UL_{u}')]]; update.message.reply_text(f"ACTION FOR {u}:", reply_markup=InlineKeyboardMarkup(kb)); context.user_data['act'] = None
    except: pass

def main():
    req = Request(connect_timeout=20.0, read_timeout=20.0)
    updater = Updater(TOKEN, request_kwargs={'read_timeout': 20, 'connect_timeout': 20}, use_context=True)
    dp = updater.dispatcher
    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CallbackQueryHandler(btn, run_async=True))
    dp.add_handler(MessageHandler(Filters.text, txt))
    up.start_polling(drop_pending_updates=True)
    up.idle()

if __name__ == '__main__': main()
EOF

    # 4. Service
    cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Bot
After=network.target
[Service]
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sshbot
    systemctl start sshbot
    echo -e "${GREEN}✅ BOT INSTALLED SUCCESSFULLY!${NC}"
    pause
}

fun_settings() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}                  [08] SETTINGS                   ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e " [1] FIX TIMEZONE"
    echo -e " [2] RESTART MONITOR"
    echo -e " [3] RESTART SSH"
    echo -e " [4] VIEW LOGS"
    echo -e " [5] 🤖 INSTALL / UPDATE BOT"
    echo ""
    read -p " SELECT OPTION: " s
    
    case "$s" in
        1) timedatectl set-timezone Africa/Tunis; echo -e "${GREEN}DONE.${NC}";;
        2) pkill -f kp_monitor.sh; nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 & echo -e "${GREEN}RESTARTED.${NC}";;
        3) service "$SSH_SERVICE" restart; echo -e "${GREEN}RESTARTED.${NC}";;
        4) echo ""; tail -n 10 "$LOG_FILE";;
        5) fun_install_bot ;;
    esac
    pause
}

# --- MAIN MENU ---
while true; do
    clear
    if ! pgrep -f "kp_monitor.sh" > /dev/null; then nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 & fi

    echo -e "${BLUE}==================================================${NC}"
    echo -e "${WHITE}  SSH MANAGER (V42)     ${NC}"
    echo -e "${WHITE}  OS: ${YELLOW}${OS^^}${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    echo -e "${GREEN} [01] ADD ACCOUNT${NC}"
    echo -e "${GREEN} [02] RENEW ACCOUNT${NC}"
    echo -e "${GREEN} [03] REMOVE ACCOUNT${NC}"
    echo -e "${GREEN} [04] LOCK ACCOUNT${NC}"
    echo -e "${GREEN} [05] LIST ACCOUNTS${NC}"
    echo -e "${GREEN} [06] CHECK STATUS${NC}"
    echo -e "${GREEN} [07] BACKUP DATA${NC}"
    echo -e "${GREEN} [08] SETTINGS${NC}"
    echo -e "${GREEN} [00] EXIT${NC}"
    echo ""
    echo -e "${BLUE}==================================================${NC}"
    read -p " SELECT OPTION: " opt
    
    case "$opt" in
        1|01) fun_create ;; 2|02) fun_renew ;; 3|03) fun_remove ;; 4|04) fun_lock ;;
        5|05) fun_list ;; 6|06) fun_online ;; 7|07) fun_save ;; 8|08) fun_settings ;;
        0|00) clear; exit 0 ;; *) echo "INVALID OPTION"; sleep 1 ;;
    esac
done
