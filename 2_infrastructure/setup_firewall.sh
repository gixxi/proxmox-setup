#!/bin/bash

# Proxmox Firewall Setup Script
# This script configures the Proxmox firewall to accept only specific connections

set -e

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

print_status "Starting Proxmox firewall configuration..."

# Flush existing rules and set default policies
print_status "Flushing existing iptables rules..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Set default policies
print_status "Setting default policies..."
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback interface
print_status "Allowing loopback interface..."
iptables -A INPUT -i lo -j ACCEPT

# Allow established and related connections
print_status "Allowing established and related connections..."
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH (TCP port 22) from specified IPs
print_status "Configuring SSH access from specified IPs..."
iptables -A INPUT -p tcp --dport 22 -s 116.203.216.1 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -s 5.161.184.133 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -s 192.168.3.0/24 -j ACCEPT

# Allow MOSH (UDP port 60000-61000) from specified IPs
print_status "Configuring MOSH access from specified IPs..."
iptables -A INPUT -p udp --dport 60000:61000 -s 116.203.216.1 -j ACCEPT
iptables -A INPUT -p udp --dport 60000:61000 -s 5.161.184.133 -j ACCEPT
iptables -A INPUT -p udp --dport 60000:61000 -s 192.168.3.0/24 -j ACCEPT

# Allow HTTP traffic (ports 80 and 443)
print_status "Configuring HTTP/HTTPS access..."
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow Proxmox management console (port 8006)
print_status "Configuring Proxmox management console access..."
iptables -A INPUT -p tcp --dport 8006 -j ACCEPT

# Allow ICMP (ping) for network diagnostics
print_status "Allowing ICMP for network diagnostics..."
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

# Save iptables rules
print_status "Saving iptables rules..."
if command -v iptables-save >/dev/null 2>&1; then
    iptables-save > /etc/iptables/rules.v4
    print_status "Rules saved to /etc/iptables/rules.v4"
else
    print_warning "iptables-save not found. Rules will not persist after reboot."
    print_warning "Consider installing iptables-persistent: apt-get install iptables-persistent"
fi

# Enable iptables service if available
if systemctl list-unit-files | grep -q iptables; then
    print_status "Enabling iptables service..."
    systemctl enable iptables
    systemctl start iptables
fi

# Display current rules
print_status "Current firewall rules:"
iptables -L -v -n

print_status "Firewall configuration completed successfully!"
print_warning "Make sure you can still access the system before closing this session!"
print_warning "If you lose access, you may need to reboot or manually reset the firewall." 