#!/bin/bash

# ==============================================================================
# Project: GOST WORMHOLE (Phantom Edition v11.1)
# Description: Encrypted Tunneling with Smart Downloader & Anti-DPI
# ==============================================================================

# --- Auto-Install Shortcut ---
function install_shortcut() {
    local BIN_PATH="/usr/local/bin/wormhole"
    local REPO_URL="https://raw.githubusercontent.com/isajad7/Gost-Wormhole/main/install.sh"
    if [[ ! -f "$BIN_PATH" ]] || [[ "$0" != "$BIN_PATH" ]]; then
        if command -v curl >/dev/null; then curl -fsSL "$REPO_URL" -o "$BIN_PATH"; chmod +x "$BIN_PATH"; fi
    fi
}
install_shortcut

# ==============================================================================
# 1. CONFIGURATION
# ==============================================================================

INSTALL_PATH="/usr/local/bin/gost"
WATCHDOG_PATH="/usr/local/bin/gost_watchdog"
SYSTEMD_DIR="/etc/systemd/system"
LOG_DIR="/var/log/gost"

# Sources
GITHUB_URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz"
MIRROR_IP="178.239.144.62:8080" 
MIRROR_URL="http://$MIRROR_IP/gost.gz"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==============================================================================
# 2. UTILS & FIREWALL
# ==============================================================================

function log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
function log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
function log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
function log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

function check_root() { if [[ $EUID -ne 0 ]]; then log_error "Run as root!"; exit 1; fi; }

function open_firewall_ports() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then return; fi
    if command -v ufw >/dev/null; then ufw allow "$port"/tcp >/dev/null 2>&1; ufw allow "$port"/udp >/dev/null 2>&1; fi
    if command -v iptables >/dev/null; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
        if command -v netfilter-persistent >/dev/null; then netfilter-persistent save >/dev/null 2>&1; fi
    fi
}

function install_dependencies() {
    local deps=("wget" "curl" "cron" "openssl")
    local missing=()
    for d in "${deps[@]}"; do if ! command -v $d >/dev/null; then missing+=($d); fi; done
    if [ ${#missing[@]} -gt 0 ]; then apt-get update -q && apt-get install -y "${missing[@]}" -q; fi
    mkdir -p "$LOG_DIR"
}

# --- SMART DOWNLOADER (NEW) ---
function install_gost() {
    if [[ -f "$INSTALL_PATH" ]]; then return; fi
    log_info "Installing GOST Core..."

    local MAX_ATTEMPTS=5
    local ATTEMPT=1
    
    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        # Dynamic Timeout: Starts at 5s, increases by 5s each loop (5, 10, 15, 20...)
        local TIMEOUT=$((ATTEMPT * 5))
        
        log_info "Attempt $ATTEMPT/$MAX_ATTEMPTS (Timeout: ${TIMEOUT}s)..."

        # 1. Try GitHub (Best for Kharej)
        if wget -q --timeout="$TIMEOUT" --tries=1 "$GITHUB_URL" -O /tmp/gost.gz; then
            if [[ -s "/tmp/gost.gz" ]]; then break; fi
        fi

        # 2. Try Mirror (Best for Iran)
        if wget -q --timeout="$TIMEOUT" --tries=1 "$MIRROR_URL" -O /tmp/gost.gz; then
            if [[ -s "/tmp/gost.gz" ]]; then break; fi
        fi

        log_warn "Download failed. Retrying..."
        rm -f /tmp/gost.gz
        ((ATTEMPT++))
        sleep 1
    done

    if [[ -s "/tmp/gost.gz" ]]; then
        gzip -d -f /tmp/gost.gz
        mv /tmp/gost "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
        log_success "GOST installed successfully."
    else
        log_error "Critical: Failed to download GOST from any source."
        exit 1
    fi
}

# ==============================================================================
# 3. WATCHDOG
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
    systemctl restart "\$SERVICE"
fi
EOF
    chmod +x "$WATCHDOG_PATH"
}

function register_watchdog_cron() {
    local svc=$1; local ip=$2
    if crontab -l 2>/dev/null | grep -q "$svc"; then return; fi
    (crontab -l 2>/dev/null; echo "*/3 * * * * $WATCHDOG_PATH $svc $ip") | crontab -
}

# ==============================================================================
# 4. ENCRYPTION & PROTOCOL LOGIC
# ==============================================================================

function generate_secret() {
    openssl rand -hex 8
}

function select_protocol_scheme() {
    {
        echo -e "${CYAN}--- Select Stealth Protocol (Encrypted) ---${NC}"
        echo "1) KCP-Phantom (Obfuscated & Encrypted)"
        echo "2) gRPC-Gun (Best for most networks)"
        echo "3) WS-Secure (WebSocket + Encryption)"
    } >&2
    read -p "Select [1-3]: " P < /dev/tty
    
    case $P in
        1) echo "relay+kcp|mode=fast2&crypt=chacha20-ietf-poly1305&mtu=1350&sndwnd=1024&rcvwnd=1024&dshard=10&pshard=5&keepalive=true" ;;
        2) echo "relay+grpc|keepalive=true&ping=30" ;;
        3) echo "relay+mw|keepalive=true&mbind=true" ;;
        *) echo "relay+kcp|mode=fast2&crypt=chacha20-ietf-poly1305&mtu=1350&sndwnd=1024&rcvwnd=1024&dshard=10&pshard=5&keepalive=true" ;;
    esac
}

# ==============================================================================
# 5. TUNNEL SETUP
# ==============================================================================

function configure_iran() {
    echo ""; log_info "--- IRAN CLIENT SETUP (Encrypted) ---"
    read -p "Remote Server IP (Kharej): " REMOTE_IP < /dev/tty
    if [[ -z "$REMOTE_IP" ]]; then log_error "IP required"; return; fi
    read -p "Tunnel Port (Transport, e.g., 9000): " TUNNEL_PORT < /dev/tty
    if [[ -z "$TUNNEL_PORT" ]]; then TUNNEL_PORT="9000"; fi
    echo -e "${YELLOW}IMPORTANT: Enter the SAME password used on Kharej server!${NC}"
    read -p "Tunnel Password (Secret): " SEC_KEY < /dev/tty
    if [[ -z "$SEC_KEY" ]]; then log_error "Password cannot be empty!"; return; fi
    read -p "Ports to Forward (e.g., 443,2082): " FWD_PORTS < /dev/tty
    
    local PROTO_DATA=$(select_protocol_scheme)
    local SCHEME=$(echo "$PROTO_DATA" | cut -d'|' -f1)
    local ARGS=$(echo "$PROTO_DATA" | cut -d'|' -f2)
    local PROTO_NAME=${SCHEME#*+}
    local SERVICE_NAME="gost-client-${PROTO_NAME}-${TUNNEL_PORT}"
    
    local LISTEN_ARGS=""
    IFS=',' read -ra PORTS <<< "$FWD_PORTS"
    for FPORT in "${PORTS[@]}"; do
        FPORT=$(echo $FPORT | xargs)
        if [[ -n "$FPORT" ]]; then
            open_firewall_ports "$FPORT"
            LISTEN_ARGS+=" -L tcp://:$FPORT/127.0.0.1:$FPORT -L udp://:$FPORT/127.0.0.1:$FPORT"
        fi
    done

    CMD="$INSTALL_PATH -D $LISTEN_ARGS -F \"$SCHEME://$REMOTE_IP:$TUNNEL_PORT?$ARGS&key=$SEC_KEY\""
    
    cat > "${SYSTEMD_DIR}/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=GOST Client Encrypted ($PROTO_NAME -> $TUNNEL_PORT)
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
    systemctl daemon-reload; systemctl enable "$SERVICE_NAME" --now >/dev/null
    log_success "Encrypted Tunnel [$SERVICE_NAME] Started!"; register_watchdog_cron "$SERVICE_NAME" "$REMOTE_IP"
}

function configure_kharej() {
    echo ""; log_info "--- KHAREJ SERVER SETUP (Encrypted) ---"
    read -p "Tunnel Port to Listen on (e.g., 9000): " TUNNEL_PORT < /dev/tty
    if [[ -z "$TUNNEL_PORT" ]]; then log_error "Port required"; return; fi
    local GEN_PASS=$(generate_secret)
    echo -e "${YELLOW}--- SECRET PASSWORD GENERATED ---${NC}"
    echo -e "${GREEN}Password: $GEN_PASS${NC}"
    echo -e "${YELLOW}---------------------------------${NC}"
    read -p "Press Enter to use this, or type your own: " CUSTOM_PASS < /dev/tty
    if [[ -n "$CUSTOM_PASS" ]]; then GEN_PASS="$CUSTOM_PASS"; fi
    
    local PROTO_DATA=$(select_protocol_scheme)
    local SCHEME=$(echo "$PROTO_DATA" | cut -d'|' -f1)
    local ARGS=$(echo "$PROTO_DATA" | cut -d'|' -f2)
    local PROTO_NAME=${SCHEME#*+}
    SERVICE_NAME="gost-server-${PROTO_NAME}-${TUNNEL_PORT}"
    
    open_firewall_ports "$TUNNEL_PORT"
    
    if [[ "$PROTO_NAME" == "kcp" ]]; then
     CMD="$INSTALL_PATH -D -L \"$SCHEME://:$TUNNEL_PORT?$ARGS&key=$GEN_PASS\""
    else
     CMD="$INSTALL_PATH -D -L \"$SCHEME://:$TUNNEL_PORT?$ARGS&key=$GEN_PASS\""
    fi
    
    cat > "${SYSTEMD_DIR}/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=GOST Server Encrypted ($PROTO_NAME : $TUNNEL_PORT)
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
    systemctl daemon-reload; systemctl enable "$SERVICE_NAME" --now >/dev/null
    log_success "Server Started on Port $TUNNEL_PORT"; echo -e "Password: ${CYAN}$GEN_PASS${NC}"
}

# ==============================================================================
# 6. MANAGEMENT
# ==============================================================================
function remove_service() {
    echo ""; log_info "--- Delete Service ---"
    AVAILABLE_SERVICES=($(systemctl list-units --type=service --state=running --no-pager --plain | grep "gost-" | awk '{print $1}'))
    if [ ${#AVAILABLE_SERVICES[@]} -eq 0 ]; then log_warn "No active tunnels."; return; fi
    local i=1
    for SVC in "${AVAILABLE_SERVICES[@]}"; do echo -e "${YELLOW}[$i]${NC} $SVC"; ((i++)); done
    echo -e "${YELLOW}[0]${NC} Cancel"
    read -p "Select: " SEL < /dev/tty
    if [[ "$SEL" =~ ^[0-9]+$ ]] && [ "$SEL" -gt 0 ]; then
        INDEX=$((SEL - 1))
        if [ "$INDEX" -ge 0 ] && [ "$INDEX" -lt "${#AVAILABLE_SERVICES[@]}" ]; then
            SVC="${AVAILABLE_SERVICES[$INDEX]}"
            systemctl stop "$SVC"; systemctl disable "$SVC"; rm "${SYSTEMD_DIR}/${SVC}"; systemctl daemon-reload
            crontab -l 2>/dev/null | grep -v "$SVC" | crontab -
            log_success "Deleted $SVC"
        fi
    fi
}

function view_live_logs() {
    echo ""; log_info "--- Live Logs ---"
    AVAILABLE_SERVICES=($(systemctl list-units --type=service --state=running --no-pager --plain | grep "gost-" | awk '{print $1}'))
    if [ ${#AVAILABLE_SERVICES[@]} -eq 0 ]; then log_warn "No active tunnels."; return; fi
    local i=1
    for SVC in "${AVAILABLE_SERVICES[@]}"; do echo -e "${YELLOW}[$i]${NC} $SVC"; ((i++)); done
    read -p "Select: " SEL < /dev/tty
    if [[ "$SEL" =~ ^[0-9]+$ ]] && [ "$SEL" -gt 0 ]; then
        INDEX=$((SEL - 1))
        SVC="${AVAILABLE_SERVICES[$INDEX]}"
        echo "Streaming logs for $SVC (Ctrl+C to exit)..."
        journalctl -u "$SVC" -f -n 20
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================
check_root
install_dependencies
install_gost
setup_watchdog_script

while true; do
    clear
    echo -e "${CYAN}==============================================${NC}"
    echo -e "${CYAN}   GOST WORMHOLE v11.1 (Smart Download)       ${NC}"
    echo -e "${CYAN}==============================================${NC}"
    echo "1. Setup IRAN (Client)"
    echo "2. Setup KHAREJ (Server)"
    echo "3. List Services"
    echo "4. View Live Logs"
    echo "5. Delete Service"
    echo "0. Exit"
    read -p "Select: " OPT < /dev/tty
    case $OPT in
        1) configure_iran ;;
        2) configure_kharej ;;
        3) echo ""; systemctl list-units --type=service --state=running | grep "gost-" | awk '{print $1}'; read -p "..." ;;
        4) view_live_logs ;;
        5) remove_service ;;
        0) exit 0 ;;
    esac
done