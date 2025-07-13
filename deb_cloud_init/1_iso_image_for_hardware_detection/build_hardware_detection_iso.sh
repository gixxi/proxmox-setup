#!/bin/bash

# Hardware Detection ISO Builder
# This script builds a Debian Live ISO for hardware detection and email reporting

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
    echo "Hardware Detection ISO Builder"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --clean         Clean previous build artifacts"
    echo "  -v, --verbose       Enable verbose output"
    echo "  -o, --output DIR    Set output directory (default: ./output)"
    echo "  -e, --email EMAIL   Set email address for hardware reports"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Build with default settings"
    echo "  $0 --clean                           # Clean and build"
    echo "  $0 --email admin@example.com         # Set email address"
    echo "  $0 --output /path/to/output          # Set custom output directory"
    echo ""
    echo "This script builds a Debian Live ISO that:"
    echo "  - Detects hardware automatically on boot"
    echo "  - Sends hardware report via email"
    echo "  - Provides manual hardware detection tools"
    echo "  - Supports both automated and interactive modes"
}

# Parse command line arguments
CLEAN_BUILD=false
VERBOSE=false
CUSTOM_OUTPUT=""
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
        -o|--output)
            if [ -z "$2" ]; then
                print_status "ERROR" "Output directory not specified for -o/--output"
                show_usage
                exit 1
            fi
            CUSTOM_OUTPUT="$2"
            shift 2
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
    
    # Validate output directory if provided
    if [ -n "$CUSTOM_OUTPUT" ]; then
        # Check if parent directory exists and is writable
        local parent_dir=$(dirname "$CUSTOM_OUTPUT")
        if [ ! -d "$parent_dir" ]; then
            print_status "ERROR" "Parent directory does not exist: $parent_dir"
            exit 1
        fi
        
        if [ ! -w "$parent_dir" ]; then
            print_status "ERROR" "Parent directory is not writable: $parent_dir"
            exit 1
        fi
        
        print_status "SUCCESS" "Output directory validated: $CUSTOM_OUTPUT"
    fi
    
    # Check for conflicting options
    if [ "$CLEAN_BUILD" = true ] && [ -n "$CUSTOM_OUTPUT" ]; then
        print_status "WARNING" "Clean build will remove existing output directory: $CUSTOM_OUTPUT"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "INFO" "Build cancelled by user"
            exit 0
        fi
    fi
    
    print_status "SUCCESS" "Parameter validation completed"
}

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
    
    # Check if hardware detection script exists
    if [ ! -f "$SCRIPT_DIR/hardware_detect.sh" ]; then
        print_status "ERROR" "Hardware detection script not found: $SCRIPT_DIR/hardware_detect.sh"
        exit 1
    fi
    
    # Check if email config exists
    if [ ! -f "$SCRIPT_DIR/email_config.sh" ]; then
        print_status "WARNING" "Email configuration not found: $SCRIPT_DIR/email_config.sh"
        print_status "INFO" "Will use default email configuration"
    fi
    
    print_status "SUCCESS" "Prerequisites check completed"
}

# Clean previous build
clean_build() {
    if [ "$CLEAN_BUILD" = true ]; then
        print_status "INFO" "Cleaning previous build artifacts..."
        
        # Clean build directory
        if [ -d "/workspace/debian-hardware-detect-build" ]; then
            rm -rf /workspace/debian-hardware-detect-build
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
    local iso_file=$(find /workspace/debian-hardware-detect-build -name "*.iso" 2>/dev/null | head -1)
    
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
    echo "Log file: $LOG_FILE"
    echo "Output directory: $OUTPUT_DIR"
}

# Main execution
main() {
    echo "=== Hardware Detection ISO Builder ==="
    echo ""
    
    # Check root privileges
    check_root
    
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
    
    # Copy ISO to output directory
    copy_iso
    
    # Restore email configuration
    restore_email_config
    
    # Show final information
    show_final_info
}

# Run main function
main "$@" 