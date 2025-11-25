# Newt Service Manager

Complete automation for running Newt Pangolin as a persistent Linux service with automatic updates.

## Quick Start

### Installation (Interactive)

```bash
sudo bash newt-manager.sh install
```

You'll be prompted to enter:
- Client ID
- Client Secret
- Endpoint

### Installation (Environment Variables)

```bash
export NEWT_CLIENT_ID="your-client-id"
export NEWT_CLIENT_SECRET="your-secret"
export NEWT_ENDPOINT="your-endpoint"

sudo -E bash newt-manager.sh install --env
```

### Installation (One-liner)

```bash
curl -fsSL https://github.com/MohamedElashri/newt_service/raw/refs/heads/main/newt-manager.sh | sudo -E bash -s install --env
```

## Commands

### Service Management

```bash
# View service status
sudo bash newt-manager.sh status

# View logs (last 50 lines)
sudo bash newt-manager.sh logs

# Follow logs in real-time
sudo bash newt-manager.sh logs -f

# Restart service
sudo bash newt-manager.sh restart

# Start service
sudo bash newt-manager.sh start

# Stop service
sudo bash newt-manager.sh stop
```

### Updates

```bash
# Manually trigger update
sudo bash newt-manager.sh update

# Check update timer status
systemctl status newt-updater.timer
```

### Uninstallation

```bash
# Uninstall (keep configuration)
sudo bash newt-manager.sh uninstall

# Uninstall and remove everything
sudo bash newt-manager.sh uninstall --purge
```

## System Integration

### Using systemctl directly

```bash
# Status
systemctl status newt

# Start/Stop/Restart
systemctl start newt
systemctl stop newt
systemctl restart newt

# Enable/Disable auto-start
systemctl enable newt
systemctl disable newt

# View logs
journalctl -u newt -f
journalctl -u newt --since today
journalctl -u newt --since "1 hour ago"
```

### File Locations

```
/etc/newt/config                      - Configuration file
/var/log/newt/newt.log               - Service logs
/var/log/newt/updater.log            - Update logs
/usr/local/bin/newt                  - Newt binary
/usr/local/bin/newt-updater          - Update script
/etc/systemd/system/newt.service     - Systemd service
/etc/systemd/system/newt-updater.*   - Update timer/service
```

## Configuration

Configuration is stored in `/etc/newt/config`:

```bash
CLIENT_ID="your-client-id"
CLIENT_SECRET="your-secret"
ENDPOINT="your-endpoint"
```

To update configuration:
1. Edit the file: `sudo nano /etc/newt/config`
2. Restart service: `sudo systemctl restart newt`

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

## Advanced Usage

### Running multiple instances

To run multiple newt instances with different configurations:

1. Copy the script: `cp newt-manager.sh newt-manager-2.sh`
2. Edit the script and change:
   - `CONFIG_DIR="/etc/newt2"`
   - `SERVICE_FILE="/etc/systemd/system/newt2.service"`
   - `LOG_DIR="/var/log/newt2"`
3. Install: `sudo bash newt-manager-2.sh install`

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

To run as non-root user:
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

