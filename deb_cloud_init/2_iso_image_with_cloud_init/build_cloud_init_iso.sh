#!/bin/bash

# Cloud-Init Deployment ISO Builder
# This script builds a Debian Live ISO for cloud-init based server deployment

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/debian_live_config/build_iso.sh"
OUTPUT_DIR="$SCRIPT_DIR/output"
LOG_FILE="$SCRIPT_DIR/build.log"

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

# Show usage
show_usage() {
    echo "Cloud-Init Deployment ISO Builder"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --clean         Clean previous build artifacts"
    echo "  -v, --verbose       Enable verbose output"
    echo "  -o, --output DIR    Set output directory (default: ./output)"
    echo "  -k, --ssh-key FILE  Set SSH public key file for admin user"
    echo "  -w, --workload USER Create workload user with specified name"
    echo "  -p, --password      Set root password (interactive)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Build with default settings"
    echo "  $0 --clean                           # Clean and build"
    echo "  $0 --ssh-key ~/.ssh/id_rsa.pub       # Set SSH key for admin"
    echo "  $0 --workload myapp                  # Create workload user 'myapp'"
    echo "  $0 --output /path/to/output          # Set custom output directory"
    echo "  $0 --password                        # Set root password interactively"
    echo ""
    echo "This script builds a Debian Live ISO that:"
    echo "  - Installs Debian with cloud-init"
    echo "  - Configures ZFS storage"
    echo "  - Sets up Docker and networking"
    echo "  - Creates admin and workload users"
    echo "  - Configures security and firewall"
    echo "  - Supports automated server deployment"
}

# Parse command line arguments
CLEAN_BUILD=false
VERBOSE=false
CUSTOM_OUTPUT=""
SSH_KEY_FILE=""
WORKLOAD_USER=""
SET_PASSWORD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -o|--output)
            CUSTOM_OUTPUT="$2"
            shift 2
            ;;
        -k|--ssh-key)
            SSH_KEY_FILE="$2"
            shift 2
            ;;
        -w|--workload)
            WORKLOAD_USER="$2"
            shift 2
            ;;
        -p|--password)
            SET_PASSWORD=true
            shift
            ;;
        *)
            print_status "ERROR" "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_status "ERROR" "This script must be run as root"
        echo "Use: sudo $0 [OPTIONS]"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_status "INFO" "Checking prerequisites..."
    
    # Check if build script exists
    if [ ! -f "$BUILD_SCRIPT" ]; then
        print_status "ERROR" "Build script not found: $BUILD_SCRIPT"
        exit 1
    fi
    
    # Check if cloud-init templates exist
    if [ ! -d "$SCRIPT_DIR/cloud_init_templates" ]; then
        print_status "ERROR" "Cloud-init templates not found: $SCRIPT_DIR/cloud_init_templates"
        exit 1
    fi
    
    # Check if scripts directory exists
    if [ ! -d "$SCRIPT_DIR/scripts" ]; then
        print_status "ERROR" "Scripts directory not found: $SCRIPT_DIR/scripts"
        exit 1
    fi
    
    # Check SSH key file if specified
    if [ -n "$SSH_KEY_FILE" ] && [ ! -f "$SSH_KEY_FILE" ]; then
        print_status "ERROR" "SSH key file not found: $SSH_KEY_FILE"
        exit 1
    fi
    
    print_status "SUCCESS" "Prerequisites check completed"
}

# Clean previous build
clean_build() {
    if [ "$CLEAN_BUILD" = true ]; then
        print_status "INFO" "Cleaning previous build artifacts..."
        
        # Clean build directory
        if [ -d "/tmp/debian-cloud-init-build" ]; then
            rm -rf /tmp/debian-cloud-init-build
        fi
        
        # Clean output directory
        if [ -d "$OUTPUT_DIR" ]; then
            rm -rf "$OUTPUT_DIR"
        fi
        
        print_status "SUCCESS" "Build artifacts cleaned"
    fi
}

# Update SSH key configuration
update_ssh_config() {
    if [ -n "$SSH_KEY_FILE" ]; then
        print_status "INFO" "Updating SSH key configuration..."
        
        # Read SSH public key
        local ssh_key=$(cat "$SSH_KEY_FILE")
        
        # Update base config template
        local base_config="$SCRIPT_DIR/cloud_init_templates/base_config.yml"
        if [ -f "$base_config" ]; then
            # Create backup
            cp "$base_config" "$base_config.backup"
            
            # Update SSH key
            sed -i "s|ssh-rsa YOUR_PUBLIC_KEY_HERE|$ssh_key|" "$base_config"
            print_status "SUCCESS" "SSH key updated in base configuration"
        fi
    fi
}

# Update workload user configuration
update_workload_config() {
    if [ -n "$WORKLOAD_USER" ]; then
        print_status "INFO" "Updating workload user configuration..."
        
        # Create workload user config if it doesn't exist
        local workload_config="$SCRIPT_DIR/cloud_init_templates/workload_user_config.yml"
        if [ ! -f "$workload_config" ]; then
            print_status "WARNING" "Workload user config not found, creating default..."
            cat > "$workload_config" << 'EOF'
#cloud-config
# Workload User Configuration Template
WORKLOAD_USERNAME: myapp

runcmd:
  - /usr/local/bin/create_workload_user.sh ${WORKLOAD_USERNAME}
EOF
        fi
        
        # Update workload username
        sed -i "s/WORKLOAD_USERNAME: .*/WORKLOAD_USERNAME: $WORKLOAD_USER/" "$workload_config"
        print_status "SUCCESS" "Workload user set to: $WORKLOAD_USER"
    fi
}

# Set root password
set_root_password() {
    if [ "$SET_PASSWORD" = true ]; then
        print_status "INFO" "Setting root password..."
        
        echo -n "Enter root password: "
        read -s ROOT_PASSWORD
        echo
        
        echo -n "Confirm root password: "
        read -s ROOT_PASSWORD_CONFIRM
        echo
        
        if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
            print_status "ERROR" "Passwords do not match"
            exit 1
        fi
        
        # Update base config template
        local base_config="$SCRIPT_DIR/cloud_init_templates/base_config.yml"
        if [ -f "$base_config" ]; then
            # Create backup
            cp "$base_config" "$base_config.backup"
            
            # Update root password
            sed -i "s/root:your_secure_root_password_here/root:$ROOT_PASSWORD/" "$base_config"
            print_status "SUCCESS" "Root password updated in configuration"
        fi
    fi
}

# Set output directory
setup_output() {
    if [ -n "$CUSTOM_OUTPUT" ]; then
        OUTPUT_DIR="$CUSTOM_OUTPUT"
    fi
    
    mkdir -p "$OUTPUT_DIR"
    print_status "INFO" "Output directory: $OUTPUT_DIR"
}

# Build the ISO
build_iso() {
    print_status "INFO" "Starting ISO build process..."
    
    # Set up logging
    if [ "$VERBOSE" = true ]; then
        # Run with verbose output
        "$BUILD_SCRIPT" 2>&1 | tee "$LOG_FILE"
    else
        # Run with progress output
        "$BUILD_SCRIPT" 2>&1 | tee "$LOG_FILE" | grep -E "(INFO|SUCCESS|WARNING|ERROR|Building|Creating|Configuring)"
    fi
    
    # Check if build was successful
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "ISO build completed successfully!"
    else
        print_status "ERROR" "ISO build failed. Check log file: $LOG_FILE"
        exit 1
    fi
}

# Copy ISO to output directory
copy_iso() {
    print_status "INFO" "Copying ISO to output directory..."
    
    # Find the generated ISO
    local iso_file=$(find /tmp/debian-cloud-init-build -name "*.iso" 2>/dev/null | head -1)
    
    if [ -n "$iso_file" ] && [ -f "$iso_file" ]; then
        cp "$iso_file" "$OUTPUT_DIR/"
        local iso_name=$(basename "$iso_file")
        print_status "SUCCESS" "ISO copied to: $OUTPUT_DIR/$iso_name"
        
        # Show file information
        echo ""
        print_status "INFO" "ISO Information:"
        echo "  File: $OUTPUT_DIR/$iso_name"
        echo "  Size: $(du -h "$OUTPUT_DIR/$iso_name" | cut -f1)"
        echo "  Created: $(date -r "$OUTPUT_DIR/$iso_name")"
    else
        print_status "ERROR" "Generated ISO not found"
        exit 1
    fi
}

# Restore configuration files
restore_config() {
    print_status "INFO" "Restoring configuration files..."
    
    # Restore base config
    if [ -f "$SCRIPT_DIR/cloud_init_templates/base_config.yml.backup" ]; then
        mv "$SCRIPT_DIR/cloud_init_templates/base_config.yml.backup" "$SCRIPT_DIR/cloud_init_templates/base_config.yml"
    fi
    
    print_status "SUCCESS" "Configuration files restored"
}

# Show final information
show_final_info() {
    echo ""
    print_status "SUCCESS" "Cloud-Init Deployment ISO build completed!"
    echo ""
    echo "Next steps:"
    echo "  1. Burn the ISO to USB or CD:"
    echo "     sudo dd if=$OUTPUT_DIR/*.iso of=/dev/sdX bs=4M status=progress"
    echo ""
    echo "  2. Boot from the ISO on target hardware"
    echo ""
    echo "  3. The system will automatically:"
    echo "     - Install Debian with cloud-init"
    echo "     - Configure ZFS storage"
    echo "     - Set up Docker and networking"
    echo "     - Create admin and workload users"
    echo "     - Configure security and firewall"
    echo ""
    echo "  4. After deployment, connect via SSH:"
    if [ -n "$SSH_KEY_FILE" ]; then
        echo "     ssh admin@<server-ip>"
    else
        echo "     ssh admin@<server-ip> (using default SSH key)"
    fi
    echo ""
    echo "Configuration:"
    if [ -n "$SSH_KEY_FILE" ]; then
        echo "  SSH Key: $SSH_KEY_FILE"
    fi
    if [ -n "$WORKLOAD_USER" ]; then
        echo "  Workload User: $WORKLOAD_USER"
    fi
    if [ "$SET_PASSWORD" = true ]; then
        echo "  Root Password: Set"
    fi
    echo ""
    echo "Log file: $LOG_FILE"
    echo "Output directory: $OUTPUT_DIR"
}

# Main execution
main() {
    echo "=== Cloud-Init Deployment ISO Builder ==="
    echo ""
    
    # Check root privileges
    check_root
    
    # Check prerequisites
    check_prerequisites
    
    # Clean build if requested
    clean_build
    
    # Update configurations
    update_ssh_config
    update_workload_config
    set_root_password
    
    # Set up output directory
    setup_output
    
    # Build the ISO
    build_iso
    
    # Copy ISO to output directory
    copy_iso
    
    # Restore configuration files
    restore_config
    
    # Show final information
    show_final_info
}

# Run main function
main "$@" 