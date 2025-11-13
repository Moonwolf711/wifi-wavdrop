# Quick Reference - Wireless USB Bridge

## 🚀 Quick Start (After Installing PlatformIO)

### Option 1: Using Helper Scripts (Easiest)

```bash
cd /home/moon_wolf/WaveDrop/WirelessUSB-Bridge

# MVP (Simulated USB - Quick Test)
./build-mvp.sh          # Build firmware
./upload-mvp.sh         # Upload & monitor

# Production (Real USB Host)
./build-production.sh   # Build firmware (10 min first time)
./upload-production.sh  # Upload & monitor
```

### Option 2: Manual Commands

```bash
cd /home/moon_wolf/WaveDrop/WirelessUSB-Bridge

# MVP Version
pio run -e esp32s3 --target upload
pio device monitor

# Production Version
cp platformio-espidf.ini platformio.ini
pio run --target clean
pio run -e esp32s3-usb-host --target upload
pio device monitor
```

## ⚙️ Configuration

### WiFi Settings
Edit `include/Config.h`:
```cpp
#define WIFI_SSID "YourNetworkName"
#define WIFI_PASSWORD "YourPassword"
```

### Device Settings
```cpp
#define DEVICE_NAME "WaveDrop-USB-Bridge"
#define MDNS_HOSTNAME "wavedrop-usb"
#define HTTP_SERVER_PORT 8081
```

## 🔍 Testing

### 1. Check Serial Monitor
```
I (2345) WirelessUSB: ✓ WiFi Connected! IP: 192.168.1.100
I (2346) WirelessUSB: ✓ mDNS service started
I (2347) WirelessUSB: ✓ HTTP server started
I (5234) USBHostManager: ✓ USB drive mounted at /usb
```

### 2. Test From Browser
```bash
# Check device info
curl http://wavedrop-usb.local:8081/api/info

# List files
curl "http://wavedrop-usb.local:8081/api/files?path=/"

# Or use IP address
curl http://192.168.1.100:8081/api/info
```

### 3. Test From iOS App
1. Open WaveDrop app
2. Go to "Wireless USB" tab
3. Device should appear automatically
4. Tap to browse files

## 🚨 Troubleshooting

### PlatformIO Not Found
```bash
pip install platformio
# or
pip3 install platformio

# Add to PATH
export PATH="$HOME/.local/bin:$PATH"
```

### ESP32 Not Detected
```bash
# List USB devices
pio device list

# Check permissions (Linux)
sudo usermod -a -G dialout $USER
# Logout and login
```

### USB Drive Not Mounting
1. Check USB drive is FAT32 formatted
2. Check serial monitor for error messages
3. Try different USB drive
4. Check USB cable supports data (not charge-only)

### WiFi Not Connecting
1. Check SSID and password in `include/Config.h`
2. Rebuild after changing config
3. Check router supports 2.4GHz (ESP32 doesn't support 5GHz)

## 📊 LED Status

| LED    | Color  | Meaning           |
|--------|--------|-------------------|
| GPIO10 | Blue   | Power ON          |
| GPIO11 | Green  | WiFi Connected    |
| GPIO12 | Yellow | USB Drive Mounted |
| GPIO13 | Red    | Error             |

## 🔧 Common Commands

```bash
# List available devices
pio device list

# Build only (no upload)
pio run -e esp32s3

# Clean build
pio run --target clean

# Update libraries
pio pkg update

# Monitor serial (115200 baud)
pio device monitor

# Upload and monitor in one command
pio run -e esp32s3 --target upload && pio device monitor
```

## 📡 API Endpoints

### GET /api/info
Returns device status and USB drive info

### GET /api/files?path=/
Lists files in directory

### GET /api/download?path=/file.mp3
Downloads file from USB drive

## 🔗 Resources

- **Setup Guide**: PLATFORMIO_SETUP.md
- **USB Host Guide**: USB_HOST_GUIDE.md
- **Architecture**: WIRELESS_USB_MVP.md
- **Quick Start**: WIRELESS_USB_QUICKSTART.md

## 📝 Notes

- **First ESP-IDF build**: Takes 5-10 minutes (downloads framework)
- **Subsequent builds**: ~30 seconds
- **Transfer speed**: 8-10 MB/s
- **Max file size**: 1MB per request (configurable)
- **Supported filesystems**: FAT32, FAT16
- **USB drives**: Must be FAT32 formatted (<32GB on Windows)
