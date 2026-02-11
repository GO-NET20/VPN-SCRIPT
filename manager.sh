#!/bin/bash
# ==================================================
#  SSH MANAGER V28.4 (LITE EDITION) 🚀
#  - INTERFACE: CLASSIC V28.4 MENU
#  - BOT ENGINE: V50 (ACTIVE)
#  - PROTECTION: REMOVED (NO MONITOR)
# ==================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- CONFIG ---
USER_DB="/etc/xpanel/users_db.txt"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"

# --- COLORS ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"

# ==================================================
#  (تم حذف نظام المراقبة والحماية من هنا)
# ==================================================
# تم إيقاف: kp_monitor.sh
# تم إيقاف: فحص تعدد الدخول (Multi-Login)
# تم إيقاف: الحذف التلقائي عند الانتهاء
pkill -f kp_monitor.sh 2>/dev/null

# ==================================================
#  FUNCTIONS (V28.4 STYLE)
# ==================================================

pause() { echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"; read; }

fun_create() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}   [01] ADD ACCOUNT     ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo ""
    read -p " ENTER USERNAME : " u
    if id "$u" &>/dev/null; then echo -e "${RED}❌ ERROR: EXISTS!${NC}"; pause; return; fi
    read -p " ENTER PASSWORD : " p
    echo -e "${CYAN}------------------------${NC}"
    read -p " SET EXPIRY DATE? (Y/N) : " choice
    if [[ "$choice" == "Y" || "$choice" == "y" ]]; then
        read -p " ENTER DATE (YYYY-MM-DD): " d
        read -p " ENTER TIME (HH:MM)     : " t
        [[ -z "$t" ]] && t="23:59"
    else d="NEVER"; t="00:00"; echo -e "${GREEN}ℹ️  SET TO UNLIMITED${NC}"; fi
    
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    echo "$u|$d|$t|V28" >> "$USER_DB"
    echo -e "${GREEN}✔ ACCOUNT CREATED!${NC}"; pause
}

fun_renew() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}  [02] RENEW ACCOUNT    ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo ""
    read -p " ENTER USERNAME  : " u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "${RED}❌ NOT FOUND!${NC}"; pause; return; fi
    read -p " ENTER NEW DATE (YYYY-MM-DD) : " d
    sed -i "/^$u|/d" "$USER_DB"
    echo "$u|$d|23:59|Renew" >> "$USER_DB"
    usermod -U "$u"
    echo -e "${GREEN}✔ RENEWED!${NC}"; pause
}

fun_remove() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${RED}  [03] REMOVE ACCOUNT   ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo ""
    read -p " ENTER USERNAME: " u
    read -p " CONFIRM (Y/N): " c
    if [[ "$c" == "Y" || "$c" == "y" ]]; then
        pkill -u "$u"; userdel -f -r "$u"; sed -i "/^$u|/d" "$USER_DB"
        echo -e "${RED}🗑️ DELETED.${NC}"
    fi
    pause
}

fun_lock() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}   [04] LOCK ACCOUNT    ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo ""
    read -p " ENTER USERNAME: " u
    echo " [1] LOCK ⛔"; echo " [2] UNLOCK 🔓"
    read -p " SELECT: " act
    if [[ "$act" == "1" ]]; then usermod -L "$u"; pkill -KILL -u "$u"; echo -e "${RED}LOCKED.${NC}";
    else usermod -U "$u"; echo -e "${GREEN}UNLOCKED.${NC}"; fi
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
        if pgrep -f "sshd: $u " >/dev/null || pgrep -u "$u" "dropbear" >/dev/null; then st="${GREEN}ONLINE 🟢${NC}"
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
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if pgrep -f "sshd: $u " >/dev/null || pgrep -u "$u" "dropbear" >/dev/null; then
            printf "${YELLOW}%-14s ${NC}| ${GREEN}ONLINE 🟢${NC}\n" "$u"
        fi
    done < "$USER_DB"
    pause
}

fun_save() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}    [07] BACKUP DATA    ${NC}"
    echo -e "${BLUE}========================${NC}"
    cp "$USER_DB" "$BACKUP_DIR/backup_$(date +%F).txt"
    echo -e "${GREEN}✅ DATA BACKED UP!${NC}"; pause
}

# --- 🤖 BOT INSTALLATION (V50 ENGINE) ---
fun_install_bot() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}   INSTALLING BOT...    ${NC}"
    echo -e "${BLUE}========================${NC}"
    
    # 1. Libs
    echo -e ">> INSTALLING LIBS..."
    if [[ -f /etc/debian_version ]]; then apt-get update -y >/dev/null; apt-get install python3 python3-pip -y >/dev/null
    else yum install epel-release -y >/dev/null; yum install python3 python3-pip -y >/dev/null; fi
    pip3 install --upgrade --force-reinstall python-telegram-bot==13.7 schedule >/dev/null 2>&1

    # 2. Cleanup
    systemctl stop sshbot >/dev/null 2>&1
    rm -f /root/ssh_bot.py

    # 3. Write Bot
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, threading, time, datetime
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext, ConversationHandler
from telegram.utils.request import Request

# CREDENTIALS
TOKEN = "7867550558:AAHqNQ6s6lveMXs9CS51g_ZSbcga63sfacE"
ADMIN_ID = 7587310857
DB_FILE = "/etc/xpanel/users_db.txt"

logging.basicConfig(level=logging.ERROR)

(WAIT_U_ADD, WAIT_P_ADD, WAIT_D_ADD, WAIT_U_REN, WAIT_D_REN, WAIT_U_DEL) = range(6)

def run_cmd(c):
    try: subprocess.run(c, shell=True, check=True); return True
    except: return False

def get_status(u):
    if subprocess.getoutput(f"pgrep -f 'sshd: {u} '") or subprocess.getoutput(f"pgrep -u {u} dropbear"): return "ONLINE 🟢"
    if " L " in subprocess.getoutput(f"passwd -S {u}"): return "LOCKED ⛔"
    return "OFFLINE 🔴"

# KEYBOARDS
def main_kb():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ ADD USER", callback_data='add'), InlineKeyboardButton("🔄 RENEW", callback_data='ren')],
        [InlineKeyboardButton("🗑️ DELETE", callback_data='del'), InlineKeyboardButton("📋 LIST", callback_data='list')],
        [InlineKeyboardButton("🟢 ONLINE", callback_data='onl'), InlineKeyboardButton("🔒 LOCK", callback_data='lock')]
    ])
def back_kb(): return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='menu')]])

# HANDLERS
def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    context.user_data.clear()
    update.message.reply_text("*⚡ SSH MANAGER V28.4 BOT (NO-MONITOR)*", parse_mode=ParseMode.MARKDOWN, reply_markup=main_kb())
    return ConversationHandler.END

def menu_cb(update: Update, context: CallbackContext):
    q = update.callback_query
    try: q.answer()
    except: pass
    d = q.data
    
    if d == 'menu':
        context.user_data.clear()
        q.edit_message_text("*⚡ SSH MANAGER V28.4 BOT (NO-MONITOR)*", parse_mode=ParseMode.MARKDOWN, reply_markup=main_kb())
        return ConversationHandler.END
        
    elif d == 'add': q.edit_message_text("👤 ENTER USERNAME:", reply_markup=back_kb()); return WAIT_U_ADD
    elif d == 'ren': q.edit_message_text("🔄 ENTER USERNAME:", reply_markup=back_kb()); return WAIT_U_REN
    elif d == 'del': q.edit_message_text("🗑️ ENTER USERNAME:", reply_markup=back_kb()); return WAIT_U_DEL
    elif d == 'lock': q.edit_message_text("🔒 ENTER USERNAME:", reply_markup=back_kb()); return WAIT_U_DEL
    
    elif d == 'list':
        # Threading prevents freeze on large lists
        threading.Thread(target=do_list, args=(update, q)).start()
        
    elif d == 'onl':
        threading.Thread(target=do_onl, args=(update, q)).start()
        
    return ConversationHandler.END

def do_list(update, q):
    msg = "USER | EXPIRY\n------------------\n"
    if os.path.exists(DB_FILE):
        with open(DB_FILE) as f:
            for l in f:
                p = l.strip().split('|')
                if len(p)>=2: msg += f"`{p[0]:<10}` | {p[1]}\n"
    q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=back_kb())

def do_onl(update, q):
    msg = "USER | STATUS\n------------------\n"
    if os.path.exists(DB_FILE):
        with open(DB_FILE) as f:
            for l in f:
                u = l.strip().split('|')[0]
                st = get_status(u)
                if "ONLINE" in st: msg += f"`{u:<10}` | {st}\n"
    q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=back_kb())

# ADD FLOW
def add_1(update: Update, context: CallbackContext):
    u = update.message.text.strip()
    if run_cmd(f"id {u}"): update.message.reply_text("❌ EXISTS", reply_markup=back_kb()); return WAIT_U_ADD
    context.user_data['u'] = u
    update.message.reply_text("🔑 ENTER PASSWORD:", reply_markup=back_kb()); return WAIT_P_ADD

def add_2(update: Update, context: CallbackContext):
    context.user_data['p'] = update.message.text.strip()
    kb = [[InlineKeyboardButton("30 DAYS", callback_data='30'), InlineKeyboardButton("UNLIMITED", callback_data='0')]]
    update.message.reply_text("📅 CHOOSE DURATION:", reply_markup=InlineKeyboardMarkup(kb)); return WAIT_D_ADD

def add_3(update: Update, context: CallbackContext):
    q = update.callback_query; q.answer()
    days = q.data; u = context.user_data['u']; p = context.user_data['p']
    
    run_cmd(f"useradd -M -s /bin/false {u}")
    run_cmd(f"echo '{u}:{p}' | chpasswd")
    
    if days == '0': d_txt = "NEVER"
    else: d_txt = (datetime.datetime.now() + datetime.timedelta(days=int(days))).strftime('%Y-%m-%d')
    
    with open(DB_FILE, 'a') as f: f.write(f"{u}|{d_txt}|23:59|Bot\n")
    q.edit_message_text(f"✅ CREATED\nUser: `{u}`\nPass: `{p}`\nExp: {d_txt}", parse_mode=ParseMode.MARKDOWN, reply_markup=back_kb())
    return ConversationHandler.END

# RENEW FLOW
def ren_1(update: Update, context: CallbackContext):
    u = update.message.text.strip()
    context.user_data['u'] = u
    update.message.reply_text("📅 ADD DAYS (e.g. 30):", reply_markup=back_kb()); return WAIT_D_REN

def ren_2(update: Update, context: CallbackContext):
    d = update.message.text.strip(); u = context.user_data['u']
    if not d.isdigit(): update.message.reply_text("❌ Invalid", reply_markup=back_kb()); return WAIT_D_REN
    new_d = (datetime.datetime.now() + datetime.timedelta(days=int(d))).strftime('%Y-%m-%d')
    
    lines = []
    with open(DB_FILE, 'r') as f: lines = f.readlines()
    with open(DB_FILE, 'w') as f:
        for l in lines:
            if not l.startswith(f"{u}|"): f.write(l)
        f.write(f"{u}|{new_d}|23:59|RenewBot\n")
        
    run_cmd(f"usermod -U {u}")
    update.message.reply_text(f"✅ RENEWED: {u} -> {new_d}", reply_markup=back_kb()); return ConversationHandler.END

# DELETE FLOW
def del_1(update: Update, context: CallbackContext):
    u = update.message.text.strip()
    run_cmd(f"pkill -u {u}"); run_cmd(f"userdel -f -r {u}")
    
    lines = []
    with open(DB_FILE, 'r') as f: lines = f.readlines()
    with open(DB_FILE, 'w') as f:
        for l in lines:
            if not l.startswith(f"{u}|"): f.write(l)
            
    update.message.reply_text(f"🗑️ DELETED: {u}", reply_markup=back_kb()); return ConversationHandler.END

def main():
    req = Request(connect_timeout=20.0, read_timeout=20.0)
    up = Updater(TOKEN, request_kwargs={'read_timeout': 20, 'connect_timeout': 20}, use_context=True)
    dp = up.dispatcher
    
    conv_add = ConversationHandler(
        entry_points=[CallbackQueryHandler(menu_cb, pattern='^add$')],
        states={
            WAIT_U_ADD: [MessageHandler(Filters.text, add_1)],
            WAIT_P_ADD: [MessageHandler(Filters.text, add_2)],
            WAIT_D_ADD: [CallbackQueryHandler(add_3)]
        }, fallbacks=[CallbackQueryHandler(menu_cb, pattern='^menu$')]
    )
    
    conv_ren = ConversationHandler(
        entry_points=[CallbackQueryHandler(menu_cb, pattern='^ren$')],
        states={
            WAIT_U_REN: [MessageHandler(Filters.text, ren_1)],
            WAIT_D_REN: [MessageHandler(Filters.text, ren_2)]
        }, fallbacks=[CallbackQueryHandler(menu_cb, pattern='^menu$')]
    )
    
    conv_del = ConversationHandler(
        entry_points=[CallbackQueryHandler(menu_cb, pattern='^del$')],
        states={WAIT_U_DEL: [MessageHandler(Filters.text, del_1)]},
        fallbacks=[CallbackQueryHandler(menu_cb, pattern='^menu$')]
    )
    
    dp.add_handler(conv_add); dp.add_handler(conv_ren); dp.add_handler(conv_del)
    dp.add_handler(CommandHandler("start", start)); dp.add_handler(CallbackQueryHandler(menu_cb))
    
    up.start_polling(); up.idle()

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
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sshbot
    systemctl start sshbot
    echo -e "${GREEN}✅ BOT INSTALLED!${NC}"
    pause
}

fun_settings() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}      [08] SETTINGS     ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo " [1] FIX TIMEZONE (TUNISIA)"
    # Option 2 removed (Monitor)
    echo " [3] RESTART SSH SERVICE"
    echo " [4] VIEW LOGS"
    echo -e "${GREEN} [5] INSTALL BOT (Telegram)${NC}"
    echo ""
    read -p " SELECT: " s
    case "$s" in
        1) timedatectl set-timezone Africa/Tunis; echo "DONE.";;
        # 2) removed
        3) service "$SSH_SERVICE" restart; echo "SSH RESTARTED.";;
        4) echo ""; tail -n 10 "$LOG_FILE";;
        5) fun_install_bot ;;
    esac
    pause
}

# --- MAIN MENU ---
while true; do
    clear
    # تم حذف تشغيل المراقبة من هنا

    echo -e "${BLUE}========================${NC}"
    echo -e "${WHITE}  SSH MANAGER (V28.4)   ${NC}"
    echo -e "${WHITE}  OS: ${YELLOW}${OS^^}${NC}"
    echo -e "${BLUE}========================${NC}"
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
    echo -e "${BLUE}========================${NC}"
    read -p " SELECT OPTION: " opt
    
    case "$opt" in
        1|01) fun_create ;; 2|02) fun_renew ;; 3|03) fun_remove ;; 4|04) fun_lock ;;
        5|05) fun_list ;; 6|06) fun_online ;; 7|07) fun_save ;; 8|08) fun_settings ;;
        0|00) clear; exit 0 ;; *) echo "INVALID OPTION"; sleep 1 ;;
    esac
done
