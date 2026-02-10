#!/bin/bash
# ==================================================
#  SSH MANAGER UNLIMITED - V29.1 🛡️
#  - MULTI-LOGIN: ALLOWED (No Restrictions)
#  - EXPIRY: DISABLED (Never Expire by Default)
#  - CREATE: Username & Password Only
#  - NETWORK: Netstat Based (Real-time Detection)
#  - LANGUAGE: English Only
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
#  MONITOR ENGINE (Expiry Check Only)
# ==================================================
pkill -f kp_monitor.sh
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
DB="/etc/xpanel/users_db.txt"
while true; do
    NOW=$(date +%s)
    if [[ -f "$DB" ]]; then
        while IFS='|' read -r user date time note; do
            [[ -z "$user" || "$date" == "never" ]] && continue
            
            # CHECK EXPIRY ONLY
            EXP_TS=$(date -d "$date $time" +%s 2>/dev/null)
            if [[ -n "$EXP_TS" && "$NOW" -ge "$EXP_TS" ]]; then
                pkill -KILL -u "$user" 2>/dev/null
                userdel -f -r "$user" 2>/dev/null
                sed -i "/^$user|/d" "$DB"
            fi
        done < "$DB"
    fi
    sleep 60 # SCAN EVERY MINUTE
done
EOF
chmod +x "$MONITOR_SCRIPT"
nohup "$MONITOR_SCRIPT" >/dev/null 2>&1 &

# ==================================================
#  FUNCTIONS
# ==================================================

pause() {
    echo -e "\n${CYAN}PRESS [ENTER] TO RETURN...${NC}"
    read
}

# [01] ADD USER (Fast Creation)
fun_create() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}                 [01] ADD USER                    ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    
    read -p " ENTER USERNAME :" u
    if [[ -z "$u" ]]; then echo -e "${RED}❌ Username cannot be empty!${NC}"; pause; return; fi
    if id "$u" &>/dev/null; then echo -e "${RED}❌ User already exists!${NC}"; pause; return; fi
    
    read -p " ENTER PASSWORD :" p
    if [[ -z "$p" ]]; then echo -e "${RED}❌ Password cannot be empty!${NC}"; pause; return; fi
    
    # DEFAULT SETTINGS: MULTI ALLOWED & NEVER EXPIRE
    useradd -M -s /bin/false "$u"
    echo "$u:$p" | chpasswd
    echo "$u|never|00:00|Unlimited" >> "$USER_DB"
    
    echo ""
    echo -e "${GREEN}✔ USER CREATED SUCCESSFULLY!${NC}"
    echo -e "${WHITE}----------------------------------${NC}"
    echo -e "${CYAN}👤 USERNAME : ${YELLOW}$u${NC}"
    echo -e "${CYAN}🔑 PASSWORD : ${YELLOW}$p${NC}"
    echo -e "${CYAN}📅 EXPIRY   : ${GREEN}NEVER (Unlimited)${NC}"
    echo -e "${WHITE}----------------------------------${NC}"
    pause
}

# [05] SHOW ALL USERS (Real-time Status)
fun_list() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}              [05] SHOW ALL USERS                 ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${WHITE}USER           | STATUS      | ACTIVE DEVICES${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        # CHECK ACTUAL NETWORK CONNECTIONS
        COUNT=$(netstat -atp 2>/dev/null | grep sshd | grep "$u" | grep ESTABLISHED | wc -l)
        
        if ! id "$u" &>/dev/null; then st="${RED}OFFLINE${NC}"
        elif passwd -S "$u" 2>/dev/null | grep -q "L"; then st="${RED}LOCKED ⛔${NC}"
        elif [ "$COUNT" -gt 0 ]; then st="${GREEN}ONLINE 🟢${NC}"
        else st="${RED}OFFLINE${NC}"; fi
        
        printf "${YELLOW}%-14s ${NC}| %-11b | %s Active Devices\n" "$u" "$st" "$COUNT"
    done < "$USER_DB"
    pause
}

# [06] CHECK ONLINE (Real-time Network Check)
fun_online() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}             [06] CHECK WHO IS ONLINE             ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${WHITE}USER           | ACTIVE CONNECTIONS${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    total_on=0
    while IFS='|' read -r u d t n; do
        [[ -z "$u" ]] && continue
        COUNT=$(netstat -atp 2>/dev/null | grep sshd | grep "$u" | grep ESTABLISHED | wc -l)
        if [ "$COUNT" -gt 0 ]; then
            printf "${YELLOW}%-14s ${NC}| ${GREEN}%s ACTIVE${NC}\n" "$u" "$COUNT"
            ((total_on++))
        fi
    done < "$USER_DB"
    
    if [[ $total_on -eq 0 ]]; then echo "NO USERS ONLINE."; fi
    pause
}

# [03] REMOVE USER
fun_remove() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${RED}                [03] REMOVE USER                  ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    read -p " ENTER USERNAME TO REMOVE: " u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "${RED}❌ User not found!${NC}"; pause; return; fi
    pkill -u "$u" 2>/dev/null
    userdel -f -r "$u" 2>/dev/null
    sed -i "/^$u|/d" "$USER_DB"
    echo -e "${GREEN}🗑️ Deleted successfully.${NC}"
    pause
}

# [04] LOCK / UNLOCK
fun_lock() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}             [04] LOCK / UNLOCK USER              ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    read -p " ENTER USERNAME: " u
    if ! grep -q "^$u|" "$USER_DB"; then echo -e "${RED}❌ Not found!${NC}"; pause; return; fi
    echo ""
    echo " [1] LOCK ⛔"
    echo " [2] UNLOCK 🔓"
    echo ""
    read -p " SELECT ACTION: " act
    if [[ "$act" == "1" ]]; then 
        usermod -L "$u" && pkill -u "$u"
        echo -e "${RED}USER $u LOCKED.${NC}"
    else 
        usermod -U "$u"
        echo -e "${GREEN}USER $u UNLOCKED.${NC}"
    fi
    pause
}

# [07] SAVE DATA (Backup)
fun_save() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}                 [07] SAVE DATA                   ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    B_NAME="BACKUP_$(date '+%Y%m%d').txt"
    cp "$USER_DB" "$BACKUP_DIR/$B_NAME"
    echo -e "${GREEN}✅ DATA SAVED TO: $BACKUP_DIR/$B_NAME${NC}"
    pause
}

# --- MAIN MENU ---
while true; do
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${WHITE}       SSH MANAGER UNLIMITED (STABLE V29.1)       ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e ""
    echo -e " [01] ADD USER (Name/Pass Only)"
    echo -e " [03] REMOVE USER"
    echo -e " [04] LOCK / UNLOCK USER"
    echo -e " [05] SHOW ALL USERS"
    echo -e " [06] CHECK WHO IS ONLINE"
    echo -e " [07] SAVE DATA (Backup)"
    echo -e " [00] EXIT"
    echo -e ""
    echo -e "${BLUE}==================================================${NC}"
    echo -e " CONFIG: ${GREEN}UNLIMITED${NC} | STATUS: ${CYAN}STABLE${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo ""
    read -p " SELECT OPTION: " opt
    
    case "$opt" in
        1|01) fun_create ;; 
        3|03) fun_remove ;; 
        4|04) fun_lock ;;
        5|05) fun_list ;; 
        6|06) fun_online ;; 
        7|07) fun_save ;;
        0|00) clear; exit 0 ;; 
        *) sleep 1 ;;
    esac
done
