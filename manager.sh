#!/bin/bash
# ==================================================================
#  SSH MANAGER V50 - ENTERPRISE EDITION 🛡️
#  - ARCHITECTURE: Threaded Bot + State Machine + Config Separation
#  - STABILITY: Auto-Recovery, Zero-Freeze
#  - DATABASE: Structured (User|Pass|Exp|Plan|Status|Created)
# ==================================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- 1. SETUP PATHS & CONFIG ---
BASE_DIR="/etc/xpanel"
DB_FILE="$BASE_DIR/users_db.txt"
CONFIG_FILE="$BASE_DIR/config.conf"
LOG_FILE="/var/log/kp_manager.log"
BOT_LOG="/var/log/kp_bot.log"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.sh"
BOT_SCRIPT="/root/ssh_bot.py"

# Colors
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; NC='\033[0m'

# --- 2. INITIALIZE SYSTEM ---
init_system() {
    mkdir -p "$BASE_DIR"
    touch "$LOG_FILE" "$BOT_LOG"
    
    # Init DB if not exists
    if [[ ! -s "$DB_FILE" ]]; then
        echo "#USER|PASS|EXPIRY|PLAN|STATUS|CREATED" > "$DB_FILE"
    fi

    # Create Config File (Pre-filled with your Info)
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
MAX_LOGIN=1
BOT_TOKEN='7867550558:AAHqNQ6s6lveMXs9CS51g_ZSbcga63sfacE'
ADMIN_ID=7587310857
EOF
    fi
}

# --- 3. CORE BASH FUNCTIONS ---

core_add_user() {
    local u="$1"
    local p="$2"
    local days="$3"
    
    if id "$u" &>/dev/null; then return 1; fi 
    
    if [[ "$days" == "UNLIMITED" ]]; then
        exp_date="NEVER"
    else
        exp_date=$(date -d "+$days days" +%Y-%m-%d)
    fi
    created_date=$(date +%Y-%m-%d)

    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    
    # Atomic append to DB
    echo "$u|$p|$exp_date|Standard|active|$created_date" >> "$DB_FILE"
    
    echo "$(date) | ADDED USER: $u" >> "$LOG_FILE"
    return 0
}

core_renew_user() {
    local u="$1"
    local days="$2"
    
    if ! id "$u" &>/dev/null; then return 1; fi
    
    # Read current expiry
    current_exp=$(grep "^$u|" "$DB_FILE" | cut -d'|' -f3)
    
    if [[ "$days" == "UNLIMITED" ]]; then
        new_exp="NEVER"
    else
        today=$(date +%Y-%m-%d)
        # If expired or never, start from today. Else add to existing.
        if [[ "$current_exp" == "NEVER" ]] || [[ "$current_exp" < "$today" ]]; then
            new_exp=$(date -d "+$days days" +%Y-%m-%d)
        else
            new_exp=$(date -d "$current_exp +$days days" +%Y-%m-%d)
        fi
    fi
    
    # Update DB using temporary file
    grep -v "^$u|" "$DB_FILE" > "$DB_FILE.tmp"
    # Get other details
    line=$(grep "^$u|" "$DB_FILE")
    IFS='|' read -r user pass old_exp plan status created <<< "$line"
    echo "$u|$pass|$new_exp|$plan|active|$created" >> "$DB_FILE.tmp"
    mv "$DB_FILE.tmp" "$DB_FILE"
    
    usermod -U "$u"
    echo "$(date) | RENEWED USER: $u -> $new_exp" >> "$LOG_FILE"
    return 0
}

core_del_user() {
    local u="$1"
    if ! id "$u" &>/dev/null; then return 1; fi
    
    pkill -KILL -u "$u"
    userdel -f -r "$u" &>/dev/null
    
    grep -v "^$u|" "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
    
    echo "$(date) | DELETED USER: $u" >> "$LOG_FILE"
    return 0
}

# --- 4. MONITOR ENGINE (Optimized) ---
install_monitor() {
    cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
source /etc/xpanel/config.conf
DB="/etc/xpanel/users_db.txt"
LOG="/var/log/kp_manager.log"

while true; do
    sleep 10 # Low CPU usage
    
    if [[ -f "$DB" ]]; then
        today=$(date +%Y-%m-%d)
        
        while IFS='|' read -r u p exp plan st created; do
            [[ "$u" =~ ^#.* ]] && continue
            [[ -z "$u" ]] && continue
            
            # 1. Expiry Check
            if [[ "$exp" != "NEVER" && "$st" == "active" ]]; then
                if [[ "$today" > "$exp" ]]; then
                    usermod -L "$u"
                    pkill -KILL -u "$u"
                    # Update status to expired
                    sed -i "s/^$u|.*|active|/$u|$p|$exp|$plan|expired|/" "$DB"
                    echo "$(date) | EXPIRED: Locked $u" >> "$LOG"
                fi
            fi
            
            # 2. Multi-Login (Ignore root & expired)
            if [[ "$u" == "root" || "$st" != "active" ]]; then continue; fi
            
            # Accurate Counting using pgrep
            count=$(pgrep -f "sshd: $u " | wc -l)
            drop_count=$(pgrep -u "$u" "dropbear" | wc -l)
            total=$((count + drop_count))
            
            if [[ "$total" -gt "$MAX_LOGIN" ]]; then
                # Anti-False Positive: Check again after 15s
                sleep 15
                count2=$(pgrep -f "sshd: $u " | wc -l)
                drop2=$(pgrep -u "$u" "dropbear" | wc -l)
                total2=$((count2 + drop2))
                
                if [[ "$total2" -gt "$MAX_LOGIN" ]]; then
                    pkill -KILL -u "$u"
                    echo "$(date) | MULTI-LOGIN: Kicked $u ($total2 connections)" >> "$LOG"
                fi
            fi
            
        done < "$DB"
    fi
done
EOF
    chmod +x "$MONITOR_SCRIPT"
    
    # Monitor Service
    cat > /etc/systemd/system/kp_monitor.service << 'EOF'
[Unit]
Description=SSH Monitor V50
After=network.target

[Service]
ExecStart=/usr/local/bin/kp_monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable kp_monitor
    systemctl restart kp_monitor
}

# --- 5. ENTERPRISE BOT (Python) ---
install_bot() {
    echo -e "${BLUE}>> INSTALLING PYTHON LIBRARIES...${NC}"
    # Force clean install of compatible libraries
    if [[ -f /etc/debian_version ]]; then
        apt-get update -y >/dev/null
        apt-get install python3 python3-pip -y >/dev/null
    else
        yum install python3 python3-pip -y >/dev/null
    fi
    
    pip3 uninstall python-telegram-bot telegram schedule -y &>/dev/null
    pip3 install python-telegram-bot==13.7 schedule &>/dev/null

    echo -e "${BLUE}>> GENERATING BOT CODE...${NC}"
    cat > "$BOT_SCRIPT" << 'EOF'
import logging, os, subprocess, threading, time
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext, ConversationHandler

# --- CONFIG ---
CONFIG = {}
with open("/etc/xpanel/config.conf") as f:
    for line in f:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            CONFIG[k] = v.strip("'\"")

TOKEN = CONFIG['BOT_TOKEN']
ADMIN_ID = int(CONFIG['ADMIN_ID'])
DB_FILE = "/etc/xpanel/users_db.txt"

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', filename='/var/log/kp_bot.log')
logger = logging.getLogger(__name__)

# --- STATES ---
(ADD_USER, ADD_PASS, ADD_EXPIRY, RENEW_USER, RENEW_DAYS, DEL_USER) = range(6)

# --- UTILS ---
def run_sys(cmd):
    try:
        subprocess.run(cmd, shell=True, check=True)
        return True
    except:
        return False

def get_db():
    users = []
    if os.path.exists(DB_FILE):
        with open(DB_FILE) as f:
            for l in f:
                if l.startswith("#") or not l.strip(): continue
                p = l.strip().split('|')
                if len(p) >= 5: users.append({'u': p[0], 'e': p[2], 's': p[4]})
    return users

# --- MENUS ---
def menu_kb():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ Create", callback_data='add'), InlineKeyboardButton("🔄 Renew", callback_data='renew')],
        [InlineKeyboardButton("🗑️ Delete", callback_data='del'), InlineKeyboardButton("👥 List", callback_data='list')],
        [InlineKeyboardButton("🟢 Online", callback_data='online'), InlineKeyboardButton("📊 Stats", callback_data='stats')]
    ])

def back_kb():
    return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Back", callback_data='menu')]])

# --- HANDLERS ---
def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    context.user_data.clear()
    update.message.reply_text("<b>🔐 SSH MANAGER V50</b>", reply_markup=menu_kb(), parse_mode=ParseMode.HTML)
    return ConversationHandler.END

def menu_callback(update: Update, context: CallbackContext):
    q = update.callback_query
    q.answer()
    
    if q.data == 'menu':
        context.user_data.clear()
        q.edit_message_text("<b>🔐 SSH MANAGER V50</b>", reply_markup=menu_kb(), parse_mode=ParseMode.HTML)
        return ConversationHandler.END
        
    elif q.data == 'add':
        q.edit_message_text("👤 <b>Enter Username:</b>", parse_mode=ParseMode.HTML, reply_markup=back_kb())
        return ADD_USER
        
    elif q.data == 'renew':
        q.edit_message_text("🔄 <b>Enter Username to Renew:</b>", parse_mode=ParseMode.HTML, reply_markup=back_kb())
        return RENEW_USER
        
    elif q.data == 'del':
        q.edit_message_text("🗑️ <b>Enter Username to Delete:</b>", parse_mode=ParseMode.HTML, reply_markup=back_kb())
        return DEL_USER
        
    elif q.data == 'list':
        threading.Thread(target=do_list, args=(update, context)).start()
        
    elif q.data == 'online':
        threading.Thread(target=do_online, args=(update, context)).start()
        
    return ConversationHandler.END

# --- THREADED TASKS ---
def do_list(update, context):
    try:
        us = get_db()
        msg = "<b>📋 Users:</b>\n"
        for u in us:
            icon = "✅" if u['s'] == 'active' else "⛔"
            msg += f"{icon} <code>{u['u']}</code> | {u['e']}\n"
        if not us: msg = "No users."
        context.bot.edit_message_text(chat_id=update.effective_chat.id, message_id=update.callback_query.message.message_id, text=msg, parse_mode=ParseMode.HTML, reply_markup=back_kb())
    except Exception as e: logger.error(e)

def do_online(update, context):
    try:
        us = get_db()
        msg = "<b>🟢 Online:</b>\n"
        cnt = 0
        for u in us:
            if subprocess.getoutput(f"pgrep -f 'sshd: {u['u']} '") or subprocess.getoutput(f"pgrep -u {u['u']} dropbear"):
                msg += f"👤 <code>{u['u']}</code>\n"
                cnt += 1
        if cnt == 0: msg += "No active sessions."
        context.bot.edit_message_text(chat_id=update.effective_chat.id, message_id=update.callback_query.message.message_id, text=msg, parse_mode=ParseMode.HTML, reply_markup=back_kb())
    except Exception as e: logger.error(e)

# --- ADD FLOW ---
def add_user_1(update: Update, context: CallbackContext):
    u = update.message.text.strip()
    if run_sys(f"id {u}"):
        update.message.reply_text("❌ User exists.", reply_markup=back_kb())
        return ADD_USER
    context.user_data['u'] = u
    update.message.reply_text(f"🔑 Password for <b>{u}</b>:", parse_mode=ParseMode.HTML, reply_markup=back_kb())
    return ADD_PASS

def add_user_2(update: Update, context: CallbackContext):
    context.user_data['p'] = update.message.text.strip()
    kb = [[InlineKeyboardButton("30 Days", callback_data='30'), InlineKeyboardButton("Unlimited", callback_data='UNLIMITED')]]
    update.message.reply_text("📅 Select Duration:", reply_markup=InlineKeyboardMarkup(kb))
    return ADD_EXPIRY

def add_user_3(update: Update, context: CallbackContext):
    q = update.callback_query
    q.answer()
    days = q.data
    u = context.user_data['u']
    p = context.user_data['p']
    
    # Execute Bash Logic via subprocess
    cmd = f"/root/manager.sh core_add '{u}' '{p}' '{days}'"
    subprocess.run(f"useradd -M -s /bin/false {u} && echo '{u}:{p}' | chpasswd", shell=True)
    
    # DB Update (Python Side for reliability)
    import datetime
    if days == 'UNLIMITED': exp = "NEVER"
    else: exp = (datetime.datetime.now() + datetime.timedelta(days=int(days))).strftime('%Y-%m-%d')
    now = datetime.datetime.now().strftime('%Y-%m-%d')
    
    with open(DB_FILE, 'a') as f:
        f.write(f"{u}|{p}|{exp}|Standard|active|{now}\n")
        
    q.edit_message_text(f"✅ Created <b>{u}</b>\nExp: {exp}", parse_mode=ParseMode.HTML, reply_markup=back_kb())
    return ConversationHandler.END

# --- RENEW FLOW ---
def renew_1(update: Update, context: CallbackContext):
    u = update.message.text.strip()
    context.user_data['u'] = u
    update.message.reply_text("📅 Enter days to add (e.g. 30):", reply_markup=back_kb())
    return RENEW_DAYS

def renew_2(update: Update, context: CallbackContext):
    days = update.message.text.strip()
    u = context.user_data['u']
    
    # Simplified Renew (DB update + Unlock)
    lines = []
    with open(DB_FILE, 'r') as f: lines = f.readlines()
    
    found = False
    with open(DB_FILE, 'w') as f:
        for l in lines:
            if l.startswith(f"{u}|"):
                found = True
                p = l.strip().split('|')
                import datetime
                new_exp = (datetime.datetime.now() + datetime.timedelta(days=int(days))).strftime('%Y-%m-%d')
                p[2] = new_exp
                p[4] = "active"
                f.write("|".join(p) + "\n")
            else:
                f.write(l)
    
    if found:
        subprocess.run(f"usermod -U {u}", shell=True)
        update.message.reply_text(f"✅ Renewed <b>{u}</b>", parse_mode=ParseMode.HTML, reply_markup=back_kb())
    else:
        update.message.reply_text("❌ User not found.", reply_markup=back_kb())
    return ConversationHandler.END

# --- DELETE FLOW ---
def del_1(update: Update, context: CallbackContext):
    u = update.message.text.strip()
    subprocess.run(f"pkill -u {u}", shell=True)
    subprocess.run(f"userdel -f -r {u}", shell=True)
    
    lines = []
    with open(DB_FILE, 'r') as f: lines = f.readlines()
    with open(DB_FILE, 'w') as f:
        for l in lines:
            if not l.startswith(f"{u}|"): f.write(l)
            
    update.message.reply_text(f"🗑️ Deleted <b>{u}</b>", parse_mode=ParseMode.HTML, reply_markup=back_kb())
    return ConversationHandler.END

def main():
    updater = Updater(TOKEN, use_context=True)
    dp = updater.dispatcher
    
    # State Handlers
    add_handler = ConversationHandler(
        entry_points=[CallbackQueryHandler(menu_callback, pattern='^add$')],
        states={
            ADD_USER: [MessageHandler(Filters.text, add_user_1)],
            ADD_PASS: [MessageHandler(Filters.text, add_user_2)],
            ADD_EXPIRY: [CallbackQueryHandler(add_user_3)]
        },
        fallbacks=[CallbackQueryHandler(menu_callback, pattern='^menu$')]
    )
    
    renew_handler = ConversationHandler(
        entry_points=[CallbackQueryHandler(menu_callback, pattern='^renew$')],
        states={
            RENEW_USER: [MessageHandler(Filters.text, renew_1)],
            RENEW_DAYS: [MessageHandler(Filters.text, renew_2)]
        },
        fallbacks=[CallbackQueryHandler(menu_callback, pattern='^menu$')]
    )
    
    del_handler = ConversationHandler(
        entry_points=[CallbackQueryHandler(menu_callback, pattern='^del$')],
        states={
            DEL_USER: [MessageHandler(Filters.text, del_1)]
        },
        fallbacks=[CallbackQueryHandler(menu_callback, pattern='^menu$')]
    )

    dp.add_handler(add_handler)
    dp.add_handler(renew_handler)
    dp.add_handler(del_handler)
    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CallbackQueryHandler(menu_callback))

    updater.start_polling()
    updater.idle()

if __name__ == '__main__':
    main()
EOF

    # Bot Service (Restart on Failure)
    cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Bot V50
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable sshbot
    systemctl restart sshbot
}

# --- 6. MAIN MENU CLI ---
init_system

while true; do
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}       SSH MANAGER V50 (ENTERPRISE) 🛡️       ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN} [01]${NC} CREATE USER"
    echo -e "${GREEN} [02]${NC} RENEW USER"
    echo -e "${GREEN} [03]${NC} DELETE USER"
    echo -e "${GREEN} [04]${NC} LOCK/UNLOCK"
    echo -e "${GREEN} [05]${NC} LIST USERS"
    echo -e "${GREEN} [06]${NC} ONLINE STATUS"
    echo -e "${GREEN} [07]${NC} BACKUP DATA"
    echo -e "${GREEN} [08]${NC} SETTINGS (INSTALL BOT & MONITOR)"
    echo -e "${GREEN} [00]${NC} EXIT"
    echo -e "${BLUE}==================================================${NC}"
    read -p " Select Option: " opt

    case $opt in
        1|01) 
            read -p " Username: " u; read -p " Password: " p; read -p " Days: " d
            core_add_user "$u" "$p" "$d" && pause ;;
        2|02) 
            read -p " Username: " u; read -p " Days: " d
            core_renew_user "$u" "$d" && pause ;;
        3|03)
            read -p " Username: " u
            core_del_user "$u" && pause ;;
        4|04)
            read -p " Username: " u
            usermod -U "$u" 2>/dev/null || usermod -L "$u"
            echo "Toggled Lock/Unlock"; pause ;;
        5|05)
            echo "USER | EXPIRY | STATUS"; grep -v "#" "$DB_FILE" | cut -d'|' -f1,3,5
            pause ;;
        6|06)
            echo "Checking..."; pgrep -a sshd; pause ;;
        7|07)
            cp "$DB_FILE" "$BASE_DIR/backup.txt"; echo "Done"; pause ;;
        8|08)
            echo "1. Install Monitor"; echo "2. Install Bot"
            read -p "Choice: " c
            if [[ "$c" == "1" ]]; then install_monitor; pause; fi
            if [[ "$c" == "2" ]]; then install_bot; pause; fi
            ;;
        0|00) exit 0 ;;
    esac
done
