# Wireless USB Bridge - ESP32-S3 Firmware

Transform any USB drive into a wireless drive accessible from the WaveDrop iOS app!

## Hardware Requirements

- **ESP32-S3-DevKitC-1** with USB OTG support
- USB-C cable for power
- USB drive (FAT32 formatted)
- (Optional) 4x LEDs + resistors for status indicators

## Quick Start

### 1. Install PlatformIO

```bash
# Install PlatformIO Core (if not already installed)
pip install platformio

# Or use PlatformIO IDE extension in VS Code
```

### 2. Configure WiFi

Edit `include/Config.h` and update:

```cpp
#define WIFI_SSID "YourWiFiSSID"          // Your WiFi name
#define WIFI_PASSWORD "YourWiFiPassword"  // Your WiFi password
```

### 3. Build & Upload

```bash
# Navigate to firmware directory
cd WirelessUSB-Bridge

# Build the firmware
pio run

# Upload to ESP32-S3
pio run --target upload

# Monitor serial output
pio device monitor
```

### 4. Connect USB Drive

1. Power on ESP32-S3
2. Wait for Green LED (WiFi connected)
3. Plug in USB drive
4. Wait for Yellow LED (USB mounted)

### 5. Access from WaveDrop App

1. Open WaveDrop iOS app
2. Go to "Wireless USB" tab
3. Your drive should appear automatically
4. Tap to browse and download files

## Web Interface

You can also access via browser:

```
http://wavedrop-usb.local:8081
```

Or using IP address (check serial monitor):

```
http://192.168.1.xxx:8081
```

## API Endpoints

### GET /api/info
Returns drive information.

```bash
curl http://wavedrop-usb.local:8081/api/info
```

### GET /api/files?path=/
Lists files at specified path.

```bash
curl "http://wavedrop-usb.local:8081/api/files?path=/"
```

### GET /api/download?path=/file.mp3
Downloads specified file.

```bash
curl "http://wavedrop-usb.local:8081/api/download?path=/Music/track.mp3" -o track.mp3
```

## LED Indicators

| GPIO | Color  | Meaning              |
|------|--------|----------------------|
| 10   | Blue   | Power ON             |
| 11   | Green  | WiFi Connected       |
| 12   | Yellow | USB Drive Mounted    |
| 13   | Red    | Error State          |

## Project Structure

```
WirelessUSB-Bridge/
├── platformio.ini           # PlatformIO configuration
├── include/
│   └── Config.h            # Configuration (WiFi, pins, etc.)
├── src/
│   └── main.cpp            # Main firmware
└── README.md               # This file
```

## Troubleshooting

### WiFi Won't Connect
- Check SSID and password in Config.h
- Ensure 2.4GHz WiFi (ESP32 doesn't support 5GHz)
- Check signal strength (move closer to router)

### USB Drive Not Detected
- Ensure drive is FAT32 formatted
- Try a different USB drive
- Check power supply (use 1A+ USB adapter)

### Device Not Discoverable
- Ensure iOS device on same WiFi network
- Check router allows mDNS/Bonjour (port 5353)
- Try accessing via IP address instead of hostname

### Build Errors
```bash
# Clean and rebuild
pio run --target clean
pio run
```

## Development

### Enable Debug Logging

Debug logging is enabled by default in `Config.h`:

```cpp
#define WU_DEBUG 1
```

View logs via serial monitor:

```bash
pio device monitor
```

### Modify Configuration

All settings in `include/Config.h`:
- WiFi credentials
- Server port
- LED pins
- Timeouts
- API paths

## MVP Limitations

This is an MVP (Minimum Viable Product) with simulated USB functionality:

- ✅ WiFi connectivity
- ✅ Bonjour/mDNS discovery
- ✅ HTTP file server
- ✅ REST API
- ✅ LED status indicators
- ⚠️ USB drive mounting (simulated)
- ⚠️ File operations (simulated)

**Next Steps**: Integrate real USB Host library for actual USB drive support.

## License

Same as WaveDrop project.

## Support

For issues or questions:
- Check WaveDrop main documentation
- Review WIRELESS_USB_MVP.md for architecture details
- Check serial monitor output for errors

---

**Version**: 1.0.0 MVP
**Status**: Firmware foundation complete, USB host integration pending
**Next**: Integrate ESP32-S3 USB Host library for real USB drive support
