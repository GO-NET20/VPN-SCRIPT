#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- [ Settings & Config ] ---
USER_DB="/etc/xpanel/users_db.txt"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.sh"
BOT_FILE="/root/ssh_bot.py"
BOT_TOKEN="7867550558:AAHqNQ6s6lveMXs9CS51g_ZSbcga63sfacE"
ADMIN_ID="7587310857"

# --- [ Colors Definition ] ---
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; CYAN='\033[1;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

# --- [ Initializing Directories ] ---
mkdir -p /etc/xpanel && touch "$USER_DB"
timedatectl set-timezone Africa/Tunis

# ==================================================
# 🛡️ 1. MONITORING ENGINE (Background Service)
# ==================================================
pkill -f kp_monitor.sh
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
USER_DB="/etc/xpanel/users_db.txt"
BOT_TOKEN="7867550558:AAHqNQ6s6lveMXs9CS51g_ZSbcga63sfacE"
ADMIN_ID="7587310857"
while true; do
    sleep 5
    [[ ! -f "$USER_DB" ]] && continue
    while IFS='|' read -r user date time note; do
        [[ -z "$user" || "$user" == "root" ]] && continue
        
        # Check Multi-login
        COUNT=$(pgrep -u "$user" | wc -l)
        if [[ "$COUNT" -gt 1 ]]; then
            sleep 30
            RE_COUNT=$(pgrep -u "$user" | wc -l)
            if [[ "$RE_COUNT" -gt 1 ]]; then
                curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$ADMIN_ID" -d "text=🚨 *User Removed (Multi-login)* %0A👤 User: \`$user\`" -d "parse_mode=Markdown" > /dev/null
                pkill -KILL -u "$user"; userdel -f -r "$user"; sed -i "/^$user|/d" "$USER_DB"
            fi
        fi
        
        # Check Expiry
        NOW=$(date +%s)
        EXP_TS=$(date -d "$date $time" +%s 2>/dev/null)
        if [[ -n "$EXP_TS" && "$NOW" -ge "$EXP_TS" ]]; then
             pkill -KILL -u "$user"; userdel -f -r "$user"; sed -i "/^$user|/d" "$USER_DB"
        fi
    done < "$USER_DB"
done
EOF
chmod +x "$MONITOR_SCRIPT"
nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 &

# ==================================================
# 🤖 2. TELEGRAM BOT (Python Implementation)
# ==================================================
cat > "$BOT_FILE" << EOF
import subprocess, os, datetime
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler

TOKEN = "$BOT_TOKEN"
ADMIN_ID = $ADMIN_ID
DB_FILE = "$USER_DB"

def kb():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ Add User", callback_data='h'), InlineKeyboardButton("🔄 Renew", callback_data='h')],
        [InlineKeyboardButton("🗑️ Delete", callback_data='h'), InlineKeyboardButton("🔒 Lock/Unlock", callback_data='h')],
        [InlineKeyboardButton("📋 User List", callback_data='list'), InlineKeyboardButton("🟢 Online Now", callback_data='onl')],
        [InlineKeyboardButton("📤 Backup", callback_data='h'), InlineKeyboardButton("⚙️ System", callback_data='sys')]
    ])

def start(update, context):
    if update.effective_user.id == ADMIN_ID:
        update.message.reply_text("🛡️ *SSH MANAGER V41.0 BOT*", parse_mode=ParseMode.MARKDOWN, reply_markup=kb())

def handle(update, context):
    q = update.callback_query
    q.answer()
    if q.data == 'onl':
        msg = "🟢 *Real-time Online USERS:*%0A"
        if os.path.exists(DB_FILE):
            with open(DB_FILE, 'r') as f:
                for l in f:
                    u = l.split('|')[0]
                    c = subprocess.getoutput(f"pgrep -u {u} | wc -l")
                    if int(c) > 0: msg += f"👤 \`{u}\` -> {c} Devices%0A"
        q.edit_message_text(msg or "No users online.", parse_mode=ParseMode.MARKDOWN, reply_markup=kb())
    elif q.data == 'list':
        msg = "📋 *Full Account List:*%0A"
        if os.path.exists(DB_FILE):
            with open(DB_FILE, 'r') as f:
                for l in f:
                    p = l.strip().split('|')
                    c = subprocess.getoutput(f"pgrep -u {p[0]} | wc -l")
                    st = "🟢" if int(c) > 0 else "🔴"
                    msg += f"{st} \`{p[0]:<10}\` | {p[1]}%0A"
        q.edit_message_text(msg or "Database is empty.", parse_mode=ParseMode.MARKDOWN, reply_markup=kb())

u = Updater(TOKEN, use_context=True)
u.dispatcher.add_handler(CommandHandler("start", start))
u.dispatcher.add_handler(CallbackQueryHandler(handle))
u.start_polling()
EOF

# Install Bot as a System Service
systemctl stop sshbot >/dev/null 2>&1
cat > /etc/systemd/system/sshbot.service << EOF
[Unit]
Description=SSH Bot Service
[Service]
ExecStart=/usr/bin/python3 $BOT_FILE
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable sshbot && systemctl start sshbot

# ==================================================
# 🖥️ 3. SERVER DASHBOARD (Main Menu)
# ==================================================
while true; do
    clear
    UP_TIME=$(uptime -p)
    TOTAL_USERS=$(wc -l < "$USER_DB")
    CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${BLUE}${BOLD}==================================================${NC}"
    echo -e "  ${WHITE}${BOLD}🚀 SSH MANAGER PREMIUM${NC}        ${CYAN}V41.0${NC}"
    echo -e "  ${BLUE}UPTIME:${NC} ${WHITE}$UP_TIME${NC}    ${BLUE}USERS:${NC} ${GREEN}$TOTAL_USERS${NC}"
    echo -e "  ${BLUE}REGION:${NC} ${YELLOW}TUNISIA${NC}         ${BLUE}TIME:${NC} ${WHITE}$CURRENT_DATE${NC}"
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    echo -e "  ${CYAN}[01]${NC} Create New User      ${CYAN}[05]${NC} List All Users"
    echo -e "  ${CYAN}[02]${NC} Renew Account        ${CYAN}[06]${NC} Who is Online"
    echo -e "  ${CYAN}[03]${NC} Delete User          ${CYAN}[07]${NC} Removal Logs"
    echo -e "  ${CYAN}[04]${NC} Lock/Unlock User     ${CYAN}[08]${NC} System Settings"
    echo -e ""
    echo -e "  ${RED}${BOLD}[00] Exit Dashboard${NC}"
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    read -p " Select an option: " opt

    case $opt in
        1|01)
            read -p " Username: " u; read -p " Password: " p
            read -p " Expiry Date (YYYY-MM-DD): " d; read -p " Expiry Time (HH:MM): " t
            if ! date -d "$d $t" >/dev/null 2>&1; then echo "Invalid date format!"; sleep 1; continue; fi
            useradd -M -s /bin/false "$u" && echo "$u:$p" | chpasswd
            echo "$u|$d|$t|V41" >> "$USER_DB"
            curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$ADMIN_ID" -d "text=✅ *New User Created*%0AUser: \`$u\`%0AExp: $d $t" -d "parse_mode=Markdown" > /dev/null
            echo "Done!"; sleep 1 ;;
        5|05)
            clear; printf "%-12s | %-12s | %-10s\n" "USER" "EXPIRY" "STATUS"
            echo "--------------------------------------------------"
            while IFS='|' read -r u d t n; do
                [[ -z "$u" ]] && continue
                c=$(pgrep -u "$u" | wc -l); [[ $c -gt 0 ]] && st="${GREEN}ON($c)${NC}" || st="${RED}OFF${NC}"
                printf "%-12s | %-12s | %b\n" "$u" "$d" "$st"
            done < "$USER_DB"; read -p "Press Enter to return..." ;;
        6|06)
            clear; echo "Currently Online:"; while IFS='|' read -r u d t n; do
            c=$(pgrep -u "$u" | wc -l); [[ $c -gt 0 ]] && echo "- $u ($c devices)"; done < "$USER_DB"; read -p "Enter..." ;;
        3|03) read -p " Enter User to Delete: " u; pkill -KILL -u "$u"; userdel -f -r "$u"; sed -i "/^$u|/d" "$USER_DB"; sleep 1 ;;
        8|08) systemctl restart sshbot; pkill -f kp_monitor.sh; nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 & echo "Services Updated"; sleep 1 ;;
        0|00) exit 0 ;;
    esac
done
