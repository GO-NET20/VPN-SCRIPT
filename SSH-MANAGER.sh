#!/bin/bash
# ==================================================
#  SSH MANAGER V28.3
#  - MENU DESIGN: UPDATED
#  - FEATURES: 60s DELAY + EXPIRY CHOICE
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
#  MONITOR ENGINE (BACKGROUND SERVICE)
# ==================================================
pkill -f kp_monitor.sh
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
DB="/etc/xpanel/users_db.txt"
LOG="/var/log/kp_manager.log"
MAX_LOGIN=1

while true; do
    NOW=$(date +%s)
    if [[ -f "$DB" ]]; then
        while IFS='|' read -r user date time note; do
            [[ -z "$user" || -z "$date" ]] && continue
            
            # 1. CHECK EXPIRY (IGNORE "NEVER")
            if [[ "$date" != "NEVER" ]]; then
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

            # 2. ANTI-MULTILOGIN (WITH 60s DELAY)
            if [[ "$user" == "root" ]]; then continue; fi
            COUNT=$(ps -u "$user" -o stat,comm 2>/dev/null | grep -v "Z" | grep "sshd" | wc -l)
            
            if [[ "$COUNT" -gt "$MAX_LOGIN" ]]; then
                # WAIT 60 SECONDS (GRACE PERIOD)
                sleep 60
                
                # CHECK AGAIN
                COUNT_AGAIN=$(ps -u "$user" -o stat,comm 2>/dev/null | grep -v "Z" | grep "sshd" | wc -l)
                
                if [[ "$COUNT_AGAIN" -gt "$MAX_LOGIN" ]]; then
                    pkill -KILL -u "$user"
                    killall -u "$user" 2>/dev/null
                    userdel -f -r "$user" 2>/dev/null
                    sed -i "/^$user|/d" "$DB"
                    echo "$(date) | CHEATER | REMOVED $user" >> "$LOG"
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

pause() {
    echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"
    read
}

# [01] ADD ACCOUNT
fun_create() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}   [01] ADD ACCOUNT     ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo ""
    
    # 1. USERNAME
    read -p " ENTER USERNAME : " u
    if id "$u" &>/dev/null; then 
        echo -e "${RED}❌ ERROR: ACCOUNT ALREADY EXISTS!${NC}"
        pause
        return
    fi
    
    # 2. PASSWORD
    read -p " ENTER PASSWORD : " p
    
    echo -e "${CYAN}------------------------${NC}"
    
    # 3. EXPIRY CHOICE
    read -p " SET EXPIRY DATE? (Y/N) : " choice
    
    if [[ "$choice" == "Y" || "$choice" == "y" ]]; then
        read -p " ENTER DATE (YYYY-MM-DD): " d
        if ! date -d "$d" >/dev/null 2>&1; then 
            echo -e "${RED}❌ ERROR: INVALID DATE FORMAT!${NC}"
            pause
            return
        fi
        
        read -p " ENTER TIME (HH:MM)     : " t
        [[ -z "$t" ]] && t="23:59"
    else
        d="NEVER"
        t="00:00"
        echo -e "${GREEN}ℹ️  SET TO UNLIMITED (NEVER EXPIRES)${NC}"
    fi
    
    # CREATE USER
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    echo "$u|$d|$t|V28" >> "$USER_DB"
    
    echo ""
    echo -e "${BLUE}========================${NC}"
    echo -e "${GREEN}✔ ACCOUNT CREATED!${NC}"
    echo -e " USERNAME : ${YELLOW}$u${NC}"
    echo -e " PASSWORD : ${YELLOW}$p${NC}"
    if [[ "$d" == "NEVER" ]]; then
        echo -e " EXPIRES  : ${GREEN}UNLIMITED ♾️${NC}"
    else
        echo -e " EXPIRES  : ${RED}$d @ $t${NC}"
    fi
    echo -e "${BLUE}========================${NC}"
    pause
}

# [02] RENEW ACCOUNT
fun_renew() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}  [02] RENEW ACCOUNT    ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo ""
    
    read -p " ENTER USERNAME  : " u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "${RED}❌ ACCOUNT NOT FOUND!${NC}"; pause; return; fi
    
    read -p " ENTER NEW DATE (YYYY-MM-DD) : " d
    if ! date -d "$d" >/dev/null 2>&1; then echo -e "${RED}❌ INVALID DATE!${NC}"; pause; return; fi

    read -p " ENTER NEW TIME (HH:MM)      : " t
    [[ -z "$t" ]] && t="23:59"
    
    sed -i "/^$u|/d" "$USER_DB"
    echo "$u|$d|$t|Renew" >> "$USER_DB"
    usermod -U "$u"
    
    echo -e "${GREEN}✔ ACCOUNT RENEWED SUCCESSFULLY!${NC}"
    pause
}

# [03] REMOVE ACCOUNT
fun_remove() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${RED}  [03] REMOVE ACCOUNT   ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo ""
    read -p " ENTER USERNAME TO REMOVE: " u
    
    echo -e "${RED}ARE YOU SURE YOU WANT TO DELETE ($u)? (Y/N)${NC}"
    read -p "> " confirm
    if [[ "$confirm" == "Y" || "$confirm" == "y" ]]; then
        pkill -u "$u"; userdel -f -r "$u"
        sed -i "/^$u|/d" "$USER_DB"
        echo -e "${RED}🗑️ ACCOUNT DELETED.${NC}"
    else
        echo "OPERATION CANCELLED."
    fi
    pause
}

# [04] LOCK ACCOUNT
fun_lock() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}   [04] LOCK ACCOUNT    ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo ""
    read -p " ENTER USERNAME: " u
    echo ""
    echo " [1] LOCK ⛔ (BAN)"
    echo " [2] UNLOCK 🔓 (UNBAN)"
    echo ""
    read -p " SELECT ACTION: " act
    
    if [[ "$act" == "1" ]]; then 
        usermod -L "$u"; pkill -KILL -u "$u"
        echo -e "${RED}⛔ ACCOUNT $u LOCKED.${NC}"
    elif [[ "$act" == "2" ]]; then 
        usermod -U "$u"
        echo -e "${GREEN}🔓 ACCOUNT $u UNLOCKED.${NC}"
    fi
    pause
}

# [05] LIST ACCOUNTS
fun_list() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}               [05] LIST ACCOUNTS                 ${NC}"
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

# [06] CHECK STATUS (ONLINE USERS)
fun_online() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}               [06] CHECK STATUS                  ${NC}"
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
    
    # Also show Monitor Status here
    echo -e "${CYAN}--------------------------------------------------${NC}"
    if pgrep -f "kp_monitor.sh" > /dev/null; then
        echo -e " MONITOR ENGINE: ${GREEN}RUNNING 🟢${NC}"
    else
        echo -e " MONITOR ENGINE: ${RED}STOPPED 🔴${NC}"
    fi
    pause
}

# [07] BACKUP DATA
fun_save() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}    [07] BACKUP DATA    ${NC}"
    echo -e "${BLUE}========================${NC}"
    B_NAME="BACKUP_$(date '+%Y%m%d').txt"
    cp "$USER_DB" "$BACKUP_DIR/$B_NAME"
    echo ""
    echo -e "${GREEN}✅ DATA BACKED UP!${NC}"
    echo -e "PATH: $BACKUP_DIR/$B_NAME"
    pause
}

# [08] SETTINGS
fun_settings() {
    clear
    echo -e "${BLUE}========================${NC}"
    echo -e "${YELLOW}      [08] SETTINGS     ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo " [1] FIX TIMEZONE (TUNISIA)"
    echo " [2] RESTART MONITOR SERVICE"
    echo " [3] SET SERVER BANNER"
    echo " [4] VIEW LOGS"
    echo ""
    read -p " SELECT OPTION: " s
    
    case "$s" in
        1) timedatectl set-timezone Africa/Tunis; echo -e "${GREEN}DONE.${NC}";;
        2) pkill -f kp_monitor.sh; nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 & echo -e "${GREEN}SERVICE RESTARTED.${NC}";;
        3) read -p "BANNER TEXT: " b; echo "$b" > "$BANNER_FILE"; service ssh restart; echo -e "${GREEN}UPDATED.${NC}";;
        4) echo ""; tail -n 10 "$LOG_FILE";;
    esac
    pause
}

# --- MAIN MENU ---
while true; do
    clear
    
    # Auto-restart monitor
    if ! pgrep -f "kp_monitor.sh" > /dev/null; then
        nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 &
    fi

    echo -e "${BLUE}========================${NC}"
    echo -e "${WHITE}       SSH MANAGER      ${NC}"
    echo -e "${BLUE}========================${NC}"
    echo ""
    echo -e " [01] ADD ACCOUNT"
    echo -e " [02] RENEW ACCOUNT"
    echo -e " [03] REMOVE ACCOUNT"
    echo -e " [04] LOCK ACCOUNT"
    echo -e " [05] LIST ACCOUNTS"
    echo -e " [06] CHECK STATUS"
    echo -e " [07] BACKUP DATA"
    echo -e " [08] SETTINGS"
    echo -e " [00] EXIT"
    echo ""
    echo -e "${BLUE}========================${NC}"
    read -p " SELECT OPTION: " opt
    
    case "$opt" in
        1|01) fun_create ;; 2|02) fun_renew ;; 3|03) fun_remove ;; 4|04) fun_lock ;;
        5|05) fun_list ;; 6|06) fun_online ;; 7|07) fun_save ;; 8|08) fun_settings ;;
        0|00) clear; exit 0 ;; *) echo "INVALID OPTION"; sleep 1 ;;
    esac
done
