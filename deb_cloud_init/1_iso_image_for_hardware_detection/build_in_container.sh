#!/bin/bash

# Build Debian Live ISO in Container
# This script builds the hardware detection ISO inside a Debian container
# Useful when building on non-Debian systems like Fedora

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="debian-iso-builder"
DEBIAN_IMAGE="debian:bookworm-slim"
OUTPUT_DIR="$SCRIPT_DIR/output"

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
    echo "Debian Live ISO Builder (Container Version)"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --clean         Clean previous build artifacts and container"
    echo "  -v, --verbose       Enable verbose output"
    echo "  -e, --email EMAIL   Set email address for hardware reports"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Build with default settings"
    echo "  $0 --clean                           # Clean and build"
    echo "  $0 --email admin@example.com         # Set email address"
    echo ""
    echo "This script builds a Debian Live ISO inside a Debian container."
    echo "Useful when building on non-Debian systems like Fedora."
}

# Parse command line arguments
CLEAN_BUILD=false
VERBOSE=false
EMAIL_ADDRESS=""

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
        -e|--email)
            if [ -z "$2" ]; then
                print_status "ERROR" "Email address not specified for -e/--email"
                show_usage
                exit 1
            fi
            EMAIL_ADDRESS="$2"
            shift 2
            ;;
        *)
            print_status "ERROR" "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate parameters
validate_parameters() {
    print_status "INFO" "Validating parameters..."
    
    # Validate email address format if provided
    if [ -n "$EMAIL_ADDRESS" ]; then
        if [[ ! "$EMAIL_ADDRESS" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            print_status "ERROR" "Invalid email address format: $EMAIL_ADDRESS"
            exit 1
        fi
        print_status "SUCCESS" "Email address format validated: $EMAIL_ADDRESS"
    fi
    
    print_status "SUCCESS" "Parameter validation completed"
}

# Check prerequisites
check_prerequisites() {
    print_status "INFO" "Checking prerequisites..."
    
    # Check if podman is available
    if ! command -v podman >/dev/null 2>&1; then
        print_status "ERROR" "Podman is not installed. Please install podman first."
        exit 1
    fi
    
    # Check if we can run containers
    if ! podman info >/dev/null 2>&1; then
        print_status "ERROR" "Cannot run podman. Make sure podman is properly configured."
        exit 1
    fi
    
    print_status "SUCCESS" "Prerequisites check completed"
}

# Clean previous build
clean_build() {
    if [ "$CLEAN_BUILD" = true ]; then
        print_status "INFO" "Cleaning previous build artifacts..."
        
        # Stop and remove existing container
        if podman ps -a --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
            print_status "INFO" "Removing existing container: $CONTAINER_NAME"
            podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
        fi
        
        # Clean output directory
        if [ -d "$OUTPUT_DIR" ]; then
            rm -rf "$OUTPUT_DIR"
        fi
        
        print_status "SUCCESS" "Build artifacts cleaned"
    fi
}

# Update email configuration
update_email_config() {
    if [ -n "$EMAIL_ADDRESS" ]; then
        print_status "INFO" "Updating email configuration..."
        
        # Create backup of original email config
        if [ -f "$SCRIPT_DIR/email_config.sh" ]; then
            cp "$SCRIPT_DIR/email_config.sh" "$SCRIPT_DIR/email_config.sh.backup"
        fi
        
        # Update email address in hardware detection script
        if [ -f "$SCRIPT_DIR/hardware_detect.sh" ]; then
            sed -i "s/EMAIL_ADDRESS=.*/EMAIL_ADDRESS=\"$EMAIL_ADDRESS\"/" "$SCRIPT_DIR/hardware_detect.sh"
            print_status "SUCCESS" "Email address updated to: $EMAIL_ADDRESS"
        fi
    fi
}

# Create output directory
setup_output() {
    mkdir -p "$OUTPUT_DIR"
    print_status "INFO" "Output directory: $OUTPUT_DIR"
}

# Build the ISO in container
build_iso() {
    print_status "INFO" "Starting ISO build in Debian container..."
    
    # Create container and build ISO
    podman run --rm \
        --name "$CONTAINER_NAME" \
        --privileged \
        -v "$SCRIPT_DIR:/workspace:Z" \
        -v "$OUTPUT_DIR:/output:Z" \
        -w /workspace \
        "$DEBIAN_IMAGE" \
        bash -c "
            # Update package lists
            apt-get update
            
            # Install required packages
            apt-get install -y live-build live-config live-boot live-tools \
                debootstrap squashfs-tools xorriso isolinux syslinux-common \
                syslinux-efi grub-pc-bin grub-efi-amd64-bin mtools dosfstools \
                rsync curl wget
            
            # Ensure workspace directory has proper permissions but preserve ownership
            chmod 755 /workspace
            
            # Make build script executable 
            chmod +x debian_live_config/build_iso.sh
            
            # Run the build
            ./debian_live_config/build_iso.sh
            
            # Copy ISO to output directory
            if [ -f output/*.iso ]; then
                cp output/*.iso /output/
                echo 'ISO copied to output directory'
            else
                echo 'ERROR: ISO not found'
                exit 1
            fi
        "
    
    if [ $? -eq 0 ]; then
        print_status "SUCCESS" "ISO build completed successfully!"
    else
        print_status "ERROR" "ISO build failed"
        exit 1
    fi
}

# Restore email configuration
restore_email_config() {
    if [ -n "$EMAIL_ADDRESS" ] && [ -f "$SCRIPT_DIR/email_config.sh.backup" ]; then
        print_status "INFO" "Restoring original email configuration..."
        mv "$SCRIPT_DIR/email_config.sh.backup" "$SCRIPT_DIR/email_config.sh"
    fi
}

# Show final information
show_final_info() {
    echo ""
    print_status "SUCCESS" "Hardware Detection ISO build completed!"
    echo ""
    echo "Next steps:"
    echo "  1. Burn the ISO to USB or CD:"
    echo "     sudo dd if=$OUTPUT_DIR/*.iso of=/dev/sdX bs=4M status=progress"
    echo ""
    echo "  2. Boot from the ISO on target hardware"
    echo ""
    echo "  3. The system will automatically:"
    echo "     - Detect hardware components"
    echo "     - Generate detailed report"
    echo "     - Send report via email"
    echo ""
    echo "  4. For manual detection, run:"
    echo "     /usr/local/bin/hardware_detect.sh"
    echo ""
    echo "Output directory: $OUTPUT_DIR"
}

# Main execution
main() {
    echo "=== Debian Live ISO Builder (Container Version) ==="
    echo ""
    
    # Validate parameters
    validate_parameters
    
    # Check prerequisites
    check_prerequisites
    
    # Clean build if requested
    clean_build
    
    # Update email configuration
    update_email_config
    
    # Set up output directory
    setup_output
    
    # Build the ISO
    build_iso
    
    # Restore email configuration
    restore_email_config
    
    # Show final information
    show_final_info
}

# Run main function
main "$@" 