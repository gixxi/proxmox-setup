# Hardware Detection ISO

This directory contains tools for building a Debian Live ISO that automatically detects hardware and sends reports via email.

## Build Scripts

### **Primary Script: `build_hardware_detection_iso.sh`** ⭐ **Use This One**

This is the **main script** you should use for building the hardware detection ISO. It provides:

- **Command-line options** for easy customization
- **Email configuration** management
- **Output directory** control
- **Clean build** functionality
- **Error handling** and logging
- **User-friendly interface**
- **Parameter validation** and error checking

#### Usage Examples:
```bash
# Basic build
sudo ./build_hardware_detection_iso.sh

# With custom email
sudo ./build_hardware_detection_iso.sh --email admin@example.com

# With custom output and clean build
sudo ./build_hardware_detection_iso.sh \
  --email admin@example.com \
  --output /mnt/storage/isos \
  --clean \
  --verbose
```

#### Parameter Validation:
The script now includes comprehensive parameter validation:
- **Email format validation**: Ensures valid email addresses
- **Output directory validation**: Checks if parent directory exists and is writable
- **Missing parameter detection**: Prevents incomplete command usage
- **Conflict detection**: Warns about potentially destructive operations

### **Core Script: `debian_live_config/build_iso.sh`** 🔧 **Advanced Use Only**

This is the **core build script** that contains the actual Debian Live configuration. You typically don't need to run this directly unless you're:

- **Developing** the ISO configuration
- **Debugging** build issues
- **Customizing** the core build process
- **Integrating** with other build systems

#### When to Use:
```bash
# Only if you need direct control over the build process
cd debian_live_config/
sudo ./build_iso.sh
```

#### Can I Delete `build_iso.sh`?
**No, do NOT delete `build_iso.sh`** - it's essential because:

1. **Core functionality**: Contains all the Debian Live build configuration
2. **Called by wrapper**: The wrapper script calls this core script
3. **Development tool**: Needed for debugging and customization
4. **Modular design**: Separates user interface from build logic

The wrapper script (`build_hardware_detection_iso.sh`) is just a user-friendly interface that calls the core script (`build_iso.sh`).

## Script Relationship

```
build_hardware_detection_iso.sh (Wrapper)
    ↓
debian_live_config/build_iso.sh (Core)
    ↓
Debian Live Build Tools
    ↓
Hardware Detection ISO
```

## Quick Start

### 1. Build the ISO
```bash
# Navigate to the directory
cd deb_cloud_init/1_iso_image_for_hardware_detection/

# Build with your email address
sudo ./build_hardware_detection_iso.sh --email your-email@example.com
```

### 2. Create Bootable USB
```bash
# Find your USB device (replace sdX with actual device)
lsblk

# Burn the ISO (BE CAREFUL - this will overwrite the USB drive)
sudo dd if=output/*.iso of=/dev/sdX bs=4M status=progress
```

### 3. Boot and Detect
1. **Boot** target server from the USB drive
2. **Wait** for automatic hardware detection
3. **Check email** for hardware report
4. **Review** hardware specifications

## Configuration

### Email Settings
The wrapper script can automatically configure email settings:

```bash
# Set email address during build
sudo ./build_hardware_detection_iso.sh --email admin@example.com
```

Or manually edit `email_config.sh`:
```bash
# Edit email configuration
nano email_config.sh

# Test email configuration
./email_config.sh test
```

### Output Directory
```bash
# Set custom output directory
sudo ./build_hardware_detection_iso.sh --output /path/to/output
```

## Hardware Detection Features

### Automatic Detection
- **Storage devices**: NVMe, SATA, RAID controllers
- **Network interfaces**: Ethernet, WiFi, speeds, MAC addresses
- **CPU information**: Model, cores, frequency, cache
- **Memory**: Total RAM, DIMM configuration
- **Motherboard**: Manufacturer, model, BIOS version
- **PCI devices**: Graphics cards, network cards, etc.

### Manual Detection
If automatic detection doesn't run, you can manually trigger it:

```bash
# Manual hardware detection
/usr/local/bin/hardware_detect.sh

# Test email configuration
/usr/local/bin/email_config.sh test
```

## Troubleshooting

### Build Issues
```bash
# Clean build
sudo ./build_hardware_detection_iso.sh --clean --verbose

# Check logs
tail -f build.log
```

### Detection Issues
```bash
# Check if hardware detection script exists
ls -la /usr/local/bin/hardware_detect.sh

# Run manual detection
/usr/local/bin/hardware_detect.sh

# Check email configuration
/usr/local/bin/email_config.sh test
```

### Email Issues
```bash
# Test email configuration
/usr/local/bin/email_config.sh test

# Check SMTP settings
cat /usr/local/bin/email_config.sh

# Verify network connectivity
ping smtp.gmail.com
```

## File Structure

```
1_iso_image_for_hardware_detection/
├── build_hardware_detection_iso.sh     # ⭐ Main build script (USE THIS)
├── debian_live_config/
│   └── build_iso.sh                    # 🔧 Core build script (advanced)
├── hardware_detect.sh                  # Hardware detection logic
├── email_config.sh                     # Email configuration
├── output/                             # Generated ISOs
├── build.log                           # Build logs
└── README.md                           # This file
```

## Next Steps

After hardware detection:
1. **Review** the email report
2. **Note** hardware specifications
3. **Build** cloud-init deployment ISO
4. **Deploy** server using the hardware information

For cloud-init deployment, see: `../2_iso_image_with_cloud_init/` 