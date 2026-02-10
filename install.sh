#!/bin/bash

# ==================================================
#  UNLIMITED SSH BOT - V29.6 (DESIGN PRO) 🛡️
#  - NEW: COPY-PASTE FRIENDLY ADD USER REPORT
#  - UI: ENHANCED DESIGN & SCANABILITY
#  - VERSION: UNLIMITED (No Auto-Kill / No Expiry)
# ==================================================

# --- 1. SYSTEM PREP ---
echo -e "\033[1;34m>> UPDATING TO V29.6 PRO DESIGN...\033[0m"
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED >/dev/null 2>&1
apt-get update -y && apt-get install python3-pip net-tools -y
pip3 install python-telegram-bot==13.7 --break-system-packages 2>/dev/null || pip3 install python-telegram-bot==13.7

# --- 2. CLEANUP OLD SERVICES ---
systemctl stop sshbot >/dev/null 2>&1
rm -f /etc/systemd/system/sshbot.service /root/ssh_bot.py

# --- 3. CREATE ENHANCED BOT SCRIPT ---
cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, threading, time
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

def run_cmd(cmd):
    try:
        subprocess.run(cmd, shell=True, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except: return False

# --- UI DESIGN HELPER ---
def get_menu_kb():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 ADD USER", callback_data='add'), InlineKeyboardButton("🔄 RENEW USER", callback_data='ren')],
        [InlineKeyboardButton("🗑️ REMOVE USER", callback_data='del'), InlineKeyboardButton("🔒 LOCK / UNLOCK", callback_data='lock')],
        [InlineKeyboardButton("📋 SHOW ALL", callback_data='list'), InlineKeyboardButton("🟢 CHECK ONLINE", callback_data='onl')],
        [InlineKeyboardButton("💾 SAVE DATA", callback_data='bak'), InlineKeyboardButton("⚙️ SETTINGS", callback_data='set')]
    ])

# --- MAIN MENU ---
def start(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    msg = (
        "✨ *Panel SSH MANAGER V29.6*\n"
        "───────────────────\n"
        "🚀 *Status:* `Unlimited Mode`\n"
        "🛡️ *Security:* `Netstat Monitor`\n"
        "───────────────────"
    )
    if update.callback_query: update.callback_query.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=get_menu_kb())
    else: update.message.reply_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=get_menu_kb())

# --- BUTTON LOGIC ---
def btn(update: Update, context: CallbackContext):
    q = update.callback_query; q.answer(); data = q.data
    back_kb = InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK TO MENU", callback_data='back')]])
    
    if data == 'back': start(update, context)
    elif data == 'add': context.user_data['act'] = 'a1'; q.edit_message_text("👤 *ENTER USERNAME:*", parse_mode=ParseMode.MARKDOWN)
    elif data == 'del': context.user_data['act'] = 'd1'; q.edit_message_text("🗑️ *ENTER USERNAME TO REMOVE:*", parse_mode=ParseMode.MARKDOWN)
    elif data == 'lock': context.user_data['act'] = 'l1'; q.edit_message_text("🔒 *ENTER USERNAME TO LOCK/UNLOCK:*", parse_mode=ParseMode.MARKDOWN)
    elif data == 'ren': context.user_data['act'] = 'r1'; q.edit_message_text("🔄 *ENTER USERNAME TO RENEW:*", parse_mode=ParseMode.MARKDOWN)
    
    elif data == 'list':
        users = []
        if os.path.exists(DB_FILE):
            with open(DB_FILE, 'r') as f:
                for l in f:
                    p = l.strip().split('|')
                    if len(p) >= 1: users.append(p[0])
        msg = "📋 *DATABASE USERS:*\n`───────────────────`\n"
        msg += "\n".join([f"• `{u}`" for u in users]) if users else "No users found."
        q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=back_kb)
    
    elif data == 'onl':
        users = []
        if os.path.exists(DB_FILE):
            with open(DB_FILE, 'r') as f:
                for l in f:
                    p = l.strip().split('|')
                    if len(p) >= 1: users.append(p[0])
        msg = "🟢 *ACTIVE CONNECTIONS:*\n`───────────────────`\n"
        found = False
        for u in users:
            count = int(subprocess.getoutput(f"netstat -atp 2>/dev/null | grep sshd | grep '{u}' | grep ESTABLISHED | wc -l") or 0)
            if count > 0:
                msg += f"👤 `{u:<12}` ⮕ *{count}* Devices\n"
                found = True
        if not found: msg += "No active connections."
        q.edit_message_text(msg, parse_mode=ParseMode.MARKDOWN, reply_markup=back_kb)
        
    elif data == 'bak':
        if os.path.exists(DB_FILE): context.bot.send_document(chat_id=ADMIN_ID, document=open(DB_FILE, 'rb'), filename="backup_db.txt", caption="✅ *Database Backup Exported*")
    
    elif data == 'set':
        kb = InlineKeyboardMarkup([[InlineKeyboardButton("🌍 FIX TIME (TUNIS)", callback_data='tz')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
        q.edit_message_text("⚙️ *SYSTEM SETTINGS:*", parse_mode=ParseMode.MARKDOWN, reply_markup=kb)
    
    elif data == 'tz':
        run_cmd("timedatectl set-timezone Africa/Tunis")
        q.edit_message_text("✅ *TIMEZONE UPDATED TO TUNIS.*", parse_mode=ParseMode.MARKDOWN, reply_markup=back_kb)

# --- TEXT FLOW (ADD USER REPORT FIX) ---
def txt(update: Update, context: CallbackContext):
    if update.effective_user.id != ADMIN_ID: return
    msg = update.message.text; act = context.user_data.get('act')
    back_kb = InlineKeyboardMarkup([[InlineKeyboardButton("🔙 MENU", callback_data='back')]])
    
    if act == 'a1':
        context.user_data.update({'nu': msg, 'act': 'a2'})
        update.message.reply_text(f"👤 USER: `{msg}`\n🔑 *NOW ENTER PASSWORD:*", parse_mode=ParseMode.MARKDOWN)
    elif act == 'a2':
        u, p = context.user_data['nu'], msg
        if run_cmd(f"useradd -M -s /bin/false {u}"):
            run_cmd(f"echo '{u}:{p}' | chpasswd")
            with open(DB_FILE, 'a') as f: f.write(f"{u}|never|00:00|Unlimited\n")
            # --- THE NEW REPORT FORMAT ---
            report = (
                "------------------------------------------\n"
                "✅ *SSH ACCOUNT*\n"
                f"👤 *USER:* `{u}`\n"
                f"🔑 *PASS:* `{p}`\n"
                "------------------------------------------\n"
                f"`{u}:{p}`\n"
                "------------------------------------------"
            )
            update.message.reply_text(report, parse_mode=ParseMode.MARKDOWN, reply_markup=back_kb)
        else: update.message.reply_text("❌ *ERROR:* Username already exists.", parse_mode=ParseMode.MARKDOWN)
        context.user_data['act'] = None

    elif act == 'd1':
        run_cmd(f"userdel -f -r {msg}; pkill -u {msg}; sed -i '/^{msg}|/d' {DB_FILE}")
        update.message.reply_text(f"🗑️ *USER* `{msg}` *HAS BEEN REMOVED.*", parse_mode=ParseMode.MARKDOWN, reply_markup=back_kb)
        context.user_data['act'] = None

    elif act == 'l1':
        st = subprocess.getoutput(f"passwd -S {msg}")
        if " L " in st: run_cmd(f"usermod -U {msg}"); res = f"🔓 *USER* `{msg}` *UNLOCKED.*"
        else: run_cmd(f"usermod -L {msg}; pkill -u {msg}"); res = f"⛔ *USER* `{msg}` *LOCKED.*"
        update.message.reply_text(res, parse_mode=ParseMode.MARKDOWN, reply_markup=back_kb)
        context.user_data['act'] = None

def main():
    up = Updater(TOKEN, use_context=True); dp = up.dispatcher
    dp.add_handler(CommandHandler("start", start)); dp.add_handler(CallbackQueryHandler(btn))
    dp.add_handler(MessageHandler(Filters.text & ~Filters.command, txt))
    up.start_polling(); up.idle()

if __name__ == '__main__': main()
EOF

# --- 4. SYSTEMD SERVICE ---
cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=Unlimited SSH Bot V29.6
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

echo -e "\033[1;32m✅ V29.6 INSTALLED! DESIGN AND REPORT FORMAT UPDATED.\033[0m"
