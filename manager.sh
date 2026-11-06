#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

trap '' HUP PIPE

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

USER_DB="/etc/xpanel/users_db.txt"
TROJAN_DB="/etc/xpanel/trojan_db.txt"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_ACCESS_LOG="/var/log/xray/access.log"
BOT_CONF="/etc/xpanel/bot.conf"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.py"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"
MIGRATION_FILE="/root/migration_users.txt"
MIGRATION_TROJAN="/root/migration_trojan.txt"
VENV_DIR="/etc/xpanel/venv"
PYTHON_BIN="$VENV_DIR/bin/python3"
PIP_BIN="$VENV_DIR/bin/pip3"
DB_LOCK="/etc/xpanel/.db.lock"

RED=$'\033[1;31m'; B_RED=$'\033[1;31m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'; CYAN=$'\033[1;36m'; L_BLUE=$'\033[1;36m'; D_BLUE=$'\033[0;34m'
NC=$'\033[0m'; WHITE=$'\033[1;37m'
LINE="${BLUE}===============================================${NC}"

mkdir -p /etc/xpanel "$BACKUP_DIR" /var/log/xray /usr/local/etc/xray
touch "$USER_DB" "$TROJAN_DB" "$LOG_FILE" "$DB_LOCK" "$XRAY_ACCESS_LOG"
chmod 666 "$XRAY_ACCESS_LOG" 2>/dev/null
[[ ! -f "$BOT_CONF" ]] && touch "$BOT_CONF"

if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null || ! command -v curl &> /dev/null || ! command -v unzip &> /dev/null || ! command -v fuser &> /dev/null; then
eval "$CMD python3 python3-pip python3-venv systemd-logind curl unzip iproute2 psmisc" > /dev/null 2>&1
fi

if [ ! -d "$VENV_DIR" ]; then
python3 -m venv "$VENV_DIR"
fi

sync_trojan_xray() {
python3 - << 'PYEOF'
import json, os, subprocess

trojan_db = "/etc/xpanel/trojan_db.txt"
xray_conf = "/usr/local/etc/xray/config.json"

if not os.path.exists(xray_conf):
    exit(0)

try:
    with open(xray_conf, "r") as f:
        cfg = json.load(f)
except Exception:
    exit(0)

clients = []
if os.path.exists(trojan_db):
    with open(trojan_db, "r") as f:
        for line in f:
            parts = line.strip().split("|")
            if len(parts) >= 3:
                pwd, exp_d, exp_t = parts[0], parts[1], parts[2]
                st = parts[3] if len(parts) >= 4 else "ACTIVE"
                if exp_d != "EXPIRED" and st == "ACTIVE":
                    clients.append({"password": pwd, "email": pwd, "level": 0})

cfg["log"] = {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
}
cfg["stats"] = {}
cfg["api"] = {
    "tag": "api",
    "services": ["HandlerService", "LoggerService", "StatsService"]
}
cfg["policy"] = {
    "levels": {
        "0": {
            "statsUserUplink": True,
            "statsUserDownlink": True,
            "statsUserOnline": True
        }
    },
    "system": {
        "statsInboundUplink": True,
        "statsInboundDownlink": True
    }
}

inbounds = cfg.get("inbounds", [])
has_api_in = False
updated = False

for inbound in inbounds:
    if inbound.get("tag") == "api":
        has_api_in = True
    if inbound.get("protocol") == "trojan":
        if "settings" not in inbound:
            inbound["settings"] = {}
        inbound["settings"]["clients"] = clients
        updated = True

if not has_api_in:
    inbounds.append({
        "listen": "127.0.0.1",
        "port": 10085,
        "protocol": "dokodemo-door",
        "settings": {"address": "127.0.0.1"},
        "tag": "api"
    })
cfg["inbounds"] = inbounds

routing = cfg.get("routing", {})
rules = routing.get("rules", [])
if not any(r.get("outboundTag") == "api" for r in rules):
    rules.insert(0, {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "type": "field"
    })
routing["rules"] = rules
cfg["routing"] = routing

if updated:
    with open(xray_conf, "w") as f:
        json.dump(cfg, f, indent=2)
    subprocess.Popen(
        "sleep 0.6 && systemctl restart xray >/dev/null 2>&1",
        shell=True,
        start_new_session=True
    )
PYEOF
}

get_trojan_online_counts() {
python3 - << 'PYEOF'
import subprocess, json, re, os, datetime

xray_bin = "/usr/local/bin/xray"
if not os.path.exists(xray_bin):
    xray_bin = "xray"

xray_conf = "/usr/local/etc/xray/config.json"
access_log = "/var/log/xray/access.log"
counts = {}

xray_port = 2000
try:
    with open(xray_conf, "r") as f:
        cfg = json.load(f)
        for ib in cfg.get("inbounds", []):
            if ib.get("protocol") == "trojan":
                xray_port = ib.get("port", 2000)
except Exception:
    pass

active_tcp_sockets = 0
try:
    ss_out = subprocess.getoutput(f"ss -tn state established '( dport = :{xray_port} or sport = :{xray_port} )' 2>/dev/null")
    lines = [l for l in ss_out.splitlines() if str(xray_port) in l]
    active_tcp_sockets = len(lines)
except Exception:
    active_tcp_sockets = 1

if active_tcp_sockets == 0:
    print("{}")
    exit(0)

api_worked = False
try:
    res = subprocess.run(
        [xray_bin, "api", "statsquery", "--server=127.0.0.1:10085", "-pattern", "user>>>"],
        capture_output=True, text=True, timeout=2
    )
    if res.returncode == 0 and res.stdout.strip():
        data = json.loads(res.stdout)
        for item in data.get("stat", []):
            name = item.get("name", "")
            val = int(item.get("value", 0))
            if ">>>online" in name:
                api_worked = True
                parts = name.split(">>>")
                if len(parts) >= 2 and val > 0:
                    counts[parts[1]] = val
except Exception:
    pass

if not api_worked and not counts and os.path.exists(access_log):
    try:
        now = datetime.datetime.now()
        tail_lines = subprocess.getoutput(f"tail -n 500 {access_log} 2>/dev/null").splitlines()
        user_ips = {}
        for line in tail_lines:
            if "email:" not in line:
                continue
            m_time = re.match(r"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", line)
            if m_time:
                try:
                    t_log = datetime.datetime.strptime(m_time.group(1), "%Y/%m/%d %H:%M:%S")
                    if (now - t_log).total_seconds() > 25:
                        continue
                except Exception:
                    pass
            m_email = re.search(r"email:\s*([^\s]+)", line)
            m_src = re.search(r"from\s+(?:tcp:)?([0-9a-fA-F.:]+):\d+", line)
            if m_email:
                usr = m_email.group(1).strip()
                ip = m_src.group(1) if m_src else "session"
                user_ips.setdefault(usr, set()).add(ip)
        for u, ips in user_ips.items():
            counts[u] = len(ips)
    except Exception:
        pass

print(json.dumps(counts))
PYEOF
}

cat > "$MONITOR_SCRIPT" << 'EOF'
#!/usr/bin/env python3
import datetime, subprocess, os, time, fcntl, json
import urllib.request, urllib.parse

DB_FILE = "/etc/xpanel/users_db.txt"
TROJAN_DB = "/etc/xpanel/trojan_db.txt"
XRAY_CONF = "/usr/local/etc/xray/config.json"
LOCK_FILE = "/etc/xpanel/.db.lock"
CONF_FILE = "/etc/xpanel/bot.conf"
LOG_FILE = "/var/log/kp_manager.log"
alert_cache = {}

def load_config():
    c = {}
    try:
        for l in open(CONF_FILE):
            if "=" in l: k, v = l.strip().split("=", 1); c[k] = v.strip().replace('"', '')
    except: pass
    return c

def log_event(msg):
    try:
        timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        with open(LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {msg}\n")
    except: pass

def send_alert(msg, user_key):
    try:
        cfg = load_config()
        if cfg.get("ALERTS") != "ON": return
        now = time.time()
        if user_key in alert_cache and now - alert_cache[user_key] < 60: return
        alert_cache[user_key] = now
        token = cfg.get("BOT_TOKEN")
        admin = cfg.get("ADMIN_ID")
        if token and admin:
            url = f"https://api.telegram.org/bot{token}/sendMessage"
            data = urllib.parse.urlencode({'chat_id': admin, 'text': msg, 'parse_mode': 'HTML'}).encode('utf-8')
            req = urllib.request.Request(url, data=data)
            urllib.request.urlopen(req, timeout=3)
    except: pass

def kill_user(user):
    os.system(f"usermod -L {user} >/dev/null 2>&1")
    os.system(f"pkill -9 -u {user} >/dev/null 2>&1")
    os.system(f"ps xaf | grep -E 'sshd|dropbear' | grep ' {user} ' | grep -v grep | awk '{{print $1}}' | xargs -r kill -9 >/dev/null 2>&1")
    os.system(f"loginctl terminate-user {user} >/dev/null 2>&1")

def sync_xray():
    if not os.path.exists(XRAY_CONF): return
    try:
        with open(XRAY_CONF, "r") as f:
            cfg = json.load(f)
        clients = []
        if os.path.exists(TROJAN_DB):
            with open(TROJAN_DB, "r") as f:
                for line in f:
                    parts = line.strip().split("|")
                    if len(parts) >= 3:
                        pwd, exp_d, exp_t = parts[0], parts[1], parts[2]
                        st = parts[3] if len(parts) >= 4 else "ACTIVE"
                        if exp_d != "EXPIRED" and st == "ACTIVE":
                            clients.append({"password": pwd, "email": pwd, "level": 0})
        for inbound in cfg.get("inbounds", []):
            if inbound.get("protocol") == "trojan":
                inbound.setdefault("settings", {})["clients"] = clients
        with open(XRAY_CONF, "w") as f:
            json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "xray"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except: pass

def check_loop():
    while True:
        try:
            with open(LOCK_FILE, "a") as lock_f:
                fcntl.flock(lock_f, fcntl.LOCK_EX)
                now = datetime.datetime.now()
                if os.path.exists(DB_FILE):
                    with open(DB_FILE, 'r+') as f:
                        lines = f.readlines()
                        new_lines = []
                        status_changed = False
                        for line in lines:
                            parts = line.strip().split('|')
                            if len(parts) < 3: continue
                            user, exp_date, exp_time = parts[0], parts[1], parts[2]
                            if "V1" in user or "Turbo" in user or user == "root":
                                new_lines.append(line); continue
                            expired = False
                            if exp_date.upper() not in ["NEVER", "EXPIRED"]:
                                try:
                                    exp = datetime.datetime.strptime(f"{exp_date} {exp_time}", "%Y-%m-%d %H:%M")
                                    if now >= exp:
                                        kill_user(user)
                                        status_changed = True; expired = True
                                        log_event(f"ACCOUNT EXPIRED [SSH]: {user} locked and disconnected.")
                                        send_alert(f"🔒 <b>SSH ACCOUNT EXPIRED</b>\n\n👤 User: <code>{user}</code>\n🛑 Account forcefully disconnected.", f"ssh_{user}_exp")
                                except: pass
                            if expired:
                                new_lines.append(f"{user}|EXPIRED|00:00\n")
                            else:
                                new_lines.append(line)
                        if status_changed:
                            f.seek(0); f.writelines(new_lines); f.truncate()
                if os.path.exists(TROJAN_DB):
                    with open(TROJAN_DB, 'r+') as f:
                        t_lines = f.readlines()
                        new_t_lines = []
                        t_changed = False
                        for line in t_lines:
                            parts = line.strip().split('|')
                            if len(parts) < 3: continue
                            pwd, exp_date, exp_time = parts[0], parts[1], parts[2]
                            st = parts[3] if len(parts) >= 4 else "ACTIVE"
                            expired = False
                            if exp_date.upper() not in ["NEVER", "EXPIRED"]:
                                try:
                                    exp = datetime.datetime.strptime(f"{exp_date} {exp_time}", "%Y-%m-%d %H:%M")
                                    if now >= exp:
                                        t_changed = True; expired = True
                                        log_event(f"ACCOUNT EXPIRED [TROJAN]: {pwd} locked and disconnected.")
                                        send_alert(f"🔒 <b>TROJAN ACCOUNT EXPIRED</b>\n\n🔑 Password: <code>{pwd}</code>\n🛑 Removed from Xray active clients.", f"trj_{pwd}_exp")
                                except: pass
                            if expired:
                                new_t_lines.append(f"{pwd}|EXPIRED|00:00|LOCKED\n")
                            else:
                                new_t_lines.append(f"{pwd}|{exp_date}|{exp_time}|{st}\n")
                        if t_changed:
                            f.seek(0); f.writelines(new_t_lines); f.truncate()
                sync_xray()
                fcntl.flock(lock_f, fcntl.LOCK_UN)
        except: pass
        time.sleep(10)

if __name__ == "__main__":
    check_loop()
EOF
chmod +x "$MONITOR_SCRIPT"

cat > /etc/systemd/system/kp_monitor.service << EOF
[Unit]
Description=SSH & Trojan Monitor & Alerts
After=network.target
[Service]
ExecStart=$PYTHON_BIN /usr/local/bin/kp_monitor.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kp_monitor >/dev/null 2>&1
systemctl restart kp_monitor

sync_trojan_xray

pause() { echo -e "\n${BLUE}PRESS [ENTER] TO RETURN...${NC}"; read; }

draw_header() {
clear
echo -e "${LINE}"
echo -e " ${BLUE}=== SSH & TROJAN • MANAGER ===${NC}"
echo -e "${LINE}"
}

select_protocol() {
echo -e " ${BLUE}[1] SSH${NC}"
echo -e " ${BLUE}[2] TROJAN${NC}"
echo -e " ${BLUE}[0] BACK${NC}\n${LINE}"
echo -ne " ${BLUE}SELECT PROTOCOL: ${NC}"
read proto_choice
}

fun_create() {
draw_header
echo -e " 👤 ${BLUE}CREATE ACCOUNT${NC}\n${LINE}"
select_protocol
case "$proto_choice" in
1)
draw_header
echo -e " 🛡️ ${BLUE}CREATE SSH ACCOUNT${NC}\n${LINE}"
echo -ne " ${BLUE}👤 Enter Username : ${NC}"
read u
if [[ -z "$u" ]]; then echo -e "\n${RED} ❌ Username cannot be empty!${NC}"; pause; return; fi
if [[ ! "$u" =~ ^[a-zA-Z0-9_]+$ ]]; then echo -e "\n${RED} ❌ Invalid Username! Use only letters and numbers.${NC}"; pause; return; fi
if id "$u" &>/dev/null || grep -q "^$u|" "$USER_DB"; then echo -e "\n${RED} ❌ USER ALREADY EXISTS!${NC}"; pause; return; fi

echo -ne " ${BLUE}🔑 Enter Password : ${NC}"
read p
if [[ -z "$p" ]]; then echo -e "\n${RED} ❌ Password cannot be empty!${NC}"; pause; return; fi
echo -ne " ${BLUE}⏳ Set Expiry Date [Y/N] : ${NC}"
read exp_choice
if [[ "${exp_choice,,}" == "y" ]]; then
echo -ne " ${BLUE}📅 Enter number of days : ${NC}"
read CUSTOM_DAYS
if [[ "$CUSTOM_DAYS" =~ ^[0-9]+$ ]] && [ "$CUSTOM_DAYS" -gt 0 ]; then
START_TIMESTAMP=$(date +%s)
SECONDS_IN_DURATION=$(( CUSTOM_DAYS * 24 * 60 * 60 ))
EXPIRATION_TIMESTAMP=$(( START_TIMESTAMP + SECONDS_IN_DURATION ))
d=$(date -d "@$EXPIRATION_TIMESTAMP" +"%Y-%m-%d")
t=$(date -d "@$EXPIRATION_TIMESTAMP" +"%H:%M")
else
echo -e "\n${RED} ❌ Invalid number of days! Setting to NEVER.${NC}"
sleep 2; d="NEVER"; t="00:00"
fi
else
d="NEVER"; t="00:00"
fi
useradd -M -s /bin/false "$u" >/dev/null 2>&1
echo "$u:$p" | chpasswd >/dev/null 2>&1
( flock -x 200; echo "$u|$d|$t" >> "$USER_DB" ) 200>"$DB_LOCK"
clear
echo -e "${LINE}\n ${WHITE}SSH ACCOUNT CREATED${NC}\n${LINE}\n"
echo -e " ${BLUE}👤 Username :${NC} ${WHITE}$u${NC}\n ${BLUE}🔑 Password :${NC} ${WHITE}$p${NC}"
echo -e " ${BLUE}📅 Expiry :${NC} ${WHITE}$d${NC}\n ${BLUE}⏰ Time :${NC} ${WHITE}$t${NC}\n\n${LINE}"
echo -e " ${BLUE}📋 Copy :${NC} ${WHITE}$u:$p${NC}\n${LINE}"
pause
;;
2)
draw_header
echo -e " ${BLUE}CREATE TROJAN ACCOUNT${NC}\n${LINE}"
echo -ne " ${BLUE}🔑 Enter Password : ${NC}"
read p
if [[ -z "$p" ]]; then echo -e "\n${RED} ❌ Password cannot be empty!${NC}"; pause; return; fi
if [[ ! "$p" =~ ^[a-zA-Z0-9_@-]+$ ]]; then echo -e "\n${RED} ❌ Invalid Password! Use letters, numbers, _, -, or @.${NC}"; pause; return; fi
if grep -q "^$p|" "$TROJAN_DB"; then echo -e "\n${RED} ❌ PASSWORD ALREADY EXISTS!${NC}"; pause; return; fi
echo -ne " ${BLUE}⏳ Set Expiry Date [Y/N] : ${NC}"
read exp_choice
if [[ "${exp_choice,,}" == "y" ]]; then
echo -ne " ${BLUE}📅 Enter number of days : ${NC}"
read CUSTOM_DAYS
if [[ "$CUSTOM_DAYS" =~ ^[0-9]+$ ]] && [ "$CUSTOM_DAYS" -gt 0 ]; then
START_TIMESTAMP=$(date +%s)
SECONDS_IN_DURATION=$(( CUSTOM_DAYS * 24 * 60 * 60 ))
EXPIRATION_TIMESTAMP=$(( START_TIMESTAMP + SECONDS_IN_DURATION ))
d=$(date -d "@$EXPIRATION_TIMESTAMP" +"%Y-%m-%d")
t=$(date -d "@$EXPIRATION_TIMESTAMP" +"%H:%M")
else
echo -e "\n${RED} ❌ Invalid number of days! Setting to NEVER.${NC}"
sleep 2; d="NEVER"; t="00:00"
fi
else
d="NEVER"; t="00:00"
fi
( flock -x 200; echo "$p|$d|$t|ACTIVE" >> "$TROJAN_DB" ) 200>"$DB_LOCK"
clear
echo -e "${LINE}\n ${WHITE}TROJAN ACCOUNT CREATED${NC}\n${LINE}\n"
echo -e " ${BLUE}🔑 Password :${NC} ${WHITE}$p${NC}"
echo -e " ${BLUE}📅 Expiry :${NC} ${WHITE}$d${NC}\n ${BLUE}⏰ Time :${NC} ${WHITE}$t${NC}\n\n${LINE}"
echo -e " ${BLUE}📋 Copy :${NC} ${WHITE}$p${NC}\n${LINE}"
sync_trojan_xray
pause
;;
0) return ;;
*) echo -e "\n${RED} ❌ Invalid choice!${NC}"; sleep 1 ;;
esac
}

fun_renew() {
draw_header
echo -e " 🔄 ${BLUE}RENEW ACCOUNT${NC}\n${LINE}"
select_protocol
case "$proto_choice" in
1)
draw_header
echo -e " 🔄 ${BLUE}RENEW SSH ACCOUNT${NC}\n${LINE}"
echo -ne " ${BLUE}👤 USERNAME : ${NC}"
read u
if [[ -z "$u" ]] || ! grep -q "^$u|" "$USER_DB"; then echo -e "\n${RED} ❌ NOT FOUND!${NC}"; pause; return; fi

echo -ne " ${BLUE}⏳ Set Expiry Date [Y/N] : ${NC}"
read exp_choice
if [[ "${exp_choice,,}" == "y" ]]; then
echo -ne " ${BLUE}📅 Enter number of days to renew : ${NC}"
read CUSTOM_DAYS
if [[ "$CUSTOM_DAYS" =~ ^[0-9]+$ ]] && [ "$CUSTOM_DAYS" -gt 0 ]; then
START_TIMESTAMP=$(date +%s)
SECONDS_IN_DURATION=$(( CUSTOM_DAYS * 24 * 60 * 60 ))
EXPIRATION_TIMESTAMP=$(( START_TIMESTAMP + SECONDS_IN_DURATION ))
d=$(date -d "@$EXPIRATION_TIMESTAMP" +"%Y-%m-%d")
t=$(date -d "@$EXPIRATION_TIMESTAMP" +"%H:%M")
else
echo -e "\n${RED} ❌ Invalid number of days! Setting to NEVER.${NC}"
sleep 2; d="NEVER"; t="23:59"
fi
else
d="NEVER"; t="00:00"
fi
( flock -x 200; sed -i "/^$u|/d" "$USER_DB"; echo "$u|$d|$t" >> "$USER_DB" ) 200>"$DB_LOCK"
usermod -U "$u" >/dev/null 2>&1
echo -e "\n${GREEN} ✅ SSH ACCOUNT RENEWED SUCCESSFULLY${NC}"; pause
;;
2)
draw_header
echo -e " 🔄 ${BLUE}RENEW TROJAN ACCOUNT${NC}\n${LINE}"
echo -ne " ${BLUE}🔑 PASSWORD : ${NC}"
read p
if [[ -z "$p" ]] || ! grep -q "^$p|" "$TROJAN_DB"; then echo -e "\n${RED} ❌ NOT FOUND!${NC}"; pause; return; fi
echo -ne " ${BLUE}⏳ Set Expiry Date [Y/N] : ${NC}"
read exp_choice
if [[ "${exp_choice,,}" == "y" ]]; then
echo -ne " ${BLUE}📅 Enter number of days to renew : ${NC}"
read CUSTOM_DAYS
if [[ "$CUSTOM_DAYS" =~ ^[0-9]+$ ]] && [ "$CUSTOM_DAYS" -gt 0 ]; then
START_TIMESTAMP=$(date +%s)
SECONDS_IN_DURATION=$(( CUSTOM_DAYS * 24 * 60 * 60 ))
EXPIRATION_TIMESTAMP=$(( START_TIMESTAMP + SECONDS_IN_DURATION ))
d=$(date -d "@$EXPIRATION_TIMESTAMP" +"%Y-%m-%d")
t=$(date -d "@$EXPIRATION_TIMESTAMP" +"%H:%M")
else
echo -e "\n${RED} ❌ Invalid number of days! Setting to NEVER.${NC}"
sleep 2; d="NEVER"; t="23:59"
fi
else
d="NEVER"; t="00:00"
fi
( flock -x 200; sed -i "/^$p|/d" "$TROJAN_DB"; echo "$p|$d|$t|ACTIVE" >> "$TROJAN_DB" ) 200>"$DB_LOCK"
echo -e "\n${GREEN} ✅ TROJAN ACCOUNT RENEWED & UNLOCKED SUCCESSFULLY${NC}"
sync_trojan_xray
pause
;;
0) return ;;
*) echo -e "\n${RED} ❌ Invalid choice!${NC}"; sleep 1 ;;
esac
}

fun_remove() {
draw_header
echo -e " 🗑️ ${BLUE}DELETE ACCOUNT${NC}\n${LINE}"
select_protocol
case "$proto_choice" in
1)
draw_header
echo -e " 🗑️ ${BLUE}DELETE SSH ACCOUNT${NC}\n${LINE}"
echo -ne " ${BLUE}👤 USERNAME : ${NC}"
read u
if [[ -z "$u" ]] || ! grep -q "^$u|" "$USER_DB"; then echo -e "\n${RED} ❌ NOT FOUND!${NC}"; pause; return; fi
echo -ne " ${BLUE}⚠️ CONFIRM [Y/N]: ${NC}"
read c
if [[ "${c,,}" == "y" ]]; then
loginctl terminate-user "$u" >/dev/null 2>&1
pkill -KILL -u "$u" >/dev/null 2>&1
userdel -f "$u" >/dev/null 2>&1
( flock -x 200; sed -i "/^$u|/d" "$USER_DB" ) 200>"$DB_LOCK"
echo -e "\n${RED} 🗑️ SSH ACCOUNT DELETED SUCCESSFULLY${NC}"
fi
pause
;;
2)
draw_header
echo -e " 🗑️ ${BLUE}DELETE TROJAN ACCOUNT${NC}\n${LINE}"
echo -ne " ${BLUE}🔑 PASSWORD : ${NC}"
read p
if [[ -z "$p" ]] || ! grep -q "^$p|" "$TROJAN_DB"; then echo -e "\n${RED} ❌ NOT FOUND!${NC}"; pause; return; fi
echo -ne " ${BLUE}⚠️ CONFIRM [Y/N]: ${NC}"
read c
if [[ "${c,,}" == "y" ]]; then
( flock -x 200; sed -i "/^$p|/d" "$TROJAN_DB" ) 200>"$DB_LOCK"
echo -e "\n${RED} 🗑️ TROJAN ACCOUNT DELETED SUCCESSFULLY${NC}"
sync_trojan_xray
fi
pause
;;
0) return ;;
*) echo -e "\n${RED} ❌ Invalid choice!${NC}"; sleep 1 ;;
esac
}

fun_lock() {
draw_header
echo -e " 🔒 ${BLUE}LOCK/UNLOCK ACCOUNT${NC}\n${LINE}"
select_protocol
case "$proto_choice" in
1)
draw_header
echo -e " 🔒 ${BLUE}LOCK/UNLOCK SSH${NC}\n${LINE}"
echo -ne " ${BLUE}👤 USERNAME : ${NC}"
read u
if [[ -z "$u" ]] || ! grep -q "^$u|" "$USER_DB"; then echo -e "\n${RED} ❌ NOT FOUND!${NC}"; pause; return; fi
echo -e " ${BLUE}[1] LOCK ⛔${NC}\n ${BLUE}[2] UNLOCK 🔓${NC}"
echo -ne " ${BLUE}SELECT: ${NC}"
read s
if [[ "$s" == "1" ]]; then
usermod -L "$u" >/dev/null 2>&1; loginctl terminate-user "$u" >/dev/null 2>&1; pkill -KILL -u "$u" >/dev/null 2>&1; ps xaf | grep -E 'sshd|dropbear' | grep " $u " | grep -v grep | awk '{print $1}' | xargs -r kill -9 >/dev/null 2>&1
echo -e "\n${GREEN} ⛔ SSH ACCOUNT LOCKED & DISCONNECTED${NC}"
else
usermod -U "$u" >/dev/null 2>&1
echo -e "\n${GREEN} 🔓 SSH ACCOUNT UNLOCKED${NC}"
fi
pause
;;
2)
draw_header
echo -e " 🔒 ${BLUE}LOCK/UNLOCK TROJAN${NC}\n${LINE}"
echo -ne " ${BLUE}🔑 PASSWORD : ${NC}"
read p
if [[ -z "$p" ]] || ! grep -q "^$p|" "$TROJAN_DB"; then echo -e "\n${RED} ❌ NOT FOUND!${NC}"; pause; return; fi
echo -e " ${BLUE}[1] LOCK ⛔${NC}\n ${BLUE}[2] UNLOCK 🔓${NC}"
echo -ne " ${BLUE}SELECT: ${NC}"
read s
line_data=$(grep "^$p|" "$TROJAN_DB" | head -n 1)
IFS='|' read -r _ d t _ < <(echo "$line_data")
if [[ "$s" == "1" ]]; then
( flock -x 200; sed -i "/^$p|/d" "$TROJAN_DB"; echo "$p|$d|$t|LOCKED" >> "$TROJAN_DB" ) 200>"$DB_LOCK"
echo -e "\n${GREEN} ⛔ TROJAN ACCOUNT LOCKED & DISCONNECTED${NC}"
sync_trojan_xray
else
( flock -x 200; sed -i "/^$p|/d" "$TROJAN_DB"; echo "$p|$d|$t|ACTIVE" >> "$TROJAN_DB" ) 200>"$DB_LOCK"
echo -e "\n${GREEN} 🔓 TROJAN ACCOUNT UNLOCKED${NC}"
sync_trojan_xray
fi
pause
;;
0) return ;;
*) echo -e "\n${RED} ❌ Invalid choice!${NC}"; sleep 1 ;;
esac
}

fun_list() {
draw_header
echo -e " 📋 ${BLUE}LIST ACCOUNTS${NC}\n${LINE}"
echo -e " ${BLUE}[1] SSH ACCOUNTS${NC}"
echo -e " ${BLUE}[2] TROJAN ACCOUNTS${NC}"
echo -e " ${BLUE}[3] LIST ALL SSH & TROJAN${NC}"
echo -e " ${BLUE}[0] BACK${NC}\n${LINE}"
echo -ne " ${BLUE}SELECT: ${NC}"
read l_choice

clear
if [[ "$l_choice" == "1" || "$l_choice" == "3" ]]; then
echo -e "${LINE}\n ${BLUE}SSH ACCOUNTS LIST${NC}\n${LINE}"
SHADOW_CACHE=$(cat /etc/shadow 2>/dev/null)
while IFS='|' read -r u d t rest; do
[[ -z "$u" ]] && continue
if id "$u" &>/dev/null; then
if [[ "$d" == "NEVER" || "$d" == "EXPIRED" ]]; then DATE_STR="$d"; else DATE_STR="$d $t"; fi
if echo "$SHADOW_CACHE" | grep -q "^${u}:!"; then LOCK_STAT="⛔"; else LOCK_STAT="🟢"; fi
printf " ${BLUE}👤 %-15s${NC} %s ${BLUE}📅 %s${NC}\n" "$u" "$LOCK_STAT" "$DATE_STR"
fi
done < "$USER_DB"
echo -e "${LINE}"
fi
if [[ "$l_choice" == "2" || "$l_choice" == "3" ]]; then
echo -e "\n${LINE}\n ${BLUE}TROJAN ACCOUNTS LIST${NC}\n${LINE}"
while IFS='|' read -r p d t st rest; do
[[ -z "$p" ]] && continue
if [[ "$d" == "NEVER" || "$d" == "EXPIRED" ]]; then DATE_STR="$d"; else DATE_STR="$d $t"; fi
if [[ "$st" == "LOCKED" || "$d" == "EXPIRED" ]]; then LOCK_STAT="⛔"; else LOCK_STAT="🟢"; fi
printf " ${BLUE}🔑 %-15s${NC} %s ${BLUE}📅 %s${NC}\n" "$p" "$LOCK_STAT" "$DATE_STR"
done < "$TROJAN_DB"
echo -e "${LINE}"
fi
[[ "$l_choice" != "0" ]] && pause
}

fun_search() {
clear
echo -e "${LINE}\n 🔍 ${BLUE}SEARCH ACCOUNT${NC}\n${LINE}"
echo -ne " ${BLUE}🔍 Enter Username or Trojan Password : ${NC}"
read search_q

if [[ -z "$search_q" ]]; then echo -e "\n${RED} ❌ Search cannot be empty!${NC}"; pause; return; fi
ssh_results=$(grep -i "$search_q" "$USER_DB" 2>/dev/null)
trj_results=$(grep -i "$search_q" "$TROJAN_DB" 2>/dev/null)
if [[ -z "$ssh_results" && -z "$trj_results" ]]; then
echo -e "\n${RED} ❌ NO ACCOUNT FOUND MATCHING: ${WHITE}$search_q${NC}"
else
echo -e "\n${GREEN} ✅ RESULTS FOUND:${NC}\n${LINE}"
SHADOW_CACHE=$(cat /etc/shadow 2>/dev/null)
if [[ -n "$ssh_results" ]]; then
while IFS='|' read -r u d t rest; do
[[ -z "$u" ]] && continue
if id "$u" &>/dev/null; then
if [[ "$d" == "NEVER" || "$d" == "EXPIRED" ]]; then DATE_STR="$d"; else DATE_STR="$d $t"; fi
if echo "$SHADOW_CACHE" | grep -q "^${u}:!"; then LOCK_STAT="${RED}⛔ LOCKED (EXPIRED OR BANNED)${NC}"; else LOCK_STAT="${GREEN}🟢 ACTIVE${NC}"; fi
echo -e " ${CYAN}[SSH]${NC}"
echo -e " ${BLUE}👤 Username :${NC} ${WHITE}$u${NC}"
echo -e " ${BLUE}📊 Status :${NC} $LOCK_STAT"
echo -e " ${BLUE}📅 Expiry :${NC} ${WHITE}$DATE_STR${NC}"
echo -e "${LINE}"
fi
done < <(echo "$ssh_results")
fi
if [[ -n "$trj_results" ]]; then
while IFS='|' read -r p d t st rest; do
[[ -z "$p" ]] && continue
if [[ "$d" == "NEVER" || "$d" == "EXPIRED" ]]; then DATE_STR="$d"; else DATE_STR="$d $t"; fi
if [[ "$st" == "LOCKED" || "$d" == "EXPIRED" ]]; then LOCK_STAT="${RED}⛔ LOCKED (EXPIRED OR BANNED)${NC}"; else LOCK_STAT="${GREEN}🟢 ACTIVE${NC}"; fi
echo -e " ${YELLOW}[TROJAN]${NC}"
echo -e " ${BLUE}🔑 Password :${NC} ${WHITE}$p${NC}"
echo -e " ${BLUE}📊 Status :${NC} $LOCK_STAT"
echo -e " ${BLUE}📅 Expiry :${NC} ${WHITE}$DATE_STR${NC}"
echo -e "${LINE}"
done < <(echo "$trj_results")
fi
fi
pause
}

fun_monitor_view() {
draw_header
echo -e " 👁 ${BLUE}LIVE SSH & TROJAN MONITOR${NC}\n${LINE}"
echo -e " ${BLUE}[1] LIVE SSH ACCOUNTS${NC}"
echo -e " ${BLUE}[2] LIVE TROJAN ACCOUNTS${NC}"
echo -e " ${BLUE}[3] LIVE SSH • TROJAN ACCOUNTS${NC}"
echo -e " ${BLUE}[0] BACK${NC}\n${LINE}"
echo -ne " ${BLUE}SELECT: ${NC}"
read m_choice

if [[ "$m_choice" == "0" ]]; then return; fi
clear
echo -e "${LINE}\n ${BLUE}======= 👁 LIVE MONITOR =======${NC}\n${LINE}"
if [[ "$m_choice" == "1" || "$m_choice" == "3" ]]; then
echo -e " ${CYAN} [ SSH ACCOUNTS ]${NC}"
ACTIVE_USERS_DATA=$(ps -axo user:32,comm 2>/dev/null | grep -E 'sshd|dropbear' | awk '{print $1}' | sort | uniq -c)
while IFS='|' read -r u d t rest; do
[[ -z "$u" ]] && continue
if id "$u" &>/dev/null; then
USER_CONN_COUNT=$(echo "$ACTIVE_USERS_DATA" | grep -w "$u" | awk '{print $1}')
if [[ -n "$USER_CONN_COUNT" && "$USER_CONN_COUNT" -gt 0 ]]; then
STATUS="${GREEN}🟢 ONLINE [ ${USER_CONN_COUNT} ]${NC}"
else
STATUS="${RED}🔴 OFFLINE${NC}"
fi
printf " ${BLUE}👤 %-16s${NC} %s\n" "$u" "$STATUS"
fi
done < "$USER_DB"
echo -e "${LINE}"
fi
if [[ "$m_choice" == "2" || "$m_choice" == "3" ]]; then
echo -e " ${YELLOW} [ TROJAN ACCOUNTS ]${NC}"
TROJAN_COUNTS_JSON=$(get_trojan_online_counts)
while IFS='|' read -r p d t st rest; do
[[ -z "$p" ]] && continue
TRJ_COUNT=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d.get(sys.argv[2], 0))" "$TROJAN_COUNTS_JSON" "$p" 2>/dev/null)
if [[ -n "$TRJ_COUNT" && "$TRJ_COUNT" -gt 0 ]]; then
STATUS="${GREEN}🟢 ONLINE [ ${TRJ_COUNT} ]${NC}"
else
STATUS="${RED}🔴 OFFLINE${NC}"
fi
printf " ${BLUE}🔑 %-16s${NC} %s\n" "$p" "$STATUS"
done < "$TROJAN_DB"
echo -e "${LINE}"
fi
pause
}

fun_backup() {
draw_header
echo -e " 💾 ${BLUE}BACKUP DATA${NC}\n${LINE}"
cp "$USER_DB" "$BACKUP_DIR/ssh_backup_$(date +%F).txt"
cp "$TROJAN_DB" "$BACKUP_DIR/trojan_backup_$(date +%F).txt"
echo -e "${GREEN} ✅ SSH & TROJAN BACKUPS SAVED IN $BACKUP_DIR${NC}"; pause
}

fun_export_users() {
draw_header; echo -e "${BLUE} 📤 EXPORTING SSH & TROJAN USERS...${NC}"
cp "$USER_DB" "$MIGRATION_FILE"
cp "$TROJAN_DB" "$MIGRATION_TROJAN"
echo -e "${GREEN} ✅ EXPORT SUCCESSFUL!${NC}"
echo -e " SSH FILE : $MIGRATION_FILE"
echo -e " TROJAN FILE : $MIGRATION_TROJAN"
pause
}

fun_import_users() {
draw_header; echo -e "${BLUE} 📥 RESTORING USERS...${NC}"
count_ssh=0
count_trj=0
if [[ -f "$MIGRATION_FILE" ]]; then
while IFS='|' read -r u d t rest; do
[[ -z "$u" ]] && continue
if ! id "$u" &>/dev/null; then
useradd -M -s /bin/false "$u" >/dev/null 2>&1; echo "$u:12345" | chpasswd >/dev/null 2>&1
echo -e " CREATED SSH: ${GREEN}$u${NC}"; ((count_ssh++))
fi
done < "$MIGRATION_FILE"
( flock -x 200; cat "$MIGRATION_FILE" > "$USER_DB" ) 200>"$DB_LOCK"
fi

if [[ -f "$MIGRATION_TROJAN" ]]; then
( flock -x 200; cat "$MIGRATION_TROJAN" > "$TROJAN_DB" ) 200>"$DB_LOCK"
count_trj=$(wc -l < "$TROJAN_DB")
sync_trojan_xray
fi
echo -e "\n${GREEN} ✅ RESTORED: $count_ssh SSH USERS & $count_trj TROJAN USERS${NC}"; pause
}

fun_violations() {
clear
echo -e "${LINE}\n 🔔 ${BLUE}ALERTS LOG (EXPIRED LOGS)${NC}\n${LINE}\n"
if [ -f "$LOG_FILE" ]; then
ALERTS=$(grep "ACCOUNT EXPIRED" "$LOG_FILE" | tail -n 20)
if [[ -z "$ALERTS" ]]; then echo -e " ${GREEN}✅ NO EXPIRED ACCOUNTS DETECTED YET.${NC}"
else
while read -r line; do echo -e " ${YELLOW}🕒 $line${NC}"; done < <(echo "$ALERTS")
fi
else
echo -e " ${YELLOW}LOG FILE IS EMPTY.${NC}"
fi
echo -e "\n${LINE}"; pause
}

fun_install_bot() {
clear; echo -e "${BLUE}INSTALLING SECURE BOT ENVIRONMENT...${NC}"
echo -ne " ${BLUE}🤖 Enter your Telegram Bot Token: ${NC}"
read -r input_token
if [[ -z "$input_token" ]]; then echo -e "${RED}❌ Token cannot be empty! Installation aborted.${NC}"; pause; return; fi
echo -ne " ${BLUE}👤 Enter your Telegram Admin ID: ${NC}"
read -r input_id
if [[ -z "$input_id" ]]; then echo -e "${RED}❌ Admin ID cannot be empty! Installation aborted.${NC}"; pause; return; fi
pkill -f ssh_bot.py 2>/dev/null
systemctl stop sshbot >/dev/null 2>&1
echo -e "${YELLOW}⚙️ Installing Python dependencies in Secure VENV...${NC}"
$PIP_BIN install urllib3==1.26.15 python-telegram-bot==13.7 schedule requests >/dev/null 2>&1
echo "BOT_TOKEN=\"$input_token\"" > "$BOT_CONF"
echo "ADMIN_ID=\"$input_id\"" >> "$BOT_CONF"
echo "ALERTS=\"ON\"" >> "$BOT_CONF"
chmod 600 "$BOT_CONF"
cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, re, fcntl, datetime, json
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(message)s')
CONF_FILE = "/etc/xpanel/bot.conf"
DB_FILE = "/etc/xpanel/users_db.txt"
TROJAN_DB = "/etc/xpanel/trojan_db.txt"
XRAY_CONF = "/usr/local/etc/xray/config.json"
XRAY_ACCESS_LOG = "/var/log/xray/access.log"
LOCK_FILE = "/etc/xpanel/.db.lock"
LOG_FILE = "/var/log/kp_manager.log"
TLINE = "============================"

def load_config():
    c = {}
    try:
        for l in open(CONF_FILE):
            if "=" in l: k, v = l.strip().split("=", 1); c[k] = v.strip().replace('"', '')
    except: pass
    return c

cfg = load_config(); TOKEN = cfg.get("BOT_TOKEN"); ADMIN_ID = int(cfg.get("ADMIN_ID", 0))

def kill_user(user):
    os.system(f"usermod -L {user} >/dev/null 2>&1")
    os.system(f"pkill -9 -u {user} >/dev/null 2>&1")
    os.system(f"ps xaf | grep -E 'sshd|dropbear' | grep ' {user} ' | grep -v grep | awk '{{print $1}}' | xargs -r kill -9 >/dev/null 2>&1")
    os.system(f"loginctl terminate-user {user} >/dev/null 2>&1")

def sync_xray():
    if not os.path.exists(XRAY_CONF): return
    try:
        with open(XRAY_CONF, "r") as f:
            xcfg = json.load(f)
        clients = []
        if os.path.exists(TROJAN_DB):
            with open(TROJAN_DB, "r") as f:
                for line in f:
                    parts = line.strip().split("|")
                    if len(parts) >= 3:
                        pwd, exp_d, exp_t = parts[0], parts[1], parts[2]
                        st = parts[3] if len(parts) >= 4 else "ACTIVE"
                        if exp_d != "EXPIRED" and st == "ACTIVE":
                            clients.append({"password": pwd, "email": pwd, "level": 0})
        for inbound in xcfg.get("inbounds", []):
            if inbound.get("protocol") == "trojan":
                inbound.setdefault("settings", {})["clients"] = clients
        with open(XRAY_CONF, "w") as f:
            json.dump(xcfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "xray"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except: pass

def get_trojan_counts():
    xray_bin = "/usr/local/bin/xray" if os.path.exists("/usr/local/bin/xray") else "xray"
    counts = {}
    xray_port = 2000
    try:
        with open(XRAY_CONF, "r") as f:
            xcfg = json.load(f)
            for ib in xcfg.get("inbounds", []):
                if ib.get("protocol") == "trojan":
                    xray_port = ib.get("port", 2000)
    except: pass

    try:
        ss_out = subprocess.getoutput(f"ss -tn state established '( dport = :{xray_port} or sport = :{xray_port} )' 2>/dev/null")
        if len([l for l in ss_out.splitlines() if str(xray_port) in l]) == 0:
            return {}
    except: pass

    api_worked = False
    try:
        res = subprocess.run([xray_bin, "api", "statsquery", "--server=127.0.0.1:10085", "-pattern", "user>>>"], capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout)
            for item in data.get("stat", []):
                name = item.get("name", "")
                val = int(item.get("value", 0))
                if ">>>online" in name:
                    api_worked = True
                    parts = name.split(">>>")
                    if len(parts) >= 2 and val > 0:
                        counts[parts[1]] = val
    except: pass

    if not api_worked and not counts and os.path.exists(XRAY_ACCESS_LOG):
        try:
            now = datetime.datetime.now()
            tail_lines = subprocess.getoutput(f"tail -n 500 {XRAY_ACCESS_LOG} 2>/dev/null").splitlines()
            user_ips = {}
            for line in tail_lines:
                if "email:" not in line: continue
                m_time = re.match(r"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", line)
                if m_time:
                    try:
                        t_log = datetime.datetime.strptime(m_time.group(1), "%Y/%m/%d %H:%M:%S")
                        if (now - t_log).total_seconds() > 25: continue
                    except: pass
                m_email = re.search(r"email:\s*([^\s]+)", line)
                m_src = re.search(r"from\s+(?:tcp:)?([0-9a-fA-F\.:]+):\d+", line)
                if m_email:
                    usr = m_email.group(1).strip()
                    ip = m_src.group(1) if m_src else "session"
                    user_ips.setdefault(usr, set()).add(ip)
            for u, ips in user_ips.items():
                counts[u] = len(ips)
        except: pass
    return counts

def get_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 CREATE", callback_data='proto_add'), InlineKeyboardButton("🔄 RENEW", callback_data='proto_ren')],
        [InlineKeyboardButton("🗑 DELETE", callback_data='proto_del'), InlineKeyboardButton("🔒 LOCK/UNLOCK", callback_data='proto_lock')],
        [InlineKeyboardButton("📋 LIST ALL", callback_data='list'), InlineKeyboardButton("🔍 SEARCH", callback_data='search_menu')],
        [InlineKeyboardButton("👁 MONITOR", callback_data='onl'), InlineKeyboardButton("💾 BACKUP", callback_data='bak')],
        [InlineKeyboardButton("🔔 ALERTS", callback_data='alerts'), InlineKeyboardButton("⚙ SETTINGS", callback_data='bot_set')],
        [InlineKeyboardButton("🚪 EXIT", callback_data='close')]
    ])

def get_proto_kb(prefix):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🛡️ SSH", callback_data=f"{prefix}_ssh"), InlineKeyboardButton("⚡ TROJAN", callback_data=f"{prefix}_trj")],
        [InlineKeyboardButton("🔙 BACK", callback_data='back')]
    ])

def get_settings_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("💻 Server Info", callback_data='set_info')],
        [InlineKeyboardButton("🔄 Restart Monitor", callback_data='set_mon')],
        [InlineKeyboardButton("🚀 Migration", callback_data='migrate')],
        [InlineKeyboardButton("🔙 BACK", callback_data='back')]
    ])

def get_back_btn():
    return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 BACK", callback_data='back')]])

def start(u, c):
    if u.effective_user.id == ADMIN_ID:
        u.message.reply_text("⚡ SSH & TROJAN MANAGER V10", parse_mode=ParseMode.HTML, reply_markup=get_menu())

def btn(u, c):
    q = u.callback_query; q.answer(); d = q.data
    if d == 'close':
        try: q.message.delete()
        except: pass
        return
    if d == 'back':
        c.user_data.clear()
        q.edit_message_text("⚡ SSH & TROJAN MANAGER V10", parse_mode=ParseMode.HTML, reply_markup=get_menu())
        return
    try:
        if d in ['proto_add', 'proto_ren', 'proto_del', 'proto_lock']:
            act_map = {'proto_add': 'add', 'proto_ren': 'ren', 'proto_del': 'del', 'proto_lock': 'lock'}
            q.edit_message_text("🔀 Select Protocol:", parse_mode=ParseMode.HTML, reply_markup=get_proto_kb(act_map[d]))
        elif d == 'add_ssh':
            c.user_data['proto'] = 'ssh'; c.user_data['act'] = 'add_u'
            q.edit_message_text("🛡️ <b>[SSH] Send the New Username:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'add_trj':
            c.user_data['proto'] = 'trj'; c.user_data['act'] = 'add_trj_p'
            q.edit_message_text("⚡ <b>[TROJAN] Send the New Password:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'add_yes':
            c.user_data['act'] = 'a_datetime'
            if c.user_data.get('proto') == 'trj':
                q.edit_message_text(f"🔑 Password : <code>{c.user_data['p']}</code>\n\n📅 <b>Enter number of days:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            else:
                q.edit_message_text(f"👤 Username : <code>{c.user_data['u']}</code>\n🔑 Password : <code>{c.user_data['p']}</code>\n\n📅 <b>Enter number of days:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'add_no':
            dt = "NEVER"; tm = "00:00"
            if c.user_data.get('proto') == 'trj':
                pwd = c.user_data['p']
                with open(LOCK_FILE, "a") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    with open(TROJAN_DB, 'a') as f:
                        f.write(f"{pwd}|{dt}|{tm}|ACTIVE\n")
                    fcntl.flock(lock_f, fcntl.LOCK_UN)
                sync_xray()
                resp = f"<b>{TLINE}</b>\n <b>TROJAN CREATED</b> \n<b>{TLINE}</b>\n\n🔑 Password : <code>{pwd}</code>\n📅 Expiry : <code>{dt}</code>\n⏰ Time : <code>{tm}</code>\n\n<b>{TLINE}</b>\n📋 Copy : <code>{pwd}</code>\n<b>{TLINE}</b>"
            else:
                usr = c.user_data['u']; pwd = c.user_data['p']
                subprocess.run(["useradd", "-M", "-s", "/bin/false", usr], stdout=subprocess.DEVNULL)
                subprocess.run(["chpasswd"], input=f"{usr}:{pwd}".encode(), stdout=subprocess.DEVNULL)
                with open(LOCK_FILE, "a") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    with open(DB_FILE, 'a') as f:
                        f.write(f"{usr}|{dt}|{tm}\n")
                    fcntl.flock(lock_f, fcntl.LOCK_UN)
                resp = f"<b>{TLINE}</b>\n <b>SSH CREATED</b> \n<b>{TLINE}</b>\n\n👤 Username : <code>{usr}</code>\n🔑 Password : <code>{pwd}</code>\n📅 Expiry : <code>{dt}</code>\n⏰ Time : <code>{tm}</code>\n\n<b>{TLINE}</b>\n📋 Copy : <code>{usr}:{pwd}</code>\n<b>{TLINE}</b>"
            q.edit_message_text(resp, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            c.user_data.clear()
        elif d == 'ren_ssh':
            c.user_data['proto'] = 'ssh'; c.user_data['act'] = 'r_user'
            q.edit_message_text("🔄 <b>[SSH] Enter Username to Renew:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'ren_trj':
            c.user_data['proto'] = 'trj'; c.user_data['act'] = 'r_user'
            q.edit_message_text("🔄 <b>[TROJAN] Enter Password to Renew:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'ren_yes':
            c.user_data['act'] = 'r_val'
            q.edit_message_text("📅 <b>Enter number of days to renew:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'ren_no':
            usr = c.user_data.get('ru')
            if c.user_data.get('proto') == 'trj':
                with open(LOCK_FILE, "a") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    with open(TROJAN_DB, 'r+') as f:
                        lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                        lines.append(f"{usr}|NEVER|00:00|ACTIVE\n")
                        f.seek(0); f.writelines(lines); f.truncate()
                    fcntl.flock(lock_f, fcntl.LOCK_UN)
                sync_xray()
            else:
                with open(LOCK_FILE, "a") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    with open(DB_FILE, 'r+') as f:
                        lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                        lines.append(f"{usr}|NEVER|00:00\n")
                        f.seek(0); f.writelines(lines); f.truncate()
                    fcntl.flock(lock_f, fcntl.LOCK_UN)
                subprocess.run(["usermod", "-U", usr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            q.edit_message_text(f"✅ <b>RENEWED & UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'del_ssh':
            c.user_data['proto'] = 'ssh'; c.user_data['act'] = 'd1'
            q.edit_message_text("🗑️ <b>[SSH] Enter Username to Delete:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'del_trj':
            c.user_data['proto'] = 'trj'; c.user_data['act'] = 'd1'
            q.edit_message_text("🗑️ <b>[TROJAN] Enter Password to Delete:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'del_yes':
            usr = c.user_data.get('del_u')
            if usr:
                if c.user_data.get('proto') == 'trj':
                    if os.path.exists(TROJAN_DB):
                        with open(LOCK_FILE, "a") as lock_f:
                            fcntl.flock(lock_f, fcntl.LOCK_EX)
                            with open(TROJAN_DB, 'r+') as f:
                                lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                                f.seek(0); f.writelines(lines); f.truncate()
                            fcntl.flock(lock_f, fcntl.LOCK_UN)
                        sync_xray()
                else:
                    kill_user(usr)
                    subprocess.run(["userdel", "-f", usr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    if os.path.exists(DB_FILE):
                        with open(LOCK_FILE, "a") as lock_f:
                            fcntl.flock(lock_f, fcntl.LOCK_EX)
                            with open(DB_FILE, 'r+') as f:
                                lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                                f.seek(0); f.writelines(lines); f.truncate()
                            fcntl.flock(lock_f, fcntl.LOCK_UN)
                q.edit_message_text(f"🗑️ <b>DELETED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'del_no':
            q.edit_message_text("❌ <b>Deletion Cancelled.</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'lock_ssh':
            c.user_data['proto'] = 'ssh'; c.user_data['act'] = 'lu_user'
            q.edit_message_text("🔒/🔓 <b>[SSH] Enter Username:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'lock_trj':
            c.user_data['proto'] = 'trj'; c.user_data['act'] = 'lu_user'
            q.edit_message_text("🔒/🔓 <b>[TROJAN] Enter Password:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d.startswith('do_lock_'):
            usr = d.split('_', 2)[2]
            if c.user_data.get('proto') == 'trj':
                with open(LOCK_FILE, "a") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    with open(TROJAN_DB, 'r+') as f:
                        new_l = []
                        for l in f.readlines():
                            p = l.strip().split('|')
                            if len(p) >= 3 and p[0] == usr:
                                new_l.append(f"{p[0]}|{p[1]}|{p[2]}|LOCKED\n")
                            else:
                                new_l.append(l)
                        f.seek(0); f.writelines(new_l); f.truncate()
                    fcntl.flock(lock_f, fcntl.LOCK_UN)
                sync_xray()
            else:
                kill_user(usr)
            q.edit_message_text(f"⛔ <b>LOCKED & DISCONNECTED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d.startswith('do_unlock_'):
            usr = d.split('_', 2)[2]
            if c.user_data.get('proto') == 'trj':
                with open(LOCK_FILE, "a") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    with open(TROJAN_DB, 'r+') as f:
                        new_l = []
                        for l in f.readlines():
                            p = l.strip().split('|')
                            if len(p) >= 3 and p[0] == usr:
                                new_l.append(f"{p[0]}|{p[1]}|{p[2]}|ACTIVE\n")
                            else:
                                new_l.append(l)
                        f.seek(0); f.writelines(new_l); f.truncate()
                    fcntl.flock(lock_f, fcntl.LOCK_UN)
                sync_xray()
            else:
                subprocess.run(["usermod", "-U", usr], stdout=subprocess.DEVNULL)
            q.edit_message_text(f"🔓 <b>UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'search_menu':
            c.user_data['act'] = 'search_u'
            q.edit_message_text("🔍 <b>Enter SSH Username or Trojan Password:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'list':
            try: shadow_data = open('/etc/shadow', 'r').read()
            except: shadow_data = ""
            items = []
            if os.path.exists(DB_FILE):
                for l in open(DB_FILE):
                    p = l.strip().split('|')
                    if len(p) >= 3 and "root" not in p[0]:
                        date_str = p[1] if p[1] in ["NEVER", "EXPIRED"] else f"{p[1]} {p[2]}"
                        lock_icon = " ⛔" if f"\n{p[0]}:!" in shadow_data or shadow_data.startswith(f"{p[0]}:!") else " 🟢"
                        items.append(f"🛡️ [SSH] 👤 <code>{p[0]}</code>{lock_icon}\n📅 <code>{date_str}</code>\n\n")
            if os.path.exists(TROJAN_DB):
                for l in open(TROJAN_DB):
                    p = l.strip().split('|')
                    if len(p) >= 3:
                        st = p[3] if len(p) >= 4 else "ACTIVE"
                        date_str = p[1] if p[1] in ["NEVER", "EXPIRED"] else f"{p[1]} {p[2]}"
                        lock_icon = " ⛔" if (st == "LOCKED" or p[1] == "EXPIRED") else " 🟢"
                        items.append(f"⚡ [TRJ] 🔑 <code>{p[0]}</code>{lock_icon}\n📅 <code>{date_str}</code>\n\n")
            if not items:
                q.edit_message_text("No accounts found.", reply_markup=get_back_btn())
                return
            chunk_size = 40
            chunks = [items[i:i + chunk_size] for i in range(0, len(items), chunk_size)]
            for idx, chunk in enumerate(chunks):
                header = f"<b>{TLINE}</b>\n <b>ALL ACCOUNTS ({idx+1}/{len(chunks)})</b>\n<b>{TLINE}</b>\n\n"
                body = header + "".join(chunk)
                if idx == 0:
                    q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if len(chunks) == 1 else None)
                else:
                    c.bot.send_message(chat_id=u.effective_chat.id, text=body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if idx == len(chunks) - 1 else None)
        elif d == 'onl':
            ssh_counts = {}
            try:
                ps_out = subprocess.getoutput("ps -axo user:32,comm | grep -E 'sshd|dropbear' | awk '{print $1}'").split()
                for u_name in ps_out:
                    ssh_counts[u_name] = ssh_counts.get(u_name, 0) + 1
            except: pass
            trj_counts = get_trojan_counts()
            items = []
            if os.path.exists(DB_FILE):
                for l in open(DB_FILE):
                    p = l.strip().split('|')
                    if len(p) >= 3 and "root" not in p[0]:
                        cnt = ssh_counts.get(p[0], 0)
                        st = f"🟢 ONLINE [ {cnt} ]" if cnt > 0 else "🔴 OFFLINE"
                        items.append(f"🛡️ [SSH] 👤 <code>{p[0]}</code> : {st}\n")
            if os.path.exists(TROJAN_DB):
                for l in open(TROJAN_DB):
                    p = l.strip().split('|')
                    if len(p) >= 3:
                        cnt = trj_counts.get(p[0], 0)
                        st = f"🟢 ONLINE [ {cnt} ]" if cnt > 0 else "🔴 OFFLINE"
                        items.append(f"⚡ [TRJ] 🔑 <code>{p[0]}</code> : {st}\n")
            if not items:
                q.edit_message_text("No accounts found.", reply_markup=get_back_btn())
                return
            body = f"<b>{TLINE}</b>\n <b>LIVE MONITOR</b> \n<b>{TLINE}</b>\n\n" + "".join(items[:80])
            q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'alerts':
            if os.path.exists(LOG_FILE):
                alerts_raw = subprocess.getoutput(f"grep 'ACCOUNT EXPIRED' {LOG_FILE} | tail -n 15")
                msg = "✅ <b>NO EXPIRED ACCOUNTS YET.</b>" if not alerts_raw.strip() else "🔔 <b>ALERTS LOG (EXPIRED)</b>\n\n" + "\n".join(f"🕒 {l}" for l in alerts_raw.split('\n') if l.strip())
            else:
                msg = "⚠️ <b>LOG FILE IS EMPTY.</b>"
            q.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'bak':
            if os.path.exists(DB_FILE): c.bot.send_document(ADMIN_ID, open(DB_FILE, 'rb'), caption="🛡️ SSH DB Backup")
            if os.path.exists(TROJAN_DB): c.bot.send_document(ADMIN_ID, open(TROJAN_DB, 'rb'), caption="⚡ Trojan DB Backup")
            q.edit_message_text("✅ <b>SSH & TROJAN DATA SAVED & SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'bot_set':
            q.edit_message_text("⚙️ <b>SETTINGS</b>\nChoose an option:", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'set_info':
            up = subprocess.getoutput("uptime -p")
            ram = subprocess.getoutput("free -m | awk 'NR==2{printf \"%.2f%%\", $3*100/$2 }'")
            cpu = subprocess.getoutput("top -bn1 | grep load | awk '{printf \"%.2f%%\", $(NF-2)}'")
            msg = f"💻 <b>SERVER INFO</b>\n\n⏱ <b>Uptime:</b> {up}\n🧠 <b>RAM:</b> {ram}\n⚙️ <b>CPU Load:</b> {cpu}"
            q.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'set_mon':
            subprocess.run(["systemctl", "restart", "kp_monitor"])
            q.edit_message_text("✅ <b>Monitor Restarted!</b>", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'migrate':
            if os.path.exists(DB_FILE):
                subprocess.run(["cp", DB_FILE, "/root/migration_users.txt"])
                c.bot.send_document(ADMIN_ID, open("/root/migration_users.txt", 'rb'), caption="🚀 <b>SSH MIGRATION FILE</b>", parse_mode=ParseMode.HTML)
            if os.path.exists(TROJAN_DB):
                subprocess.run(["cp", TROJAN_DB, "/root/migration_trojan.txt"])
                c.bot.send_document(ADMIN_ID, open("/root/migration_trojan.txt", 'rb'), caption="🚀 <b>TROJAN MIGRATION FILE</b>", parse_mode=ParseMode.HTML)
            q.edit_message_text("✅ <b>MIGRATION FILES SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
    except: pass

def txt(u, c):
    if u.effective_user.id != ADMIN_ID: return
    msg = u.message.text.strip(); act = c.user_data.get('act')
    try:
        if act == 'add_u':
            if not re.match(r"^[a-zA-Z0-9_]+$", msg):
                u.message.reply_text("❌ Invalid Username! Try again:", parse_mode=ParseMode.HTML, reply_markup=get_back_btn()); return
            if subprocess.run(["id", msg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0 or (os.path.exists(DB_FILE) and f"{msg}|" in open(DB_FILE).read()):
                u.message.reply_text("❌ User already exists! Try another:", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            else:
                c.user_data['u'] = msg; c.user_data['act'] = 'add_p'
                u.message.reply_text(f"👤 Username: {msg}\n\n🔑 Send the Password:", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif act == 'add_trj_p':
            if not re.match(r"^[a-zA-Z0-9_@-]+$", msg):
                u.message.reply_text("❌ <b>Invalid Password!</b> Try again:", parse_mode=ParseMode.HTML, reply_markup=get_back_btn()); return
            if os.path.exists(TROJAN_DB) and f"{msg}|" in open(TROJAN_DB).read():
                u.message.reply_text("❌ <b>Password already exists!</b> Try another:", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            else:
                c.user_data['p'] = msg; c.user_data['act'] = ''
                kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='add_yes'), InlineKeyboardButton("🔴 NO", callback_data='add_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
                u.message.reply_text(f"🔑 Trojan Password: <code>{msg}</code>\n\n⏳ <b>Set Expiry Date by Days?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
        elif act == 'add_p':
            c.user_data['p'] = msg; c.user_data['act'] = ''
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='add_yes'), InlineKeyboardButton("🔴 NO", callback_data='add_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"👤 Username: <code>{c.user_data['u']}</code>\n🔑 Password: <code>{msg}</code>\n\n⏳ <b>Set Expiry Date by Days?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
        elif act == 'lu_user':
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🔒 LOCK", callback_data=f"do_lock_{msg}"), InlineKeyboardButton("🔓 UNLOCK", callback_data=f"do_unlock_{msg}")], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"Select action for <code>{msg}</code>:", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''
        elif act == 'r_user':
            c.user_data['ru'] = msg; c.user_data['act'] = ''
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='ren_yes'), InlineKeyboardButton("🔴 NO", callback_data='ren_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"⏳ <b>Set Expiry Date by Days for <code>{msg}</code>?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
        elif act == 'search_u':
            sq = msg.lower(); results = []
            try: shadow_data = open('/etc/shadow', 'r').read()
            except: shadow_data = ""
            if os.path.exists(DB_FILE):
                for l in open(DB_FILE):
                    p = l.strip().split('|')
                    if len(p) >= 3 and sq in p[0].lower() and "root" not in p[0]:
                        ds = p[1] if p[1] in ["NEVER", "EXPIRED"] else f"{p[1]} {p[2]}"
                        ls = "⛔ LOCKED" if (f"\n{p[0]}:!" in shadow_data or shadow_data.startswith(f"{p[0]}:!")) else "🟢 ACTIVE"
                        results.append(f"🛡️ [SSH] 👤 <code>{p[0]}</code>\n📊 {ls} | 📅 <code>{ds}</code>\n")
            if os.path.exists(TROJAN_DB):
                for l in open(TROJAN_DB):
                    p = l.strip().split('|')
                    if len(p) >= 3 and sq in p[0].lower():
                        st = p[3] if len(p) >= 4 else "ACTIVE"
                        ds = p[1] if p[1] in ["NEVER", "EXPIRED"] else f"{p[1]} {p[2]}"
                        ls = "⛔ LOCKED" if (st == "LOCKED" or p[1] == "EXPIRED") else "🟢 ACTIVE"
                        results.append(f"⚡ [TRJ] 🔑 <code>{p[0]}</code>\n📊 {ls} | 📅 <code>{ds}</code>\n")
            reply_text = "✅ <b>RESULTS FOUND:</b>\n\n" + "\n".join(results[:15]) if results else f"❌ <b>NO ACCOUNT FOUND:</b> {msg}"
            u.message.reply_text(reply_text, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            c.user_data['act'] = ''
        elif act == 'a_datetime':
            if msg.isdigit() and int(msg) > 0:
                exp_date = datetime.datetime.now() + datetime.timedelta(days=int(msg))
                d = exp_date.strftime("%Y-%m-%d"); t = exp_date.strftime("%H:%M")
            else:
                d = "NEVER"; t = "00:00"
            if c.user_data.get('proto') == 'trj':
                pwd = c.user_data['p']
                with open(LOCK_FILE, "a") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    with open(TROJAN_DB, 'a') as f:
                        f.write(f"{pwd}|{d}|{t}|ACTIVE\n")
                    fcntl.flock(lock_f, fcntl.LOCK_UN)
                sync_xray()
                resp = f"<b>{TLINE}</b>\n <b>TROJAN CREATED</b> \n<b>{TLINE}</b>\n\n🔑 Password : <code>{pwd}</code>\n📅 Expiry : <code>{d}</code>\n⏰ Time : <code>{t}</code>\n\n<b>{TLINE}</b>\n📋 Copy : <code>{pwd}</code>\n<b>{TLINE}</b>"
            else:
                usr = c.user_data['u']; pwd = c.user_data['p']
                subprocess.run(["useradd", "-M", "-s", "/bin/false", usr], stdout=subprocess.DEVNULL)
                subprocess.run(["chpasswd"], input=f"{usr}:{pwd}".encode(), stdout=subprocess.DEVNULL)
                with open(LOCK_FILE, "a") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    with open(DB_FILE, 'a') as f:
                        f.write(f"{usr}|{d}|{t}\n")
                    fcntl.flock(lock_f, fcntl.LOCK_UN)
                resp = f"<b>{TLINE}</b>\n <b>SSH CREATED</b> \n<b>{TLINE}</b>\n\n👤 Username : <code>{usr}</code>\n🔑 Password : <code>{pwd}</code>\n📅 Expiry : <code>{d}</code>\n⏰ Time : <code>{t}</code>\n\n<b>{TLINE}</b>\n📋 Copy : <code>{usr}:{pwd}</code>\n<b>{TLINE}</b>"
            u.message.reply_text(resp, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            c.user_data.clear()
        elif act == 'r_val':
            usr = c.user_data.get('ru')
            if msg.isdigit() and int(msg) > 0:
                exp_date = datetime.datetime.now() + datetime.timedelta(days=int(msg))
                d = exp_date.strftime("%Y-%m-%d"); t = exp_date.strftime("%H:%M")
            else:
                d = "NEVER"; t = "23:59"
            if c.user_data.get('proto') == 'trj':
                with open(LOCK_FILE, "a") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    with open(TROJAN_DB, 'r+') as f:
                        lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                        lines.append(f"{usr}|{d}|{t}|ACTIVE\n")
                        f.seek(0); f.writelines(lines); f.truncate()
                    fcntl.flock(lock_f, fcntl.LOCK_UN)
                sync_xray()
            else:
                with open(LOCK_FILE, "a") as lock_f:
                    fcntl.flock(lock_f, fcntl.LOCK_EX)
                    with open(DB_FILE, 'r+') as f:
                        lines = [l for l in f.readlines() if not l.startswith(f"{usr}|")]
                        lines.append(f"{usr}|{d}|{t}\n")
                        f.seek(0); f.writelines(lines); f.truncate()
                    fcntl.flock(lock_f, fcntl.LOCK_UN)
                subprocess.run(["usermod", "-U", usr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            u.message.reply_text(f"✅ <b>RENEWED & UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif act == 'd1':
            c.user_data['del_u'] = msg; c.user_data['act'] = ''
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='del_yes'), InlineKeyboardButton("🔴 NO", callback_data='del_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"⚠️ <b>Are you sure you want to delete</b> <code>{msg}</code><b>?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
    except: pass

def main():
    if not TOKEN: return
    up = Updater(TOKEN, use_context=True)
    up.dispatcher.add_handler(CommandHandler('start', start))
    up.dispatcher.add_handler(CallbackQueryHandler(btn))
    up.dispatcher.add_handler(MessageHandler(Filters.text, txt))
    up.start_polling(); up.idle()

if __name__ == '__main__': main()
EOF

cat > /etc/systemd/system/sshbot.service << EOF
[Unit]
Description=SSH & Trojan Telegram Bot Service
After=network.target
[Service]
Type=simple
ExecStart=$PYTHON_BIN /root/ssh_bot.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable sshbot >/dev/null 2>&1; systemctl restart sshbot

echo -e "\n${GREEN}✅ SECURE BOT INSTALLED (WITH SSH & TROJAN SUPPORT)!${NC}"
echo -e "${YELLOW}👉 Go to your Telegram Bot and send /start${NC}"
pause
}

fun_settings() {
while true; do
draw_header
echo -e " ⚙️ ${BLUE}SETTINGS & TOOLS${NC}\n${LINE}"
echo -e " ${BLUE}[1] 🛠️ INSTALL TELEGRAM BOT${NC}"
echo -e " ${BLUE}[2] 🌍 SET TIMEZONE${NC}"
echo -e " ${BLUE}[3] 📤 EXPORT USERS${NC}"
echo -e " ${BLUE}[4] 📥 RESTORE USERS${NC}"
echo -e " ${BLUE}[0] 🔙 BACK${NC}\n${LINE}"
echo -ne " ${BLUE}SELECT: ${NC}"
read s
case "$s" in
1) fun_install_bot ;;
2)
echo -ne " ${BLUE}🌍 Enter Timezone : ${NC}"
read tz
if timedatectl set-timezone "$tz" 2>/dev/null; then
echo -e "\n${GREEN} ✅ TIMEZONE SET TO $tz${NC}"; pause
else
echo -e "\n${RED} ❌ INVALID TIMEZONE!${NC}"; pause
fi
;;
3) fun_export_users ;;
4) fun_import_users ;;
0) break ;;
*) echo -e "\n${RED} INVALID OPTION!${NC}" ; sleep 1 ;;
esac
done
}

function pause_menu() {
echo
read -rp "PRESS ENTER TO RETURN TO WS-TUNNEL MENU..."
}

function prepare_system_and_download() {
echo -e "${YELLOW}🔄 UPDATING SYSTEM AND INSTALLING DEPENDENCIES${NC}"
apt-get update -y > /dev/null 2>&1
apt-get install curl unzip psmisc -y > /dev/null 2>&1

if [ ! -f "/usr/local/bin/WebSocket-VPN" ]; then
echo -e "${YELLOW}⬇️ DOWNLOADING WEBSOCKET-VPN FROM GITHUB${NC}"
curl -s -o WebSocket-VPN https://raw.githubusercontent.com/GO-HAMZA/VPN-SCRIPT/main/WebSocket-VPN
chmod 777 WebSocket-VPN
mv WebSocket-VPN /usr/local/bin/WebSocket-VPN
echo -e "${GREEN}✅ WEBSOCKET-VPN DOWNLOADED AND READY!${NC}"
fi
}

function install_ssh_ws() {
clear
echo -e "${L_BLUE}========================================${NC}"
echo -e "${CYAN} INSTALL SSH OVER WEBSOCKET ${NC}"
echo -e "${L_BLUE}========================================${NC}"

prepare_system_and_download
echo
read -rp "🌐 LISTEN PORT [DEFAULT 80]: " ws_port
ws_port=${ws_port:-80}
read -rp "⚙️ TARGET PORT [DEFAULT 22]: " ssh_port
ssh_port=${ssh_port:-22}

# Stop conflicting web servers if port 80 is selected and free the target port
if [[ "$ws_port" == "80" ]]; then
systemctl stop nginx apache2 2>/dev/null
systemctl disable nginx apache2 2>/dev/null
fi
fuser -k "${ws_port}/tcp" >/dev/null 2>&1

# Automatically open selected port in firewall for all tunnel apps
ufw allow "$ws_port"/tcp >/dev/null 2>&1
iptables -I INPUT -p tcp --dport "$ws_port" -j ACCEPT >/dev/null 2>&1

echo
echo -e "${YELLOW}⚙️ CREATING SYSTEMD SERVICE FOR SSH-WS...${NC}"
tee /etc/systemd/system/ssh-ws.service > /dev/null <<EOF
[Unit]
Description=SSH WebSocket Tunnel
After=network.target ssh.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/WebSocket-VPN -listenAddr :$ws_port -targetAddr 127.0.0.1:$ssh_port
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ssh-ws > /dev/null 2>&1
systemctl restart ssh-ws
echo
echo -e "${GREEN}✅ SSH WS INSTALLED SUCCESSFULLY!${NC}"
printf "EXTERNAL PORT      : ${CYAN}%s${NC}\n" "$ws_port"
printf "TARGET PORT        : ${CYAN}%s (SSH)${NC}\n" "$ssh_port"
printf "SERVICE NAME       : ${CYAN}SSH-WS${NC}\n"
pause_menu
}

function install_trojan_ws() {
clear
echo -e "${L_BLUE}========================================${NC}"
echo -e "${CYAN} INSTALL TROJAN OVER WEBSOCKET ${NC}"
echo -e "${L_BLUE}========================================${NC}"

prepare_system_and_download
echo
read -rp "🔑 TROJAN PASSWORD [OPTIONAL]: " trojan_password
read -rp "🌐 LISTEN PORT [DEFAULT 8080]: " ws_port
ws_port=${ws_port:-8080}
read -rp "⚙️ TARGET PORT [DEFAULT 2000]: " xray_port
xray_port=${xray_port:-2000}
listen_ip="127.0.0.1"

# Stop conflicting web servers if port 80 is selected and free the target port
if [[ "$ws_port" == "80" ]]; then
systemctl stop nginx apache2 2>/dev/null
systemctl disable nginx apache2 2>/dev/null
fi
fuser -k "${ws_port}/tcp" >/dev/null 2>&1

# Automatically open selected port in firewall for all tunnel apps
ufw allow "$ws_port"/tcp >/dev/null 2>&1
iptables -I INPUT -p tcp --dport "$ws_port" -j ACCEPT >/dev/null 2>&1

echo
echo -e "${YELLOW}📦 INSTALLING XRAY CORE...${NC}"
curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s -- install > /dev/null 2>&1
systemctl stop xray > /dev/null 2>&1
mkdir -p /usr/local/etc/xray /var/log/xray
touch "$XRAY_ACCESS_LOG"
chmod 666 "$XRAY_ACCESS_LOG"

if [[ -n "$trojan_password" ]] && ! grep -q "^$trojan_password|" "$TROJAN_DB"; then
( flock -x 200; echo "$trojan_password|NEVER|00:00|ACTIVE" >> "$TROJAN_DB" ) 200>"$DB_LOCK"
fi

echo -e "${YELLOW}⚙️ CONFIGURING XRAY...${NC}"
tee "$XRAY_CONF" > /dev/null <<EOF
{
"log": {
"access": "/var/log/xray/access.log",
"error": "/var/log/xray/error.log",
"loglevel": "info"
},
"stats": {},
"api": {
"tag": "api",
"services": ["HandlerService", "LoggerService", "StatsService"]
},
"policy": {
"levels": {
"0": {
"statsUserUplink": true,
"statsUserDownlink": true,
"statsUserOnline": true
}
},
"system": {
"statsInboundUplink": true,
"statsInboundDownlink": true
}
},
"inbounds": [
{
"tag": "trojan-inbound",
"listen": "$listen_ip",
"port": $xray_port,
"protocol": "trojan",
"settings": {
"clients": []
},
"streamSettings": {
"network": "tcp",
"security": "none"
}
},
{
"listen": "127.0.0.1",
"port": 10085,
"protocol": "dokodemo-door",
"settings": {
"address": "127.0.0.1"
},
"tag": "api"
}
],
"outbounds": [
{
"protocol": "freedom"
}
],
"routing": {
"rules": [
{
"inboundTag": ["api"],
"outboundTag": "api",
"type": "field"
}
]
}
}
EOF

sync_trojan_xray
echo -e "${YELLOW}⚙️ CREATING SYSTEMD SERVICE FOR TROJAN-WS...${NC}"
tee /etc/systemd/system/trojan-ws.service > /dev/null <<EOF
[Unit]
Description=Trojan WebSocket Tunnel
After=network.target xray.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/WebSocket-VPN -listenAddr :$ws_port -targetAddr 127.0.0.1:$xray_port
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray > /dev/null 2>&1
systemctl restart xray
systemctl enable trojan-ws > /dev/null 2>&1
systemctl restart trojan-ws
echo
echo -e "${GREEN}✅ TROJAN WS INSTALLED SUCCESSFULLY!${NC}"
printf "EXTERNAL PORT      : ${CYAN}%s${NC}\n" "$ws_port"
printf "XRAY LOCAL PORT    : ${CYAN}%s${NC}\n" "$xray_port"
printf "SERVICE NAMES      : ${CYAN}XRAY • TROJAN-WS${NC}\n"
[[ -n "$trojan_password" ]] && printf "TROJAN PASSWORD    : ${CYAN}%s [ Saved ]${NC}\n" "$trojan_password"
pause_menu
}

function restart_services() {
clear
echo -e "${L_BLUE}========================================${NC}"
echo -e "${CYAN} RESTART SERVICES ${NC}"
echo -e "${L_BLUE}========================================${NC}"
echo -e " ${YELLOW}[01]${NC} RESTART SSH WS"
echo -e " ${YELLOW}[02]${NC} RESTART TROJAN WS (XRAY)"
echo -e "${L_BLUE}========================================${NC}"
read -rp "➡️ [1-2]: " srv_choice

echo
case $srv_choice in
1|01)
echo -e "${YELLOW}🔄 RESTARTING SSH-WS SERVICE...${NC}"
systemctl restart ssh-ws
echo -e "${GREEN}✅ SSH-WS RESTARTED SUCCESSFULLY!${NC}"
;;
2|02)
echo -e "${YELLOW}🔄 RESTARTING XRAY AND TROJAN-WS SERVICES...${NC}"
systemctl restart xray
systemctl restart trojan-ws
echo -e "${GREEN}✅ TROJAN-WS AND XRAY RESTARTED SUCCESSFULLY!${NC}"
;;
*) echo -e "${RED}❌ INVALID CHOICE!${NC}" ;;
esac
pause_menu
}

function check_status() {
clear
echo -e "${L_BLUE}========================================${NC}"
echo -e "${CYAN} CHECK SERVICE STATUS ${NC}"
echo -e "${L_BLUE}========================================${NC}"
echo -e " ${YELLOW}[01]${NC} STATUS OF SSH WS"
echo -e " ${YELLOW}[02]${NC} STATUS OF TROJAN WS"
echo -e "${L_BLUE}========================================${NC}"
read -rp "➡️ [1-2]: " stat_choice

echo
case $stat_choice in
1|01)
echo -e "${YELLOW}ℹ️ FETCHING SSH-WS STATUS...${NC}"
systemctl status ssh-ws --no-pager
;;
2|02)
echo -e "${YELLOW}ℹ️ FETCHING TROJAN-WS AND XRAY STATUS...${NC}"
systemctl status trojan-ws --no-pager
echo -e "${L_BLUE}----------------------------------------${NC}"
systemctl status xray --no-pager
;;
*) echo -e "${RED}❌ INVALID CHOICE!${NC}" ;;
esac
pause_menu
}

function uninstall_all() {
clear
echo -e "${L_BLUE}========================================${NC}"
echo -e "${RED} UNINSTALL & CLEAN UP ${NC}"
echo -e "${L_BLUE}========================================${NC}"
echo -e "${YELLOW}STOPPING AND REMOVING ALL SERVICES...${NC}"

systemctl stop ssh-ws trojan-ws xray 2>/dev/null
systemctl disable ssh-ws trojan-ws xray 2>/dev/null
rm -f /etc/systemd/system/ssh-ws.service
rm -f /etc/systemd/system/trojan-ws.service
rm -f /usr/local/bin/WebSocket-VPN
systemctl daemon-reload
echo
echo -e "${GREEN}✅ ALL CUSTOM SERVICES AND FILES HAVE BEEN COMPLETELY REMOVED.${NC}"
pause_menu
}

fun_ws_tunnel_menu() {
while true; do
clear
echo -e "${L_BLUE}========================================${NC}"
echo -e "${B_RED}        V P N • I N S T A L L E R ${NC}"
echo -e "${L_BLUE}========================================${NC}"
echo -e " ${YELLOW}[01]${NC} ${D_BLUE}INSTALL SSH WS${NC}"
echo -e " ${YELLOW}[02]${NC} ${D_BLUE}INSTALL TROJAN WS${NC}"
echo -e " ${YELLOW}[03]${NC} ${D_BLUE}RESTART SERVICES${NC}"
echo -e " ${YELLOW}[04]${NC} ${D_BLUE}CHECK SERVICE STATUS${NC}"
echo -e " ${YELLOW}[05]${NC} ${D_BLUE}UNINSTALL SERVICES${NC}"
echo -e " ${YELLOW}[00]${NC} ${D_BLUE}BACK TO MAIN MANAGER${NC}"
echo -e "${L_BLUE}========================================${NC}"
read -rp "➡️ [0-5]: " choice

case $choice in
1|01) install_ssh_ws ;;
2|02) install_trojan_ws ;;
3|03) restart_services ;;
4|04) check_status ;;
5|05) uninstall_all ;;
0|00) break ;;
*) echo -e "${RED}❌ INVALID OPTION! PLEASE TRY AGAIN.${NC}"; sleep 1 ;;
esac
done
}

while true; do
draw_header
echo -e " ${BLUE}[01] • CREATE ACCOUNT${NC}"
echo -e " ${BLUE}[02] • RENEW ACCOUNT${NC}"
echo -e " ${BLUE}[03] • DELETE ACCOUNT${NC}"
echo -e " ${BLUE}[04] • LOCK - UNLOCK ACCOUNT${NC}"
echo -e " ${BLUE}[05] • LIST ACCOUNTS${NC}"
echo -e " ${BLUE}[06] • SEARCH ACCOUNT${NC}"
echo -e " ${BLUE}[07] • MONITOR ACCOUNT${NC}"
echo -e " ${BLUE}[08] • BACKUP DATA${NC}"
echo -e " ${BLUE}[09] • EXPIRED ACCOUNTS${NC}"
echo -e " ${BLUE}[10] • SETTINGS & BOT${NC}"
echo -e " ${BLUE}[11] • SSH WS & TROJAN WS${NC}"
echo -e " ${BLUE}[00] • EXIT${NC}\n${LINE}"
echo -ne " ${BLUE}SELECT :${NC} "
read o
case "$o" in
1|01) fun_create ;;
2|02) fun_renew ;;
3|03) fun_remove ;;
4|04) fun_lock ;;
5|05) fun_list ;;
6|06) fun_search ;;
7|07) fun_monitor_view ;;
8|08) fun_backup ;;
9|09) fun_violations ;;
10) fun_settings ;;
11) fun_ws_tunnel_menu ;;
0|00) clear; exit 0 ;;
*) echo -e "\n${RED} INVALID OPTION!${NC}" ; sleep 1 ;;
esac
done
