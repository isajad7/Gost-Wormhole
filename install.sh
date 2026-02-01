#!/bin/bash

# ==============================================================================
# Project: GOST WORMHOLE
# Author: isajad01
# ==============================================================================

# --- Auto-Install the 'wormhole' command ---
function install_shortcut() {
    local BIN_PATH="/usr/local/bin/wormhole"
    local REPO_URL="https://raw.githubusercontent.com/isajad7/Gost-Wormhole/main/install.sh"
    local TMP_FILE="/tmp/wormhole.$$"

    # اگر قبلاً نصب شده و از خودش اجرا شده، کاری نکن
    if [[ -x "$BIN_PATH" && "$0" == "$BIN_PATH" ]]; then
        return
    fi

    echo "Installing 'wormhole' command to system..."

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$REPO_URL" -o "$TMP_FILE" || {
            echo "Failed to download wormhole"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$REPO_URL" -O "$TMP_FILE" || {
            echo "Failed to download wormhole"
            return 1
        }
    else
        echo "Error: curl or wget not found."
        return 1
    fi

    chmod +x "$TMP_FILE"
    mv "$TMP_FILE" "$BIN_PATH"

    echo -e "\033[0;32m[SUCCESS]\033[0m Wormhole installed! You can now type 'wormhole' to run it."
    echo ""
}


# فراخوانی تابع نصب در ابتدای اجرا
install_shortcut


# ==============================================================================
# 1. GLOBAL CONFIGURATION
# ==============================================================================

INSTALL_PATH="/usr/local/bin/gost"
WATCHDOG_PATH="/usr/local/bin/gost_watchdog"
SYSTEMD_DIR="/etc/systemd/system"
LOG_DIR="/var/log/gost"

# --- Mirror Settings ---
MIRROR_IP="178.239.144.62:8080"
BASE_URL="http://$MIRROR_IP"

# --- Protocol Definitions ---
declare -A PROTO_ARGS
declare -A PROTO_SCHEMES

# 🏆 1. KCP - FEC
PROTO_SCHEMES["kcp-fec"]="relay+kcp"
PROTO_ARGS["kcp-fec"]="mode=manual&resend=0&nc=1&dshard=10&pshard=3&mtu=1350&sndwnd=1024&rcvwnd=1024&keepalive=true"

# 🏎️ 2. KCP - Classic
PROTO_SCHEMES["kcp-classic"]="relay+kcp"
PROTO_ARGS["kcp-classic"]="mode=fast&resend=2&interval=20&mtu=1350&sndwnd=512&rcvwnd=512&keepalive=true"

# 🚀 3. QUIC
PROTO_SCHEMES["quic"]="relay+quic"
PROTO_ARGS["quic"]="keepalive=true&timeout=60s&sndwnd=4096&rcvwnd=4096&mtu=1350&congestion_control=true"

# 🌐 4. WS (MW)
PROTO_SCHEMES["mw"]="relay+mw"
PROTO_ARGS["mw"]="keepalive=true&ping=30&mbind=true"

# 🛡️ 5. gRPC
PROTO_SCHEMES["grpc"]="relay+grpc"
PROTO_ARGS["grpc"]="keepalive=true&ping=30"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==============================================================================
# 2. CORE UTILITIES & FIREWALL
# ==============================================================================

function log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
function log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
function log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
function log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

function check_root() {
    if [[ $EUID -ne 0 ]]; then log_error "Run as root!"; exit 1; fi
}

function open_firewall_ports() {
    local port=$1
    # Check if port is valid number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then return; fi

    log_info "Opening firewall for Port: $port (TCP/UDP)..."

    # 1. UFW Logic
    if command -v ufw >/dev/null; then
        ufw allow "$port"/tcp >/dev/null 2>&1
        ufw allow "$port"/udp >/dev/null 2>&1
    fi

    # 2. IPTABLES Logic
    if command -v iptables >/dev/null; then
        if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        fi
        if ! iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null; then
            iptables -I INPUT -p udp --dport "$port" -j ACCEPT
        fi
        
        if command -v netfilter-persistent >/dev/null; then
            netfilter-persistent save >/dev/null 2>&1
        elif command -v service >/dev/null; then
             service iptables save >/dev/null 2>&1
        fi
    fi
}

function install_dependencies() {
    local deps=("wget" "lsof" "nano" "curl" "cron")
    local missing=()
    for d in "${deps[@]}"; do
        if ! command -v $d >/dev/null; then missing+=($d); fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Installing: ${missing[*]}"
        apt-get update -q && apt-get install -y "${missing[@]}" -q
    fi
    mkdir -p "$LOG_DIR"
}

function install_gost() {
    if [[ -x "$INSTALL_PATH" ]]; then
        return
    fi

    log_info "Installing GOST..."

    TMP_DIR=$(mktemp -d)
    GZ_FILE="$TMP_DIR/gost.gz"

    # دانلود از سورس اصلی
    wget -q --timeout=10 "$BASE_URL/gost.gz" -O "$GZ_FILE"

    # اگر دانلود خالی بود، از گیتهاب بگیر
    if [[ ! -s "$GZ_FILE" ]]; then
        wget -q "https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz" -O "$GZ_FILE"
    fi

    # اگر باز هم فایل نداریم، fail
    if [[ ! -s "$GZ_FILE" ]]; then
        log_error "Failed to download GOST"
        rm -rf "$TMP_DIR"
        return 1
    fi

    # unzip
    gzip -d "$GZ_FILE"

    # پیدا کردن فایل gost (هر اسمی که داشته باشه)
    GOST_BIN=$(find "$TMP_DIR" -type f -perm -111 | head -n 1)

    if [[ -z "$GOST_BIN" ]]; then
        log_error "GOST binary not found after extraction"
        rm -rf "$TMP_DIR"
        return 1
    fi

    mv "$GOST_BIN" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"

    rm -rf "$TMP_DIR"
    log_info "GOST installed successfully"
}


# ==============================================================================
# 3. WATCHDOG SYSTEM
# ==============================================================================

function setup_watchdog_script() {
    if [[ -f "$WATCHDOG_PATH" ]]; then return; fi
    cat > "$WATCHDOG_PATH" <<EOF
#!/bin/bash
SERVICE=\$1
TARGET_IP=\$2
if systemctl is-active --quiet "\$SERVICE"; then
    ping -c 3 -W 5 "\$TARGET_IP" > /dev/null 2>&1
    if [ \$? -ne 0 ]; then
        echo "\$(date): Connection lost. Restarting \$SERVICE..." >> /var/log/gost_watchdog.log
        systemctl restart "\$SERVICE"
    fi
else
    echo "\$(date): Service \$SERVICE dead. Restarting..." >> /var/log/gost_watchdog.log
    systemctl restart "\$SERVICE"
fi
EOF
    chmod +x "$WATCHDOG_PATH"
}

function register_watchdog_cron() {
    local service_name=$1
    local target_ip=$2
    if crontab -l 2>/dev/null | grep -q "$service_name"; then return; fi
    (crontab -l 2>/dev/null; echo "*/3 * * * * $WATCHDOG_PATH $service_name $target_ip") | crontab -
    log_success "Watchdog activated."
}

# ==============================================================================
# 4. TUNNEL CREATION (UNIFIED LOGIC)
# ==============================================================================

function select_protocol() {
    {
        echo -e "${CYAN}--- Protocol Selection ---${NC}"
        echo "1) KCP-FEC (Best Reliability)"
        echo "2) KCP-Classic (Max Speed)"
        echo "3) QUIC (Video/Stream)"
        echo "4) WS-MW (Stealth TCP)"
        echo "5) gRPC (Anti-Filter)"
    } >&2
    read -p "Select [1-5]: " P < /dev/tty
    case $P in
        1) echo "kcp-fec" ;; 2) echo "kcp-classic" ;; 3) echo "quic" ;; 4) echo "mw" ;; 5) echo "grpc" ;; *) echo "kcp-fec" ;;
    esac
}

# ==============================================================================
# UPDATED FUNCTIONS FOR LIVE TRAFFIC LOGGING (v10.0)
# ==============================================================================

function configure_iran() {
    echo ""
    log_info "--- IRAN CLIENT SETUP (With Traffic Logs) ---"
    
    read -p "Remote Server IP (Kharej): " REMOTE_IP < /dev/tty
    if [[ -z "$REMOTE_IP" ]]; then log_error "IP required"; return; fi

    read -p "Tunnel Port (Transport Port, e.g., 9000): " TUNNEL_PORT < /dev/tty
    if [[ -z "$TUNNEL_PORT" ]]; then TUNNEL_PORT="9000"; fi

    read -p "Ports to Forward (comma separated, e.g., 80,443,2082): " FWD_PORTS < /dev/tty
    
    local PROTO=$(select_protocol)
    local SCHEME="${PROTO_SCHEMES[$PROTO]}"
    local ARGS="${PROTO_ARGS[$PROTO]}"

    local SERVICE_NAME="gost-client-${PROTO}-${TUNNEL_PORT}"
    local LISTEN_ARGS=""
    
    IFS=',' read -ra PORTS <<< "$FWD_PORTS"
    for FPORT in "${PORTS[@]}"; do
        FPORT=$(echo $FPORT | xargs)
        if [[ -n "$FPORT" ]]; then
            open_firewall_ports "$FPORT"
            LISTEN_ARGS+=" -L tcp://:$FPORT/127.0.0.1:$FPORT -L udp://:$FPORT/127.0.0.1:$FPORT"
        fi
    done

    # 🔥 FIX: Added '-D' flag for Debug/Verbose logging
    CMD="$INSTALL_PATH -D $LISTEN_ARGS -F \"$SCHEME://$REMOTE_IP:$TUNNEL_PORT?$ARGS\""
    
    cat > "${SYSTEMD_DIR}/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=GOST Client ($PROTO -> $REMOTE_IP:$TUNNEL_PORT)
After=network.target
[Service]
ExecStart=$CMD
Restart=always
RestartSec=3
LimitNOFILE=65536
# Ensure logs go to journald for live streaming
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" --now >/dev/null
    
    log_success "Service [$SERVICE_NAME] Created with Live Logging!"
    register_watchdog_cron "$SERVICE_NAME" "$REMOTE_IP"
}

function configure_kharej() {
    echo ""
    log_info "--- KHAREJ SERVER SETUP (With Traffic Logs) ---"
    
    read -p "Tunnel Port to Listen on (e.g., 9000): " TUNNEL_PORT < /dev/tty
    if [[ -z "$TUNNEL_PORT" ]]; then log_error "Port required"; return; fi

    local PROTO=$(select_protocol)
    local SCHEME="${PROTO_SCHEMES[$PROTO]}"
    
    SERVICE_NAME="gost-server-${PROTO}-${TUNNEL_PORT}"
    
    open_firewall_ports "$TUNNEL_PORT"
    
    # 🔥 FIX: Added '-D' flag here too
    CMD="$INSTALL_PATH -D -L \"$SCHEME://:$TUNNEL_PORT\""
    
    cat > "${SYSTEMD_DIR}/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=GOST Server ($PROTO : $TUNNEL_PORT)
After=network.target
[Service]
ExecStart=$CMD
Restart=always
RestartSec=3
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" --now >/dev/null
    log_success "Server Service [$SERVICE_NAME] Started with Logs."
}
# ==============================================================================
# 5. MANAGEMENT & LOGS
# ==============================================================================

function get_services_list() {
    # Returns global array AVAILABLE_SERVICES
    AVAILABLE_SERVICES=($(systemctl list-units --type=service --state=running --no-pager --plain | grep "gost-" | awk '{print $1}'))
}

function remove_service() {
    echo ""
    log_info "--- Delete Service ---"
    get_services_list

    if [ ${#AVAILABLE_SERVICES[@]} -eq 0 ]; then
        log_warn "No active tunnels."
        return
    fi

    local i=1
    for SVC in "${AVAILABLE_SERVICES[@]}"; do
        echo -e "${YELLOW}[$i]${NC} $SVC"
        ((i++))
    done
    echo -e "${YELLOW}[0]${NC} Cancel"

    echo ""
    read -p "Select Number to DELETE: " SELECTION < /dev/tty

    if [[ "$SELECTION" == "0" || ! "$SELECTION" =~ ^[0-9]+$ ]]; then return; fi
    INDEX=$((SELECTION - 1))

    if [ "$INDEX" -ge 0 ] && [ "$INDEX" -lt "${#AVAILABLE_SERVICES[@]}" ]; then
        SELECTED_SVC="${AVAILABLE_SERVICES[$INDEX]}"
        log_warn "Deleting $SELECTED_SVC..."
        
        systemctl stop "$SELECTED_SVC"
        systemctl disable "$SELECTED_SVC"
        rm "${SYSTEMD_DIR}/${SELECTED_SVC}"
        crontab -l 2>/dev/null | grep -v "$SELECTED_SVC" | crontab -
        systemctl daemon-reload
        log_success "Deleted."
    fi
}

function view_live_logs() {
    echo ""
    log_info "--- Live Logs Stream ---"
    get_services_list

    if [ ${#AVAILABLE_SERVICES[@]} -eq 0 ]; then
        log_warn "No active tunnels to view."
        return
    fi

    local i=1
    for SVC in "${AVAILABLE_SERVICES[@]}"; do
        echo -e "${YELLOW}[$i]${NC} $SVC"
        ((i++))
    done
    echo -e "${YELLOW}[0]${NC} Back"

    echo ""
    read -p "Select Number to View Logs: " SELECTION < /dev/tty

    if [[ "$SELECTION" == "0" || ! "$SELECTION" =~ ^[0-9]+$ ]]; then return; fi
    INDEX=$((SELECTION - 1))

    if [ "$INDEX" -ge 0 ] && [ "$INDEX" -lt "${#AVAILABLE_SERVICES[@]}" ]; then
        SELECTED_SVC="${AVAILABLE_SERVICES[$INDEX]}"
        echo ""
        log_info "Streaming logs for $SELECTED_SVC (Press Ctrl+C to exit)..."
        echo "-----------------------------------------------------"
        # Using journalctl -f for live tail
        journalctl -u "$SELECTED_SVC" -f -n 20
    fi
}

# ==============================================================================
# 6. MAIN MENU
# ==============================================================================
check_root
install_dependencies
install_gost
setup_watchdog_script

while true; do
    clear
    echo -e "${CYAN}==============================================${NC}"
    echo -e "${CYAN}   TUNNEL MASTER v9.0 (Unified + Logs)        ${NC}"
    echo -e "${CYAN}==============================================${NC}"
    echo "1. Setup IRAN (Multi-Port Unified)"
    echo "2. Setup KHAREJ (Server)"
    echo "3. List Active Services"
    echo "4. View Live Logs (Stream)"
    echo "5. Delete Service"
    echo "0. Exit"
    read -p "Select: " OPT < /dev/tty
    
    case $OPT in
        1) configure_iran ;;
        2) configure_kharej ;;
        3) 
           echo ""; systemctl list-units --type=service --state=running | grep "gost-" | awk '{print $1}'
           read -p "Press Enter..." 
           ;;
        4) view_live_logs ;;
        5) remove_service ;;
        0) exit 0 ;;
    esac
done
