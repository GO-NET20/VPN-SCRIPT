#!/bin/bash

# ==================================================
#  FULL UNLIMITED SSH BOT - V29.4 🛡️
#  - UI: MATCHES IMAGES EXACTLY
#  - VERSION: UNLIMITED (No Auto-Kill)
#  - CREATION: Fast Username & Password Flow
# ==================================================

# --- 1. SYSTEM CLEANUP & PREP ---
echo -e "\033[1;34m>> CLEANING OLD FILES & INSTALLING V29.4...\033[0m"
systemctl stop sshbot >/dev/null 2>&1
rm -f /etc/systemd/system/sshbot.service /root/ssh_bot.py
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED >/dev/null 2>&1
apt-get update -y && apt-get install python3-pip net-tools -y
pip3 install python-telegram-bot==13.7 --break-system-packages 2>/dev/null || pip3 install python-telegram-bot==13.7

mkdir -p /etc/xpanel
touch /etc/xpanel/users_db.txt

# --- 2. CREATE THE BOT SCRIPT ---
cat > /root/ssh_bot.py << 'EOF'
import os, subprocess, threading, time, logging
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

# ==========================================
# 👇 CONFIGURATION (EDIT HERE) 👇
# ==========================================
TOKEN = "7867550558:AAHqNQ6s6lveMXs9CS51g_ZSbcga63sfacE"
ADMIN_ID = 7587310857
# ==========================================

DB_FILE = "/etc/xpanel/users_db.txt"

logging.basicConfig(format='%(asctime)s - %(message)s', level=logging.INFO)

def run_cmd(cmd):
    try:
        subprocess.run(cmd, shell=True, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except: return False

def get_users():
    users = []
    if os.path.exists(DB_FILE):
        with open(DB_FILE, 'r') as f:
            for line in f:
                p = line.strip().split('|')
                if len(p) >= 1: users.append({'u': p[0], 'd': p[1]})
    return users

# --- MAIN MENU (MATCHING IMAGE 1000032127.jpg) ---
def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    kb = [
        [InlineKeyboardButton("👤 ADD USER", callback_data='add')],
        [InlineKeyboardButton("🔄 RENEW USER", callback_data='ren')],
        [InlineKeyboardButton("🗑️ REMOVE USER", callback_data='del')],
        [InlineKeyboardButton("🔒 LOCK / UNLOCK", callback_data='lock')],
        [InlineKeyboardButton("📋 SHOW ALL USERS", callback_data='list')],
        [InlineKeyboardButton("🟢 CHECK ONLINE", callback_data='onl')],
        [InlineKeyboardButton("💾 SAVE DATA", callback_data='bak')],
        [InlineKeyboardButton("⚙️ SETTINGS", callback_data='set')]
    ]
    msg = "*Panel SSH MANAGER*"
    if update.callback_query: update.callback_query.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
    else: update.message.reply_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))

# --- BUTTON HANDLER ---
def btn(update: Update, context: CallbackContext):
    q = update.callback_query; q.answer(); data = q.data
    if data == 'back': start(update, context)
    elif data == 'add': context.user_data['act'] = 'a1'; q.edit_message_text("ENTER USERNAME :")
    elif data == 'ren': context.user_data['act'] = 'r1'; q.edit_message_text("ENTER USERNAME TO RENEW :")
    elif data == 'del': context.user_data['act'] = 'd1'; q.edit_message_text("ENTER USERNAME TO REMOVE :")
    elif data == 'lock': context.user_data['act'] = 'l1'; q.edit_message_text("ENTER USERNAME TO LOCK/UNLOCK :")
    
    elif data == 'list':
        us = get_users()
        msg = "📋 *USER LIST:*\n\n" + "\n".join([f"• `{x['u']:<12} | {x['d']}`" for x in us]) if us else "EMPTY."
        q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]]))
    
    elif data == 'onl':
        us = get_users()
        msg = "🟢 *ONLINE DEVICES:*\n\n"
        found = False
        for x in us:
            count = int(subprocess.getoutput(f"netstat -atp 2>/dev/null | grep sshd | grep '{x['u']}' | grep ESTABLISHED | wc -l") or 0)
            if count > 0:
                msg += f"👤 `{x['u']}` ⮕ *{count}* Devices\n"
                found = True
        if not found: msg = "NO ONE IS ONLINE."
        q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]]))
        
    elif data == 'bak':
        if os.path.exists(DB_FILE): context.bot.send_document(chat_id=ADMIN_ID, document=open(DB_FILE, 'rb'), filename="users_db.txt")
        q.edit_message_text("✅ DATA SAVED!", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]]))
    
    elif data == 'set':
        q.edit_message_text("⚙️ *SETTINGS:*", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🌍 FIX TIME (TUNIS)", callback_data='tz')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]]))
    
    elif data == 'tz':
        run_cmd("timedatectl set-timezone Africa/Tunis")
        q.edit_message_text("🌍 TIME FIXED.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]]))

# --- TEXT INPUT (MATCHING Screenshot Flow) ---
def txt(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    msg = update.message.text; act = context.user_data.get('act')
    
    # 👤 ADD USER FLOW
    if act == 'a1':
        context.user_data.update({'nu': msg, 'act': 'a2'})
        update.message.reply_text(f"👤 USER: `{msg}`\n🔑 ENTER PASSWORD:", parse_mode=ParseMode.MARKDOWN)
    elif act == 'a2':
        u, p = context.user_data['nu'], msg
        if run_cmd(f"useradd -M -s /bin/false {u}"):
            run_cmd(f"echo '{u}:{p}' | chpasswd")
            with open(DB_FILE, 'a') as f: f.write(f"{u}|never|00:00|Unlimited\n")
            res = f"✅ *ACCOUNT CREATED!*\n\n👤 USER : {u}\n🔑 PASS : {p}\n♾️ EXP : NEVER"
            update.message.reply_text(res, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 MENU", callback_data='back')]]))
        else: update.message.reply_text("❌ ERROR: User exists.")
        context.user_data['act'] = None

    # 🗑️ REMOVE USER
    elif act == 'd1':
        run_cmd(f"userdel -f -r {msg}; pkill -u {msg}; sed -i '/^{msg}|/d' {DB_FILE}")
        update.message.reply_text(f"🗑️ `{msg}` REMOVED.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 MENU", callback_data='back')]]))
        context.user_data['act'] = None

    # 🔒 LOCK / UNLOCK TOGGLE
    elif act == 'l1':
        status = subprocess.getoutput(f"passwd -S {msg}")
        if " L " in status: run_cmd(f"usermod -U {msg}"); res = f"🔓 `{msg}` UNLOCKED."
        else: run_cmd(f"usermod -L {msg}; pkill -u {msg}"); res = f"⛔ `{msg}` LOCKED."
        update.message.reply_text(res, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 MENU", callback_data='back')]]))
        context.user_data['act'] = None

    # 🔄 RENEW (Force Never Expire)
    elif act == 'r1':
        if run_cmd(f"usermod -U {msg}"):
            update.message.reply_text(f"🔄 `{msg}` RENEWED (NEVER EXPIRE).", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 MENU", callback_data='back')]]))
        else: update.message.reply_text("❌ USER NOT FOUND.")
        context.user_data['act'] = None

def main():
    up = Updater(TOKEN, use_context=True); dp = up.dispatcher
    dp.add_handler(CommandHandler("start", start)); dp.add_handler(CallbackQueryHandler(btn))
    dp.add_handler(MessageHandler(Filters.text & ~Filters.command, txt))
    up.start_polling(); up.idle()

if __name__ == '__main__': main()
EOF

# --- 3. SYSTEMD SERVICE ---
cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=Unlimited SSH Bot V29.4
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable sshbot && systemctl restart sshbot

echo -e "\033[1;32m✅ INSTALLATION COMPLETE! V29.4 MATCHES YOUR IMAGES.\033[0m"
