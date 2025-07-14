#!/bin/bash

# SSH Hardening Script
# This script configures SSH for key-based authentication only

set -e

# Configuration
SSH_CONFIG="/etc/ssh/sshd_config"
ALLOWED_USERS="${1:-gix}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_status "Starting SSH hardening..."

# Create backup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${SSH_CONFIG}.backup.${TIMESTAMP}"

print_status "Creating backup at ${BACKUP_FILE}"
cp "${SSH_CONFIG}" "${BACKUP_FILE}"

# Check if backup was successful
if [ ! -f "${BACKUP_FILE}" ]; then
    print_error "Failed to create backup file. Aborting."
    exit 1
fi

print_status "Modifying SSH configuration..."

# Create a temporary file for the new configuration
TMP_FILE=$(mktemp)

# Get original permissions to preserve them
ORIGINAL_PERMS=$(stat -c "%a" "${SSH_CONFIG}")

# Create new SSH configuration
cat > "${TMP_FILE}" << EOF
# SSH Configuration hardened on $(date)
# Original file backed up at ${BACKUP_FILE}

# Basic SSH settings
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication settings
LoginGraceTime 30
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 10

# Key-based authentication
PubkeyAuthentication yes
AuthorizedKeysFile %h/.ssh/authorized_keys

# Disable password authentication
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Disable legacy authentication methods
RhostsRSAAuthentication no
HostbasedAuthentication no

# User restrictions
AllowUsers ${ALLOWED_USERS}
DenyUsers root

# Connection settings
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive yes

# Logging
SyslogFacility AUTH
LogLevel INFO

# Security settings
X11Forwarding no
AllowTcpForwarding no
GatewayPorts no
PermitTunnel no
PrintMotd no
PrintLastLog yes
IgnoreRhosts yes
EOF

# Apply the changes
mv "${TMP_FILE}" "${SSH_CONFIG}"

# Restore original permissions
chmod "${ORIGINAL_PERMS}" "${SSH_CONFIG}"

print_status "SSH configuration updated successfully."

# Validate the configuration
print_status "Validating SSH configuration..."
if sshd -t; then
    print_status "SSH configuration is valid."
else
    print_error "SSH configuration is invalid. Restoring backup..."
    cp "${BACKUP_FILE}" "${SSH_CONFIG}"
    chmod "${ORIGINAL_PERMS}" "${SSH_CONFIG}"
    print_error "Backup restored. Please check your configuration manually."
    exit 1
fi

# Create a test SSH connection script
TEST_SCRIPT="/tmp/test_ssh_connection.sh"
cat > "${TEST_SCRIPT}" << 'EOF'
#!/bin/bash
# Test SSH connection before reloading service
echo "Testing SSH configuration..."
if sshd -t; then
    echo "SSH configuration is valid. Proceeding with reload..."
    systemctl reload ssh
    echo "SSH service reloaded successfully."
else
    echo "SSH configuration is invalid. Please check manually."
    exit 1
fi
EOF

chmod +x "${TEST_SCRIPT}"

print_status "Running SSH configuration test..."
if "${TEST_SCRIPT}"; then
    print_status "SSH service reloaded successfully."
else
    print_error "Failed to reload SSH service."
    exit 1
fi

# Clean up test script
rm -f "${TEST_SCRIPT}"

print_status "SSH hardening completed successfully!"
print_status "Backup location: ${BACKUP_FILE}"
print_status "Allowed users: ${ALLOWED_USERS}"

print_warning "IMPORTANT: Make sure you have SSH key access before logging out!"
print_warning "Test your SSH connection from another terminal before closing this session."

echo ""
print_status "SSH Configuration Summary:"
echo "- Root login: Disabled"
echo "- Password authentication: Disabled"
echo "- Key-based authentication: Enabled"
echo "- Allowed users: ${ALLOWED_USERS}"
echo "- Port: 22"
echo "- Login grace time: 30 seconds"
echo "- Max auth tries: 3"

echo ""
print_status "To test SSH access from another machine:"
echo "ssh ${ALLOWED_USERS}@$(hostname -I | awk '{print $1}')"

echo ""
print_status "Next steps:"
echo "1. Test SSH access from another terminal"
echo "2. Proceed to network configuration"
echo "3. If SSH access fails, restore backup: cp ${BACKUP_FILE} ${SSH_CONFIG}" 