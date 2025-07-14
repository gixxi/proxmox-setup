#!/bin/bash

# Network Interface Detection Script
# This script detects and displays available network interfaces

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_header() {
    echo -e "${BLUE}[HEADER]${NC} $1"
}

print_status "Detecting network interfaces..."

# Get all network interfaces
INTERFACES=$(ip link show | grep -E '^[0-9]+:' | awk -F: '{print $2}' | tr -d ' ' | grep -v 'lo')

if [[ -z "$INTERFACES" ]]; then
    print_error "No network interfaces found!"
    exit 1
fi

print_header "Available Network Interfaces:"
echo ""

# Counter for interface numbering
COUNTER=1

# Process each interface
for interface in $INTERFACES; do
    echo "Interface $COUNTER: $interface"
    
    # Get interface details
    echo "  Status: $(ip link show $interface | grep -o 'state [A-Z]*' | cut -d' ' -f2)"
    
    # Get IP address if assigned
    IP_ADDR=$(ip addr show $interface | grep -o 'inet [0-9.]*' | cut -d' ' -f2 | head -1)
    if [[ -n "$IP_ADDR" ]]; then
        echo "  IP Address: $IP_ADDR"
    else
        echo "  IP Address: Not assigned"
    fi
    
    # Get MAC address
    MAC_ADDR=$(ip link show $interface | grep -o 'link/ether [a-f0-9:]*' | cut -d' ' -f2)
    if [[ -n "$MAC_ADDR" ]]; then
        echo "  MAC Address: $MAC_ADDR"
    fi
    
    # Get interface speed if available
    SPEED=$(ethtool $interface 2>/dev/null | grep -o 'Speed: [0-9]*' | cut -d' ' -f2)
    if [[ -n "$SPEED" ]]; then
        echo "  Speed: ${SPEED}Mb/s"
    fi
    
    # Get interface type (physical/virtual)
    if [[ -e "/sys/class/net/$interface/device" ]]; then
        echo "  Type: Physical"
    else
        echo "  Type: Virtual"
    fi
    
    echo ""
    COUNTER=$((COUNTER + 1))
done

print_header "Network Configuration Summary:"
echo ""

# Check if systemd-networkd is available
if command -v systemctl &> /dev/null && systemctl is-active --quiet systemd-networkd; then
    print_status "systemd-networkd is active"
    echo "  Configuration directory: /etc/systemd/network/"
    echo "  Current configuration files:"
    if [[ -d "/etc/systemd/network" ]]; then
        ls -la /etc/systemd/network/ 2>/dev/null || echo "    No configuration files found"
    fi
else
    print_warning "systemd-networkd is not active"
fi

# Check if NetworkManager is available
if command -v nmcli &> /dev/null; then
    print_status "NetworkManager is available"
    echo "  Active connections:"
    nmcli connection show --active 2>/dev/null || echo "    No active connections"
else
    print_warning "NetworkManager is not available"
fi

print_header "Recommended Configuration:"
echo ""
echo "Based on your requirements, you should configure:"
echo ""
echo "1. Internet NIC (Primary):"
echo "   - Purpose: Internet access and external communication"
echo "   - Configuration: DHCP or static IP"
echo "   - Network: Your local network (e.g., 192.168.1.0/24)"
echo ""
echo "2. 10Gbit NIC (Secondary):"
echo "   - Purpose: High-speed connection to Synology NAS"
echo "   - Configuration: Static IP on dedicated network"
echo "   - Network: Dedicated network (e.g., 10.0.0.0/24)"
echo "   - Gateway: None (direct connection)"
echo ""

print_status "Next steps:"
echo "1. Identify which interface is which (check MAC addresses or labels)"
echo "2. Run configure_dual_nic.sh to set up the network configuration"
echo "3. Run setup_nfs_mount.sh to configure NFS mounting"

# Save interface list to file for other scripts
echo "$INTERFACES" > /tmp/detected_interfaces.txt
print_status "Interface list saved to /tmp/detected_interfaces.txt" 