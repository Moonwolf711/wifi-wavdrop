# PlatformIO Setup Guide

Complete guide for installing PlatformIO to build the Wireless USB Bridge firmware.

## Prerequisites

- **Python 3.7+** (required for PlatformIO)
- **Git** (optional, for version control)
- **USB-C cable** (for uploading to ESP32-S3)

## Installation Options

### Option 1: Install via Python pip (Recommended)

**Step 1: Install Python**

**Windows:**
1. Download Python from https://www.python.org/downloads/
2. Run installer, **check "Add Python to PATH"**
3. Verify installation:
   ```powershell
   python --version
   pip --version
   ```

**WSL/Linux:**
```bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv
python3 --version
```

**macOS:**
```bash
brew install python3
python3 --version
```

**Step 2: Install PlatformIO**

```bash
# Install PlatformIO Core
pip install platformio

# Or use pip3 if pip points to Python 2
pip3 install platformio

# Verify installation
pio --version
```

**Step 3: Add to PATH (if needed)**

If `pio` command is not found, add to PATH:

**Windows:**
Add `C:\Users\YourName\AppData\Roaming\Python\Python3XX\Scripts` to PATH

**WSL/Linux/macOS:**
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"

# Reload shell
source ~/.bashrc
```

### Option 2: Install via VS Code Extension

1. Install **Visual Studio Code**
2. Install **PlatformIO IDE** extension
3. Extension automatically installs PlatformIO Core
4. Use built-in terminal or PlatformIO buttons for all operations

### Option 3: Use uv (Python package runner)

If you have `uv` installed (like for Obsidian MCP):

```bash
# Install platformio via uvx
uvx platformio --version

# Use uvx prefix for all commands
uvx platformio run -e esp32s3-usb-host
```

## Verify Installation

```bash
# Check PlatformIO version
pio --version

# Check installed platforms
pio platform list

# Check installed libraries
pio lib list
```

## Building Wireless USB Bridge Firmware

### MVP Version (Arduino Framework - Quick Test)

```bash
cd /home/moon_wolf/WaveDrop/WirelessUSB-Bridge

# Copy Arduino config
cp platformio.ini platformio.ini.backup
# Use platformio.ini (default)

# Build
pio run -e esp32s3

# Upload to ESP32-S3
pio run -e esp32s3 --target upload

# Monitor serial output
pio device monitor
```

### Production Version (ESP-IDF Framework - Real USB)

```bash
cd /home/moon_wolf/WaveDrop/WirelessUSB-Bridge

# Copy ESP-IDF config
cp platformio-espidf.ini platformio.ini

# Clean previous build (IMPORTANT when switching frameworks)
pio run --target clean
rm -rf .pio

# Build (first build takes 5-10 minutes)
pio run -e esp32s3-usb-host

# Upload to ESP32-S3
pio run -e esp32s3-usb-host --target upload

# Monitor serial output
pio device monitor
```

## First Build (ESP-IDF)

The first build of the ESP-IDF version will:
1. Download ESP-IDF framework (~500MB)
2. Download toolchain
3. Compile all ESP-IDF components
4. Compile project code

**Expected times:**
- First build: 5-10 minutes
- Subsequent builds: 30-60 seconds

## Troubleshooting

### "pio: command not found"

**Solution:**
```bash
# Find where pip installed it
pip show platformio

# Add to PATH (example for Linux/WSL)
export PATH="$HOME/.local/bin:$PATH"

# Make permanent
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### "Permission denied" when uploading

**Windows:**
Install CP210x USB driver from https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers

**Linux/WSL:**
```bash
# Add user to dialout group
sudo usermod -a -G dialout $USER

# Logout and login for changes to take effect
```

### "platformio install failed"

**Solution 1: Upgrade pip**
```bash
python -m pip install --upgrade pip
pip install platformio
```

**Solution 2: Use virtual environment**
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install platformio
```

### ESP-IDF build fails

**Clean and rebuild:**
```bash
pio run --target clean
rm -rf .pio
pio run -e esp32s3-usb-host
```

**Install missing dependencies:**
```bash
# Install ESP-IDF component manually
pio pkg install --library "espressif/usb_host_msc@^1.1.3"
```

## USB Driver Installation

### Windows

**ESP32-S3 drivers:**
- Usually automatic via Windows Update
- If needed: https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers

### macOS

**Install drivers:**
```bash
# Install via Homebrew
brew tap homebrew/cask-drivers
brew install --cask silicon-labs-vcp-driver
```

### Linux

Drivers usually included in kernel. If not:
```bash
sudo apt install brltty
sudo systemctl stop brltty
sudo systemctl disable brltty
```

## Hardware Setup

### ESP32-S3 Connections

1. **Programming Port**: USB-C (for uploading firmware)
2. **USB Host Port**: USB-C OTG (for USB drives)
3. **Power**: 5V via USB-C (1A minimum)

### LED Connections (Optional)

```
ESP32-S3 GPIO → LED → 220Ω Resistor → GND

GPIO 10 → Blue LED   (Power)
GPIO 11 → Green LED  (WiFi)
GPIO 12 → Yellow LED (USB)
GPIO 13 → Red LED    (Error)
```

## Quick Reference

### Common Commands

```bash
# Build project
pio run

# Upload firmware
pio run --target upload

# Monitor serial output
pio device monitor

# Upload and monitor
pio run --target upload && pio device monitor

# Clean build
pio run --target clean

# List serial ports
pio device list

# Update PlatformIO
pip install --upgrade platformio

# Update all libraries
pio pkg update
```

### Build Flags

Defined in `platformio.ini`:
- `CORE_DEBUG_LEVEL=3` - ESP32 logging level (0-5)
- `BOARD_HAS_PSRAM` - Enable PSRAM support
- `WU_DEBUG=1` - Enable debug output

### Switching Frameworks

```bash
# Switch to Arduino (MVP)
cp platformio.ini.backup platformio.ini
pio run --target clean
pio run -e esp32s3

# Switch to ESP-IDF (Production)
cp platformio-espidf.ini platformio.ini
pio run --target clean
pio run -e esp32s3-usb-host
```

## Next Steps

After successful installation:

1. **Configure WiFi** - Edit `include/Config.h`:
   ```cpp
   #define WIFI_SSID "YourNetwork"
   #define WIFI_PASSWORD "YourPassword"
   ```

2. **Build MVP** - Quick test with simulated USB:
   ```bash
   pio run -e esp32s3 --target upload
   ```

3. **Build Production** - Real USB Host support:
   ```bash
   cp platformio-espidf.ini platformio.ini
   pio run -e esp32s3-usb-host --target upload
   ```

4. **Test Hardware** - See `USB_HOST_GUIDE.md` for testing procedures

## Resources

- **PlatformIO Docs**: https://docs.platformio.org/
- **ESP32-S3 Docs**: https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/
- **USB Host MSC**: https://components.espressif.com/components/espressif/usb_host_msc
- **Project Issues**: https://github.com/Moonwolf711/wavedrop/issues

---

**Last Updated**: 2025-11-12
**Version**: 1.0.0
**Status**: Setup Guide
