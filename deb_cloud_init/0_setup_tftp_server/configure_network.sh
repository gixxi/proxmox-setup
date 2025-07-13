#!/bin/bash

# PXE TFTP Server Network Configuration Script
# This script configures the network interface for PXE server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_status "ERROR" "This script must be run as root"
        echo "Use: sudo $0"
        exit 1
    fi
}

# Show current network interfaces
show_interfaces() {
    print_status "INFO" "Current network interfaces:"
    echo ""
    ip addr show | grep -E "^[0-9]+:|inet " | grep -v "127.0.0.1" | sed 's/^/  /'
    echo ""
}

# Get network interface
get_interface() {
    local interfaces=()
    
    # Get all interfaces except loopback
    while IFS= read -r line; do
        if [[ $line =~ ^[0-9]+:[[:space:]]+([^:]+): ]]; then
            interface="${BASH_REMATCH[1]}"
            if [ "$interface" != "lo" ]; then
                interfaces+=("$interface")
            fi
        fi
    done < <(ip addr show)
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        print_status "ERROR" "No network interfaces found"
        exit 1
    fi
    
    if [ ${#interfaces[@]} -eq 1 ]; then
        INTERFACE="${interfaces[0]}"
        print_status "INFO" "Using interface: $INTERFACE"
    else
        echo "Available interfaces:"
        for i in "${!interfaces[@]}"; do
            echo "  $((i+1)). ${interfaces[$i]}"
        done
        echo ""
        read -p "Select interface (1-${#interfaces[@]}): " choice
        
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#interfaces[@]} ]; then
            print_status "ERROR" "Invalid selection"
            exit 1
        fi
        
        INTERFACE="${interfaces[$((choice-1))]}"
        print_status "INFO" "Selected interface: $INTERFACE"
    fi
}

# Get network configuration
get_network_config() {
    print_status "INFO" "Network configuration for PXE server"
    echo ""
    
    # Get current IP
    CURRENT_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$CURRENT_IP" ]; then
        print_status "INFO" "Current IP: $CURRENT_IP"
        read -p "Use current IP? (Y/n): " use_current
        if [[ ! "$use_current" =~ ^[Nn]$ ]]; then
            PXE_IP="$CURRENT_IP"
            return
        fi
    fi
    
    # Get new IP
    read -p "Enter PXE server IP address: " PXE_IP
    if [ -z "$PXE_IP" ]; then
        print_status "ERROR" "IP address is required"
        exit 1
    fi
    
    # Validate IP format
    if [[ ! "$PXE_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_status "ERROR" "Invalid IP address format"
        exit 1
    fi
}

# Get DHCP range
get_dhcp_range() {
    print_status "INFO" "DHCP configuration"
    echo ""
    
    # Calculate DHCP range from PXE IP
    IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$PXE_IP"
    DHCP_START="$ip1.$ip2.$ip3.100"
    DHCP_END="$ip1.$ip2.$ip3.200"
    
    echo "Suggested DHCP range: $DHCP_START - $DHCP_END"
    read -p "Use suggested range? (Y/n): " use_suggested
    
    if [[ "$use_suggested" =~ ^[Nn]$ ]]; then
        read -p "Enter DHCP start IP: " DHCP_START
        read -p "Enter DHCP end IP: " DHCP_END
        
        if [ -z "$DHCP_START" ] || [ -z "$DHCP_END" ]; then
            print_status "ERROR" "DHCP range is required"
            exit 1
        fi
    fi
}

# Configure static IP
configure_static_ip() {
    print_status "INFO" "Configuring static IP..."
    
    # Detect network manager
    if command -v nmcli >/dev/null 2>&1; then
        # NetworkManager
        print_status "INFO" "Using NetworkManager"
        
        # Get connection name
        CONNECTION=$(nmcli -t -f DEVICE,TYPE,CONNECTION dev | grep "$INTERFACE" | cut -d: -f3)
        if [ -z "$CONNECTION" ]; then
            print_status "INFO" "No NetworkManager connection found for $INTERFACE"
            print_status "INFO" "Creating new connection..."
            
            # Create new connection
            nmcli con add type ethernet con-name "PXE-$INTERFACE" ifname "$INTERFACE"
            CONNECTION="PXE-$INTERFACE"
        fi
        
        # Configure static IP
        nmcli con mod "$CONNECTION" ipv4.addresses "$PXE_IP/24"
        nmcli con mod "$CONNECTION" ipv4.method manual
        nmcli con down "$CONNECTION" 2>/dev/null || true
        nmcli con up "$CONNECTION"
        
    elif [ -f /etc/network/interfaces ]; then
        # Debian/Ubuntu networking
        print_status "INFO" "Using /etc/network/interfaces"
        
        # Backup original
        cp /etc/network/interfaces /etc/network/interfaces.backup
        
        # Add static configuration
        cat >> /etc/network/interfaces << EOF

# PXE Server Configuration
auto $INTERFACE
iface $INTERFACE inet static
    address $PXE_IP
    netmask 255.255.255.0
    network $ip1.$ip2.$ip3.0
    broadcast $ip1.$ip2.$ip3.255
EOF
        
        # Restart networking
        systemctl restart networking
        
    else
        print_status "WARNING" "Unknown network configuration method"
        print_status "INFO" "Please configure static IP manually:"
        echo "  IP: $PXE_IP"
        echo "  Netmask: 255.255.255.0"
        echo "  Interface: $INTERFACE"
    fi
    
    print_status "SUCCESS" "Static IP configured"
}

# Test network connectivity
test_connectivity() {
    print_status "INFO" "Testing network connectivity..."
    
    # Wait for interface to be ready
    sleep 3
    
    # Test IP configuration
    if ip addr show $INTERFACE | grep -q "$PXE_IP"; then
        print_status "SUCCESS" "IP address configured correctly"
    else
        print_status "ERROR" "IP address not configured"
        exit 1
    fi
    
    # Test basic connectivity
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        print_status "SUCCESS" "Internet connectivity confirmed"
    else
        print_status "WARNING" "No internet connectivity - this is normal for isolated networks"
    fi
}

# Create configuration file
create_config() {
    print_status "INFO" "Creating network configuration file..."
    
    cat > network_config.env << EOF
# PXE Server Network Configuration
PXE_INTERFACE=$INTERFACE
PXE_IP=$PXE_IP
DHCP_START=$DHCP_START
DHCP_END=$DHCP_END
NETWORK=$ip1.$ip2.$ip3.0
NETMASK=255.255.255.0
BROADCAST=$ip1.$ip2.$ip3.255
EOF
    
    print_status "SUCCESS" "Network configuration saved to network_config.env"
}

# Show configuration summary
show_summary() {
    echo ""
    print_status "SUCCESS" "Network configuration completed!"
    echo ""
    echo "Configuration Summary:"
    echo "  Interface: $INTERFACE"
    echo "  PXE Server IP: $PXE_IP"
    echo "  DHCP Range: $DHCP_START - $DHCP_END"
    echo "  Network: $ip1.$ip2.$ip3.0/24"
    echo ""
    echo "Next steps:"
    echo "  1. Setup TFTP server: ./setup_tftp.sh"
    echo "  2. Configure dnsmasq: ./configure_dnsmasq.sh"
    echo "  3. Start services: ./start_services.sh"
    echo ""
}

# Main execution
main() {
    echo "=== PXE TFTP Server Network Configuration ==="
    echo ""
    
    # Check root privileges
    check_root
    
    # Show current interfaces
    show_interfaces
    
    # Get interface
    get_interface
    
    # Get network configuration
    get_network_config
    
    # Get DHCP range
    get_dhcp_range
    
    # Configure static IP
    configure_static_ip
    
    # Test connectivity
    test_connectivity
    
    # Create configuration file
    create_config
    
    # Show summary
    show_summary
}

# Run main function
main "$@" 