# Testing Checklist - Wireless USB Bridge

Complete step-by-step guide for testing the Wireless USB Bridge.

## Prerequisites

- [ ] PlatformIO installed (`pip install platformio`)
- [ ] ESP32-S3 DevKitC-1 board
- [ ] USB-C cable (data capable)
- [ ] FAT32 formatted USB drive
- [ ] iOS device with WaveDrop app
- [ ] Computer and device on same WiFi network

## Phase 1: Environment Setup

### 1.1 Install PlatformIO
```bash
pip install platformio

# Verify
pio --version
```
**Expected**: `PlatformIO Core, version X.X.X`

- [ ] PlatformIO installed successfully

### 1.2 Configure WiFi
```bash
cd /home/moon_wolf/WaveDrop/WirelessUSB-Bridge
nano include/Config.h
```

Change these lines:
```cpp
#define WIFI_SSID "YourActualSSID"
#define WIFI_PASSWORD "YourActualPassword"
```

- [ ] WiFi credentials configured
- [ ] Config.h saved

### 1.3 Connect ESP32-S3
- [ ] Connect ESP32-S3 to computer via USB-C
- [ ] Check device detected: `pio device list`
- [ ] Note the serial port (e.g., /dev/ttyUSB0 or COM3)

## Phase 2: MVP Testing (Simulated USB)

### 2.1 Build MVP Firmware
```bash
./build-mvp.sh
# Or manually:
# pio run -e esp32s3
```

**Expected**: Build completes without errors

- [ ] MVP firmware builds successfully
- [ ] No compilation errors

### 2.2 Upload MVP Firmware
```bash
./upload-mvp.sh
# Or manually:
# pio run -e esp32s3 --target upload
```

**Expected**:
```
Writing at 0x00040000... (100 %)
Wrote XXXXX bytes
Hash of data verified.
Leaving...
Hard resetting via RTS pin...
```

- [ ] Firmware uploaded successfully

### 2.3 Monitor Serial Output
```bash
pio device monitor
```

**Expected Output**:
```
======================================
 Wireless USB Bridge - MVP
 Version: 1.0.0
======================================
I (234) WirelessUSB: Initializing WiFi...
I (1567) WirelessUSB: ✓ WiFi Connected! IP: 192.168.1.XXX
I (1568) WirelessUSB: ✓ mDNS service started: _wavedrop-usb._tcp
I (1569) WirelessUSB: ✓ HTTP server started
======================================
 🎉 System Ready!
======================================
 Server URL: http://wavedrop-usb.local:8081
======================================
```

- [ ] WiFi connects successfully
- [ ] mDNS service starts
- [ ] HTTP server starts
- [ ] Note the IP address: ________________

### 2.4 Test API from Browser
```bash
# Replace IP with your ESP32's IP
curl http://192.168.1.XXX:8081/api/info
```

**Expected**: JSON response with device info

- [ ] `/api/info` responds
- [ ] `/api/files?path=/` responds
- [ ] Browser shows simulated files

### 2.5 Test from iOS App
1. Open WaveDrop app
2. Go to "Wireless USB" tab
3. Wait for device discovery

- [ ] ESP32 appears in device list
- [ ] Shows as "WaveDrop-USB-Bridge"
- [ ] Can tap to view files
- [ ] Shows simulated files (track001.mp3, etc.)

**✓ Phase 2 Complete** - MVP working with simulated USB

## Phase 3: Production Testing (Real USB Host)

### 3.1 Prepare USB Drive
Format USB drive as FAT32:

**Windows**:
```
Right-click drive → Format → FAT32 → Start
```

**macOS**:
```bash
diskutil list  # Find drive (e.g., disk2)
diskutil eraseDisk FAT32 DJ_MUSIC MBRFormat /dev/diskX
```

**Linux**:
```bash
sudo mkfs.vfat -F 32 -n DJ_MUSIC /dev/sdX1
```

- [ ] USB drive formatted as FAT32
- [ ] Volume label set to "DJ_MUSIC" (or similar)

### 3.2 Add Test Files
Copy test files to USB drive:
- [ ] Add some MP3 files
- [ ] Add some directories
- [ ] Create test structure: `/Music/House/track.mp3`

### 3.3 Build Production Firmware
```bash
./build-production.sh
# Or manually:
# cp platformio-espidf.ini platformio.ini
# pio run --target clean
# pio run -e esp32s3-usb-host
```

**Note**: First build takes 5-10 minutes!

- [ ] ESP-IDF framework downloads
- [ ] All components compile
- [ ] Firmware builds successfully

### 3.4 Upload Production Firmware
```bash
./upload-production.sh
# Or manually:
# pio run -e esp32s3-usb-host --target upload
```

- [ ] Production firmware uploaded
- [ ] Serial monitor shows boot messages

### 3.5 Test USB Drive Detection

**Without USB drive:**
```
I (1567) WirelessUSB: ✓ WiFi Connected!
I (1568) WirelessUSB: ✓ mDNS service started
I (1569) WirelessUSB: ✓ HTTP server started
I (1570) WirelessUSB: 🎉 System Ready!
```

- [ ] System boots successfully
- [ ] WiFi connects
- [ ] HTTP server ready
- [ ] Yellow LED is OFF (no USB)

**Plug in USB drive:**
```
I (5234) USBHostManager: MSC Device Connected
I (5450) USBHostManager: ✓ USB drive mounted at /usb
I (5451) USBHostManager:    Volume: DJ_MUSIC
I (5452) USBHostManager:    Total: 31.98 GB
I (5453) USBHostManager:    Free: 18.45 GB
```

- [ ] USB device detected (~2 seconds)
- [ ] Filesystem mounts successfully
- [ ] Yellow LED turns ON
- [ ] Drive info displays correctly

### 3.6 Test File Operations

**List files:**
```bash
curl "http://192.168.1.XXX:8081/api/files?path=/"
```

**Expected**: JSON with real files from USB drive

- [ ] Returns actual file list
- [ ] File sizes are correct
- [ ] Directories shown as `"type": "directory"`

**Download file:**
```bash
curl "http://192.168.1.XXX:8081/api/download?path=/Music/track.mp3" --output test.mp3
```

- [ ] File downloads successfully
- [ ] File size matches original
- [ ] File plays correctly

### 3.7 Test Hot-Plug

**Remove USB drive:**
- [ ] Yellow LED turns OFF
- [ ] Serial shows "USB Disconnected"
- [ ] API returns "USB not mounted" error

**Re-insert USB drive:**
- [ ] USB detected automatically
- [ ] Filesystem re-mounts
- [ ] Yellow LED turns back ON
- [ ] Files accessible again

### 3.8 Test from iOS App (Production)

1. Restart WaveDrop iOS app
2. Go to "Wireless USB" tab
3. Select device

- [ ] Device discovered automatically
- [ ] Shows real USB drive info (volume label, size)
- [ ] Displays actual files from USB drive
- [ ] Can navigate directories
- [ ] Can download files
- [ ] Progress bar works during download
- [ ] Downloaded files are correct

## Phase 4: Advanced Testing

### 4.1 Multiple Files
- [ ] Select multiple files in iOS app
- [ ] Download all simultaneously
- [ ] All downloads complete successfully

### 4.2 Large Files
- [ ] Download file >10MB
- [ ] Progress updates in real-time
- [ ] File integrity verified

### 4.3 Network Range
- [ ] Test from different rooms
- [ ] Test through walls
- [ ] Verify transfer speed (8-10 MB/s expected)

### 4.4 Error Handling
- [ ] Unplug USB during transfer (should fail gracefully)
- [ ] Request non-existent file (should return 404)
- [ ] Request invalid path (should return 400)

### 4.5 Stability
- [ ] Let run for 1 hour
- [ ] No crashes or resets
- [ ] No memory leaks
- [ ] Consistent performance

## Phase 5: LED Verification

Physical LED check (if LEDs installed):

| Condition | Blue (GPIO10) | Green (GPIO11) | Yellow (GPIO12) | Red (GPIO13) |
|-----------|---------------|----------------|-----------------|--------------|
| Boot      | ✓ ON          | OFF            | OFF             | OFF          |
| WiFi OK   | ✓ ON          | ✓ ON           | OFF             | OFF          |
| USB OK    | ✓ ON          | ✓ ON           | ✓ ON            | OFF          |
| Error     | ✓ ON          | ?              | ?               | ✓ ON         |

- [ ] Power LED (Blue) - Always ON
- [ ] WiFi LED (Green) - ON when connected
- [ ] USB LED (Yellow) - ON when USB mounted
- [ ] Error LED (Red) - OFF during normal operation

## Final Checklist

- [ ] All API endpoints working
- [ ] iOS app integration complete
- [ ] File downloads successful
- [ ] Hot-plug working
- [ ] LED indicators accurate
- [ ] No crashes or errors
- [ ] Performance acceptable
- [ ] Ready for production use

## Troubleshooting

If any test fails, see:
- **USB_HOST_GUIDE.md** - Troubleshooting section
- **PLATFORMIO_SETUP.md** - Installation issues
- **QUICKREF.md** - Quick fixes

## Success Criteria

✓ **MVP Phase**: Simulated USB works, iOS app discovers device
✓ **Production Phase**: Real USB Host works, files transfer correctly
✓ **Integration Phase**: iOS app works end-to-end with hardware
✓ **Stability Phase**: System runs reliably for extended period

---

**Date Tested**: ________________
**Tested By**: ________________
**Result**: ☐ PASS  ☐ FAIL  ☐ PARTIAL
**Notes**:

