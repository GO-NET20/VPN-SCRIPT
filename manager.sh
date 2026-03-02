#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

timedatectl set-timezone Africa/Tunis 2>/dev/null

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
BOT_CONF="/etc/xpanel/bot.conf"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.py"
LOG_FILE="/var/log/kp_manager.log"
BACKUP_DIR="/root/backups"
MIGRATION_FILE="/root/migration_users.txt"

MY_TOKEN="8134717950:AAGj2wWaABBUWbPLa7jX6yEWHgwjgUelpwg"
MY_ID="7587310857"

RED=$'\033[1;31m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'; CYAN=$'\033[1;36m'; NC=$'\033[0m'; WHITE=$'\033[1;37m'
LINE="${BLUE}===============================================${NC}"

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"
[[ ! -f "$BOT_CONF" ]] && touch "$BOT_CONF"

if ! command -v python3 &> /dev/null; then
    $CMD python3 > /dev/null 2>&1
fi

is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

cat > "$MONITOR_SCRIPT" << 'EOF'
#!/usr/bin/env python3
import datetime, subprocess, os, time
import urllib.request, urllib.parse

DB_FILE = "/etc/xpanel/users_db.txt"
CONF_FILE = "/etc/xpanel/bot.conf"
LOG_FILE = "/var/log/kp_manager.log"
MAX_LOGIN = 1
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

def check_loop():
    while True:
        try:
            if os.path.exists(DB_FILE):
                with open(DB_FILE, 'r') as f:
                    lines = f.readlines()
                new_lines = []
                status_changed = False
                now = datetime.datetime.now()
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
                                os.system(f"usermod -L {user} 2>/dev/null")
                                os.system(f"killall -9 -u {user} 2>/dev/null")
                                os.system(f"pkill -KILL -u {user} 2>/dev/null")
                                status_changed = True; expired = True
                                log_event(f"ACCOUNT EXPIRED: {user} locked.")
                                send_alert(f"🔒 <b>ACCOUNT EXPIRED</b>\n\n👤 User: <code>{user}</code>\n🛑 Account automatically locked.", f"{user}_exp")
                        except: pass
                    
                    if expired:
                        new_lines.append(f"{user}|EXPIRED|00:00|SSH\n")
                        continue

                    try:
                        ssh_procs = subprocess.getoutput(f"ps -u {user} -o comm= 2>/dev/null | grep -cE 'sshd|dropbear'")
                        total = int(ssh_procs) if ssh_procs.strip().isdigit() else 0
                        
                        if total > MAX_LOGIN:
                            os.system(f"killall -9 -u {user} 2>/dev/null")
                            os.system(f"pkill -KILL -u {user} 2>/dev/null")
                            log_event(f"MULTI-LOGIN KICK: {user} used {total} connections.")
                            send_alert(f"⚠️ <b>MULTI-LOGIN DETECTED</b>\n\n👤 User: <code>{user}</code>\n💻 Devices: {total}\n🛑 User has been kicked out.", f"{user}_multi")
                    except: pass
                    new_lines.append(line)
                
                if status_changed:
                    with open(DB_FILE, 'w') as f:
                        f.writelines(new_lines)
        except: pass
        time.sleep(3)

if __name__ == "__main__":
    check_loop()
EOF
chmod +x "$MONITOR_SCRIPT"

cat > /etc/systemd/system/kp_monitor.service << 'EOF'
[Unit]
Description=SSH Monitor & Alerts
After=network.target
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/kp_monitor.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kp_monitor >/dev/null 2>&1
systemctl restart kp_monitor

pause() { echo -e "\n${BLUE}PRESS [ENTER] TO RETURN...${NC}"; read; }

draw_header() {
    clear
    echo -e "${LINE}"
    echo -e "             ⚡ ${BLUE}SSH MANAGER V 10${NC} ⚡"
    echo -e "${LINE}"
}

fun_create() {
    draw_header
    
    echo -ne " ${BLUE}👤 Enter Username : ${NC}"
    read u
    
    if [[ -z "$u" ]]; then
        echo -e "\n${RED} ❌ Username cannot be empty!${NC}"
        pause; return
    fi

    if id "$u" &>/dev/null || grep -q "^$u|" "$USER_DB"; then
        echo -e "\n${RED} ❌ USER ALREADY EXISTS!${NC}"
        pause; return
    fi

    echo -ne " ${BLUE}🔑 Enter Password : ${NC}"
    read p
    
    if [[ -z "$p" ]]; then
        echo -e "\n${RED} ❌ Password cannot be empty!${NC}"
        pause; return
    fi
    
    echo -ne " ${BLUE}⏳ Set Expiry Date? [Y/N] : ${NC}"
    read exp_choice
    
    if [[ "${exp_choice,,}" == "y" ]]; then
        echo -ne " ${BLUE}📅 Enter Date and Time (YYYY-MM-DD HH:MM) : ${NC}"
        read dt_input
        d=$(echo "$dt_input" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
        t=$(echo "$dt_input" | grep -oE '[0-9]{2}:[0-9]{2}' | head -1)
        [[ -z "$d" ]] && d="NEVER"
        [[ -z "$t" ]] && t="00:00"
    else
        d="NEVER"
        t="00:00"
    fi
    
    useradd -M -s /bin/false "$u" >/dev/null 2>&1
    echo "$u:$p" | chpasswd >/dev/null 2>&1
    echo "$u|$d|$t|SSH" >> "$USER_DB"
    clear
    echo -e "${LINE}"
    echo -e "                 ${WHITE}ACCOUNT CREATED${NC} "
    echo -e "${LINE}"
    echo -e ""
    echo -e " ${BLUE}👤 Username :${NC} ${WHITE}$u${NC}"
    echo -e " ${BLUE}🔑 Password :${NC} ${WHITE}$p${NC}"
    echo -e " ${BLUE}📅 Expiry   :${NC} ${WHITE}$d${NC}"
    echo -e " ${BLUE}⏰ Time     :${NC} ${WHITE}$t${NC}"
    echo -e ""
    echo -e "${LINE}"
    echo -e " ${BLUE}📋 Copy     :${NC} ${WHITE}$u:$p${NC}"
    echo -e "${LINE}"
    pause
}

fun_renew() {
    draw_header
    echo -e "               🔄 ${BLUE}RENEW ACCOUNT${NC}"
    echo -e "${LINE}"
    echo -ne " ${BLUE}👤 USERNAME : ${NC}"
    read u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "\n${RED} ❌ NOT FOUND!${NC}"; pause; return; fi
    
    echo -ne " ${BLUE}⏳ Set Expiry Date? [Y/N] : ${NC}"
    read exp_choice
    if [[ "${exp_choice,,}" == "y" ]]; then
        echo -ne " ${BLUE}📅 Enter New Date and Time (YYYY-MM-DD HH:MM) : ${NC}"
        read dt_input
        d=$(echo "$dt_input" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
        t=$(echo "$dt_input" | grep -oE '[0-9]{2}:[0-9]{2}' | head -1)
        [[ -z "$d" ]] && d="NEVER"
        [[ -z "$t" ]] && t="23:59"
    else
        d="NEVER"
        t="00:00"
    fi
    
    sed -i "/^$u|/d" "$USER_DB"
    echo "$u|$d|$t|Renew" >> "$USER_DB"
    usermod -U "$u" >/dev/null 2>&1
    echo -e "\n${GREEN} ✅ RENEWED SUCCESSFULLY${NC}"; pause
}

fun_remove() {
    draw_header
    echo -e "               🗑️ ${BLUE}DELETE ACCOUNT${NC}"
    echo -e "${LINE}"
    echo -ne " ${BLUE}👤 USERNAME : ${NC}"
    read u
    echo -ne " ${BLUE}⚠️ CONFIRM? [Y/N]: ${NC}"
    read c
    if [[ "${c,,}" == "y" ]]; then
        pkill -KILL -u "$u" >/dev/null 2>&1
        userdel -f "$u" >/dev/null 2>&1
        sed -i "/^$u|/d" "$USER_DB"
        echo -e "\n${RED} 🗑️ DELETED SUCCESSFULLY${NC}"
    fi
    pause
}

fun_lock() {
    draw_header
    echo -e "               🔒 ${BLUE}LOCK ACCOUNT${NC}"
    echo -e "${LINE}"
    echo -ne " ${BLUE}👤 USERNAME : ${NC}"
    read u
    echo -e " ${BLUE}[1] LOCK ⛔${NC}"
    echo -e " ${BLUE}[2] UNLOCK 🔓${NC}"
    echo -ne " ${BLUE}SELECT: ${NC}"
    read s
    if [[ "$s" == "1" ]]; then
        usermod -L "$u" >/dev/null 2>&1; pkill -KILL -u "$u" >/dev/null 2>&1; echo -e "\n${GREEN} ⛔ LOCKED${NC}"
    else
        usermod -U "$u" >/dev/null 2>&1; echo -e "\n${GREEN} 🔓 UNLOCKED${NC}"
    fi
    pause
}

fun_list() {
    clear
    echo -e "${LINE}"
    echo -e "               📋 ${BLUE}LIST ACCOUNTS${NC}"
    echo -e "${LINE}"
    SHADOW_CACHE=$(cat /etc/shadow 2>/dev/null)
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             if [[ "$d" == "NEVER" || "$d" == "EXPIRED" ]]; then DATE_STR="$d"; else DATE_STR="$d $t"; fi
             if echo "$SHADOW_CACHE" | grep -q "^${u}:!"; then LOCK_STAT="⛔"; else LOCK_STAT="  "; fi
             printf " ${BLUE}👤 %-12s${NC} %s ${BLUE}📅 %s${NC}\n" "$u" "$LOCK_STAT" "$DATE_STR"
        fi
    done < <(sort -V "$USER_DB")
    echo -e "${LINE}"
    pause
}

fun_monitor_view() {
    clear
    echo -e "${LINE}"
    echo -e "               👁 ${BLUE}MONITOR ACCOUNT${NC}"
    echo -e "${LINE}"
    ACTIVE_PROCS=$(ps -eo user,comm 2>/dev/null | grep -E 'sshd|dropbear')
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then
             if echo "$ACTIVE_PROCS" | grep -q "^${u} "; then
                STATUS="${GREEN}🟢 ONLINE${NC}"
             else
                STATUS="${RED}🔴 OFFLINE${NC}"
             fi
             printf " ${BLUE}👤 %-12s${NC}   %s\n" "$u" "$STATUS"
        fi
    done < <(sort -V "$USER_DB")
    echo -e "${LINE}"
    pause
}

fun_backup() {
    draw_header
    echo -e "               💾 ${BLUE}BACKUP DATA${NC}"
    echo -e "${LINE}"
    cp "$USER_DB" "$BACKUP_DIR/users_backup_$(date +%F).txt"
    echo -e "${GREEN} ✅ BACKUP SAVED IN $BACKUP_DIR${NC}"
    pause
}

fun_export_users() {
    draw_header; echo -e "${BLUE} 📤 EXPORTING USERS...${NC}"
    cp "$USER_DB" "$MIGRATION_FILE"
    echo -e "${GREEN} ✅ EXPORT SUCCESSFUL!${NC}\n FILE: $MIGRATION_FILE\n UPLOAD THIS TO NEW SERVER."; pause
}

fun_import_users() {
    draw_header; echo -e "${BLUE} 📥 RESTORING USERS...${NC}"
    if [[ ! -f "$MIGRATION_FILE" ]]; then echo -e "${RED} ❌ FILE NOT FOUND ($MIGRATION_FILE)${NC}"; pause; return; fi
    count=0
    while IFS='|' read -r u d t tag; do
        [[ -z "$u" ]] && continue
        if ! id "$u" &>/dev/null; then
            useradd -M -s /bin/false "$u" >/dev/null 2>&1; echo "$u:12345" | chpasswd >/dev/null 2>&1
            echo -e " CREATED: ${GREEN}$u${NC}"; ((count++))
        fi
    done < "$MIGRATION_FILE"
    cat "$MIGRATION_FILE" > "$USER_DB"
    echo -e "\n${GREEN} ✅ RESTORED: $count USERS${NC}"; pause
}

fun_violations() {
    clear
    echo -e "${LINE}"
    echo -e "         🔔 ${BLUE}ALERTS LOG (VIOLATIONS)${NC}"
    echo -e "${LINE}"
    echo -e ""
    if [ -f "$LOG_FILE" ]; then
        ALERTS=$(grep "MULTI-LOGIN KICK" "$LOG_FILE" | tail -n 15)
        if [[ -z "$ALERTS" ]]; then
            echo -e " ${GREEN}✅ NO VIOLATIONS DETECTED YET.${NC}"
        else
            while read -r line; do
                echo -e " ${RED}⚠️  $line${NC}"
            done <<< "$ALERTS"
        fi
    else
        echo -e " ${YELLOW}LOG FILE IS EMPTY.${NC}"
    fi
    echo -e ""
    echo -e "${LINE}"
    pause
}

# =============================================
# WEBSOCKET VPN INSTALLER FUNCTIONS
# =============================================

fun_install_websocket_vpn_deps() {
    echo -e "${YELLOW}🔄 Updating system and downloading dependencies...${NC}"
    sudo apt update > /dev/null 2>&1
    sudo apt install curl unzip -y > /dev/null 2>&1
    echo -e "${YELLOW}⬇️ Downloading WebSocket-VPN...${NC}"
    curl -o /tmp/WebSocket-VPN https://raw.githubusercontent.com/GO-HAMZA/VPN-SCRIPT/main/WebSocket-VPN 2>/dev/null
    chmod 777 /tmp/WebSocket-VPN
    sudo cp /tmp/WebSocket-VPN /usr/local/bin/WebSocket-VPN
    sudo chmod +x /usr/local/bin/WebSocket-VPN
    rm -f /tmp/WebSocket-VPN
}

fun_install_ssh_ws() {
    clear
    echo -e "${LINE}"
    echo -e "       🌐 ${BLUE}INSTALL SSH OVER WEBSOCKET${NC}"
    echo -e "${LINE}"
    
    fun_install_websocket_vpn_deps
    
    echo -ne " ${BLUE}Enter external port for SSH-WS (Listen Port) [Default 80]: ${NC}"
    read ws_port
    ws_port=${ws_port:-80}
    
    echo -ne " ${BLUE}Enter internal SSH port (Target Port) [Default 22]: ${NC}"
    read ssh_port
    ssh_port=${ssh_port:-22}

    echo -e "${YELLOW}⚙️ Creating systemd service for SSH-WS...${NC}"
    cat > /etc/systemd/system/ssh-ws.service << EOF
[Unit]
Description=SSH WebSocket Tunnel
After=network.target ssh.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/WebSocket-VPN -listenAddr :$ws_port -targetAddr 127.0.0.1:$ssh_port
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ssh-ws >/dev/null 2>&1
    sudo systemctl restart ssh-ws

    echo -e ""
    echo -e "${GREEN}✅ SSH WS Installed Successfully!${NC}"
    echo -e " External Port : ${CYAN}$ws_port${NC}"
    echo -e " Target Port   : ${CYAN}$ssh_port (SSH)${NC}"
    echo -e " Service Name  : ${CYAN}ssh-ws${NC}"
    echo -e ""
    pause
}

fun_install_trojan_ws() {
    clear
    echo -e "${LINE}"
    echo -e "       🌐 ${BLUE}INSTALL TROJAN OVER WEBSOCKET${NC}"
    echo -e "${LINE}"
    
    fun_install_websocket_vpn_deps
    
    echo -ne " ${BLUE}Enter a password for Trojan clients: ${NC}"
    read trojan_password
    echo -ne " ${BLUE}Enter external port for Trojan-WS (Listen Port) [Default 8080]: ${NC}"
    read ws_port
    ws_port=${ws_port:-8080}
    
    echo -ne " ${BLUE}Enter internal Xray port (Target Port) [Default 2000]: ${NC}"
    read xray_port
    xray_port=${xray_port:-2000}

    listen_ip="127.0.0.1"

    echo -e "${YELLOW}📦 Installing Xray...${NC}"
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

    sudo systemctl stop xray
    sudo mkdir -p /usr/local/etc/xray

    cat > /usr/local/etc/xray/config.json << EOF
{
  "inbounds": [
    {
      "tag": "trojan-inbound",
      "listen": "$listen_ip",
      "port": $xray_port,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "$trojan_password"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

    echo -e "${YELLOW}⚙️ Creating systemd service for Trojan-WS...${NC}"
    cat > /etc/systemd/system/trojan-ws.service << EOF
[Unit]
Description=Trojan WebSocket Tunnel
After=network.target xray.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/WebSocket-VPN -listenAddr :$ws_port -targetAddr 127.0.0.1:$xray_port
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable xray >/dev/null 2>&1
    sudo systemctl restart xray
    sudo systemctl enable trojan-ws >/dev/null 2>&1
    sudo systemctl restart trojan-ws

    echo -e ""
    echo -e "${GREEN}✅ Trojan WS Installed Successfully!${NC}"
    echo -e " External Port   : ${CYAN}$ws_port${NC}"
    echo -e " Xray Local Port : ${CYAN}$xray_port${NC}"
    echo -e " Trojan Password : ${CYAN}$trojan_password${NC}"
    echo -e " Service Names   : ${CYAN}xray, trojan-ws${NC}"
    echo -e ""
    pause
}

fun_uninstall_ws() {
    clear
    echo -e "${LINE}"
    echo -e "       🗑️ ${RED}UNINSTALL WEBSOCKET SERVICES${NC}"
    echo -e "${LINE}"
    echo -e "${YELLOW}Stopping and removing services...${NC}"
    
    sudo systemctl stop ssh-ws trojan-ws xray 2>/dev/null
    sudo systemctl disable ssh-ws trojan-ws xray 2>/dev/null
    
    sudo rm -f /etc/systemd/system/ssh-ws.service
    sudo rm -f /etc/systemd/system/trojan-ws.service
    
    sudo rm -f /usr/local/bin/WebSocket-VPN
    
    sudo systemctl daemon-reload
    echo -e "${GREEN}✅ All WebSocket services and files have been removed.${NC}"
    echo -e ""
    pause
}

fun_websocket_menu() {
    while true; do
        draw_header
        echo -e "         🌐 ${BLUE}WEBSOCKET VPN INSTALLER${NC}"
        echo -e "${LINE}"
        echo -e "  ${BLUE}[1] 🌐 Install SSH WS${NC}"
        echo -e "  ${BLUE}[2] 🌐 Install Trojan WS${NC}"
        echo -e "  ${BLUE}[3] 🗑️ Uninstall All WS Services${NC}"
        echo -e "  ${BLUE}[0] 🔙 BACK${NC}"
        echo -e "${LINE}"
        echo -ne "  ${BLUE}SELECT: ${NC}"
        read ws_choice
        case "$ws_choice" in
            1) fun_install_ssh_ws ;;
            2) fun_install_trojan_ws ;;
            3) fun_uninstall_ws ;;
            0) break ;;
            *) echo -e "\n${RED} INVALID OPTION!${NC}" ; sleep 1 ;;
        esac
    done
}

# =============================================
# VPN TUNNEL INSTALLER FUNCTIONS (ASH)
# =============================================

fun_install_udp_hysteria() {
    clear
    echo -e "${LINE}"
    echo -e "       ⚡ ${BLUE}INSTALL UDP HYSTERIA V1.3.5${NC}"
    echo -e "${LINE}"
    apt -y update && apt -y upgrade
    apt -y install wget nano net-tools openssl iptables-persistent screen lsof
    rm -rf /root/hy
    mkdir -p /root/hy
    cd /root/hy
    wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/ashhysteria-linux-amd64
    chmod 755 ashhysteria-linux-amd64
    openssl ecparam -genkey -name prime256v1 -out ca.key
    openssl req -new -x509 -days 36500 -key ca.key -out ca.crt -subj "/CN=bing.com"
    
    while true; do
        echo -ne " ${BLUE}Obfs : ${NC}"
        read obfs
        if [ ! -z "$obfs" ]; then break; fi
    done
    while true; do
        echo -ne " ${BLUE}Auth Str : ${NC}"
        read auth_str
        if [ ! -z "$auth_str" ]; then break; fi
    done
    while true; do
        echo -ne " ${BLUE}Remote UDP Port : ${NC}"
        read remote_udp_port
        if is_number "$remote_udp_port" && [ "$remote_udp_port" -ge 1 ] && [ "$remote_udp_port" -le 65534 ]; then
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65534.${NC}"
        fi
    done
    
    file_path="/root/hy/config.json"
    json_content='{"listen":":'"$remote_udp_port"'","protocol":"udp","cert":"/root/hy/ca.crt","key":"/root/hy/ca.key","up":"100 Mbps","up_mbps":100,"down":"100 Mbps","down_mbps":100,"disable_udp":false,"obfs":"'"$obfs"'","auth_str":"'"$auth_str"'"}'
    echo "$json_content" > "$file_path"
    
    if [ ! -e "$file_path" ]; then
        echo -e "${RED}Error: Unable to save the config.json file${NC}"
        pause; return
    fi
    
    sudo debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v4 boolean true"
    sudo debconf-set-selections <<< "iptables-persistent iptables-persistent/autosave_v6 boolean true"

    echo -ne " ${BLUE}Bind multiple UDP Ports? (y/n): ${NC}"
    read bind
    if [ "$bind" = "y" ]; then
        while true; do
            echo -ne " ${BLUE}Binding UDP Ports : from port : ${NC}"
            read first_number
            if is_number "$first_number" && [ "$first_number" -ge 1 ] && [ "$first_number" -le 65534 ]; then
                break
            else
                echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65534.${NC}"
            fi
        done
        while true; do
            echo -ne " ${BLUE}Binding UDP Ports : from port : $first_number to port : ${NC}"
            read second_number
            if is_number "$second_number" && [ "$second_number" -gt "$first_number" ] && [ "$second_number" -lt 65536 ]; then
                break
            else
                echo -e "${RED}Invalid input. Please enter a valid number greater than $first_number and less than 65536.${NC}"
            fi
        done
        iptables -t nat -L --line-numbers | awk -v var="$first_number:$second_number" '$0 ~ var {print $1}' | tac | xargs -r -I {} iptables -t nat -D PREROUTING {}
        ip6tables -t nat -L --line-numbers | awk -v var="$first_number:$second_number" '$0 ~ var {print $1}' | tac | xargs -r -I {} ip6tables -t nat -D PREROUTING {}
        iptables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport "$first_number":"$second_number" -j DNAT --to-destination :$remote_udp_port
        ip6tables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport "$first_number":"$second_number" -j DNAT --to-destination :$remote_udp_port
    fi
    
    sysctl net.ipv4.conf.all.rp_filter=0
    sysctl net.ipv4.conf.$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1).rp_filter=0 
    echo "net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1).rp_filter=0" > /etc/sysctl.conf
    sysctl -p
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    
    echo -ne " ${BLUE}Run in background or foreground service? (b/f): ${NC}"
    read bind
    if [ "$bind" = "b" ]; then
        screen -dmS hy ./ashhysteria-linux-amd64 server --log-level 0
    else
        cat > /etc/systemd/system/hy.service << EOF
[Unit]
Description=Daemonize UDP Hysteria V1 Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/hy/ashhysteria-linux-amd64 server -c /root/hy/config.json --log-level 0
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl start hy
        systemctl enable hy
    fi
    
    lsof -i :"$remote_udp_port"
    echo -e "${GREEN}UDP Hysteria V1.3.5 installed successfully, please check the logs above${NC}"
    echo -e "IP Address :"
    curl ipv4.icanhazip.com
    echo -e "Obfs : $obfs"
    echo -e "Auth Str : $auth_str"
    pause
}

fun_install_ash_wss() {
    clear
    echo -e "${LINE}"
    echo -e "       🔒 ${BLUE}INSTALL ASH WSS${NC}"
    echo -e "${LINE}"
    apt -y update && apt -y upgrade
    apt -y install openssl lsof screen
    
    while true; do
        echo -ne " ${BLUE}Remote WSS Port : ${NC}"
        read wss_port
        if is_number "$wss_port" && [ "$wss_port" -ge 1 ] && [ "$wss_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
        fi
    done
    while true; do
        echo -ne " ${BLUE}Target TCP Port : ${NC}"
        read target_port
        if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
        fi
    done
    
    rm -rf /root/ashwss
    mkdir -p /root/ashwss
    cd /root/ashwss
    wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/ashwebsocketsni-linux-amd64
    chmod 755 ashwebsocketsni-linux-amd64
    openssl genrsa -out stunnel.key 2048
    openssl req -new -key stunnel.key -x509 -days 1000 -out stunnel.crt
    cat stunnel.crt stunnel.key > stunnel.pem
    rm -rf stunnel.crt
    
    echo -ne " ${BLUE}Run in background or foreground service? (b/f): ${NC}"
    read bind
    if [ "$bind" = "b" ]; then
        screen -dmS ashwss ./ashwebsocketsni-linux-amd64 -listen :$wss_port -forward 127.0.0.1:$target_port -private_key stunnel.pem -public_key stunnel.key
    else
        cat > /etc/systemd/system/ashwss.service << EOF
[Unit]
Description=Daemonize ASH WSS Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/ashwss/ashwebsocketsni-linux-amd64 -listen :$wss_port -forward 127.0.0.1:$target_port -private_key /root/ashwss/stunnel.pem -public_key /root/ashwss/stunnel.key
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl start ashwss
        systemctl enable ashwss
    fi
    
    lsof -i :"$wss_port"
    echo -e "${GREEN}ASH WSS Installed Successfully${NC}"
    pause
}

fun_install_ash_http_ws() {
    clear
    echo -e "${LINE}"
    echo -e "       🌐 ${BLUE}INSTALL ASH HTTP + WS${NC}"
    echo -e "${LINE}"
    apt -y update && apt -y upgrade
    apt -y install iptables-persistent wget screen lsof
    
    while true; do
        echo -ne " ${BLUE}Remote HTTP Port : ${NC}"
        read http_port
        if is_number "$http_port" && [ "$http_port" -ge 1 ] && [ "$http_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
        fi
    done
    while true; do
        echo -ne " ${BLUE}Target HTTP Port : ${NC}"
        read target_port
        if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
        fi
    done
    
    echo -ne " ${BLUE}Bind multiple TCP Ports? (y/n): ${NC}"
    read bind
    if [ "$bind" = "y" ]; then
        while true; do
            echo -ne " ${BLUE}Binding TCP Ports : from port : ${NC}"
            read first_number
            if is_number "$first_number" && [ "$first_number" -ge 1 ] && [ "$first_number" -le 65534 ]; then
                break
            else
                echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65534.${NC}"
            fi
        done
        while true; do
            echo -ne " ${BLUE}Binding TCP Ports : from port : $first_number to port : ${NC}"
            read second_number
            if is_number "$second_number" && [ "$second_number" -gt "$first_number" ] && [ "$second_number" -lt 65536 ]; then
                break
            else
                echo -e "${RED}Invalid input. Please enter a valid number greater than $first_number and less than 65536.${NC}"
            fi
        done
        iptables -t nat -A PREROUTING -p tcp --dport "$first_number":"$second_number" -j REDIRECT --to-port "$http_port"
        iptables-save > /etc/iptables/rules.v4
    fi
    
    rm -rf /root/ashhttp
    mkdir -p /root/ashhttp
    cd /root/ashhttp
    wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/ashhttpproxy-linux-amd64
    chmod 755 ashhttpproxy-linux-amd64

    echo -ne " ${BLUE}Run in background or foreground service? (b/f): ${NC}"
    read bind
    if [ "$bind" = "b" ]; then
        screen -dmS ashhttp ./ashhttpproxy-linux-amd64 -listen :$http_port -forward 127.0.0.1:$target_port
    else
        cat > /etc/systemd/system/ashhttp.service << EOF
[Unit]
Description=Daemonize ASH HTTP Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/ashhttp/ashhttpproxy-linux-amd64 -listen :$http_port -forward 127.0.0.1:$target_port
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl start ashhttp
        systemctl enable ashhttp
    fi

    lsof -i :"$http_port"
    echo -e "${GREEN}ASH HTTP + WS installed successfully${NC}"
    pause
}

fun_install_dnstt() {
    clear
    echo -e "${LINE}"
    echo -e "       🌍 ${BLUE}INSTALL DNSTT, DoH AND DoT${NC}"
    echo -e "${LINE}"
    apt -y update && apt -y upgrade
    apt -y install iptables-persistent wget screen lsof
    rm -rf /root/dnstt
    mkdir -p /root/dnstt
    cd /root/dnstt
    wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/dnstt-server
    chmod 755 dnstt-server
    wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/server.key
    wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/server.pub
    
    echo -e "${YELLOW}"
    cat server.pub
    echo -e "${NC}"
    echo -e " ${BLUE}Copy the pubkey above and press Enter when done${NC}"
    read
    echo -ne " ${BLUE}Enter your Nameserver : ${NC}"
    read ns
    
    iptables -I INPUT -p udp --dport 5300 -j ACCEPT
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
    iptables-save > /etc/iptables/rules.v4

    while true; do
        echo -ne " ${BLUE}Target TCP Port : ${NC}"
        read target_port
        if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
        fi
    done

    echo -ne " ${BLUE}Run in background or foreground service? (b/f): ${NC}"
    read bind
    if [ "$bind" = "b" ]; then
        screen -dmS slowdns ./dnstt-server -udp :5300 -privkey-file server.key $ns 127.0.0.1:$target_port
    else
        cat > /etc/systemd/system/dnstt.service << EOF
[Unit]
Description=Daemonize DNSTT Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/dnstt/dnstt-server -udp :5300 -privkey-file /root/dnstt/server.key $ns 127.0.0.1:$target_port
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl start dnstt
        systemctl enable dnstt
    fi

    lsof -i :5300
    echo -e "${GREEN}DNSTT installation completed${NC}"
    pause
}

fun_install_dns2tcp() {
    clear
    echo -e "${LINE}"
    echo -e "       🌍 ${BLUE}INSTALL DNS2TCP${NC}"
    echo -e "${LINE}"
    echo -e "${YELLOW}Before you continue, make sure that:${NC}"
    echo -e " - No program uses UDP Port 53"
    echo -e " - DNSTT is not running"
    echo -e " - iptables doesn't forward the port 53 to another port"
    echo -e ""
    echo -e "${BLUE}PRESS [ENTER] TO CONTINUE...${NC}"
    read
    
    apt -y update && apt -y upgrade
    apt -y install screen lsof dns2tcp nano
    
    echo -e "${YELLOW}In this step, you will uncomment DNS and write DNS=1.1.1.1 and uncomment DNSStubListener and write DNSStubListener=no${NC}"
    nano /etc/systemd/resolved.conf
    echo -e "${YELLOW}By tapping 'Enter', you confirm that you have uncommented DNS=1.1.1.1 and DNSStubListener=no${NC}"
    read
    
    systemctl restart systemd-resolved
    mkdir -p /root/dns2tcp
    cd /root/dns2tcp
    mkdir -p /var/empty/dns2tcp
    
    echo -ne " ${BLUE}Your Nameserver: ${NC}"
    read nameserver
    echo -ne " ${BLUE}Your key: ${NC}"
    read key
    
    while true; do
        echo -ne " ${BLUE}Target TCP Port : ${NC}"
        read target_port
        if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
        fi
    done
    
    file_path="/root/dns2tcp/dns2tcpdrc"
    cat > "$file_path" << EOF
listen = 0.0.0.0
port = 53
user = ashtunnel
chroot = /var/empty/dns2tcp/
domain = $nameserver
key = $key
resources = ssh:127.0.0.1:$target_port
EOF

    echo -ne " ${BLUE}Run in background or foreground service? (b/f): ${NC}"
    read bind
    if [ "$bind" = "b" ]; then
        dns2tcpd -d 1 -f dns2tcpdrc
    else
        cat > /etc/systemd/system/dns2tcp.service << EOF
[Unit]
Description=Daemonize DNS2TCP Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/usr/bin/dns2tcpd -d 1 -F -f /root/dns2tcp/dns2tcpdrc
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl start dns2tcp
        systemctl enable dns2tcp
    fi
    
    echo -e "${YELLOW}In the next step, add nameserver 1.1.1.1 to the file if there is only nameserver 127.0.0.1 or nameserver 127.0.0.53${NC}"
    nano /etc/resolv.conf
    echo -e "${YELLOW}By tapping 'Enter', you confirm that you have added nameserver 1.1.1.1${NC}"
    read
    
    lsof -i :53
    echo -e "${GREEN}DNS2TCP server installed successfully${NC}"
    pause
}

fun_install_badvpn() {
    clear
    echo -e "${LINE}"
    echo -e "       📡 ${BLUE}INSTALL BADVPN UDPGW (PORT 7300)${NC}"
    echo -e "${LINE}"
    apt -y update && apt -y upgrade
    apt -y install wget lsof
    rm -rf /root/badvpn
    mkdir -p /root/badvpn
    cd /root/badvpn
    wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/badvpn-udpgw
    chmod 755 badvpn-udpgw
    
    cat > /etc/systemd/system/badvpn.service << 'EOF'
[Unit]
Description=Daemonize BadVPN UDPGW Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/badvpn/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10 --loglevel 0
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl start badvpn
    systemctl enable badvpn
    lsof -i :7300
    echo -e "${GREEN}BadVPN UDPGW Installed Successfully${NC}"
    pause
}

fun_install_ash_ssl() {
    clear
    echo -e "${LINE}"
    echo -e "       🔒 ${BLUE}INSTALL ASH SSL${NC}"
    echo -e "${LINE}"
    apt -y update && apt -y upgrade
    apt -y install openssl lsof screen
    
    while true; do
        echo -ne " ${BLUE}Remote SSL Port : ${NC}"
        read ssl_port
        if is_number "$ssl_port" && [ "$ssl_port" -ge 1 ] && [ "$ssl_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
        fi
    done
    while true; do
        echo -ne " ${BLUE}Target TCP Port : ${NC}"
        read target_port
        if is_number "$target_port" && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
        fi
    done
    
    rm -rf /root/ashssl
    mkdir -p /root/ashssl
    cd /root/ashssl
    wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/ashsslproxy-linux-amd64
    chmod 755 ashsslproxy-linux-amd64
    openssl genrsa -out stunnel.key 2048
    openssl req -new -key stunnel.key -x509 -days 1000 -out stunnel.crt
    cat stunnel.crt stunnel.key > stunnel.pem
    rm -rf stunnel.crt
    
    echo -ne " ${BLUE}Run in background or foreground service? (b/f): ${NC}"
    read bind
    if [ "$bind" = "b" ]; then
        screen -dmS ashssl ./ashsslproxy-linux-amd64 -listen :$ssl_port -forward 127.0.0.1:$target_port -private_key stunnel.pem -public_key stunnel.key
    else
        cat > /etc/systemd/system/ashssl.service << EOF
[Unit]
Description=Daemonize ASH SSL Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/ashssl/ashsslproxy-linux-amd64 -listen :$ssl_port -forward 127.0.0.1:$target_port -private_key /root/ashssl/stunnel.pem -public_key /root/ashssl/stunnel.key
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl start ashssl
        systemctl enable ashssl
    fi
    
    lsof -i :"$ssl_port"
    echo -e "${GREEN}ASH SSL Installed Successfully${NC}"
    pause
}

fun_install_ash_ssh() {
    clear
    echo -e "${LINE}"
    echo -e "       🔑 ${BLUE}INSTALL ASH SSH${NC}"
    echo -e "${LINE}"
    echo -e "${YELLOW}[Warning] This version of SSH is only for tunneling. It has anti-torrent features.${NC}"
    echo -e "${YELLOW}It does NOT come with shell environment support. Do NOT replace it with your${NC}"
    echo -e "${YELLOW}current SSH. Use it only for tunneling, otherwise you will lose shell access.${NC}"
    echo -e ""
    echo -e "${BLUE}Press Enter to accept and continue...${NC}"
    read
    
    apt -y update && apt -y upgrade
    apt -y install lsof screen
    
    while true; do
        echo -ne " ${BLUE}Remote SSH Port : ${NC}"
        read ssh_port
        if is_number "$ssh_port" && [ "$ssh_port" -ge 1 ] && [ "$ssh_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}Invalid input. Please enter a valid number between 1 and 65535.${NC}"
        fi
    done
    
    rm -rf /root/ashssh
    mkdir -p /root/ashssh
    cd /root/ashssh
    wget https://raw.githubusercontent.com/ASHANTENNA/VPNScript/main/ashssh-linux-amd64
    chmod 755 ashssh-linux-amd64
    
    echo -ne " ${BLUE}Run in background or foreground service? (b/f): ${NC}"
    read bind
    if [ "$bind" = "b" ]; then
        screen -dmS ashssh ./ashssh-linux-amd64 -listen :$ssh_port -hostkey /etc/ssh/ssh_host_rsa_key
    else
        cat > /etc/systemd/system/ashssh.service << EOF
[Unit]
Description=Daemonize ASH SSH Tunnel Server
Wants=network.target
After=network.target
[Service]
ExecStart=/root/ashssh/ashssh-linux-amd64 -listen :$ssh_port -hostkey /etc/ssh/ssh_host_rsa_key
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl start ashssh
        systemctl enable ashssh
    fi
    
    lsof -i :"$ssh_port"
    echo -e "${GREEN}ASH SSH Installed Successfully${NC}"
    pause
}

fun_vpn_tunnel_menu() {
    while true; do
        draw_header
        echo -e "        ⚡ ${BLUE}VPN TUNNEL INSTALLER${NC}"
        echo -e "${LINE}"
        echo -e "  ${BLUE}[1] ⚡ Install UDP Hysteria V1.3.5${NC}"
        echo -e "  ${BLUE}[2] 🔒 Install ASH WSS${NC}"
        echo -e "  ${BLUE}[3] 🌐 Install ASH HTTP + WS${NC}"
        echo -e "  ${BLUE}[4] 🌍 Install DNSTT, DoH and DoT${NC}"
        echo -e "  ${BLUE}[5] 🌍 Install DNS2TCP${NC}"
        echo -e "  ${BLUE}[6] 📡 Install BadVPN UDPGW (port 7300)${NC}"
        echo -e "  ${BLUE}[7] 🔒 Install ASH SSL${NC}"
        echo -e "  ${BLUE}[8] 🔑 Install ASH SSH${NC}"
        echo -e "  ${BLUE}[0] 🔙 BACK${NC}"
        echo -e "${LINE}"
        echo -ne "  ${BLUE}SELECT: ${NC}"
        read vpn_choice
        case "$vpn_choice" in
            1) fun_install_udp_hysteria ;;
            2) fun_install_ash_wss ;;
            3) fun_install_ash_http_ws ;;
            4) fun_install_dnstt ;;
            5) fun_install_dns2tcp ;;
            6) fun_install_badvpn ;;
            7) fun_install_ash_ssl ;;
            8) fun_install_ash_ssh ;;
            0) break ;;
            *) echo -e "\n${RED} INVALID OPTION!${NC}" ; sleep 1 ;;
        esac
    done
}

# =============================================
# TELEGRAM BOT INSTALLER
# =============================================

fun_install_bot() {
    pkill -f ssh_bot.py
    systemctl stop sshbot >/dev/null 2>&1
    clear; echo -e "${BLUE}INSTALLING BOT WITH SMART LOCK...${NC}"
    pip3 install python-telegram-bot==13.7 schedule requests --break-system-packages >/dev/null 2>&1 || \
    pip3 install python-telegram-bot==13.7 schedule requests >/dev/null 2>&1
    echo "BOT_TOKEN=\"$MY_TOKEN\"" > "$BOT_CONF"
    echo "ADMIN_ID=\"$MY_ID\"" >> "$BOT_CONF"
    echo "ALERTS=\"ON\"" >> "$BOT_CONF"
    chmod 600 "$BOT_CONF"
    cat > /root/ssh_bot.py << 'EOF'
import logging, os, subprocess, re
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, CallbackContext

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(message)s')
CONF_FILE = "/etc/xpanel/bot.conf"
DB_FILE = "/etc/xpanel/users_db.txt"
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

def get_menu():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 CREATE ACCOUNT", callback_data='add'), InlineKeyboardButton("🔄 RENEW ACCOUNT", callback_data='ren')],
        [InlineKeyboardButton("🗑 DELETE ACCOUNT", callback_data='del'), InlineKeyboardButton("🔒 LOCK ACCOUNT", callback_data='lock_menu')],
        [InlineKeyboardButton("📋 LIST ACCOUNTS", callback_data='list'), InlineKeyboardButton("👁 MONITOR ACCOUNT", callback_data='onl')],
        [InlineKeyboardButton("💾 BACKUP DATA", callback_data='bak'), InlineKeyboardButton("🔔 ALERTS LOG", callback_data='alerts')],
        [InlineKeyboardButton("⚙ SETTINGS", callback_data='bot_set'), InlineKeyboardButton("🚪 EXIT", callback_data='close')]
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
    if u.effective_user.id == ADMIN_ID: u.message.reply_text(f"⚡ <b>SSH MANAGER V 10</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu())

def btn(u, c):
    q = u.callback_query; q.answer(); d = q.data
    if d == 'close':
        try: q.message.delete()
        except: pass
        return
    if d == 'back': c.user_data.clear(); q.edit_message_text(f"⚡ <b>SSH MANAGER V 10</b>", parse_mode=ParseMode.HTML, reply_markup=get_menu()); return
    try:
        if d == 'add':
            c.user_data['act'] = 'add_u'
            q.edit_message_text("👤 <b>Send the New Username in chat:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'add_yes':
            c.user_data['act'] = 'a_datetime'
            q.edit_message_text(f"👤 Username : <code>{c.user_data['u']}</code>\n🔑 Password  : <code>{c.user_data['p']}</code>\n\n📅 <b>Enter Date and Time (YYYY-MM-DD HH:MM) :</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'add_no':
            usr = c.user_data['u']; pwd = c.user_data['p']; dt = "NEVER"; tm = "00:00"
            subprocess.run(f"useradd -M -s /bin/false {usr}", shell=True, stdout=subprocess.DEVNULL); subprocess.run(f"echo '{usr}:{pwd}' | chpasswd", shell=True, stdout=subprocess.DEVNULL)
            open(DB_FILE, 'a').write(f"{usr}|{dt}|{tm}|SSH\n")
            resp = (f"<b>{TLINE}</b>\n           <b>ACCOUNT CREATED</b>          \n<b>{TLINE}</b>\n\n👤 Username : <code>{usr}</code>\n🔑 Password : <code>{pwd}</code>\n📅 Expiry   : <code>{dt}</code>\n⏰ Time     : <code>{tm}</code>\n\n<b>{TLINE}</b>\n📋 Copy     : <code>{usr}:{pwd}</code>\n<b>{TLINE}</b>")
            q.edit_message_text(resp, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            c.user_data.clear()

        elif d == 'ren': 
            c.user_data['act']='r_user'
            q.edit_message_text("🔄 <b>Enter Username to Renew:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'ren_yes':
            c.user_data['act'] = 'r_val'
            q.edit_message_text("📅 <b>Enter New Date and Time :</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'ren_no':
            usr = c.user_data.get('ru')
            lines = [l for l in open(DB_FILE) if not l.startswith(f"{usr}|")]
            lines.append(f"{usr}|NEVER|00:00|Renew\n")
            open(DB_FILE, 'w').writelines(lines)
            subprocess.run(f"usermod -U {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            q.edit_message_text(f"✅ <b>RENEWED & UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'del': 
            c.user_data['act']='d1'
            q.edit_message_text("🗑️ <b>Username to Delete:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d == 'del_yes':
            usr = c.user_data.get('del_u')
            if usr:
                os.system(f"killall -9 -u {usr} 2>/dev/null; pkill -KILL -u {usr} 2>/dev/null")
                subprocess.run(f"userdel -f {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if os.path.exists(DB_FILE):
                    lines = [l for l in open(DB_FILE) if not l.startswith(f"{usr}|")]
                    open(DB_FILE, 'w').writelines(lines)
                q.edit_message_text(f"🗑️ <b>DELETED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
                
        elif d == 'del_no':
            q.edit_message_text("❌ <b>Deletion Cancelled.</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'lock_menu':
            c.user_data['act']='lu_user'
            q.edit_message_text("🔒/🔓 <b>Enter Username to Lock or Unlock:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d.startswith('do_lock_'):
            usr = d.split('_', 2)[2]
            subprocess.run(f"usermod -L {usr}", shell=True, stdout=subprocess.DEVNULL)
            os.system(f"killall -9 -u {usr} 2>/dev/null; pkill -KILL -u {usr} 2>/dev/null")
            q.edit_message_text(f"⛔ <b>LOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif d.startswith('do_unlock_'):
            usr = d.split('_', 2)[2]
            subprocess.run(f"usermod -U {usr}", shell=True, stdout=subprocess.DEVNULL)
            q.edit_message_text(f"🔓 <b>UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'list':
            if os.path.exists(DB_FILE):
                try: shadow_data = open('/etc/shadow', 'r').read()
                except: shadow_data = ""
                
                valid_lines = [l.strip().split('|') for l in open(DB_FILE) if len(l.strip().split('|')) >= 3 and "root" not in l]
                if not valid_lines:
                    q.edit_message_text("No users found.", reply_markup=get_back_btn())
                    return
                
                chunk_size = 100
                chunks = [valid_lines[i:i + chunk_size] for i in range(0, len(valid_lines), chunk_size)]
                
                for idx, chunk in enumerate(chunks):
                    total_pages = len(chunks)
                    if total_pages > 1:
                        pg_str = f"ALL USERS (Page {idx+1}/{total_pages})"
                        sp_l = max(0, (28 - len(pg_str)) // 2)
                        sp_r = max(0, 28 - len(pg_str) - sp_l)
                        header = f"<b>{TLINE}</b>\n{' '*sp_l}<b>{pg_str}</b>{' '*sp_r}\n<b>{TLINE}</b>\n\n"
                    else:
                        header = f"<b>{TLINE}</b>\n         <b>ALL USERS</b>         \n<b>{TLINE}</b>\n\n"
                        
                    body = header
                    for p in chunk:
                        usr, date, tm = p[0], p[1], p[2]
                        date_str = date if date in ["NEVER", "EXPIRED"] else f"{date} {tm}"
                        lock_icon = " ⛔" if f"\n{usr}:!" in shadow_data or shadow_data.startswith(f"{usr}:!") else ""
                        body += f"👤 <code>{usr}</code>{lock_icon}\n📅 <code>{date_str}</code>\n\n"
                    
                    if idx == 0:
                        q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if total_pages == 1 else None)
                    else:
                        c.bot.send_message(chat_id=u.effective_chat.id, text=body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if idx == total_pages - 1 else None)
            else:
                q.edit_message_text("No users found.", reply_markup=get_back_btn())

        elif d == 'onl':
            if os.path.exists(DB_FILE):
                try:
                    active_users_raw = subprocess.getoutput("ps -eo user,comm | grep -E 'sshd|dropbear' | awk '{print $1}'").split()
                    active_set = set(active_users_raw)
                except: active_set = set()
                
                valid_lines = [l.strip().split('|')[0] for l in open(DB_FILE) if len(l.strip().split('|')) >= 3 and "root" not in l]
                if not valid_lines:
                    q.edit_message_text("No users found.", reply_markup=get_back_btn())
                    return
                
                chunk_size = 100
                chunks = [valid_lines[i:i + chunk_size] for i in range(0, len(valid_lines), chunk_size)]
                
                for idx, chunk in enumerate(chunks):
                    total_pages = len(chunks)
                    if total_pages > 1:
                        pg_str = f"LIVE MONITOR (Page {idx+1}/{total_pages})"
                        sp_l = max(0, (28 - len(pg_str)) // 2)
                        sp_r = max(0, 28 - len(pg_str) - sp_l)
                        header = f"<b>{TLINE}</b>\n{' '*sp_l}<b>{pg_str}</b>{' '*sp_r}\n<b>{TLINE}</b>\n\n"
                    else:
                        header = f"<b>{TLINE}</b>\n        <b>LIVE MONITOR</b>        \n<b>{TLINE}</b>\n\n"
                        
                    body = header
                    for usr in chunk:
                        st = "🟢 ONLINE" if usr in active_set else "🔴 OFFLINE"
                        body += f"👤 <code>{usr}</code>\n{st}\n\n"
                    
                    if idx == 0:
                        q.edit_message_text(body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if total_pages == 1 else None)
                    else:
                        c.bot.send_message(chat_id=u.effective_chat.id, text=body, parse_mode=ParseMode.HTML, reply_markup=get_back_btn() if idx == total_pages - 1 else None)
            else:
                q.edit_message_text("No users found.", reply_markup=get_back_btn())
                
        elif d == 'alerts':
            if os.path.exists(LOG_FILE):
                try:
                    alerts_raw = subprocess.getoutput(f"grep 'MULTI-LOGIN KICK' {LOG_FILE} | tail -n 15")
                    if not alerts_raw.strip():
                        msg = "✅ <b>NO VIOLATIONS DETECTED YET.</b>"
                    else:
                        msg = "🔔 <b>ALERTS LOG (VIOLATIONS)</b>\n\n"
                        for l in alerts_raw.split('\n'):
                            if l.strip(): msg += f"⚠️ {l}\n"
                except:
                    msg = "Error reading log."
            else:
                msg = "⚠️ <b>LOG FILE IS EMPTY.</b>"
            q.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())

        elif d == 'bak':
            if os.path.exists(DB_FILE): c.bot.send_document(ADMIN_ID, open(DB_FILE, 'rb'))
            q.edit_message_text("✅ <b>DATA SAVED & SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
        elif d == 'bot_set':
            q.edit_message_text("⚙️ <b>SETTINGS</b>\nChoose an option:", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'set_info':
            try:
                up = subprocess.getoutput("uptime -p")
                ram = subprocess.getoutput("free -m | awk 'NR==2{printf \"%.2f%%\", $3*100/$2 }'")
                cpu = subprocess.getoutput("top -bn1 | grep load | awk '{printf \"%.2f%%\", $(NF-2)}'")
                msg = f"💻 <b>SERVER INFO</b>\n\n⏱ <b>Uptime:</b> {up}\n🧠 <b>RAM:</b> {ram}\n⚙️ <b>CPU Load:</b> {cpu}"
            except: msg = "💻 <b>SERVER INFO</b>\nError fetching info."
            q.edit_message_text(msg, parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'set_mon':
            subprocess.run("systemctl restart kp_monitor", shell=True)
            q.edit_message_text("✅ <b>Monitor Restarted!</b>", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
        elif d == 'migrate':
            if os.path.exists(DB_FILE):
                subprocess.run(f"cp {DB_FILE} {MIGRATION_FILE}", shell=True)
                c.bot.send_document(ADMIN_ID, open(MIGRATION_FILE, 'rb'), caption="🚀 <b>MIGRATION FILE</b>", parse_mode=ParseMode.HTML)
                q.edit_message_text("✅ <b>MIGRATION FILE SENT!</b>", parse_mode=ParseMode.HTML, reply_markup=get_settings_menu())
    except: pass

def txt(u, c):
    if u.effective_user.id != ADMIN_ID: return
    msg = u.message.text; act = c.user_data.get('act')
    try:
        if act == 'add_u':
            usr = msg.strip()
            if subprocess.run(f"id {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0 or (os.path.exists(DB_FILE) and f"{usr}|" in open(DB_FILE).read()):
                u.message.reply_text("❌ <b>User already exists!</b> Try another username:", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            else:
                c.user_data['u'] = usr
                c.user_data['act'] = 'add_p'
                u.message.reply_text(f"👤 Username: <code>{usr}</code>\n\n🔑 <b>Send the Password for this user:</b>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
                
        elif act == 'add_p':
            c.user_data['p'] = msg.strip()
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='add_yes'), InlineKeyboardButton("🔴 NO", callback_data='add_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"👤 Username: <code>{c.user_data['u']}</code>\n🔑 Password: <code>{c.user_data['p']}</code>\n\n⏳ <b>Set Expiry Date?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''

        elif act == 'lu_user':
            usr = msg.strip()
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🔒 LOCK", callback_data=f"do_lock_{usr}"), InlineKeyboardButton("🔓 UNLOCK", callback_data=f"do_unlock_{usr}")],[InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"Select action for <b>{usr}</b>:", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''
        
        elif act == 'r_user':
            c.user_data['ru'] = msg.strip()
            kb = InlineKeyboardMarkup([[InlineKeyboardButton("🟢 YES", callback_data='ren_yes'), InlineKeyboardButton("🔴 NO", callback_data='ren_no')], [InlineKeyboardButton("🔙 BACK", callback_data='back')]])
            u.message.reply_text(f"⏳ <b>Set Expiry Date for {msg}?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''

        elif act == 'a_datetime':
            usr = c.user_data['u']; pwd = c.user_data['p']
            dm = re.search(r'\d{4}-\d{2}-\d{2}', msg); tm = re.search(r'\d{2}:\d{2}', msg)
            d = dm.group(0) if dm else "NEVER"; t = tm.group(0) if tm else "00:00"
            subprocess.run(f"useradd -M -s /bin/false {usr}", shell=True, stdout=subprocess.DEVNULL); subprocess.run(f"echo '{usr}:{pwd}' | chpasswd", shell=True, stdout=subprocess.DEVNULL)
            open(DB_FILE, 'a').write(f"{usr}|{d}|{t}|SSH\n")
            resp = (f"<b>{TLINE}</b>\n           <b>ACCOUNT CREATED</b>          \n<b>{TLINE}</b>\n\n👤 Username : <code>{usr}</code>\n🔑 Password : <code>{pwd}</code>\n📅 Expiry   : <code>{d}</code>\n⏰ Time     : <code>{t}</code>\n\n<b>{TLINE}</b>\n📋 Copy     : <code>{usr}:{pwd}</code>\n<b>{TLINE}</b>")
            u.message.reply_text(resp, parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            c.user_data.clear()
            
        elif act == 'r_val':
            usr = c.user_data.get('ru'); dm = re.search(r'\d{4}-\d{2}-\d{2}', msg); tm = re.search(r'\d{2}:\d{2}', msg)
            d = dm.group(0) if dm else "NEVER"; t = tm.group(0) if tm else "23:59"
            lines = [l for l in open(DB_FILE) if not l.startswith(f"{usr}|")]
            lines.append(f"{usr}|{d}|{t}|Renew\n")
            open(DB_FILE, 'w').writelines(lines)
            subprocess.run(f"usermod -U {usr}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            u.message.reply_text(f"✅ <b>RENEWED & UNLOCKED:</b> <code>{usr}</code>", parse_mode=ParseMode.HTML, reply_markup=get_back_btn())
            
        elif act == 'd1':
            usr_to_del = msg.strip()
            c.user_data['del_u'] = usr_to_del
            kb = InlineKeyboardMarkup([
                [InlineKeyboardButton("🟢 YES", callback_data='del_yes'), InlineKeyboardButton("🔴 NO", callback_data='del_no')],
                [InlineKeyboardButton("🔙 BACK", callback_data='back')]
            ])
            u.message.reply_text(f"⚠️ <b>Are you sure you want to delete</b> <code>{usr_to_del}</code><b>?</b>", parse_mode=ParseMode.HTML, reply_markup=kb)
            c.user_data['act'] = ''
            
    except: pass

def main():
    if not TOKEN: return
    up = Updater(TOKEN, use_context=True)
    up.dispatcher.add_handler(CommandHandler('start', start))
    up.dispatcher.add_handler(CallbackQueryHandler(btn)); up.dispatcher.add_handler(MessageHandler(Filters.text, txt))
    up.start_polling(); up.idle()
if __name__ == '__main__': main()
EOF
    cat > /etc/systemd/system/sshbot.service << 'EOF'
[Unit]
Description=SSH Bot Service
After=network.target
[Service]
ExecStart=/usr/bin/python3 /root/ssh_bot.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable sshbot >/dev/null 2>&1; systemctl restart sshbot
    echo -e "\n${GREEN}✅ BOT INSTALLED SUCCESSFULLY!${NC}"; pause
}

# =============================================
# SETTINGS MENU (MERGED)
# =============================================

fun_settings() {
    while true; do
        draw_header
        echo -e "            ⚙️ ${BLUE}SETTINGS & TOOLS${NC}"
        echo -e "${LINE}"
        echo -e "  ${BLUE}[1] 🛠️ INSTALL TELEGRAM BOT${NC}"
        echo -e "  ${BLUE}[2] 🌍 SET TIMEZONE${NC}"
        echo -e "  ${BLUE}[3] 📤 EXPORT USERS${NC}"
        echo -e "  ${BLUE}[4] 📥 RESTORE USERS${NC}"
        echo -e "  ${BLUE}[5] 🌐 WEBSOCKET VPN INSTALLER${NC}"
        echo -e "  ${BLUE}[6] ⚡ VPN TUNNEL INSTALLER${NC}"
        echo -e "  ${BLUE}[0] 🔙 BACK${NC}"
        echo -e "${LINE}"
        echo -ne "  ${BLUE}SELECT: ${NC}"
        read s
        case "$s" in
            1) fun_install_bot ;;
            2) timedatectl set-timezone Africa/Tunis; echo -e "\n${GREEN} ✅ TIMEZONE SET TO TUNIS${NC}"; pause ;;
            3) fun_export_users ;;
            4) fun_import_users ;;
            5) fun_websocket_menu ;;
            6) fun_vpn_tunnel_menu ;;
            0) break ;;
            *) echo -e "\n${RED} INVALID OPTION!${NC}" ; sleep 1 ;;
        esac
    done
}

# =============================================
# MAIN MENU
# =============================================

while true; do
    draw_header
    echo -e "  ${BLUE}[01] 👤 CREATE ACCOUNT${NC}"
    echo -e "  ${BLUE}[02] 🔄 RENEW ACCOUNT${NC}"
    echo -e "  ${BLUE}[03] 🗑 DELETE ACCOUNT${NC}"
    echo -e "  ${BLUE}[04] ⛔ LOCK ACCOUNT${NC}"
    echo -e "  ${BLUE}[05] 📋 LIST ACCOUNTS${NC}"
    echo -e "  ${BLUE}[06] 👁 MONITOR ACCOUNT${NC}"
    echo -e "  ${BLUE}[07] 💾 BACKUP DATA${NC}"
    echo -e "  ${BLUE}[08] 🔔 ALERTS LOG${NC}"
    echo -e "  ${BLUE}[09] ⚙️ SETTINGS${NC}  "
    echo -e "  ${BLUE}[00] ↪️ EXIT${NC}"
    echo -e "${LINE}"
    echo -ne "  ${BLUE}SELECT:${NC} "
    read o
    case "$o" in
        1|01) fun_create ;; 
        2|02) fun_renew ;; 
        3|03) fun_remove ;; 
        4|04) fun_lock ;;
        5|05) fun_list ;; 
        6|06) fun_monitor_view ;; 
        7|07) fun_backup ;; 
        8|08) fun_violations ;; 
        9|09) fun_settings ;;  
        0|00) clear; exit 0 ;;
        *) echo -e "\n${RED} INVALID OPTION!${NC}" ; sleep 1 ;;
    esac
done
