#!/bin/bash
apt-get update -y
apt-get install python3-pip -y
pip3 install python-telegram-bot==13.7 schedule

systemctl stop sshbot >/dev/null 2>&1
systemctl disable sshbot >/dev/null 2>&1
rm -f /etc/systemd/system/sshbot.service
rm -f /root/ssh_bot.py

cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, threading, time, datetime
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

TOKEN = "7867550558:AAHqNQ6s6lveMXs9CS51g_ZSbcga63sfacE"
ADMIN_ID = 7587310857

DB_FILE = "/etc/xpanel/users_db.txt"
LOG_FILE = "/var/log/kp_manager.log"
BACKUP_DIR = "/root/backups"

if not os.path.exists("/etc/xpanel"): os.makedirs("/etc/xpanel")
if not os.path.exists(DB_FILE): open(DB_FILE,'a').close()
if not os.path.exists(LOG_FILE): open(LOG_FILE,'a').close()
if not os.path.exists(BACKUP_DIR): os.makedirs(BACKUP_DIR)

logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)

def run_cmd(cmd):
    try: subprocess.run(cmd, shell=True, check=True); return True
    except: return False

def get_users():
    users = []
    if os.path.exists(DB_FILE):
        with open(DB_FILE,'r') as f:
            for line in f:
                parts = line.strip().split('|')
                if len(parts)>=3: users.append({'u':parts[0],'d':parts[1],'t':parts[2]})
    return users

def get_status(u):
    try:
        if not run_cmd(f"id {u}"): return "OFFLINE"
        if " L " in subprocess.getoutput(f"passwd -S {u}"): return "LOCKED"
        check=subprocess.getoutput(f"ps -u {u} -o stat,comm | grep -v 'Z' | grep 'sshd'")
        if check: return "ONLINE"
    except: pass
    return "OFFLINE"

def monitor(updater):
    while True:
        try:
            now=datetime.datetime.now()
            lines_keep=[]
            changed=False
            if os.path.exists(DB_FILE):
                with open(DB_FILE,'r') as f: lines=f.readlines()
                for line in lines:
                    parts=line.strip().split('|')
                    if len(parts)<3: continue
                    u,d,t=parts[0],parts[1],parts[2]
                    kill=False
                    if d!="never":
                        try:
                            exp=datetime.datetime.strptime(f"{d} {t}","%Y-%m-%d %H:%M")
                            if now>=exp:
                                kill=True
                                run_cmd(f"pkill -KILL -u {u}")
                                run_cmd(f"userdel -f -r {u}")
                                updater.bot.send_message(chat_id=ADMIN_ID,text=f"EXPIRED | REMOVED USER: {u}")
                        except: pass
                    if not kill: lines_keep.append(line)
                    else: changed=True
                if changed:
                    with open(DB_FILE,'w') as f: f.writelines(lines_keep)
        except: pass
        time.sleep(3)

def start(update:Update,context:CallbackContext):
    if update.effective_user.id!=ADMIN_ID: return
    kb=[[InlineKeyboardButton("👤 ADD USER",callback_data='add')],
        [InlineKeyboardButton("🔄 RENEW USER",callback_data='ren')],
        [InlineKeyboardButton("🗑️ REMOVE USER",callback_data='del')],
        [InlineKeyboardButton("🔒 LOCK / UNLOCK",callback_data='lock')],
        [InlineKeyboardButton("📋 SHOW ALL USERS",callback_data='list')],
        [InlineKeyboardButton("🟢 CHECK ONLINE",callback_data='onl')],
        [InlineKeyboardButton("💾 SAVE DATA",callback_data='bak')],
        [InlineKeyboardButton("⚙️ SETTINGS",callback_data='set')]]
    msg="*SSH MANAGER PANEL*"
    if update.callback_query:
        update.callback_query.edit_message_text(msg,parse_mode=ParseMode.MARKDOWN,reply_markup=InlineKeyboardMarkup(kb))
    else:
        update.message.reply_text(msg,parse_mode=ParseMode.MARKDOWN,reply_markup=InlineKeyboardMarkup(kb))

def btn(update:Update,context:CallbackContext):
    q=update.callback_query;q.answer();data=q.data
    if data=='add': context.user_data['act']='a1'; q.edit_message_text("ENTER USERNAME:")
    elif data=='ren': context.user_data['act']='r1'; q.edit_message_text("ENTER USERNAME TO RENEW:")
    elif data=='del': context.user_data['act']='d1'; q.edit_message_text("ENTER USERNAME TO REMOVE:")
    elif data=='lock': context.user_data['act']='l1'; q.edit_message_text("ENTER USERNAME:")
    elif data=='list':
        us=get_users()
        msg="NO USERS FOUND." if not us else "USER           | DATE       | TIME\n-----------------------------------\n"+"\n".join([f"{x['u']:<14} | {x['d']:<10} | {x['t']}" for x in us])
        q.edit_message_text(f"```\n{msg}\n```",parse_mode=ParseMode.MARKDOWN,reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))
    elif data=='onl':
        us=get_users()
        if not us: msg="NO USERS FOUND."
        else:
            msg="USER           | STATUS\n-----------------------\n"
            for x in us:
                st=get_status(x['u'])
                if "ONLINE" in st: status_txt="ONLINE 🟢"
                elif "LOCKED" in st: status_txt="LOCKED ⛔"
                else: status_txt="OFFLINE 🔴"
                msg+=f"{x['u']:<14} | {status_txt}\n"
        q.edit_message_text(f"```\n{msg}\n```",parse_mode=ParseMode.MARKDOWN,reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))
    elif data=='bak':
        if os.path.exists(DB_FILE): context.bot.send_document(chat_id=ADMIN_ID,document=open(DB_FILE,'rb'),filename="users_db.txt")
        q.edit_message_text("✅ DATA SAVED SUCCESSFULLY!",reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))
    elif data=='set':
        kb=[[InlineKeyboardButton("🌍 FIX TIMEZONE",callback_data='tz')],[InlineKeyboardButton("🔙 BACK",callback_data='back')]]
        q.edit_message_text("⚙️ SETTINGS:",reply_markup=InlineKeyboardMarkup(kb))
    elif data=='tz': run_cmd("timedatectl set-timezone Africa/Tunis"); q.edit_message_text("🌍 TIMEZONE FIXED (TUNIS).",reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))
    elif data=='back': start(update,context)
    elif data.startswith('LK_'): u=data.split('_')[1]; run_cmd(f"usermod -L {u}"); run_cmd(f"pkill -KILL -u {u}"); q.edit_message_text(f"⛔ USER {u} IS NOW LOCKED.",reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))
    elif data.startswith('UL_'): u=data.split('_')[1]; run_cmd(f"usermod -U {u}"); q.edit_message_text(f"🔓 USER {u} IS NOW UNLOCKED.",reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))
    elif data.startswith('DEL_YES_'):
        u=data.split('_')[2]; run_cmd(f"pkill -u {u}"); run_cmd(f"userdel -f -r {u}")
        lines=[l for l in open(DB_FILE) if not l.startswith(f"{u}|")]
        with open(DB_FILE,'w') as f: f.writelines(lines)
        q.edit_message_text("🗑️ USER REMOVED SUCCESSFULLY.",reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))
    elif data=='DEL_NO': q.edit_message_text("❌ CANCELLED.",reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))

def txt(update:Update,context:CallbackContext):
    if update.effective_user.id!=ADMIN_ID: return
    msg=update.message.text; act=context.user_data.get('act')
    if act=='a1': context.user_data.update({'nu':msg,'act':'a2'}); update.message.reply_text("ENTER PASSWORD:")
    elif act=='a2': context.user_data.update({'np':msg,'act':'a3'}); update.message.reply_text("ENTER DATE (YYYY-MM-DD):")
    elif act=='a3': context.user_data.update({'nd':msg,'act':'a4'}); update.message.reply_text("ENTER TIME (HH:MM) [23:59]:")
    elif act=='a4':
        t=msg if msg else "23:59"; u,p,d=context.user_data['nu'],context.user_data['np'],context.user_data['nd']
        if run_cmd(f"useradd -M -s /bin/false {u}"):
            run_cmd(f"echo '{u}:{p}' | chpasswd")
            with open(DB_FILE,'a') as f: f.write(f"{u}|{d}|{t}|Bot\n")
            res="------------------------------------------\nACCOUNT \nUSER : {}\nPASS : {}\nEXPIRY DATE : {}\nTIME : {}\n------------------------------------------\n`{}:{}`\n------------------------------------------".format(u,p,d,t,u,p)
            kb=[[InlineKeyboardButton("🔙 BACK TO MENU",callback_data='back')]]
            update.message.reply_text(res,parse_mode=ParseMode.MARKDOWN,reply_markup=InlineKeyboardMarkup(kb))
        else: update.message.reply_text("❌ USER ALREADY EXISTS!",reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))
        context.user_data['act']=None
    elif act=='r1': context.user_data.update({'ru':msg,'act':'r2'}); update.message.reply_text("ENTER NEW DATE (YYYY-MM-DD):")
    elif act=='r2': context.user_data.update({'rd':msg,'act':'r3'}); update.message.reply_text("ENTER NEW TIME (HH:MM) [23:59]:")
    elif act=='r3':
        t=msg if msg else "23:59"; u,d=context.user_data['ru'],context.user_data['rd']
        lines=[]; found=False
        with open(DB_FILE,'r') as f:
            for line in f:
                if line.startswith(f"{u}|"): found=True
                else: lines.append(line)
        if found:
            with open(DB_FILE,'w') as f: f.writelines(lines)
            with open(DB_FILE,'a') as f: f.write(f"{u}|{d}|{t}|Renew\n")
            run_cmd(f"usermod -U {u}")
            update.message.reply_text("✅ RENEWED SUCCESSFULLY!",reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))
        else: update.message.reply_text("❌ USER NOT FOUND!",reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK",callback_data='back')]]))
        context.user_data['act']=None
    elif act=='d1': u=msg; kb=[[InlineKeyboardButton("YES",callback_data=f'DEL_YES_{u}'),InlineKeyboardButton("NO",callback_data='DEL_NO')]]; update.message.reply_text(f"ARE YOU SURE YOU WANT TO REMOVE ({u})?",reply_markup=InlineKeyboardMarkup(kb)); context.user_data['act']=None
    elif act=='l1': u=msg; kb=[[InlineKeyboardButton("LOCK",callback_data=f'LK_{u}'),InlineKeyboardButton("UNLOCK",callback_data=f'UL_{u}')]]; update.message.reply_text(f"SELECT ACTION FOR {u}:",reply_markup=InlineKeyboardMarkup(kb)); context.user_data['act']=None

def main():
    up=Updater(TOKEN,use_context=True); dp=up.dispatcher
    dp.add_handler(CommandHandler("start",start))
    dp.add_handler(CallbackQueryHandler(btn))
    dp.add_handler(MessageHandler(Filters.text,txt))
    t=threading.Thread(target=monitor,args=(up,))
    t.daemon=True; t.start()
    up.start_polling(); up.idle()

if __name__=='__main__': main()
EOF

cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Telegram Bot
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
systemctl start sshbot
echo -e "\033[1;32m✅ INSTALLATION COMPLETE! BOT IS RUNNING.\033[0m"
