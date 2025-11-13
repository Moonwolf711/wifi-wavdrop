# Wireless USB Bridge MVP

## Overview

Transform any USB drive into a wireless drive accessible from your WaveDrop iOS app. This MVP creates a plug-and-play WiFi-to-USB bridge device.

## Architecture

```
┌─────────────────────────────────────────┐
│         WaveDrop iOS App                │
│   (Browse & Download Files via WiFi)    │
└──────────────┬──────────────────────────┘
               │ HTTP + Bonjour
               │ WiFi
┌──────────────▼──────────────────────────┐
│      ESP32-S3 Wireless USB Bridge       │
│  ┌─────────────────────────────────┐   │
│  │  HTTP File Server (Port 8081)   │   │
│  │  Bonjour: _wavedrop-usb._tcp    │   │
│  │  USB Host Controller            │   │
│  └────────────┬────────────────────┘   │
└───────────────┼────────────────────────┘
                │ USB
       ┌────────▼────────┐
       │   USB Drive     │
       │   (Any Format)  │
       └─────────────────┘
```

## Hardware Requirements

### Option 1: ESP32-S3 USB OTG (Recommended)
- **Board**: ESP32-S3-DevKitC-1 with USB OTG
- **Features**:
  - Dual-core 240MHz
  - WiFi 802.11 b/g/n
  - USB 2.0 OTG (Full Speed)
  - 8MB Flash, 2MB PSRAM
- **Cost**: ~$10-15
- **USB**: Built-in USB host capability

### Option 2: ESP32 + MAX3421E
- **Board**: ESP32 Dev Board
- **USB Host**: MAX3421E USB Host Shield
- **Cost**: ~$15-20 total
- **Complexity**: Higher (external USB host chip)

### MVP Choice: **Option 1** (ESP32-S3 with built-in USB OTG)

## Firmware Architecture

### Core Components

```
Wireless USB Bridge Firmware
├── USBHostManager
│   ├── Mount USB Mass Storage
│   ├── FAT32/exFAT filesystem support
│   └── File enumeration & reading
├── WiFiServer
│   ├── Connect to WiFi network
│   ├── HTTP server (port 8081)
│   └── Bonjour/mDNS advertising
├── FileServer
│   ├── GET /api/files - List files
│   ├── GET /api/download?path=... - Download file
│   └── GET /api/info - Drive info
└── LEDIndicator
    ├── Power status
    ├── WiFi connection
    └── USB drive mounted
```

## MVP Features

### Phase 1: Core Functionality
- [x] Mount USB drive (FAT32)
- [x] Advertise via Bonjour (_wavedrop-usb._tcp)
- [x] HTTP file server
- [x] List directory contents
- [x] Download files
- [x] LED status indicators

### Future Enhancements
- [ ] exFAT support
- [ ] File upload to USB drive
- [ ] File deletion
- [ ] Battery power (portable version)
- [ ] OLED display with drive info
- [ ] Multiple USB drive support
- [ ] WebDAV protocol

## API Specification

### Endpoint: GET /api/info
Returns USB drive information.

**Response:**
```json
{
  "device_name": "WaveDrop-USB-Bridge",
  "usb_status": "mounted",
  "filesystem": "FAT32",
  "total_space": 32000000000,
  "free_space": 12000000000,
  "volume_label": "MY_USB"
}
```

### Endpoint: GET /api/files?path=/
Lists files and folders at specified path.

**Request:**
```
GET /api/files?path=/Music/House HTTP/1.1
Host: 192.168.1.150:8081
```

**Response:**
```json
{
  "path": "/Music/House",
  "files": [
    {
      "name": "track001.mp3",
      "size": 8453210,
      "type": "file",
      "modified": "2025-01-15T10:30:00Z"
    },
    {
      "name": "Subfolder",
      "type": "directory",
      "item_count": 15
    }
  ]
}
```

### Endpoint: GET /api/download?path=...
Downloads specified file.

**Request:**
```
GET /api/download?path=/Music/track001.mp3 HTTP/1.1
Host: 192.168.1.150:8081
```

**Response:**
```
HTTP/1.1 200 OK
Content-Type: audio/mpeg
Content-Length: 8453210
Content-Disposition: attachment; filename="track001.mp3"

[binary data]
```

## iOS App Integration

### New Model: WirelessUSBDrive

```swift
struct WirelessUSBDrive: Identifiable {
    let id: UUID
    let name: String              // Device name
    let serviceType: String       // "_wavedrop-usb._tcp"
    let endpoint: NWEndpoint      // Network endpoint
    let url: URL                  // HTTP base URL

    // Drive info (fetched from /api/info)
    var volumeLabel: String?
    var totalSpace: Int64?
    var freeSpace: Int64?
    var filesystem: String?
}

struct USBFile: Identifiable {
    let id: UUID
    let name: String
    let size: Int64?
    let type: FileType           // .file or .directory
    let path: String             // Full path
    let modified: Date?
}
```

### New Manager: WirelessUSBManager

```swift
class WirelessUSBManager: ObservableObject {
    @Published var discoveredDrives: [WirelessUSBDrive] = []
    @Published var selectedDrive: WirelessUSBDrive?
    @Published var currentFiles: [USBFile] = []
    @Published var currentPath: String = "/"

    private var browser: NWBrowser?

    // Start discovering wireless USB drives
    func startDiscovery()

    // Stop discovery
    func stopDiscovery()

    // Fetch drive information
    func fetchDriveInfo(_ drive: WirelessUSBDrive) async throws -> WirelessUSBDrive

    // Browse directory
    func listFiles(drive: WirelessUSBDrive, path: String) async throws -> [USBFile]

    // Download file
    func downloadFile(drive: WirelessUSBDrive, file: USBFile, progress: @escaping (Double) -> Void) async throws -> URL
}
```

### New View: WirelessUSBView

SwiftUI view with:
- List of discovered wireless USB drives
- File browser interface (similar to FileBrowserView)
- Download progress indicators
- Drive info display (capacity, free space)

## Bonjour Service Specification

```
Service Type: _wavedrop-usb._tcp.local.
Port: 8081
TXT Records:
  - version=1.0
  - device=WaveDrop-USB-Bridge
  - filesystem=FAT32
  - volume=MY_USB
  - capacity=32GB
```

## ESP32-S3 Firmware Implementation

### PlatformIO Configuration (`platformio.ini`)

```ini
[env:esp32s3]
platform = espressif32
board = esp32-s3-devkitc-1
framework = arduino

lib_deps =
    ESP32-USB-Host
    ESP_Async_WebServer
    ArduinoJson
    DNSServer

build_flags =
    -DCORE_DEBUG_LEVEL=3
    -DBOARD_HAS_PSRAM

monitor_speed = 115200
upload_speed = 921600
```

### Main Firmware Code Structure

```
WirelessUSB-Bridge/
├── platformio.ini
├── src/
│   ├── main.cpp                 # Entry point
│   ├── USBHostManager.h/cpp     # USB drive handling
│   ├── WiFiServerManager.h/cpp  # WiFi + HTTP server
│   ├── FileAPI.h/cpp            # REST API handlers
│   └── Config.h                 # Configuration
├── data/
│   └── index.html               # Web UI (optional)
└── README.md
```

## LED Indicators

```
GPIO Pin | Color  | Status
---------|--------|------------------
GPIO 10  | Blue   | Power ON
GPIO 11  | Green  | WiFi Connected
GPIO 12  | Yellow | USB Drive Mounted
GPIO 13  | Red    | Error State
```

**Blink Patterns:**
- Solid: Status active
- Slow blink (1Hz): Initializing
- Fast blink (4Hz): Activity
- Off: Status inactive/error

## Power Requirements

- **Input**: 5V USB power (USB-C port on ESP32-S3)
- **Current**: 500mA typical, 800mA peak (with USB drive)
- **Power Source Options**:
  - USB power adapter (5V/1A)
  - USB power bank
  - USB port from computer

## Setup Process

### 1. First-Time Configuration

```
1. Power on ESP32-S3
2. Device creates WiFi AP: "WaveDrop-USB-Setup"
3. Connect to AP with phone
4. Navigate to http://192.168.4.1
5. Enter home WiFi credentials
6. Device reboots and connects to home WiFi
7. Device appears in WaveDrop app
```

### 2. Normal Operation

```
1. Plug in USB drive
2. Power on ESP32-S3
3. Wait for Green LED (WiFi) and Yellow LED (USB)
4. Open WaveDrop app → Wireless USB tab
5. Select discovered drive
6. Browse and download files
```

## Security Considerations

### MVP (Phase 1)
- **Network**: Local network only (no internet access)
- **Authentication**: None (trusted local network)
- **Encryption**: No HTTPS (future enhancement)

### Future Security Enhancements
- PIN code protection
- HTTPS with self-signed certificate
- Device pairing via QR code
- MAC address whitelisting

## Performance

### Transfer Speeds
- **WiFi**: 802.11n (2.4GHz) → ~50-100 Mbps real-world
- **USB**: USB 2.0 Full Speed → ~12 Mbps
- **Bottleneck**: USB 2.0 (not WiFi)
- **Expected**: 8-10 MB/s for large files

### Latency
- File listing: <100ms
- Download start: <200ms
- Bonjour discovery: 1-3 seconds

## Bill of Materials (BOM)

| Component | Qty | Cost (USD) |
|-----------|-----|------------|
| ESP32-S3-DevKitC-1 | 1 | $12 |
| USB-C cable (power) | 1 | $3 |
| LEDs (4x) | 1 | $1 |
| Resistors 220Ω (4x) | 1 | $1 |
| Enclosure (3D printed or plastic) | 1 | $5 |
| **Total** | | **~$22** |

## Development Timeline

### Week 1: Hardware & Firmware Foundation
- [x] Hardware selection (ESP32-S3)
- [ ] USB host library integration
- [ ] Mount FAT32 filesystem
- [ ] Basic file reading

### Week 2: Network & API
- [ ] WiFi connection manager
- [ ] HTTP server setup
- [ ] Bonjour/mDNS advertising
- [ ] REST API implementation

### Week 3: iOS Integration
- [ ] WirelessUSBManager implementation
- [ ] WirelessUSBView UI
- [ ] File browsing integration
- [ ] Download functionality

### Week 4: Testing & Polish
- [ ] End-to-end testing
- [ ] Error handling
- [ ] LED indicator polish
- [ ] Documentation

## Testing Checklist

### Hardware Tests
- [ ] ESP32-S3 powers on
- [ ] LEDs functional
- [ ] USB drive detection
- [ ] Multiple USB drive types (different brands/sizes)

### Firmware Tests
- [ ] FAT32 mount successful
- [ ] File enumeration works
- [ ] File download complete and accurate
- [ ] HTTP server accessible
- [ ] Bonjour discoverable
- [ ] WiFi reconnection after power cycle

### iOS Integration Tests
- [ ] Device discovered in app
- [ ] Drive info fetched correctly
- [ ] File listing displays
- [ ] File download works
- [ ] Progress tracking accurate
- [ ] Error handling (disconnect, full storage)

## Future Roadmap

### Phase 2: Enhanced Features
- exFAT filesystem support
- NTFS read support
- File upload to USB drive
- File deletion capability
- Folder creation

### Phase 3: Advanced Features
- WebDAV protocol
- SMB/CIFS server
- Multiple simultaneous connections
- RAID-like multi-drive support
- Cloud sync integration

### Phase 4: Hardware Improvements
- Battery powered (18650 Li-Ion)
- OLED display for status
- Physical buttons for control
- Ruggedized enclosure
- PoE (Power over Ethernet) support

## Troubleshooting

### USB Drive Not Detected
- Check USB cable connection
- Verify drive is FAT32 formatted
- Try different USB drive
- Check ESP32-S3 power supply (needs sufficient current)

### Not Discoverable in WaveDrop
- Ensure same WiFi network
- Check firewall settings
- Restart mDNS (reboot ESP32-S3)
- Verify Bonjour service is running

### File Download Fails
- Check available storage on iPhone
- Verify file exists on USB drive
- Test with smaller files first
- Check WiFi signal strength

### WiFi Connection Drops
- Improve WiFi signal (move closer to router)
- Check for interference (2.4GHz crowded)
- Update ESP32 firmware
- Try different WiFi channel

## Cost Comparison

| Solution | Cost | Pros | Cons |
|----------|------|------|------|
| **Wireless USB Bridge (MVP)** | $22 | Plug-and-play, any USB drive | Requires hardware build |
| Commercial WiFi HDD | $80-150 | Ready-made, battery | Fixed capacity, expensive |
| NAS Device | $150-400 | Multi-drive, advanced features | Overkill for mobile DJ use |
| WaveDrop Wi-Fi Transfer (Existing) | $0 | Free, no hardware | Requires manual file copying |

**MVP Advantage**: Best balance of cost, flexibility, and DJ-specific workflow.

## Success Metrics

- ✅ Hardware assembled and powered
- ✅ USB drive mountable and readable
- ✅ WiFi connectivity stable
- ✅ Discoverable via Bonjour
- ✅ File API functional
- ✅ iOS app integration complete
- ✅ Download speed ≥8 MB/s
- ✅ Discovery time <5 seconds
- ✅ Zero data corruption in transfers

## Conclusion

The Wireless USB Bridge MVP transforms WaveDrop into a complete wireless DJ workflow system. DJs can:

1. **Plug in any USB drive** to the bridge device
2. **Discover wirelessly** from WaveDrop iOS app
3. **Browse and download** DJ tracks on the go
4. **No cables** needed between phone and USB drive

**Total Cost**: ~$22 hardware + development time
**Value**: Wireless access to any USB drive collection

---

**Created**: 2025-11-12
**Status**: Design Phase Complete, Ready for Implementation
**Next Step**: Begin ESP32-S3 firmware development
