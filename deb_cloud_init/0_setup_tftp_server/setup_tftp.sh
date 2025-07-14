#!/bin/bash

# PXE TFTP Server Setup Script
# This script sets up the TFTP server and extracts boot files from the ISO

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

# Create TFTP directory structure
create_tftp_structure() {
    print_status "INFO" "Creating TFTP directory structure..."
    
    # Create main TFTP directory
    mkdir -p /var/lib/tftpboot
    
    # Create PXE boot directories
    mkdir -p /var/lib/tftpboot/pxelinux.cfg
    mkdir -p /var/lib/tftpboot/hardware-detect
    
    # Set proper permissions
    chown -R nobody:nobody /var/lib/tftpboot
    chmod -R 755 /var/lib/tftpboot
    
    print_status "SUCCESS" "TFTP directory structure created"
}

# Copy syslinux files
copy_syslinux_files() {
    print_status "INFO" "Copying syslinux boot files..."
    
    # Copy PXE boot loader
    cp /usr/share/syslinux/pxelinux.0 /var/lib/tftpboot/
    
    # Copy menu files
    cp /usr/share/syslinux/menu.c32 /var/lib/tftpboot/
    cp /usr/share/syslinux/vesamenu.c32 /var/lib/tftpboot/
    cp /usr/share/syslinux/libcom32.c32 /var/lib/tftpboot/
    cp /usr/share/syslinux/libutil.c32 /var/lib/tftpboot/
    cp /usr/share/syslinux/ldlinux.c32 /var/lib/tftpboot/
    
    # Set permissions
    chown nobody:nobody /var/lib/tftpboot/*
    chmod 644 /var/lib/tftpboot/*
    
    print_status "SUCCESS" "Syslinux files copied"
}

# Find hardware detection ISO
find_iso() {
    print_status "INFO" "Looking for hardware detection ISO..."
    
    # Look in common locations
    local iso_locations=(
        "../output/*.iso"
        "../1_iso_image_for_hardware_detection/output/*.iso"
        "*.iso"
    )
    
    for pattern in "${iso_locations[@]}"; do
        local files=($pattern)
        if [ ${#files[@]} -gt 0 ] && [ -f "${files[0]}" ]; then
            ISO_FILE="${files[0]}"
            print_status "SUCCESS" "Found ISO: $ISO_FILE"
            return 0
        fi
    done
    
    print_status "ERROR" "Hardware detection ISO not found"
    echo "Please build the ISO first using the hardware detection build script"
    exit 1
}

# Extract boot files from ISO
extract_boot_files() {
    print_status "INFO" "Extracting boot files from ISO..."
    
    # Create temporary mount point
    local mount_point="/tmp/iso_mount"
    mkdir -p "$mount_point"
    
    # Mount ISO
    mount -o loop "$ISO_FILE" "$mount_point"
    
    # Copy boot files
    print_status "INFO" "Copying kernel and initrd..."
    cp "$mount_point/live/vmlinuz" /var/lib/tftpboot/hardware-detect/
    cp "$mount_point/live/initrd.img" /var/lib/tftpboot/hardware-detect/
    
    # Copy filesystem
    print_status "INFO" "Copying filesystem..."
    cp "$mount_point/live/filesystem.squashfs" /var/lib/tftpboot/hardware-detect/
    
    # Copy hardware detection scripts
    if [ -d "$mount_point/live" ]; then
        mkdir -p /var/lib/tftpboot/hardware-detect/scripts
        # We'll create these scripts separately
    fi
    
    # Unmount ISO
    umount "$mount_point"
    rmdir "$mount_point"
    
    # Set permissions
    chown -R nobody:nobody /var/lib/tftpboot/hardware-detect
    chmod -R 644 /var/lib/tftpboot/hardware-detect/*
    chmod 755 /var/lib/tftpboot/hardware-detect/scripts
    
    print_status "SUCCESS" "Boot files extracted"
}

# Create PXE boot menu
create_pxe_menu() {
    print_status "INFO" "Creating PXE boot menu..."
    
    cat > /var/lib/tftpboot/pxelinux.cfg/default << EOF
# PXE Boot Menu for Hardware Detection
DEFAULT vesamenu.c32
PROMPT 0
MENU TITLE Hardware Detection PXE Boot
MENU BACKGROUND splash.png
TIMEOUT 300

# Hardware Detection Options
LABEL auto-detect
        MENU LABEL ^Auto Hardware Detection
        MENU DEFAULT
        KERNEL hardware-detect/vmlinuz
        APPEND initrd=hardware-detect/initrd.img boot=live components username=live hostname=hardware-detect

LABEL manual-detect
        MENU LABEL ^Manual Hardware Detection
        KERNEL hardware-detect/vmlinuz
        APPEND initrd=hardware-detect/initrd.img boot=live components username=live hostname=hardware-detect manual=true

LABEL live-failsafe
        MENU LABEL ^Live System (failsafe)
        KERNEL hardware-detect/vmlinuz
        APPEND initrd=hardware-detect/initrd.img boot=live components memtest noapic noapm nodma nomce nolapic nomodeset nosmp nosplash vga=normal

LABEL memtest
        MENU LABEL ^Memory test
        KERNEL memtest

LABEL hd
        MENU LABEL ^Boot from first hard disk
        LOCALBOOT 0x80

# Help
LABEL help
        MENU LABEL ^Help
        KERNEL vesamenu.c32
        APPEND pxelinux.cfg/help.cfg
EOF
    
    # Create help menu
    cat > /var/lib/tftpboot/pxelinux.cfg/help.cfg << EOF
# PXE Boot Help
DEFAULT vesamenu.c32
PROMPT 0
MENU TITLE Hardware Detection Help

LABEL back
        MENU LABEL ^Back to main menu
        KERNEL vesamenu.c32
        APPEND pxelinux.cfg/default

MENU HELP
Hardware Detection PXE Boot Help

Auto Hardware Detection:
  - Automatically detects hardware
  - Sends report via email
  - Shuts down after detection

Manual Hardware Detection:
  - Interactive hardware detection
  - Manual email configuration
  - Option to continue after detection

Live System (failsafe):
  - Boot with minimal options
  - Use if auto-detection fails
  - Safe mode boot

Memory test:
  - Test system memory
  - Useful for troubleshooting

Boot from hard disk:
  - Boot normally from local storage
  - Skip hardware detection
ENDHELP
EOF
    
    # Set permissions
    chown nobody:nobody /var/lib/tftpboot/pxelinux.cfg/*
    chmod 644 /var/lib/tftpboot/pxelinux.cfg/*
    
    print_status "SUCCESS" "PXE boot menu created"
}

# Configure TFTP server
configure_tftp_server() {
    print_status "INFO" "Configuring TFTP server..."
    
    # Detect TFTP server type
    if systemctl list-unit-files | grep -q "tftp"; then
        # systemd tftp server
        print_status "INFO" "Using systemd TFTP server"
        
        # Enable and start TFTP server
        systemctl enable tftp.socket
        systemctl start tftp.socket
        
    elif command -v in.tftpd >/dev/null 2>&1; then
        # Debian/Ubuntu tftpd-hpa
        print_status "INFO" "Using tftpd-hpa"
        
        # Configure tftpd-hpa
        cat > /etc/default/tftpd-hpa << EOF
# /etc/default/tftpd-hpa

TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
RUN_DAEMON="yes"
OPTIONS="-l -s /var/lib/tftpboot"
EOF
        
        # Enable and start service
        systemctl enable tftpd-hpa
        systemctl start tftpd-hpa
        
    else
        print_status "ERROR" "TFTP server not found"
        exit 1
    fi
    
    print_status "SUCCESS" "TFTP server configured"
}

# Test TFTP server
test_tftp_server() {
    print_status "INFO" "Testing TFTP server..."
    
    # Wait for service to start
    sleep 2
    
    # Test TFTP connection
    if timeout 5 bash -c "</dev/tcp/localhost/69" 2>/dev/null; then
        print_status "SUCCESS" "TFTP server is running"
    else
        print_status "ERROR" "TFTP server is not responding"
        exit 1
    fi
    
    # Test file access
    if timeout 5 tftp localhost -c get pxelinux.0 /tmp/test_pxe 2>/dev/null; then
        print_status "SUCCESS" "TFTP file access working"
        rm -f /tmp/test_pxe
    else
        print_status "WARNING" "TFTP file access test failed"
    fi
}

# Create hardware detection scripts
create_hardware_scripts() {
    print_status "INFO" "Creating hardware detection scripts..."
    
    # Create auto-detection script
    cat > /var/lib/tftpboot/hardware-detect/scripts/auto-detect.sh << 'EOF'
#!/bin/bash
# Auto hardware detection script for PXE boot

set -e

echo "=== PXE Hardware Detection ==="
echo "Starting automatic hardware detection..."
echo ""

# Wait for network
echo "Waiting for network connectivity..."
for i in {1..60}; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "Network connectivity established"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "Warning: Network connectivity not established"
    fi
    sleep 1
done

# Run hardware detection
echo "Starting hardware detection..."
/usr/local/bin/hardware_detect.sh

echo ""
echo "Hardware detection completed."
echo "Check your email for the hardware report."
echo ""
echo "Press Enter to shutdown or Ctrl+C to continue..."
read -r

# Shutdown the system
echo "Shutting down..."
shutdown -h now
EOF
    
    chmod +x /var/lib/tftpboot/hardware-detect/scripts/auto-detect.sh
    chown nobody:nobody /var/lib/tftpboot/hardware-detect/scripts/auto-detect.sh
    
    print_status "SUCCESS" "Hardware detection scripts created"
}

# Show setup summary
show_summary() {
    echo ""
    print_status "SUCCESS" "TFTP server setup completed!"
    echo ""
    echo "Setup Summary:"
    echo "  TFTP Directory: /var/lib/tftpboot"
    echo "  Boot Files: /var/lib/tftpboot/hardware-detect/"
    echo "  PXE Menu: /var/lib/tftpboot/pxelinux.cfg/default"
    echo "  ISO Source: $ISO_FILE"
    echo ""
    echo "Files extracted:"
    echo "  - vmlinuz (kernel)"
    echo "  - initrd.img (initial ramdisk)"
    echo "  - filesystem.squashfs (root filesystem)"
    echo ""
    echo "Next steps:"
    echo "  1. Configure dnsmasq: ./configure_dnsmasq.sh"
    echo "  2. Start services: ./start_services.sh"
    echo "  3. Test PXE boot: ./test_pxe.sh"
    echo ""
}

# Main execution
main() {
    echo "=== PXE TFTP Server Setup ==="
    echo ""
    
    # Check root privileges
    check_root
    
    # Load network configuration
    load_network_config
    
    # Create TFTP structure
    create_tftp_structure
    
    # Copy syslinux files
    copy_syslinux_files
    
    # Find and extract ISO
    find_iso
    extract_boot_files
    
    # Create PXE menu
    create_pxe_menu
    
    # Configure TFTP server
    configure_tftp_server
    
    # Create hardware scripts
    create_hardware_scripts
    
    # Test TFTP server
    test_tftp_server
    
    # Show summary
    show_summary
}

# Run main function
main "$@" 