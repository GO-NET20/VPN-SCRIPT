#!/bin/bash
# ==================================================
#  SSH MANAGER V93 (PREMIUM ENGLISH) 💎
#  - FIXED: Monitor list layout (No more 'Turbo/None' bugs)
#  - LANG: 100% Professional English
#  - MODE: Auto-Sequence Users (USER1, USER2...)
#  - ENGINE: 3-Second War Mode (Instant Kick) ⚔️
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
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.sh"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"

# --- ⚠️ CREDENTIALS (PUT YOUR INFO HERE) ⚠️ ---
MY_TOKEN="8275679858:AAGCTP9tsJzCgzXXzgA9hJQ8ooqhlFY8BcA"
MY_ID="7587310857"

# --- COLORS ---
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; PURPLE='\033[1;35m'; CYAN='\033[1;36m'; NC='\033[0m'; WHITE='\033[1;37m'

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"

# ==================================================
#  🛡️ MONITOR ENGINE (WAR MODE: 3 SECONDS)
# ==================================================
pkill -f kp_monitor.sh
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
DB="/etc/xpanel/users_db.txt"
LOG="/var/log/kp_manager.log"
MAX_LOGIN=1

while true; do
    sleep 3
    if [[ -f "$DB" ]]; then
        NOW=$(date +%s)
        while IFS='|' read -r user date time note; do
            [[ -z "$user" || -z "$date" ]] && continue
            
            # Skip invalid lines or headers
            if [[ "$user" == *"V93"* || "$user" == "Turbo" ]]; then continue; fi

            # 1. Expiry Check
            if [[ "$date" != "NEVER" ]]; then
                [[ -z "$time" ]] && time="23:59"
                EXP_TS=$(date -d "$date $time" +%s 2>/dev/null)
                if [[ -n "$EXP_TS" && "$NOW" -ge "$EXP_TS" ]]; then
                    pkill -KILL -u "$user"
                    userdel -f -r "$user" 2>/dev/null
                    sed -i "/^$user|/d" "$DB"
                    continue
                fi
            fi

            # 2. Multi-Login Check (Kick Only)
            if [[ "$user" == "root" ]]; then continue; fi
            c_ssh=$(pgrep -u "$user" "sshd" | wc -l)
            c_drop=$(pgrep -u "$user" "dropbear" | wc -l)
            TOTAL=$((c_ssh + c_drop))
            
            if [[ "$TOTAL" -gt "$MAX_LOGIN" ]]; then
                pkill -KILL -u "$user"
            fi
        done < "$DB"
    fi
done
EOF
chmod +x "$MONITOR_SCRIPT"
if ! pgrep -f "kp_monitor.sh" > /dev/null; then nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 & fi

# ==================================================
#  CLI FUNCTIONS
# ==================================================

pause() { echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"; read; }
draw_header() {
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "           ${WHITE}SSH MANAGER V93 (PREMIUM)${NC}"
    echo -e "${CYAN}==================================================${NC}"
}

fun_create() {
    draw_header
    echo -e "                ${WHITE}AUTO-SEQUENCE USER${NC}"
    echo -e "${CYAN}==================================================${NC}"
    i=1
    while true; do
        u="USER${i}"
        if ! id "$u" &>/dev/null; then break; fi
        ((i++))
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
    echo "$u|$d|$t|V93" >> "$USER_DB"
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
        pkill -u "$u"; userdel -f -r "$u"; sed -i "/^$u|/d" "$USER_DB"
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
    printf "%-12s | %-12s\n" "USER" "STATUS"
    echo "--------------------------------"
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             if ps -ef | grep "sshd: $u" | grep -v grep > /dev/null 2>&1 || pgrep -u "$u" > /dev/null 2>&1; then
                printf "%-12s | ${GREEN}ON${NC}\n" "$u"
             else
                printf "%-12s | ${RED}OFF${NC}\n" "$u"
             fi
        fi
    done < "$USER_DB"; pause
}

# ==================================================
#  🤖 BOT INSTALLER (V93 PREMIUM)
# ==================================================
fun_install_bot() {
    pkill -f ssh_bot.py
    systemctl stop sshbot >/dev/null 2>&1
    clear; echo -e "${YELLOW}INSTALLING BOT V93...${NC}"
    echo "BOT_TOKEN=\"$MY_TOKEN\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$MY_ID\"" >> "$BOT_CONF"
    chmod 600 "$BOT_CONF"
    eval "$CMD python3 python3-pip" >/dev/null 2>&1
    pip3 install python-telegram-bot==13.7 schedule >/dev/null 2>&1
    
    cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Bot V93
After=network.target network-online.target
[Service]
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, time
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')

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
        shadow = subprocess.getoutput(f"grep '^{u}:' /etc/shadow")
        if "!" in shadow.split(":")[1] or "*" in shadow.split(":")[1]: return "⛔ LOCKED"
        if subprocess.getoutput(f"pgrep -u {u}"): return "🟢 ON "
    except: pass
    return "🔴 OFF"

def get_back_btn(): return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]])

def get_main_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 ADD USER (AUTO)", callback_data='add')],
        [InlineKeyboardButton("🔄 RENEW", callback_data='ren'), InlineKeyboardButton("🗑️ DELETE", callback_data='del')],
        [InlineKeyboardButton("🔒 LOCK / UNLOCK", callback_data='lock')],
        [InlineKeyboardButton("📋 USER LIST", callback_data='list'), InlineKeyboardButton("⚡ MONITOR", callback_data='onl')],
        [InlineKeyboardButton("💾 BACKUP", callback_data='bak'), InlineKeyboardButton("⚙️ SETTINGS", callback_data='set')]
    ])

def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    try: update.message.reply_text("💎 *SSH MANAGER V93*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_menu())
    except: pass

def btn(update: Update, context: CallbackContext):
    q = update.callback_query; 
    try: q.answer()
    except: pass
    data = q.data
    
    if data == 'back': 
        context.user_data.clear()
        q.edit_message_text("💎 *SSH MANAGER V93*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_main_menu())
        return

    try:
        if data == 'add': 
            i = 1
            while True:
                u = f"USER{i}"
                if subprocess.run(f"id {u}", shell=True).returncode != 0: break
                i += 1
            context.user_data['nu'] = u
            context.user_data['np'] = "12345"
            context.user_data['act']='a_date'
            q.edit_message_text(f"👤 *NEW USER:* `{u}`\n🔑 *PASS:* `12345`\n\n📅 *ENTER DATE (YYYY-MM-DD):*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        
        elif data == 'ren': context.user_data['act']='r1'; q.edit_message_text("🔄 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'del': context.user_data['act']='d1'; q.edit_message_text("🗑️ *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        
        elif data == 'del_yes':
            u = context.user_data.get('del_u')
            subprocess.run(f"pkill -u {u}", shell=True); subprocess.run(f"userdel -f -r {u}", shell=True)
            lines = [l for l in open(DB_FILE) if not l.startswith(f"{u}|")]
            with open(DB_FILE, 'w') as f: f.writelines(lines)
            q.edit_message_text(f"✅ *USER {u} DELETED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        
        elif data == 'lock': context.user_data['act']='l1'; q.edit_message_text("🔒 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'do_lock':
            u = context.user_data.get('lock_u'); subprocess.run(f"usermod -L {u}", shell=True); subprocess.run(f"pkill -KILL -u {u}", shell=True)
            q.edit_message_text(f"⛔ *USER {u} LOCKED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'do_unlock':
            u = context.user_data.get('lock_u'); subprocess.run(f"usermod -U {u}", shell=True)
            q.edit_message_text(f"🟢 *USER {u} UNLOCKED!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        
        elif data == 'list':
            body = "👤 *USER* | 📅 *EXPIRY*\n"
            body += "---------------------------\n"
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        p = l.split('|')
                        if len(p)<2 or "Turbo" in l: continue
                        body += f"`{p[0]:<12}` | {p[1]}\n"
            q.edit_message_text(body, parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

        elif data == 'onl':
            body = "👤 *USER* | ⚡ *STATUS*\n"
            body += "---------------------------\n"
            count = 0
            if os.path.exists(DB_FILE):
                with open(DB_FILE) as f:
                    for l in f:
                        u = l.split('|')[0]
                        if not u or "Turbo" in u or "V9" in u: continue 
                        if subprocess.run(f"id {u}", shell=True).returncode != 0: continue
                        st = get_status(u)
                        body += f"`{u:<12}` | {st}\n"
                        count += 1
            if count == 0: body += "🚫 NO USERS FOUND"
            q.edit_message_text(body, parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())

        elif data == 'bak':
            if os.path.exists(DB_FILE): context.bot.send_document(chat_id=ADMIN_ID, document=open(DB_FILE, 'rb'))
            q.edit_message_text("✅ *BACKUP SENT!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif data == 'set': 
            q.edit_message_text("⚙️ *SETTINGS*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("♻️ UPDATE BOT", callback_data='ins')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]]))
        
        elif data == 'ins': q.edit_message_text("♻️ *RESTARTING...*", parse_mode=ParseMode.MARKDOWN); subprocess.Popen("systemctl restart sshbot", shell=True)

    except Exception as e: logging.error(f"Btn error: {e}")

def create_user_final(update, context, d, t):
    try:
        u = context.user_data.get('nu'); p = context.user_data.get('np')
        if subprocess.run(f"useradd -M -s /bin/false {u}", shell=True).returncode == 0:
            subprocess.run(f"echo '{u}:{p}' | chpasswd", shell=True)
            with open(DB_FILE, 'a') as f: f.write(f"{u}|{d}|{t}|Bot\n")
            msg = f"━━━━━━━━━━━━━━━━━━\n✅ *ACCOUNT CREATED*\n━━━━━━━━━━━━━━━━━━\n👤 *User :* `{u}`\n🔑 *Pass :* `{p}`\n📅 *Date :* {d}\n⏰ *Time :* {t}\n━━━━━━━━━━━━━━━━━━\n📋 `{u}:{p}`"
            kb = get_back_btn()
            if update.callback_query: update.callback_query.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=kb)
            else: update.message.reply_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=kb)
    except: pass

def txt(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    msg = update.message.text; act = context.user_data.get('act')
    try:
        if act == 'a_date': 
            context.user_data.update({'nd':msg,'act':'a_time'}); update.message.reply_text("⏰ *ENTER TIME (HH:MM):*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif act == 'a_time': 
            create_user_final(update, context, context.user_data['nd'], msg)
        elif act == 'r1': context.user_data.update({'ru':msg,'act':'r2'}); update.message.reply_text("📅 *NEW DATE (YYYY-MM-DD):*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif act == 'r2': context.user_data.update({'rd':msg,'act':'r3'}); update.message.reply_text("⏰ *NEW TIME (HH:MM):*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif act == 'r3':
            u=context.user_data['ru']; lines=[l for l in open(DB_FILE) if not l.startswith(f"{u}|")]; lines.append(f"{u}|{context.user_data['rd']}|{msg}|Renew\n")
            with open(DB_FILE, 'w') as f: f.writelines(lines)
            update.message.reply_text("✅ *RENEWED SUCCESS!*", parse_mode=ParseMode.MARKDOWN, reply_markup=get_back_btn())
        elif act == 'd1': 
            context.user_data['del_u']=msg; kb=[[InlineKeyboardButton("🗑️ YES DELETE", callback_data='del_yes'), InlineKeyboardButton("🔙 CANCEL", callback_data='back')]]
            update.message.reply_text(f"⚠️ *DELETE USER {msg}?*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
        elif act == 'l1': 
            context.user_data['lock_u']=msg; kb=[[InlineKeyboardButton("🔒 LOCK", callback_data='do_lock'), InlineKeyboardButton("🔓 UNLOCK", callback_data='do_unlock')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]]
            update.message.reply_text(f"⚙️ *MANAGE {msg}*", parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
    except: pass

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
    echo -e "${GREEN}✅ BOT V93 INSTALLED!${NC}"; pause
}

# --- MAIN LOOP ---
while true; do
    draw_header
    echo -e " ${GREEN}[01]${NC} 👤 ADD ACCOUNT (AUTO)"
    echo -e " ${GREEN}[02]${NC} 🔄 RENEW ACCOUNT"
    echo -e " ${GREEN}[03]${NC} 🗑️ REMOVE ACCOUNT"
    echo -e " ${GREEN}[04]${NC} 🔐 LOCK ACCOUNT"
    echo -e " ${GREEN}[05]${NC} 📋 LIST ACCOUNTS"
    echo -e " ${GREEN}[06]${NC} ⚡ MONITOR USERS"
    echo -e " ${GREEN}[07]${NC} 💾 BACKUP DATA"
    echo -e " ${GREEN}[08]${NC} ⚙️ SETTINGS"
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
        6|06) fun_list ;; 
        7|07) fun_backup ;; 
        8|08) fun_settings ;; 
        0|00) exit 0 ;;
        *) echo -e "${RED} Invalid Option!${NC}" ; sleep 1 ;;
    esac
    
