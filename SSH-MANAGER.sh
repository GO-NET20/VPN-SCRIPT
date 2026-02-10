#!/bin/bash
# ==================================================
#  SSH MANAGER V28.1 - STABLE FIX 🔧
#  MULTILOGIN CHECK REMOVED
#  ADD USER WITH SIMPLE EXPIRY OPTION
# ==================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- COLORS ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- FILES ---
USER_DB="/etc/xpanel/users_db.txt"
MONITOR_SCRIPT="/usr/local/bin/kp_monitor.sh"
LOG_FILE="/var/log/kp_manager.log"
BANNER_FILE="/etc/issue.net"
BACKUP_DIR="/root/backups"

mkdir -p /etc/xpanel "$BACKUP_DIR"
touch "$USER_DB" "$LOG_FILE"

# ==================================================
#  MONITOR ENGINE (EXPIRY ONLY)
# ==================================================
pkill -f kp_monitor.sh
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
DB="/etc/xpanel/users_db.txt"
LOG="/var/log/kp_manager.log"

while true; do
    NOW=$(date +%s)
    if [[ -f "$DB" ]]; then
        while IFS='|' read -r user date time note; do
            [[ -z "$user" || -z "$date" ]] && continue
            if [[ "$date" != "never" ]]; then
                [[ -z "$time" ]] && time="23:59"
                EXP_TS=$(date -d "$date $time" +%s 2>/dev/null)
                if [[ -n "$EXP_TS" && "$NOW" -ge "$EXP_TS" ]]; then
                    pkill -KILL -u "$user"
                    killall -u "$user" 2>/dev/null
                    userdel -f -r "$user" 2>/dev/null
                    sed -i "/^$user|/d" "$DB"
                    echo "$(date) | EXPIRED | REMOVED $user" >> "$LOG"
                    continue
                fi
            fi
        done < "$DB"
    fi
    sleep 3
done
EOF
chmod +x "$MONITOR_SCRIPT"
if ! pgrep -f "kp_monitor.sh" > /dev/null; then nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 & fi

# ==================================================
#  FUNCTIONS
# ==================================================
pause() { echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"; read; }

# [01] ADD USER
fun_create() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}                 [01] ADD USER                    ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    
    read -p " ENTER USERNAME :" u
    if id "$u" &>/dev/null; then echo -e "${RED}❌ USER ALREADY EXISTS!${NC}"; pause; return; fi
    read -p " ENTER PASSWORD :" p
    
    read -p "Set expiry? (yes/no): " choice
    if [[ "$choice" == "yes" || "$choice" == "y" ]]; then
        read -p " ENTER DATE (YYYY-MM-DD): " d
        if ! date -d "$d" >/dev/null 2>&1; then echo "❌ INVALID DATE!"; pause; return; fi
        read -p " ENTER TIME (HH:MM) [default 23:59]: " t
        [[ -z "$t" ]] && t="23:59"
    else
        d="never"
        t="23:59"
    fi
    
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    echo "$u|$d|$t|V28" >> "$USER_DB"
    
    echo -e "${GREEN}✔ USER CREATED SUCCESSFULLY!${NC}"
    echo -e "USER: $u | EXP: $d @ $t"
    pause
}

# [02] RENEW USER
fun_renew() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}                [02] RENEW USER                   ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    
    read -p " ENTER USERNAME  :" u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "${RED}❌ USER NOT FOUND!${NC}"; pause; return; fi
    read -p " ENTER DATE      :" d
    if ! date -d "$d" >/dev/null 2>&1; then echo -e "${RED}❌ INVALID DATE!${NC}"; pause; return; fi
    read -p " ENTER TIME      :" t
    [[ -z "$t" ]] && t="23:59"
    
    sed -i "/^$u|/d" "$USER_DB"
    echo "$u|$d|$t|Renew" >> "$USER_DB"
    usermod -U "$u"
    
    echo -e "${GREEN}✔ RENEWED SUCCESSFULLY!${NC}"
    pause
}

# [03] REMOVE USER
fun_remove() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${RED}                [03] REMOVE USER                  ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    read -p " ENTER USERNAME TO REMOVE: " u
    read -p "ARE YOU SURE YOU WANT TO REMOVE ($u)? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        pkill -u "$u"; userdel -f -r "$u"
        sed -i "/^$u|/d" "$USER_DB"
        echo -e "${RED}🗑️ USER REMOVED SUCCESSFULLY.${NC}"
    else
        echo "CANCELLED."
    fi
    pause
}

# [04] LOCK OR UNLOCK
fun_lock() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}             [04] LOCK OR UNLOCK USER             ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    read -p " ENTER USERNAME: " u
    echo " [1] LOCK ⛔ (BAN USER)"
    echo " [2] UNLOCK 🔓 (UNBAN USER)"
    read -p " SELECT ACTION: " act
    
    if [[ "$act" == "1" ]]; then 
        usermod -L "$u"; pkill -KILL -u "$u"
        echo -e "${RED}⛔ USER $u IS NOW LOCKED.${NC}"
    elif [[ "$act" == "2" ]]; then 
        usermod -U "$u"
        echo -e "${GREEN}🔓 USER $u IS NOW UNLOCKED.${NC}"
    fi
    pause
}

# [05] SHOW ALL USERS
fun_list() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}              [05] SHOW ALL USERS                 ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${WHITE}USER           | DATE       | TIME  | STATUS${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if ! id "$u" &>/dev/null; then st="${RED}OFFLINE${NC}"
        elif passwd -S "$u" 2>/dev/null | grep -q "L"; then st="${RED}LOCKED ⛔${NC}"
        elif ps -u "$u" -o stat,comm 2>/dev/null | grep -v "Z" | grep -q "sshd"; then st="${GREEN}ONLINE 🟢${NC}"
        else st="${RED}OFFLINE${NC}"; fi
        printf "${YELLOW}%-14s ${NC}| %-10s | %-5s | %b\n" "$u" "$d" "$t" "$st"
    done < "$USER_DB"
    pause
}

# [06] CHECK ONLINE
fun_online() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}             [06] CHECK WHO IS ONLINE             ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${WHITE}USER           | STATUS${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    count=0
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        if ps -u "$u" -o stat,comm 2>/dev/null | grep -v "Z" | grep -q "sshd"; then
            printf "${YELLOW}%-14s ${NC}| ${GREEN}ONLINE 🟢${NC}\n" "$u"
            ((count++))
        fi
    done < "$USER_DB"
    
    if [[ $count -eq 0 ]]; then echo "NO USERS ONLINE."; fi
    pause
}

# [07] SAVE DATA
fun_save() {
    clear
    B_NAME="BACKUP_$(date '+%Y%m%d').txt"
    cp "$USER_DB" "$BACKUP_DIR/$B_NAME"
    echo -e "${GREEN}✅ DATA SAVED SUCCESSFULLY!${NC}"
    echo -e "PATH: $BACKUP_DIR/$B_NAME"
    pause
}

# [08] SETTINGS
fun_settings() {
    clear
    echo " [1] FIX TIMEZONE (TUNISIA)"
    echo " [2] RESTART MONITOR SERVICE"
    echo " [3] SET SERVER BANNER"
    echo " [4] VIEW LOGS"
    read -p " SELECT OPTION: " s
    
    case "$s" in
        1) timedatectl set-timezone Africa/Tunis ;;
        2) pkill -f kp_monitor.sh; nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 & ;;
        3) read -p "BANNER TEXT: " b; echo "$b" > "$BANNER_FILE"; service ssh restart ;;
        4) tail -n 10 "$LOG_FILE" ;;
    esac
    pause
}

# --- MAIN MENU ---
while true; do
    clear
    if pgrep -f "kp_monitor.sh" > /dev/null; then
        MON_MSG="${GREEN}ON${NC}"
    else
        MON_MSG="${RED}OFF${NC}"
        nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 &
    fi

    echo -e "${BLUE}==================================================${NC}"
    echo -e "${WHITE}                   SSH MANAGER                    ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e " [01] ADD USER"
    echo -e " [02] RENEW USER"
    echo -e " [03] REMOVE USER"
    echo -e " [04] LOCK OR UNLOCK USER"
    echo -e " [05] SHOW ALL USERS"
    echo -e " [06] CHECK WHO IS ONLINE"
    echo -e " [07] SAVE DATA"
    echo -e " [08] SETTINGS"
    echo -e " [00] EXIT"
    echo -e " MONITOR: $MON_MSG"
    read -p " SELECT OPTION: " opt
    
    case "$opt" in
        1|01) fun_create ;; 2|02) fun_renew ;; 3|03) fun_remove ;; 4|04) fun_lock ;;
        5|05) fun_list ;; 6|06) fun_online ;; 7|07) fun_save ;; 8|08) fun_settings ;;
        0|00) clear; exit 0 ;; *) echo "INVALID OPTION"; sleep 1 ;;
    esac
done
