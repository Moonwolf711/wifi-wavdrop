# WaveDrop Quick Start Guide

Get WaveDrop up and running in 5 minutes!

## Prerequisites

- macOS with Xcode 15.0 or later
- An Apple Developer account (for device deployment)
- iOS 16.0+ device or simulator

## Step 1: Open the Project

```bash
cd WaveDrop
open Package.swift
```

This will open the project in Xcode.

## Step 2: Resolve Dependencies

Xcode should automatically resolve dependencies. If not:

```bash
swift package resolve
```

Or in Xcode: **File → Packages → Resolve Package Versions**

## Step 3: Configure Signing

1. Select the **WaveDrop** target in Xcode
2. Go to **Signing & Capabilities**
3. Select your **Team**
4. Enable **Automatically manage signing**
5. Repeat for **WaveDropShareExtension** target

## Step 4: Build and Run

1. Select your target device/simulator from the scheme selector
2. Press **Cmd + R** to build and run

## Step 5: Test the App

### On Simulator (Limited Functionality)
- View the UI and navigation
- Test settings panel
- Verify SwiftUI layouts

### On Physical Device (Full Functionality)
1. Connect a USB drive via adapter
2. Wait for drive detection
3. Browse files on the drive
4. Test AirDrop file reception
5. Try audio file analysis

## Common First-Time Issues

### Issue: Dependencies Not Resolving
**Solution**:
```bash
rm -rf .build
swift package clean
swift package resolve
```

### Issue: Code Signing Error
**Solution**:
1. Check that you're logged into Xcode with your Apple ID
2. Verify your team is selected
3. Ensure you have a valid provisioning profile

### Issue: USB Drive Not Detected
**Solution**:
1. Only works on physical iOS devices (not simulator)
2. Ensure drive is formatted as exFAT or FAT32
3. Check that the drive is visible in the Files app
4. Try unplugging and reconnecting

### Issue: Share Extension Not Appearing
**Solution**:
1. Ensure both targets are built and installed
2. Open the main app at least once
3. Restart the device
4. Check Settings → WaveDrop for permissions

## Testing Audio Analysis

### BPM Detection
```swift
let extractor = AudioMetadataExtractor()
let bpm = try await extractor.detectBPM(from: audioFileURL)
print("Detected BPM: \(bpm)")
```

### Musical Key Detection
```swift
let key = try await extractor.detectMusicalKey(from: audioFileURL)
print("Musical Key: \(key)") // e.g., "8B" (C major)
```

### Full Metadata Extraction
```swift
let track = try await extractor.extractMetadata(from: audioFileURL)
print("Title: \(track.title)")
print("BPM: \(track.bpm)")
print("Key: \(track.musicalKey)")
```

## Export to DJ Software

```swift
let exporter = DJExportManager()

// Export single track
let url = try await exporter.exportTrack(
    track,
    to: .rekordbox,
    outputDirectory: destinationURL
)

// Export multiple tracks with progress
let urls = try await exporter.exportTracks(
    tracks,
    to: .serato,
    outputDirectory: destinationURL
) { completed, total in
    print("Progress: \(completed)/\(total)")
}
```

## Run Tests

```bash
# All tests
swift test

# Specific test
swift test --filter ExternalDriveManagerTests

# With coverage
swift test --enable-code-coverage
```

## Build for Release

```bash
swift build -c release
```

Or in Xcode: **Product → Archive**

## Debug Tips

### Enable Verbose Logging
Add to your code:
```swift
// In ExternalDriveManager
print("Scanning for drives...")
print("Found \(connectedDrives.count) drives")
```

### Check File Permissions
```swift
let fm = FileManager.default
if fm.isReadableFile(atPath: url.path) {
    print("File is readable")
}
```

### Monitor Drive Changes
```swift
NotificationCenter.default.addObserver(
    forName: .externalDriveConnected,
    object: nil,
    queue: .main
) { notification in
    if let drive = notification.object as? ExternalDrive {
        print("Drive connected: \(drive.name)")
    }
}
```

## Next Steps

1. **Read the full README.md** for detailed documentation
2. **Review the architecture** in PROJECT_SUMMARY.md
3. **Explore the code** - start with MainView.swift
4. **Write more tests** - expand ExternalDriveManagerTests.swift
5. **Customize the UI** - modify colors, fonts, layouts
6. **Add features** - see Roadmap in README.md

## Getting Help

- Check the **Troubleshooting** section in README.md
- Review **unit tests** for usage examples
- Look at **inline documentation** in Swift files
- Open an issue on GitHub

## Quick Reference

### Project Structure
```
Sources/WaveDrop/          → Main app code
Sources/WaveDropShareExtension/ → Share extension
Tests/WaveDropTests/       → Unit tests
.github/workflows/         → CI/CD
```

### Key Files
- `ExternalDriveManager.swift` → Drive management
- `AudioMetadataExtractor.swift` → Audio analysis
- `DJExportManager.swift` → Export functionality
- `MainView.swift` → Main UI
- `FileBrowserView.swift` → File browser

### Important Commands
```bash
swift build              # Build debug
swift build -c release   # Build release
swift test               # Run tests
swift package clean      # Clean build
swiftlint lint          # Check code style
```

---

**Happy Coding! 🎵🎧**

For questions or issues, refer to README.md or open a GitHub issue.
