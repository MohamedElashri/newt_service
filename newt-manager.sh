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
INSTANCES_DIR="${CONFIG_DIR}/instances"
SERVICE_DIR="/etc/systemd/system"
NEWT_BINARY="/usr/local/bin/newt"
LOG_DIR="/var/log/newt"
UPDATE_SCRIPT="/usr/local/bin/newt-updater"
UPDATE_SERVICE="${SERVICE_DIR}/newt-updater.service"
UPDATE_TIMER="${SERVICE_DIR}/newt-updater.timer"

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
    mkdir -p "$INSTANCES_DIR"
    mkdir -p "$LOG_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$INSTANCES_DIR"
    chmod 755 "$LOG_DIR"
    
    log_success "Directories created"
}

# List all instances
list_instances() {
    if [[ ! -d "$INSTANCES_DIR" ]]; then
        echo "No instances configured"
        return
    fi
    
    local instances=($(ls "$INSTANCES_DIR" 2>/dev/null))
    
    if [[ ${#instances[@]} -eq 0 ]]; then
        echo "No instances configured"
        return
    fi
    
    echo -e "${CYAN}${BOLD}Configured Instances:${NC}"
    echo ""
    
    for instance in "${instances[@]}"; do
        local service_file="${SERVICE_DIR}/newt@${instance}.service"
        local is_active=$(systemctl is-active "newt@${instance}.service" 2>/dev/null || echo "inactive")
        local is_enabled=$(systemctl is-enabled "newt@${instance}.service" 2>/dev/null || echo "disabled")
        
        if [[ "$is_active" == "active" ]]; then
            echo -e "  ${GREEN}●${NC} ${BOLD}${instance}${NC} (${GREEN}active${NC}, ${is_enabled})"
        else
            echo -e "  ${RED}●${NC} ${BOLD}${instance}${NC} (${RED}${is_active}${NC}, ${is_enabled})"
        fi
        
        # Show config details
        if [[ -f "${INSTANCES_DIR}/${instance}" ]]; then
            source "${INSTANCES_DIR}/${instance}"
            echo -e "      Endpoint: ${ENDPOINT}"
        fi
    done
    echo ""
}

# Get instance config file path
get_instance_config() {
    local instance="$1"
    echo "${INSTANCES_DIR}/${instance}"
}

# Get instance service name
get_instance_service() {
    local instance="$1"
    echo "newt@${instance}.service"
}

# Get instance log file path
get_instance_log() {
    local instance="$1"
    echo "${LOG_DIR}/${instance}.log"
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

# Interactive configuration for instance
configure_interactive() {
    local instance_name="$1"
    
    log_step "Configuring newt instance..."
    
    echo -e "${CYAN}${BOLD}Enter Newt Configuration${NC}"
    echo ""
    
    if [[ -z "$instance_name" ]]; then
        read -p "Instance name (e.g., prod, dev, backup): " instance_name
        instance_name=$(echo "$instance_name" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-_')
        
        if [[ -z "$instance_name" ]]; then
            log_error "Instance name is required"
            exit 1
        fi
    fi
    
    local config_file=$(get_instance_config "$instance_name")
    
    if [[ -f "$config_file" ]]; then
        log_warning "Instance '$instance_name' already exists"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Aborted"
            exit 0
        fi
    fi
    
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
    cat > "$config_file" <<EOF
# Newt Configuration for instance: $instance_name
CLIENT_ID="$CLIENT_ID"
CLIENT_SECRET="$CLIENT_SECRET"
ENDPOINT="$ENDPOINT"
EOF
    
    chmod 600 "$config_file"
    log_success "Configuration saved for instance '$instance_name'"
    
    echo "$instance_name"
}

# Configuration from environment
configure_from_env() {
    local instance_name="$1"
    
    if [[ -z "$instance_name" ]]; then
        if [[ -n "$NEWT_INSTANCE_NAME" ]]; then
            instance_name="$NEWT_INSTANCE_NAME"
        else
            instance_name="default"
        fi
    fi
    
    instance_name=$(echo "$instance_name" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-_')
    
    if [[ -n "$NEWT_CLIENT_ID" ]] && [[ -n "$NEWT_CLIENT_SECRET" ]] && [[ -n "$NEWT_ENDPOINT" ]]; then
        local config_file=$(get_instance_config "$instance_name")
        
        cat > "$config_file" <<EOF
# Newt Configuration for instance: $instance_name
CLIENT_ID="$NEWT_CLIENT_ID"
CLIENT_SECRET="$NEWT_CLIENT_SECRET"
ENDPOINT="$NEWT_ENDPOINT"
EOF
        chmod 600 "$config_file"
        log_success "Configuration saved for instance '$instance_name' from environment variables"
        echo "$instance_name"
    else
        log_error "Missing environment variables: NEWT_CLIENT_ID, NEWT_CLIENT_SECRET, NEWT_ENDPOINT"
        exit 1
    fi
}

# Create systemd service template (once)
create_service_template() {
    log_step "Creating systemd service template..."
    
    local template_file="${SERVICE_DIR}/newt@.service"
    
    cat > "$template_file" <<'EOF'
[Unit]
Description=Newt Pangolin Service (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/newt/instances/%i
ExecStart=/bin/bash -c 'newt --id "${CLIENT_ID}" --secret "${CLIENT_SECRET}" --endpoint "${ENDPOINT}"'
Restart=always
RestartSec=10
StandardOutput=append:/var/log/newt/%i.log
StandardError=append:/var/log/newt/%i.log
User=root

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 "$template_file"
    log_success "Service template created"
}

# Create service for a specific instance
create_service() {
    local instance="$1"
    
    # Ensure template exists
    if [[ ! -f "${SERVICE_DIR}/newt@.service" ]]; then
        create_service_template
    fi
    
    log_success "Service configured for instance '$instance'"
}

# Create update script
create_updater() {
    log_step "Creating auto-update mechanism..."
    
    cat > "$UPDATE_SCRIPT" <<'UPDATER_EOF'
#!/bin/bash

INSTANCES_DIR="/etc/newt/instances"
LOG_FILE="/var/log/newt/updater.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_message "Starting newt update check..."

# Download latest version
if curl -fsSL https://digpangolin.com/get-newt.sh | bash >> "$LOG_FILE" 2>&1; then
    log_message "Newt updated successfully"
    
    # Restart all active instances
    if [[ -d "$INSTANCES_DIR" ]]; then
        for instance_config in "$INSTANCES_DIR"/*; do
            if [[ -f "$instance_config" ]]; then
                instance=$(basename "$instance_config")
                if systemctl is-active --quiet "newt@${instance}.service"; then
                    log_message "Restarting instance: $instance"
                    systemctl restart "newt@${instance}.service"
                    log_message "Instance $instance restarted"
                fi
            fi
        done
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

# Start service for an instance
start_service() {
    local instance="$1"
    
    log_step "Starting newt service for instance '$instance'..."
    
    local service_name=$(get_instance_service "$instance")
    
    systemctl daemon-reload
    systemctl enable "$service_name"
    systemctl start "$service_name"
    
    sleep 2
    
    if systemctl is-active --quiet "$service_name"; then
        log_success "Newt instance '$instance' is running"
        systemctl status "$service_name" --no-pager -l
    else
        log_error "Failed to start newt instance '$instance'"
        systemctl status "$service_name" --no-pager -l
        exit 1
    fi
}

# Install command
install() {
    local instance_name="$1"
    
    log_info "${BOLD}Starting Newt Service Installation${NC}"
    echo ""
    
    check_root
    detect_distro
    install_dependencies
    create_directories
    install_newt
    
    # Configuration - auto-detect environment variables
    if [[ -n "$NEWT_CLIENT_ID" ]] && [[ -n "$NEWT_CLIENT_SECRET" ]] && [[ -n "$NEWT_ENDPOINT" ]]; then
        log_info "Detected environment variables for configuration"
        instance_name=$(configure_from_env "$instance_name")
    elif [[ "$instance_name" == "--env" ]]; then
        instance_name=$(configure_from_env "")
    else
        instance_name=$(configure_interactive "$instance_name")
    fi
    
    create_service_template
    create_service "$instance_name"
    create_updater
    start_service "$instance_name"
    
    echo ""
    log_success "${BOLD}Installation completed successfully!${NC}"
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    echo -e "  ${GREEN}$0 status $instance_name${NC}        - Check instance status"
    echo -e "  ${GREEN}$0 restart $instance_name${NC}       - Restart instance"
    echo -e "  ${GREEN}$0 logs $instance_name -f${NC}       - View live logs"
    echo -e "  ${GREEN}$0 list${NC}                          - List all instances"
    echo -e "  ${GREEN}$0 add${NC}                           - Add another instance"
    echo ""
}

# Add new instance
add_instance() {
    local instance_name="$1"
    
    log_info "${BOLD}Adding New Newt Instance${NC}"
    echo ""
    
    check_root
    
    # Ensure directories exist
    if [[ ! -d "$INSTANCES_DIR" ]]; then
        create_directories
    fi
    
    # Ensure template exists
    if [[ ! -f "${SERVICE_DIR}/newt@.service" ]]; then
        create_service_template
    fi
    
    # Configuration
    if [[ -n "$NEWT_CLIENT_ID" ]] && [[ -n "$NEWT_CLIENT_SECRET" ]] && [[ -n "$NEWT_ENDPOINT" ]]; then
        log_info "Detected environment variables for configuration"
        instance_name=$(configure_from_env "$instance_name")
    else
        instance_name=$(configure_interactive "$instance_name")
    fi
    
    create_service "$instance_name"
    start_service "$instance_name"
    
    echo ""
    log_success "${BOLD}Instance '$instance_name' added successfully!${NC}"
    echo ""
}

# Remove instance
remove_instance() {
    local instance="$1"
    
    check_root
    
    if [[ -z "$instance" ]]; then
        log_error "Instance name required"
        echo "Usage: $0 remove <instance-name>"
        exit 1
    fi
    
    local config_file=$(get_instance_config "$instance")
    local service_name=$(get_instance_service "$instance")
    local log_file=$(get_instance_log "$instance")
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Instance '$instance' not found"
        exit 1
    fi
    
    log_info "${BOLD}Removing instance '$instance'${NC}"
    echo ""
    
    # Stop and disable service
    log_step "Stopping service..."
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
    
    # Remove configuration
    log_step "Removing configuration..."
    rm -f "$config_file"
    
    # Ask about logs
    read -p "Remove logs for this instance? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$log_file"
        log_success "Logs removed"
    fi
    
    systemctl daemon-reload
    
    echo ""
    log_success "${BOLD}Instance '$instance' removed${NC}"
}

# Uninstall command
uninstall() {
    log_info "${BOLD}Starting Newt Service Uninstallation${NC}"
    echo ""
    
    check_root
    
    # Stop and disable all instance services
    log_step "Stopping services..."
    if [[ -d "$INSTANCES_DIR" ]]; then
        for instance_config in "$INSTANCES_DIR"/*; do
            if [[ -f "$instance_config" ]]; then
                instance=$(basename "$instance_config")
                systemctl stop "newt@${instance}.service" 2>/dev/null || true
                systemctl disable "newt@${instance}.service" 2>/dev/null || true
                log_info "Stopped instance: $instance"
            fi
        done
    fi
    
    systemctl stop newt-updater.timer 2>/dev/null || true
    systemctl disable newt-updater.timer 2>/dev/null || true
    
    # Remove service files
    log_step "Removing service files..."
    rm -f "${SERVICE_DIR}/newt@.service"
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
    local instance="$1"
    
    if [[ -n "$instance" ]]; then
        # Show status for specific instance
        local service_name=$(get_instance_service "$instance")
        
        echo -e "${CYAN}${BOLD}=== Status for instance: $instance ===${NC}"
        echo ""
        
        systemctl status "$service_name" --no-pager
        
        echo ""
        echo -e "${CYAN}${BOLD}=== Recent Logs ===${NC}"
        echo ""
        journalctl -u "$service_name" -n 20 --no-pager
    else
        # Show status for all instances
        echo -e "${CYAN}${BOLD}=== All Instances Status ===${NC}"
        echo ""
        
        list_instances
        
        echo ""
        echo -e "${CYAN}${BOLD}=== Update Timer Status ===${NC}"
        echo ""
        systemctl status newt-updater.timer --no-pager
    fi
}

# Logs command
logs() {
    local instance="$1"
    local follow_flag="$2"
    
    if [[ -z "$instance" ]]; then
        log_error "Instance name required"
        echo "Usage: $0 logs <instance-name> [-f|--follow]"
        echo ""
        list_instances
        exit 1
    fi
    
    local service_name=$(get_instance_service "$instance")
    
    if [[ "$follow_flag" == "-f" ]] || [[ "$follow_flag" == "--follow" ]]; then
        journalctl -u "$service_name" -f
    else
        journalctl -u "$service_name" -n 50 --no-pager
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
    echo -e "${BOLD}Newt Service Manager - Multi-Instance Support${NC}"
    echo ""
    echo -e "${CYAN}Initial Setup:${NC}"
    echo -e "  $0 ${GREEN}install [instance-name]${NC}           - Install and configure first instance"
    echo -e "  $0 ${GREEN}install --env${NC}                     - Install using environment variables"
    echo ""
    echo -e "${CYAN}Instance Management:${NC}"
    echo -e "  $0 ${GREEN}list${NC}                              - List all configured instances"
    echo -e "  $0 ${GREEN}add [instance-name]${NC}               - Add new instance"
    echo -e "  $0 ${GREEN}remove <instance-name>${NC}            - Remove an instance"
    echo ""
    echo -e "${CYAN}Service Control:${NC}"
    echo -e "  $0 ${GREEN}status [instance-name]${NC}            - Show status (all or specific instance)"
    echo -e "  $0 ${GREEN}start <instance-name>${NC}             - Start instance"
    echo -e "  $0 ${GREEN}stop <instance-name>${NC}              - Stop instance"
    echo -e "  $0 ${GREEN}restart <instance-name>${NC}           - Restart instance"
    echo -e "  $0 ${GREEN}logs <instance-name> [-f]${NC}         - View logs (optionally follow)"
    echo ""
    echo -e "${CYAN}System Management:${NC}"
    echo -e "  $0 ${GREEN}update${NC}                            - Manually trigger update (all instances)"
    echo -e "  $0 ${GREEN}uninstall${NC}                         - Uninstall all (keep config)"
    echo -e "  $0 ${GREEN}uninstall --purge${NC}                 - Uninstall and remove all data"
    echo ""
    echo -e "${CYAN}Environment Variables (auto-detected or use --env):${NC}"
    echo -e "  ${YELLOW}NEWT_CLIENT_ID${NC}                     - Client ID"
    echo -e "  ${YELLOW}NEWT_CLIENT_SECRET${NC}                 - Client Secret"
    echo -e "  ${YELLOW}NEWT_ENDPOINT${NC}                      - Endpoint URL"
    echo -e "  ${YELLOW}NEWT_INSTANCE_NAME${NC}                 - Instance name (optional)"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  $0 install prod                       - Install with instance name 'prod'"
    echo -e "  $0 add backup                         - Add another instance named 'backup'"
    echo -e "  $0 status                             - Show all instances"
    echo -e "  $0 logs prod -f                       - Follow logs for 'prod' instance"
    echo ""
}

# Main command dispatcher
case "$1" in
    install)
        install "$2"
        ;;
    add)
        add_instance "$2"
        ;;
    remove)
        remove_instance "$2"
        ;;
    list)
        list_instances
        ;;
    uninstall)
        uninstall "$2"
        ;;
    status)
        status "$2"
        ;;
    logs)
        logs "$2" "$3"
        ;;
    update)
        update
        ;;
    restart)
        check_root
        if [[ -z "$2" ]]; then
            log_error "Instance name required"
            echo "Usage: $0 restart <instance-name>"
            list_instances
            exit 1
        fi
        systemctl restart "newt@$2.service"
        log_success "Instance '$2' restarted"
        ;;
    start)
        check_root
        if [[ -z "$2" ]]; then
            log_error "Instance name required"
            echo "Usage: $0 start <instance-name>"
            list_instances
            exit 1
        fi
        systemctl start "newt@$2.service"
        log_success "Instance '$2' started"
        ;;
    stop)
        check_root
        if [[ -z "$2" ]]; then
            log_error "Instance name required"
            echo "Usage: $0 stop <instance-name>"
            list_instances
            exit 1
        fi
        systemctl stop "newt@$2.service"
        log_success "Instance '$2' stopped"
        ;;
    *)
        usage
        exit 1
        ;;
esac
