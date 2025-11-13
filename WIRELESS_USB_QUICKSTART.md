# Wireless USB Bridge - Quick Start Guide

Get your Wireless USB Bridge up and running in 10 minutes!

## What You Need

### Hardware
- ESP32-S3-DevKitC-1 board (~$12)
- USB-C cable for power
- USB drive (FAT32 formatted)
- Computer for programming

### Software
- PlatformIO (free)
- WaveDrop iOS app (your existing app)

## Step-by-Step Setup

### Step 1: Get the Hardware (5 minutes)

**Option A**: Order ESP32-S3-DevKitC-1
- Amazon/AliExpress: ~$10-15
- Look for "ESP32-S3-DevKitC-1" or "ESP32-S3 with USB OTG"

**Option B**: Use what you have
- Any ESP32-S3 board with USB OTG support works

### Step 2: Install PlatformIO (2 minutes)

**VS Code Extension (Recommended)**:
1. Install VS Code
2. Install "PlatformIO IDE" extension
3. Restart VS Code

**Or Command Line**:
```bash
pip install platformio
```

### Step 3: Configure Firmware (1 minute)

1. Open `WirelessUSB-Bridge/include/Config.h`
2. Update WiFi settings:

```cpp
#define WIFI_SSID "YourWiFiName"
#define WIFI_PASSWORD "YourPassword"
```

3. Save the file

### Step 4: Upload Firmware (2 minutes)

**VS Code**:
1. Open WirelessUSB-Bridge folder in VS Code
2. Click "PlatformIO: Upload" in bottom bar
3. Wait for upload to complete

**Command Line**:
```bash
cd WirelessUSB-Bridge
pio run --target upload
```

### Step 5: Test Connection (30 seconds)

1. Open Serial Monitor (PlatformIO → Monitor)
2. Press RESET button on ESP32-S3
3. Watch for:
   ```
   ✓ WiFi Connected!
   IP Address: 192.168.1.xxx
   ✓ HTTP Server started on port 8081
   🎉 System Ready!
   ```

### Step 6: Test Web Interface (30 seconds)

Open browser and go to:
```
http://wavedrop-usb.local:8081
```

You should see the WaveDrop USB Bridge web page!

### Step 7: Update WaveDrop iOS App (10 minutes)

**Add new files to your Xcode project**:
1. Drag `WirelessUSBManager.swift` into project
2. Drag `WirelessUSBView.swift` into project
3. Update `MainView.swift` to add Wireless USB tab

**Add Wireless USB tab to MainView**:

```swift
// In MainView.swift, add new tab:
TabView {
    // ... existing tabs ...

    WirelessUSBView()
        .tabItem {
            Label("Wireless USB", systemImage: "externaldrive.badge.wifi")
        }
}
```

### Step 8: Test End-to-End (1 minute)

1. Build and run WaveDrop app on iPhone
2. Tap "Wireless USB" tab
3. Tap "Scan" button
4. Your bridge should appear in a few seconds!
5. Tap it to browse files

## Troubleshooting

### "WiFi Connection Failed"
- Double-check SSID and password in Config.h
- Ensure 2.4GHz WiFi (ESP32 doesn't support 5GHz)
- Move ESP32 closer to router

### "Can't upload firmware"
- Check USB cable is data cable (not charge-only)
- Hold BOOT button while connecting USB
- Try different USB port
- Windows: Install CH340 driver if needed

### "Device not appearing in app"
- Ensure iPhone on same WiFi network
- Check ESP32 serial monitor shows "WiFi Connected"
- Try accessing http://192.168.1.xxx:8081 in Safari (use IP from serial monitor)
- Restart WaveDrop app

### "Build errors"
```bash
# Clean and rebuild
pio run --target clean
pio lib install
pio run
```

## Next Steps

### Add Real USB Drive Support

The MVP uses simulated USB. To add real USB host:

1. Install ESP32 USB Host library
2. Update `mountUSB()` function in main.cpp
3. Implement actual file reading from USB drive

### Customize

- Change LED pins in Config.h
- Adjust server port
- Add authentication
- Add file upload support

## Testing Checklist

- [x] ESP32 powers on (Blue LED)
- [x] Connects to WiFi (Green LED)
- [x] Web interface accessible
- [x] Discoverable from iOS app
- [x] Can browse simulated files
- [ ] Real USB drive detected (pending USB Host integration)
- [ ] Can download actual files from USB

## Performance

Expected performance (with real USB support):
- **Discovery**: 1-3 seconds
- **File listing**: <100ms
- **Download speed**: 8-10 MB/s (USB 2.0 limited)
- **Multiple clients**: 3-4 simultaneous connections

## Support

Need help?
1. Check serial monitor output
2. Review WIRELESS_USB_MVP.md for architecture
3. Test web interface first (http://wavedrop-usb.local:8081)
4. Verify WiFi connection with ping command

## What's Next?

This MVP proves the concept works! To make it production-ready:

1. **USB Host Integration**: Add real USB Mass Storage support
2. **exFAT Support**: Handle larger files and drives
3. **Authentication**: Add password protection
4. **HTTPS**: Secure the connection
5. **Battery Power**: Make it portable
6. **OLED Display**: Show status without serial monitor

---

**Total Time**: ~10-20 minutes to working prototype
**Cost**: ~$12-15 for ESP32-S3 board
**Result**: Wireless access to any USB drive from your iPhone!

🎉 **You now have a wireless USB bridge for your DJ workflow!**
