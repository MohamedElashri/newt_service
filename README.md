# Newt Service Manager

Complete automation for running multiple Newt Pangolin instances as persistent Linux services with automatic updates.

## Quick Reference

```bash
# Install first instance
sudo ./newt-manager.sh install prod

# Add more instances
sudo ./newt-manager.sh add dev
sudo ./newt-manager.sh add backup

# List all instances
sudo ./newt-manager.sh list

# Control instances
sudo ./newt-manager.sh start prod
sudo ./newt-manager.sh stop prod
sudo ./newt-manager.sh restart prod
sudo ./newt-manager.sh status prod
sudo ./newt-manager.sh logs prod -f

# Remove an instance
sudo ./newt-manager.sh remove dev
```

## Quick Start

### First Installation

#### 1. Interactive Mode (Recommended)

Download and run the script with an instance name:

```bash
curl -fsSL https://github.com/MohamedElashri/newt_service/raw/refs/heads/main/newt-manager.sh -o newt-manager.sh
chmod +x newt-manager.sh
sudo ./newt-manager.sh install prod
```

You'll be prompted to enter:
- Instance name (e.g., `prod`, `dev`, `backup`)
- Client ID
- Client Secret
- Endpoint

#### 2. Environment Variables (Auto-Detected)

The script automatically detects environment variables:

```bash
export NEWT_CLIENT_ID="your-client-id"
export NEWT_CLIENT_SECRET="your-secret"
export NEWT_ENDPOINT="your-endpoint"
export NEWT_INSTANCE_NAME="prod"  # Optional, defaults to "default"

# One-liner installation
curl -fsSL https://github.com/MohamedElashri/newt_service/raw/refs/heads/main/newt-manager.sh | sudo -E bash -s install
```

**Note:** Use `sudo -E` to preserve environment variables.

#### 3. Environment Variables (Explicit Flag)

```bash
export NEWT_CLIENT_ID="your-client-id"
export NEWT_CLIENT_SECRET="your-secret"
export NEWT_ENDPOINT="your-endpoint"

sudo -E bash newt-manager.sh install --env
```

### Adding More Instances

After initial installation, add additional Pangolin instances:

```bash
# Interactive mode
sudo bash newt-manager.sh add backup

# With environment variables
export NEWT_CLIENT_ID="backup-client-id"
export NEWT_CLIENT_SECRET="backup-secret"
export NEWT_ENDPOINT="backup-endpoint"
sudo -E bash newt-manager.sh add backup
```

## Commands

### Instance Management

```bash
# List all configured instances
sudo bash newt-manager.sh list

# Add a new instance
sudo bash newt-manager.sh add <instance-name>

# Remove an instance
sudo bash newt-manager.sh remove <instance-name>
```

### Service Control

```bash
# View status of all instances
sudo bash newt-manager.sh status

# View status of specific instance
sudo bash newt-manager.sh status prod

# Start an instance
sudo bash newt-manager.sh start prod

# Stop an instance
sudo bash newt-manager.sh stop prod

# Restart an instance
sudo bash newt-manager.sh restart prod

# View logs (last 50 lines)
sudo bash newt-manager.sh logs prod

# Follow logs in real-time
sudo bash newt-manager.sh logs prod -f
```

### Updates

```bash
# Manually trigger update for all instances
sudo bash newt-manager.sh update

# Check update timer status
systemctl status newt-updater.timer
```

### Uninstallation

```bash
# Uninstall all instances (keep configuration)
sudo bash newt-manager.sh uninstall

# Uninstall and remove everything
sudo bash newt-manager.sh uninstall --purge
```

## System Integration

### Using systemctl directly

```bash
# For specific instances
systemctl status newt@prod.service
systemctl start newt@prod.service
systemctl stop newt@prod.service
systemctl restart newt@prod.service

# Enable/Disable auto-start for instances
systemctl enable newt@prod.service
systemctl disable newt@prod.service

# View logs for specific instance
journalctl -u newt@prod.service -f
journalctl -u newt@prod.service --since today
journalctl -u newt@prod.service --since "1 hour ago"

# View logs from all instances
journalctl -u 'newt@*' -f
```

### File Locations

```
/etc/newt/
├── instances/
│   ├── prod                          - Instance configuration
│   ├── dev                           - Instance configuration
│   └── backup                        - Instance configuration

/var/log/newt/
├── prod.log                          - Instance logs
├── dev.log                           - Instance logs
├── backup.log                        - Instance logs
└── updater.log                       - Update logs

/usr/local/bin/newt                   - Newt binary
/usr/local/bin/newt-updater           - Update script (handles all instances)

/etc/systemd/system/
├── newt@.service                     - Service template
├── newt-updater.service              - Update service
└── newt-updater.timer                - Update timer
```

## Configuration

Each instance configuration is stored in `/etc/newt/instances/<instance-name>`:

```bash
# Example: /etc/newt/instances/prod
CLIENT_ID="your-client-id"
CLIENT_SECRET="your-secret"
ENDPOINT="your-endpoint"
```

To update an instance configuration:
1. Edit the file: `sudo nano /etc/newt/instances/prod`
2. Restart instance: `sudo systemctl restart newt@prod.service`

Or use the script:
```bash
# Remove and re-add with new configuration
sudo ./newt-manager.sh remove prod
sudo ./newt-manager.sh add prod
```

## Automatic Updates

The service automatically checks for updates daily at a random time. The update mechanism:

1. Downloads latest newt version
2. Installs it
3. Restarts the service if running
4. Logs everything to `/var/log/newt/updater.log`

### Customizing Update Schedule

Edit the timer: `sudo systemctl edit newt-updater.timer`

Examples:
```ini
# Every 6 hours
[Timer]
OnCalendar=*-*-* 0/6:00:00

# Weekly on Sunday at 3 AM
[Timer]
OnCalendar=Sun *-*-* 03:00:00

# Every 12 hours
[Timer]
OnCalendar=*-*-* 0,12:00:00
```

Then reload: `sudo systemctl daemon-reload && sudo systemctl restart newt-updater.timer`

## Troubleshooting

### Service won't start

```bash
# Check status and logs
sudo systemctl status newt -l
sudo journalctl -u newt -n 100

# Verify configuration
sudo cat /etc/newt/config

# Test newt manually
source /etc/newt/config
newt --id "$CLIENT_ID" --secret "$CLIENT_SECRET" --endpoint "$ENDPOINT" --accept-clients
```

### Check if binary exists

```bash
which newt
newt --version
```

### Reinstall newt

```bash
curl -fsSL https://digpangolin.com/get-newt.sh | bash
sudo systemctl restart newt
```

### View detailed logs

```bash
# All logs
sudo journalctl -u newt --no-pager

# Logs with timestamps
sudo journalctl -u newt -o short-precise

# Logs from specific time
sudo journalctl -u newt --since "2026-01-01 10:00:00"

# Export logs
sudo journalctl -u newt > newt-logs.txt
```

### Permission issues

```bash
# Fix log directory permissions
sudo chmod 755 /var/log/newt
sudo chown root:root /var/log/newt

# Fix config permissions
sudo chmod 600 /etc/newt/config
sudo chown root:root /etc/newt/config
```

### Environment variables not detected

When using piped installation, ensure you use `sudo -E` to preserve environment variables:

```bash
# Wrong - environment variables won't be passed
curl ... | sudo bash -s install

# Correct - preserves environment variables
curl ... | sudo -E bash -s install
```

## Advanced Usage

### Managing Multiple Instances

The script natively supports running multiple Pangolin instances simultaneously. Each instance has its own configuration, logs, and can be controlled independently.

#### Use Cases

- **High Availability**: Run multiple connections for redundancy
- **Multiple Environments**: Separate `prod`, `dev`, and `staging` instances
- **Load Distribution**: Distribute workload across multiple endpoints
- **Testing**: Test new configurations without affecting production

#### Configuration Structure

```
/etc/newt/
├── instances/
│   ├── prod          # Production instance config
│   ├── dev           # Development instance config
│   └── backup        # Backup instance config
└── ...

/var/log/newt/
├── prod.log          # Production logs
├── dev.log           # Development logs
└── backup.log        # Backup logs
```

#### Systemd Services

Each instance runs as a separate systemd service using a template unit:

```bash
# Template service
/etc/systemd/system/newt@.service

# Instance services (automatically created)
newt@prod.service
newt@dev.service
newt@backup.service
```

#### Complete Multi-Instance Example

```bash
# Install first instance (prod)
export NEWT_CLIENT_ID="prod-client-id"
export NEWT_CLIENT_SECRET="prod-secret"
export NEWT_ENDPOINT="prod-endpoint"
export NEWT_INSTANCE_NAME="prod"
sudo -E ./newt-manager.sh install

# Add development instance
export NEWT_CLIENT_ID="dev-client-id"
export NEWT_CLIENT_SECRET="dev-secret"
export NEWT_ENDPOINT="dev-endpoint"
sudo -E ./newt-manager.sh add dev

# Add backup instance interactively
sudo ./newt-manager.sh add backup

# List all instances
sudo ./newt-manager.sh list

# Control specific instances
sudo ./newt-manager.sh start prod
sudo ./newt-manager.sh stop dev
sudo ./newt-manager.sh restart backup

# View instance-specific logs
sudo ./newt-manager.sh logs prod -f

# Check specific instance status
sudo ./newt-manager.sh status prod

# Remove an instance
sudo ./newt-manager.sh remove dev
```

#### Using systemctl Directly with Instances

```bash
# Control specific instances
systemctl status newt@prod.service
systemctl start newt@dev.service
systemctl stop newt@backup.service
systemctl restart newt@prod.service

# View logs for specific instance
journalctl -u newt@prod.service -f

# Enable/disable auto-start
systemctl enable newt@prod.service
systemctl disable newt@backup.service

# Check all running newt instances
systemctl list-units 'newt@*'
```

#### Monitoring Multiple Instances

```bash
# Check status of all instances
sudo ./newt-manager.sh status

# View logs from all instances simultaneously (requires multitail)
sudo multitail /var/log/newt/*.log

# Or using journalctl
sudo journalctl -u 'newt@*' -f

# Check which instances are active
systemctl list-units --state=active 'newt@*'
```

### Automated deployment example

For CI/CD or automated deployments:

```bash
#!/bin/bash
# deploy-newt.sh

# Load secrets from secure storage (e.g., Vault, AWS Secrets Manager)
export NEWT_CLIENT_ID=$(get-secret newt/client-id)
export NEWT_CLIENT_SECRET=$(get-secret newt/client-secret)
export NEWT_ENDPOINT=$(get-secret newt/endpoint)

# Deploy
curl -fsSL https://github.com/MohamedElashri/newt_service/raw/refs/heads/main/newt-manager.sh | sudo -E bash -s install

# Verify
sleep 5
systemctl is-active --quiet newt.service && echo "Deployment successful" || echo "Deployment failed"
```

### Custom service options

Edit service file: `sudo systemctl edit newt.service`

Add custom options:
```ini
[Service]
# Run as different user
User=newt-user
Group=newt-group

# Resource limits
MemoryMax=512M
CPUQuota=50%

# Network restrictions
RestrictAddressFamilies=AF_INET AF_INET6

# Custom restart behavior
RestartSec=30
StartLimitInterval=200
StartLimitBurst=5
```

### Monitoring with systemd

```bash
# Enable email notifications on failure (requires mail setup)
sudo systemctl edit newt.service

[Unit]
OnFailure=status-email@%n.service
```

### Integration with monitoring tools

The service provides:
- Exit codes for monitoring
- Structured logs for log aggregation
- Systemd integration for health checks

Example Prometheus node_exporter query:
```
node_systemd_unit_state{name="newt.service",state="active"}
```

## Security Considerations

1. **Configuration File** - Contains sensitive credentials, restricted to root (600 permissions)
2. **Service User** - Runs as root by default, can be changed to dedicated user
3. **Network Access** - Service requires internet connectivity
4. **Logging** - Logs don't contain credentials but may contain connection info
5. **Environment Variables** - When using environment variables, be cautious about command history

### Best Practices

To avoid storing credentials in shell history:

```bash
# Method 1: Use a separate script
cat > /tmp/install-newt.sh <<'EOF'
export NEWT_CLIENT_ID="your-client-id"
export NEWT_CLIENT_SECRET="your-secret"
export NEWT_ENDPOINT="your-endpoint"
curl -fsSL https://github.com/MohamedElashri/newt_service/raw/refs/heads/main/newt-manager.sh | sudo -E bash -s install
EOF
bash /tmp/install-newt.sh
rm /tmp/install-newt.sh

# Method 2: Read from stdin
read -sp "Client ID: " NEWT_CLIENT_ID && export NEWT_CLIENT_ID
read -sp "Client Secret: " NEWT_CLIENT_SECRET && export NEWT_CLIENT_SECRET
read -p "Endpoint: " NEWT_ENDPOINT && export NEWT_ENDPOINT
curl -fsSL https://github.com/MohamedElashri/newt_service/raw/refs/heads/main/newt-manager.sh | sudo -E bash -s install
```

### Running as non-root user

```bash
# Create user
sudo useradd -r -s /bin/false newt-user

# Change service configuration
sudo systemctl edit newt.service

[Service]
User=newt-user
Group=newt-user

# Fix permissions
sudo chown newt-user:newt-user /etc/newt/config
sudo chown -R newt-user:newt-user /var/log/newt
```

## Distribution-Specific Notes

### Ubuntu/Debian
- Uses `apt-get` for dependencies
- Systemd is default

### RHEL/CentOS/Fedora
- Uses `dnf` or `yum` for dependencies
- May need to enable EPEL repository

### Arch Linux
- Uses `pacman` for dependencies
- AUR might have newt package

### Alpine Linux
- Uses `apk` for dependencies
- Uses OpenRC instead of systemd (script will adapt)

### openSUSE
- Uses `zypper` for dependencies
- Firewall rules might need adjustment

## Examples

### Quick test deployment

```bash
# Set variables
export NEWT_CLIENT_ID="test-client"
export NEWT_CLIENT_SECRET="test-secret"
export NEWT_ENDPOINT="https://test.example.com"

# Install
curl -fsSL https://github.com/MohamedElashri/newt_service/raw/refs/heads/main/newt-manager.sh | sudo -E bash -s install

# Check status
sudo systemctl status newt

# View logs
sudo journalctl -u newt -f
```

### Production deployment

```bash
# Download script first for review
curl -fsSL https://github.com/MohamedElashri/newt_service/raw/refs/heads/main/newt-manager.sh -o newt-manager.sh

# Review the script
less newt-manager.sh

# Set variables securely
export NEWT_CLIENT_ID="prod-client"
export NEWT_CLIENT_SECRET="prod-secret"
export NEWT_ENDPOINT="https://prod.example.com"

# Install
chmod +x newt-manager.sh
sudo -E ./newt-manager.sh install

# Verify deployment
sudo systemctl is-active newt.service && echo "Service is running"
sudo journalctl -u newt --since "5 minutes ago"
```

