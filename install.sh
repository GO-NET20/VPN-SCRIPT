#!/bin/bash

# ==================================================
#  UNLIMITED SSH BOT INSTALLER - V29.2 🛡️
#  - VERSION: UNLIMITED (No Auto-Kill)
#  - LANGUAGE: ENGLISH ONLY
#  - CREATION: Username & Password Only
# ==================================================

# --- 1. PREPARE SYSTEM ---
echo -e "\033[1;34m>> INSTALLING PYTHON & DEPENDENCIES...\033[0m"
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED >/dev/null 2>&1
apt-get update -y
apt-get install python3-pip net-tools -y
pip3 install python-telegram-bot==13.7 --break-system-packages 2>/dev/null || pip3 install python-telegram-bot==13.7

# --- 2. STOP OLD SERVICE ---
systemctl stop sshbot >/dev/null 2>&1
rm -f /etc/systemd/system/sshbot.service
rm -f /root/ssh_bot.py

# --- 3. CREATE BOT SCRIPT ---
echo -e "\033[1;34m>> CREATING UNLIMITED BOT SCRIPT...\033[0m"
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

if not os.path.exists("/etc/xpanel"): os.makedirs("/etc/xpanel")
if not os.path.exists(DB_FILE): open(DB_FILE, 'a').close()

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
                if len(p) >= 1: users.append(p[0])
    return users

# --- MAIN MENU ---
def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    kb = [
        [InlineKeyboardButton("👤 ADD USER (FAST)", callback_data='add')],
        [InlineKeyboardButton("📋 LIST ALL USERS", callback_data='list')],
        [InlineKeyboardButton("🟢 CHECK ONLINE", callback_data='onl')],
        [InlineKeyboardButton("🗑️ REMOVE USER", callback_data='del')]
    ]
    msg = "*UNLIMITED SSH MANAGER V29.2*\n\nStatus: `Unlimited Multi-Login`"
    if update.callback_query: update.callback_query.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))
    else: update.message.reply_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup(kb))

# --- BUTTON CALLBACKS ---
def btn(update: Update, context: CallbackContext):
    q = update.callback_query; q.answer(); data = q.data
    if data == 'back': start(update, context)
    elif data == 'add': context.user_data['act'] = 'a1'; q.edit_message_text("ENTER USERNAME :")
    elif data == 'list':
        us = get_users()
        msg = "USER LIST:\n\n" + "\n".join([f"• `{u}`" for u in us]) if us else "EMPTY."
        q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]]))
    elif data == 'onl':
        us = get_users()
        msg = "🟢 *ONLINE DEVICES:*\n\n"
        found = False
        for u in us:
            count = subprocess.getoutput(f"netstat -atp 2>/dev/null | grep sshd | grep '{u}' | grep ESTABLISHED | wc -l")
            if int(count) > 0:
                msg += f"👤 `{u}` ⮕ *{count}* Devices\n"
                found = True
        if not found: msg = "NO ONE IS ONLINE."
        q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]]))
    elif data == 'del':
        context.user_data['act'] = 'd1'
        q.edit_message_text("ENTER USERNAME TO REMOVE :")

# --- TEXT INPUT HANDLER ---
def txt(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    msg = update.message.text; act = context.user_data.get('act')
    
    # Fast Create Logic
    if act == 'a1':
        context.user_data.update({'nu': msg, 'act': 'a2'})
        update.message.reply_text(f"👤 USER: `{msg}`\n🔑 NOW ENTER PASSWORD:", parse_mode=ParseMode.MARKDOWN)
    elif act == 'a2':
        u, p = context.user_data['nu'], msg
        if run_cmd(f"useradd -M -s /bin/false {u}"):
            run_cmd(f"echo '{u}:{p}' | chpasswd")
            with open(DB_FILE, 'a') as f: f.write(f"{u}|never|00:00|Unlimited\n")
            res = f"✅ *ACCOUNT CREATED!*\n\n👤 USER : `{u}`\n🔑 PASS : `{p}`\n♾️ EXP  : `NEVER`"
            update.message.reply_text(res, parse_mode=ParseMode.MARKDOWN, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 MENU", callback_data='back')]]))
        else: update.message.reply_text("❌ FAILED: User already exists.")
        context.user_data['act'] = None

    # Remove Logic
    elif act == 'd1':
        u = msg
        run_cmd(f"pkill -u {u}")
        if run_cmd(f"userdel -f -r {u}"):
            run_cmd(f"sed -i '/^{u}|/d' {DB_FILE}")
            update.message.reply_text(f"🗑️ User `{u}` removed.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 MENU", callback_data='back')]]))
        else: update.message.reply_text("❌ User not found.")
        context.user_data['act'] = None

def main():
    up = Updater(TOKEN, use_context=True); dp = up.dispatcher
    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CallbackQueryHandler(btn))
    dp.add_handler(MessageHandler(Filters.text & ~Filters.command, txt))
    up.start_polling(); up.idle()

if __name__ == '__main__': main()
EOF

# --- 4. CREATE SYSTEM SERVICE ---
echo -e "\033[1;34m>> CREATING SERVICE...\033[0m"
cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=Unlimited SSH Bot V29.2
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# --- 5. START BOT ---
systemctl daemon-reload
systemctl enable sshbot
systemctl restart sshbot

echo ""
echo -e "\033[1;32m============================================\033[0m"
echo -e "\033[1;32m✅ UNLIMITED BOT V29.2 INSTALLED!\033[0m"
echo -e "\033[1;32m✅ NO AUTO-KILL | NO EXPIRY | ENGLISH ONLY\033[0m"
echo -e "\033[1;32m============================================\033[0m"
