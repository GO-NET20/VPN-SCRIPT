#!/bin/bash

# --- System Path Setup ---
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- File and Database Paths ---
USER_DB="/etc/xpanel/users_db.txt"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.sh"
BOT_FILE="/root/ssh_bot.py"
LOG_FILE="/var/log/kp_manager.log"

# --- Bot Settings (Updated) ---
BOT_TOKEN="7867550558:AAHqNQ6s6lveMXs9CS51g_ZSbcga63sfacE"
ADMIN_ID="7587310857"

# --- Colors Definition ---
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; CYAN='\033[1;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

# --- Initialization ---
mkdir -p /etc/xpanel && touch "$USER_DB" "$LOG_FILE"
timedatectl set-timezone Africa/Tunis

# ==================================================
# 🛡️ PART 1: MONITORING ENGINE (Background)
# ==================================================
pkill -f kp_monitor.sh
cat > "$MONITOR_SCRIPT" << EOF
#!/bin/bash
while true; do
    sleep 5
    [[ ! -f "$USER_DB" ]] && continue
    while IFS='|' read -r user date time note; do
        [[ -z "\$user" || "\$user" == "root" ]] && continue
        
        # Multi-login Check
        COUNT=\$(pgrep -u "\$user" | wc -l)
        if [[ "\$COUNT" -gt 1 ]]; then
            sleep 30 
            RE_COUNT=\$(pgrep -u "\$user" | wc -l)
            if [[ "\$RE_COUNT" -gt 1 ]]; then
                # Send Alert and Remove User
                curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$ADMIN_ID" -d "text=🚨 *User Removed (Multi-login)* %0A👤 User: \`\$user\` %0A📱 Devices: \$RE_COUNT" -d "parse_mode=Markdown" > /dev/null
                pkill -KILL -u "\$user"; userdel -f -r "\$user"; sed -i "/^\$user|/d" "$USER_DB"
                echo "\$(date) | REMOVED | \$user (Multi-login)" >> "$LOG_FILE"
            fi
        fi
        
        # Expiry Check
        NOW=\$(date +%s)
        EXP_TS=\$(date -d "\$date \$time" +%s 2>/dev/null)
        if [[ -n "\$EXP_TS" && "\$NOW" -ge "\$EXP_TS" ]]; then
             pkill -KILL -u "\$user"; userdel -f -r "\$user"; sed -i "/^\$user|/d" "$USER_DB"
             echo "\$(date) | EXPIRED | \$user" >> "$LOG_FILE"
        fi
    done < "$USER_DB"
done
EOF
chmod +x "$MONITOR_SCRIPT"
nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 &

# ==================================================
# 🤖 PART 2: TELEGRAM BOT (Python)
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
        update.message.reply_text("🛡️ *SSH MANAGER V40.7 BOT*", parse_mode=ParseMode.MARKDOWN, reply_markup=kb())

def handle(update, context):
    q = update.callback_query
    q.answer()
    if q.data == 'onl':
        msg = "🟢 *Real-time Online Users:*%0A---------------------------%0A"
        found = False
        with open(DB_FILE, 'r') as f:
            for l in f:
                u = l.split('|')[0]
                c = subprocess.getoutput(f"pgrep -u {u} | wc -l")
                if int(c) > 0:
                    msg += f"👤 \`{u:<10}\` -> {c} Device(s) 🟢%0A"
                    found = True
        if not found: msg += "No users online."
        q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=kb())
    elif q.data == 'list':
        msg = "📋 *Account List & Status:*%0A---------------------------%0A"
        with open(DB_FILE, 'r') as f:
            for l in f:
                p = l.strip().split('|')
                c = subprocess.getoutput(f"pgrep -u {p[0]} | wc -l")
                st = "🟢" if int(c) > 0 else "🔴"
                msg += f"{st} \`{p[0]:<10}\` | {p[1]} {p[2]}%0A"
        q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=kb())
    elif q.data == 'sys':
        now = datetime.datetime.now().strftime('%H:%M:%S')
        q.edit_message_text(f"⚙️ *System Settings:* %0A⏰ Time: {now} %0A📍 Region: Tunis", parse_mode=ParseMode.MARKDOWN, reply_markup=kb())
    elif q.data == 'h':
        q.edit_message_text("⚠️ Please use the Server Terminal for manual actions.", reply_markup=kb())

u = Updater(TOKEN, use_context=True)
u.dispatcher.add_handler(CommandHandler("start", start))
u.dispatcher.add_handler(CallbackQueryHandler(handle))
u.start_polling()
EOF

# Bot Service Setup
systemctl stop sshbot >/dev/null 2>&1
cat > /etc/systemd/system/sshbot.service << EOF
[Unit]
Description=SSH Bot
[Service]
ExecStart=/usr/bin/python3 $BOT_FILE
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable sshbot && systemctl start sshbot

# ==================================================
# 🖥️ PART 3: SERVER DASHBOARD (Menu)
# ==================================================

while true; do
    clear
    up=\$(uptime -p | sed 's/up //'); total=\$(wc -l < "$USER_DB")
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    echo -e "  ${WHITE}${BOLD}🚀 SSH MANAGER PREMIUM${NC}        ${CYAN}V40.7${NC}"
    echo -e "  ${BLUE}UPTIME:${NC} ${WHITE}\$up${NC}    ${BLUE}TOTAL USERS:${NC} ${GREEN}\$total${NC}"
    echo -e "  ${BLUE}REGION:${NC} ${YELLOW}AFRICA/TUNIS${NC}     ${BLUE}DATE:${NC} ${WHITE}\$(date '+%H:%M:%S')${NC}"
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    echo -e "  ${CYAN}[01]${NC} Create New User      ${CYAN}[05]${NC} List All Users"
    echo -e "  ${CYAN}[02]${NC} Renew Account        ${CYAN}[06]${NC} Who is Online"
    echo -e "  ${CYAN}[03]${NC} Delete User          ${CYAN}[07]${NC} Removal Logs"
    echo -e "  ${CYAN}[04]${NC} Lock/Unlock User     ${CYAN}[08]${NC} ${YELLOW}System Settings${NC}"
    echo -e ""
    echo -e "  ${RED}${BOLD}[00] Exit Dashboard${NC}"
    echo -e "${BLUE}${BOLD}==================================================${NC}"
    read -p " Select an option: " opt
    case \$opt in
        1|01)
            read -p " 👤 USERNAME : " u; read -p " 🔑 PASSWORD : " p
            echo -e "${CYAN}Format: YYYY-MM-DD (e.g., 2026-02-11)${NC}"
            read -p " 📅 DATE     : " d
            echo -e "${CYAN}Format: HH:MM (e.g., 22:00)${NC}"
            read -p " ⏰ TIME     : " t
            if ! date -d "\$d \$t" >/dev/null 2>&1; then echo -e "${RED}Invalid Date/Time!${NC}"; sleep 2; continue; fi
            useradd -M -s /bin/false "\$u" && echo "\$u:\$p" | chpasswd
            echo "\$u|\$d|\$t|V40" >> "$USER_DB"
            clear
            echo -e "${BLUE}==========================================${NC}"
            echo -e "        ${GREEN}${BOLD}ACCOUNT CREATED SUCCESSFULLY${NC}"
            echo -e "${BLUE}==========================================${NC}"
            printf "  USER : %s\n  PASS : %s\n  EXP  : %s %s\n" "\$u" "\$p" "\$d" "\$t"
            echo -e "${BLUE}==========================================${NC}"
            # Send to Bot
            curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$ADMIN_ID" -d "text=✅ *New User Created*%0AUser: \`\$u\`%0APass: \`\$p\`%0AExpiry: \$d \$t" -d "parse_mode=Markdown" > /dev/null
            read -p "Press Enter to return..." ;;
        5|05)
            clear; printf "  %-12s | %-10s | %-5s | %-10s\n" "USER" "DATE" "TIME" "STATUS"
            echo "--------------------------------------------------"
            while IFS='|' read -r u d t n; do
                [[ -z "\$u" ]] && continue
                c=\$(pgrep -u "\$u" | wc -l); [[ \$c -gt 0 ]] && st="${GREEN}ON(\$c)${NC}" || st="${RED}OFF${NC}"
                printf "  %-12s | %-10s | %-5s | %b\n" "\$u" "\$d" "\$t" "\$st"
            done < "$USER_DB"
            read -p "Press Enter to return..." ;;
        6|06)
            clear; echo -e "${GREEN}Users currently online:${NC}"
            while IFS='|' read -r u d t n; do c=\$(pgrep -u "\$u" | wc -l); [[ \$c -gt 0 ]] && echo -e " 👤 \$u is online (\$c device/s)"; done < "$USER_DB"; read -p "Press Enter to return..." ;;
        3|03)
            read -p " Enter Username to Delete: " u; pkill -KILL -u "\$u"; userdel -f -r "\$u"; sed -i "/^\$u|/d" "$USER_DB"; echo "User deleted."; sleep 1 ;;
        8|08)
            systemctl restart sshbot; pkill -f kp_monitor.sh; nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 & echo "Services updated."; sleep 2 ;;
        0|00) exit 0 ;;
    esac
done
