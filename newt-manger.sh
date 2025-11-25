#!/bin/bash

# Newt Service Manager
# Manages installation, configuration, and running of newt as a systemd service

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration paths
CONFIG_DIR="/etc/newt"
CONFIG_FILE="${CONFIG_DIR}/config"
SERVICE_FILE="/etc/systemd/system/newt.service"
NEWT_BINARY="/usr/local/bin/newt"
LOG_DIR="/var/log/newt"
LOG_FILE="${LOG_DIR}/newt.log"
UPDATE_SCRIPT="/usr/local/bin/newt-updater"
UPDATE_SERVICE="/etc/systemd/system/newt-updater.service"
UPDATE_TIMER="/etc/systemd/system/newt-updater.timer"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    logger -t newt-manager "INFO: $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    logger -t newt-manager "SUCCESS: $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    logger -t newt-manager "WARNING: $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    logger -t newt-manager "ERROR: $1"
}

log_step() {
    echo -e "${MAGENTA}[STEP]${NC} ${BOLD}$1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Detect Linux distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="rhel"
    elif [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
    else
        DISTRO="unknown"
    fi
    
    log_info "Detected distribution: ${DISTRO} ${VERSION}"
}

# Install dependencies based on distribution
install_dependencies() {
    log_step "Installing dependencies..."
    
    case "$DISTRO" in
        ubuntu|debian|pop)
            apt-get update -qq
            apt-get install -y curl wget systemd >/dev/null 2>&1
            ;;
        fedora|rhel|centos|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                dnf install -y curl wget systemd -q
            else
                yum install -y curl wget systemd -q
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm curl wget systemd >/dev/null 2>&1
            ;;
        opensuse*|sles)
            zypper install -y curl wget systemd >/dev/null 2>&1
            ;;
        alpine)
            apk add --no-cache curl wget openrc >/dev/null 2>&1
            ;;
        *)
            log_warning "Unknown distribution. Assuming curl and wget are available."
            ;;
    esac
    
    log_success "Dependencies installed"
}

# Create directory structure
create_directories() {
    log_step "Creating directory structure..."
    
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$LOG_DIR"
    
    log_success "Directories created"
}

# Download and install newt
install_newt() {
    log_step "Installing newt..."
    
    # Download and install newt
    if curl -fsSL https://digpangolin.com/get-newt.sh | bash; then
        log_success "Newt installed successfully"
        
        # Verify installation
        if command -v newt &> /dev/null; then
            NEWT_VERSION=$(newt --version 2>/dev/null || echo "unknown")
            log_info "Newt version: ${NEWT_VERSION}"
        else
            log_error "Newt binary not found after installation"
            exit 1
        fi
    else
        log_error "Failed to install newt"
        exit 1
    fi
}

# Interactive configuration
configure_interactive() {
    log_step "Configuring newt..."
    
    echo -e "${CYAN}${BOLD}Enter Newt Configuration${NC}"
    echo ""
    
    read -p "Client ID: " CLIENT_ID
    read -sp "Client Secret: " CLIENT_SECRET
    echo ""
    read -p "Endpoint: " ENDPOINT
    
    # Validate inputs
    if [[ -z "$CLIENT_ID" ]] || [[ -z "$CLIENT_SECRET" ]] || [[ -z "$ENDPOINT" ]]; then
        log_error "All fields are required"
        exit 1
    fi
    
    # Write configuration
    cat > "$CONFIG_FILE" <<EOF
# Newt Configuration
CLIENT_ID="$CLIENT_ID"
CLIENT_SECRET="$CLIENT_SECRET"
ENDPOINT="$ENDPOINT"
EOF
    
    chmod 600 "$CONFIG_FILE"
    log_success "Configuration saved to $CONFIG_FILE"
}

# Configuration from environment or file
configure_from_env() {
    if [[ -n "$NEWT_CLIENT_ID" ]] && [[ -n "$NEWT_CLIENT_SECRET" ]] && [[ -n "$NEWT_ENDPOINT" ]]; then
        cat > "$CONFIG_FILE" <<EOF
# Newt Configuration
CLIENT_ID="$NEWT_CLIENT_ID"
CLIENT_SECRET="$NEWT_CLIENT_SECRET"
ENDPOINT="$NEWT_ENDPOINT"
EOF
        chmod 600 "$CONFIG_FILE"
        log_success "Configuration saved from environment variables"
    else
        log_error "Missing environment variables: NEWT_CLIENT_ID, NEWT_CLIENT_SECRET, NEWT_ENDPOINT"
        exit 1
    fi
}

# Create systemd service
create_service() {
    log_step "Creating systemd service..."
    
    cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Newt Pangolin Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/newt/config
ExecStart=/bin/bash -c 'newt --id "${CLIENT_ID}" --secret "${CLIENT_SECRET}" --endpoint "${ENDPOINT}" --accept-clients'
Restart=always
RestartSec=10
StandardOutput=append:/var/log/newt/newt.log
StandardError=append:/var/log/newt/newt.log
User=root

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 "$SERVICE_FILE"
    log_success "Service file created"
}

# Create update script
create_updater() {
    log_step "Creating auto-update mechanism..."
    
    cat > "$UPDATE_SCRIPT" <<'UPDATER_EOF'
#!/bin/bash

LOG_FILE="/var/log/newt/updater.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_message "Starting newt update check..."

# Download latest version
if curl -fsSL https://digpangolin.com/get-newt.sh | bash >> "$LOG_FILE" 2>&1; then
    log_message "Newt updated successfully"
    
    # Restart service if it's running
    if systemctl is-active --quiet newt.service; then
        log_message "Restarting newt service..."
        systemctl restart newt.service
        log_message "Service restarted"
    fi
else
    log_message "ERROR: Failed to update newt"
fi

log_message "Update check completed"
UPDATER_EOF
    
    chmod +x "$UPDATE_SCRIPT"
    
    # Create systemd service for updater
    cat > "$UPDATE_SERVICE" <<EOF
[Unit]
Description=Newt Updater Service
After=network-online.target

[Service]
Type=oneshot
ExecStart=$UPDATE_SCRIPT
StandardOutput=append:/var/log/newt/updater.log
StandardError=append:/var/log/newt/updater.log
EOF
    
    # Create systemd timer for daily updates
    cat > "$UPDATE_TIMER" <<EOF
[Unit]
Description=Newt Daily Update Timer

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    chmod 644 "$UPDATE_SERVICE" "$UPDATE_TIMER"
    
    systemctl daemon-reload
    systemctl enable newt-updater.timer
    systemctl start newt-updater.timer
    
    log_success "Auto-update configured (daily updates enabled)"
}

# Start service
start_service() {
    log_step "Starting newt service..."
    
    systemctl daemon-reload
    systemctl enable newt.service
    systemctl start newt.service
    
    sleep 2
    
    if systemctl is-active --quiet newt.service; then
        log_success "Newt service is running"
        systemctl status newt.service --no-pager -l
    else
        log_error "Failed to start newt service"
        systemctl status newt.service --no-pager -l
        exit 1
    fi
}

# Install command
install() {
    log_info "${BOLD}Starting Newt Service Installation${NC}"
    echo ""
    
    check_root
    detect_distro
    install_dependencies
    create_directories
    install_newt
    
    # Configuration
    if [[ "$1" == "--env" ]]; then
        configure_from_env
    else
        configure_interactive
    fi
    
    create_service
    create_updater
    start_service
    
    echo ""
    log_success "${BOLD}Installation completed successfully!${NC}"
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    echo -e "  ${GREEN}systemctl status newt${NC}    - Check service status"
    echo -e "  ${GREEN}systemctl restart newt${NC}   - Restart service"
    echo -e "  ${GREEN}journalctl -u newt -f${NC}    - View live logs"
    echo -e "  ${GREEN}cat $LOG_FILE${NC}            - View service logs"
    echo ""
}

# Uninstall command
uninstall() {
    log_info "${BOLD}Starting Newt Service Uninstallation${NC}"
    echo ""
    
    check_root
    
    # Stop and disable services
    log_step "Stopping services..."
    systemctl stop newt.service 2>/dev/null || true
    systemctl disable newt.service 2>/dev/null || true
    systemctl stop newt-updater.timer 2>/dev/null || true
    systemctl disable newt-updater.timer 2>/dev/null || true
    
    # Remove service files
    log_step "Removing service files..."
    rm -f "$SERVICE_FILE"
    rm -f "$UPDATE_SERVICE"
    rm -f "$UPDATE_TIMER"
    rm -f "$UPDATE_SCRIPT"
    
    # Remove configuration (ask user)
    if [[ "$1" == "--purge" ]]; then
        log_step "Removing configuration and logs..."
        rm -rf "$CONFIG_DIR"
        rm -rf "$LOG_DIR"
    else
        echo -e "${YELLOW}Configuration kept at: $CONFIG_DIR${NC}"
        echo -e "${YELLOW}Logs kept at: $LOG_DIR${NC}"
        echo -e "${CYAN}Use 'uninstall --purge' to remove everything${NC}"
    fi
    
    # Remove newt binary (optional)
    read -p "Remove newt binary? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$NEWT_BINARY"
        log_success "Newt binary removed"
    fi
    
    systemctl daemon-reload
    
    echo ""
    log_success "${BOLD}Uninstallation completed${NC}"
}

# Status command
status() {
    echo -e "${CYAN}${BOLD}=== Newt Service Status ===${NC}"
    echo ""
    
    systemctl status newt.service --no-pager
    
    echo ""
    echo -e "${CYAN}${BOLD}=== Update Timer Status ===${NC}"
    echo ""
    systemctl status newt-updater.timer --no-pager
    
    echo ""
    echo -e "${CYAN}${BOLD}=== Recent Logs ===${NC}"
    echo ""
    journalctl -u newt.service -n 20 --no-pager
}

# Logs command
logs() {
    if [[ "$1" == "-f" ]] || [[ "$1" == "--follow" ]]; then
        journalctl -u newt.service -f
    else
        journalctl -u newt.service -n 50 --no-pager
    fi
}

# Update command
update() {
    log_info "Manually triggering update..."
    check_root
    
    bash "$UPDATE_SCRIPT"
    
    log_success "Update completed"
}

# Show usage
usage() {
    echo -e "${BOLD}Newt Service Manager${NC}"
    echo ""
    echo -e "${CYAN}Usage:${NC}"
    echo -e "  $0 ${GREEN}install${NC}              - Install and configure newt service (interactive)"
    echo -e "  $0 ${GREEN}install --env${NC}        - Install using environment variables"
    echo -e "  $0 ${GREEN}uninstall${NC}            - Uninstall newt service (keep config)"
    echo -e "  $0 ${GREEN}uninstall --purge${NC}    - Uninstall and remove all data"
    echo -e "  $0 ${GREEN}status${NC}               - Show service status"
    echo -e "  $0 ${GREEN}logs${NC}                 - Show recent logs"
    echo -e "  $0 ${GREEN}logs -f${NC}              - Follow logs in real-time"
    echo -e "  $0 ${GREEN}update${NC}               - Manually trigger update"
    echo -e "  $0 ${GREEN}restart${NC}              - Restart service"
    echo -e "  $0 ${GREEN}start${NC}                - Start service"
    echo -e "  $0 ${GREEN}stop${NC}                 - Stop service"
    echo ""
    echo -e "${CYAN}Environment Variables (for --env mode):${NC}"
    echo -e "  ${YELLOW}NEWT_CLIENT_ID${NC}        - Client ID"
    echo -e "  ${YELLOW}NEWT_CLIENT_SECRET${NC}    - Client Secret"
    echo -e "  ${YELLOW}NEWT_ENDPOINT${NC}         - Endpoint URL"
    echo ""
}

# Main command dispatcher
case "$1" in
    install)
        install "$2"
        ;;
    uninstall)
        uninstall "$2"
        ;;
    status)
        status
        ;;
    logs)
        logs "$2"
        ;;
    update)
        update
        ;;
    restart)
        check_root
        systemctl restart newt.service
        log_success "Service restarted"
        ;;
    start)
        check_root
        systemctl start newt.service
        log_success "Service started"
        ;;
    stop)
        check_root
        systemctl stop newt.service
        log_success "Service stopped"
        ;;
    *)
        usage
        exit 1
        ;;
esac
