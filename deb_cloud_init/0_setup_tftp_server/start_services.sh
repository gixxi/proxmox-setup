#!/bin/bash

# PXE TFTP Server Service Startup Script
# This script starts and manages the PXE server services

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

# Load network configuration
load_network_config() {
    if [ -f "network_config.env" ]; then
        print_status "INFO" "Loading network configuration..."
        source network_config.env
    else
        print_status "ERROR" "Network configuration not found"
        echo "Please run ./configure_network.sh first"
        exit 1
    fi
}

# Check service dependencies
check_dependencies() {
    print_status "INFO" "Checking service dependencies..."
    
    # Check if dnsmasq is installed
    if ! command -v dnsmasq >/dev/null 2>&1; then
        print_status "ERROR" "dnsmasq is not installed"
        echo "Please run ./install_packages.sh first"
        exit 1
    fi
    
    # Check if TFTP files exist
    if [ ! -f /var/lib/tftpboot/pxelinux.0 ]; then
        print_status "ERROR" "TFTP boot files not found"
        echo "Please run ./setup_tftp.sh first"
        exit 1
    fi
    
    # Check if dnsmasq config exists
    if [ ! -f /etc/dnsmasq.conf ]; then
        print_status "ERROR" "dnsmasq configuration not found"
        echo "Please run ./configure_dnsmasq.sh first"
        exit 1
    fi
    
    print_status "SUCCESS" "All dependencies satisfied"
}

# Stop conflicting services
stop_conflicting_services() {
    print_status "INFO" "Stopping conflicting services..."
    
    # Stop other DHCP servers
    local conflicting_services=(
        "dhcpd"
        "isc-dhcp-server"
        "systemd-networkd"
    )
    
    for service in "${conflicting_services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            print_status "WARNING" "Stopping conflicting service: $service"
            systemctl stop "$service" 2>/dev/null || true
        fi
    done
    
    print_status "SUCCESS" "Conflicting services stopped"
}

# Start TFTP server
start_tftp_server() {
    print_status "INFO" "Starting TFTP server..."
    
    # Enable and start TFTP socket
    systemctl enable tftp.socket
    systemctl start tftp.socket
    
    # Wait for service to start
    sleep 2
    
    # Check if TFTP is running
    if systemctl is-active --quiet tftp.socket; then
        print_status "SUCCESS" "TFTP server started"
    else
        print_status "ERROR" "Failed to start TFTP server"
        exit 1
    fi
}

# Start dnsmasq
start_dnsmasq() {
    print_status "INFO" "Starting dnsmasq..."
    
    # Enable and start dnsmasq
    systemctl enable dnsmasq
    systemctl start dnsmasq
    
    # Wait for service to start
    sleep 2
    
    # Check if dnsmasq is running
    if systemctl is-active --quiet dnsmasq; then
        print_status "SUCCESS" "dnsmasq started"
    else
        print_status "ERROR" "Failed to start dnsmasq"
        systemctl status dnsmasq
        exit 1
    fi
}

# Test services
test_services() {
    print_status "INFO" "Testing services..."
    
    # Test TFTP server
    if timeout 5 bash -c "</dev/tcp/localhost/69" 2>/dev/null; then
        print_status "SUCCESS" "TFTP server is responding"
    else
        print_status "ERROR" "TFTP server is not responding"
        exit 1
    fi
    
    # Test dnsmasq
    if timeout 5 bash -c "</dev/tcp/localhost/53" 2>/dev/null; then
        print_status "SUCCESS" "dnsmasq DNS is responding"
    else
        print_status "WARNING" "dnsmasq DNS is not responding"
    fi
    
    # Test DHCP (this is harder to test without a client)
    print_status "INFO" "DHCP service is running (will be tested when client connects)"
}

# Show service status
show_service_status() {
    echo ""
    print_status "INFO" "Service Status:"
    echo ""
    
    # TFTP status
    if systemctl is-active --quiet tftp.socket; then
        echo "  TFTP Server: ${GREEN}RUNNING${NC}"
    else
        echo "  TFTP Server: ${RED}STOPPED${NC}"
    fi
    
    # dnsmasq status
    if systemctl is-active --quiet dnsmasq; then
        echo "  dnsmasq: ${GREEN}RUNNING${NC}"
    else
        echo "  dnsmasq: ${RED}STOPPED${NC}"
    fi
    
    # Network interface status
    if ip addr show $PXE_INTERFACE | grep -q "inet.*$PXE_IP"; then
        echo "  Network Interface: ${GREEN}CONFIGURED${NC}"
    else
        echo "  Network Interface: ${RED}NOT CONFIGURED${NC}"
    fi
}

# Show usage information
show_usage_info() {
    echo ""
    print_status "SUCCESS" "PXE TFTP Server is now running!"
    echo ""
    echo "Server Information:"
    echo "  PXE Server IP: $PXE_IP"
    echo "  DHCP Range: $DHCP_START - $DHCP_END"
    echo "  TFTP Root: /var/lib/tftpboot"
    echo ""
    echo "To boot a client:"
    echo "  1. Connect client to the same network"
    echo "  2. Enable PXE boot in BIOS/UEFI"
    echo "  3. Set network boot as first option"
    echo "  4. Power on the client"
    echo "  5. Select boot option from PXE menu"
    echo ""
    echo "Useful commands:"
    echo "  Check DHCP leases: cat /var/lib/misc/dnsmasq.leases"
    echo "  Check dnsmasq logs: journalctl -u dnsmasq -f"
    echo "  Check TFTP logs: journalctl -u tftp -f"
    echo "  Stop services: systemctl stop dnsmasq tftp.socket"
    echo ""
}

# Main execution
main() {
    echo "=== PXE TFTP Server Service Startup ==="
    echo ""
    
    # Check root privileges
    check_root
    
    # Load network configuration
    load_network_config
    
    # Check dependencies
    check_dependencies
    
    # Stop conflicting services
    stop_conflicting_services
    
    # Start TFTP server
    start_tftp_server
    
    # Start dnsmasq
    start_dnsmasq
    
    # Test services
    test_services
    
    # Show status
    show_service_status
    
    # Show usage information
    show_usage_info
}

# Run main function
main "$@" 