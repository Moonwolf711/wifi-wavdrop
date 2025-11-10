# WaveDrop iOS App

Professional DJ workflow app for iOS with AirDrop integration and external USB drive support.

## Features

- **AirDrop Integration**: Receive files via AirDrop and automatically save to external USB drives
- **External Drive Management**: Detect, monitor, and manage USB drives connected via Lightning/USB-C
- **DJ-Specific Features**:
  - BPM detection with high accuracy
  - Musical key detection (Camelot Wheel notation)
  - Waveform visualization with beat grid
  - Cue point management
  - Export to Rekordbox, Serato, Traktor, Virtual DJ, and Engine Prime
- **File Transfer**: Robust file transfer with progress tracking and error recovery
- **Share Extension**: Seamless integration with iOS share sheet

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- External USB drive (via Lightning-to-USB or USB-C adapter)

## Project Structure

```
WaveDrop/
├── Sources/
│   ├── WaveDrop/              # Main app code
│   │   ├── ExternalDriveManager.swift
│   │   ├── AudioMetadataExtractor.swift
│   │   ├── DJExportManager.swift
│   │   └── Views/
│   │       ├── MainView.swift
│   │       └── FileBrowserView.swift
│   └── WaveDropShareExtension/  # Share Extension
│       ├── ShareViewController.swift
│       └── ShareExtensionView.swift
├── Tests/
│   └── WaveDropTests/        # Unit tests
│       └── ExternalDriveManagerTests.swift
├── .github/
│   └── workflows/
│       └── ios-ci.yml        # CI/CD pipeline
├── Package.swift              # Swift Package Manager config
├── Info.plist                 # App configuration
├── .swiftlint.yml            # Code style configuration
└── README.md                  # This file
```

## Setup

### 1. Clone Repository

```bash
git clone <repository-url>
cd WaveDrop
```

### 2. Install Dependencies

```bash
swift package resolve
```

### 3. Open in Xcode

```bash
open Package.swift
```

Or create an Xcode project:

```bash
swift package generate-xcodeproj
open WaveDrop.xcodeproj
```

### 4. Configure Signing

1. Open project in Xcode
2. Select project target
3. Go to "Signing & Capabilities"
4. Select your development team
5. Enable "Automatically manage signing"

### 5. Build and Run

- Select target device or simulator
- Press Cmd+R to build and run

## Dependencies

- **AudioKit** (5.6.0+): Advanced audio processing
- **ID3TagEditor** (4.0.0+): ID3 tag reading/writing
- **Alamofire** (5.8.0+): Networking for ESP32-S3 communication
- **Swift Collections**: Additional collection types

## Testing

### Run All Tests

```bash
swift test
```

### Run Specific Test Suite

```bash
swift test --filter ExternalDriveManagerTests
```

### Run with Coverage

```bash
swift test --enable-code-coverage
```

## Building

### Debug Build

```bash
swift build
```

### Release Build

```bash
swift build -c release
```

### Archive for Distribution

In Xcode:
1. Product → Archive
2. Distribute App
3. Choose distribution method (App Store, Ad Hoc, etc.)

## CI/CD

The project includes GitHub Actions workflows for:
- Automated testing on multiple simulators (iPhone 15 Pro, iPhone 14, iPad Pro)
- Code coverage reporting with Codecov
- SwiftLint code quality checks
- Automated release builds
- TestFlight deployment (on main branch)
- Slack notifications

See `.github/workflows/ios-ci.yml` for details.

### Required Secrets

For CI/CD to work, configure these GitHub secrets:
- `BUILD_CERTIFICATE_BASE64`: Base64-encoded signing certificate
- `P12_PASSWORD`: Password for the .p12 certificate
- `BUILD_PROVISION_PROFILE_BASE64`: Base64-encoded provisioning profile
- `KEYCHAIN_PASSWORD`: Password for the temporary keychain
- `APP_STORE_CONNECT_API_KEY`: App Store Connect API key
- `APP_STORE_CONNECT_ISSUER_ID`: App Store Connect issuer ID
- `SLACK_WEBHOOK_URL`: Slack webhook for notifications (optional)

## Development Guidelines

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftLint for code quality (`swiftlint lint`)
- Write unit tests for all new features
- Document public APIs with doc comments
- Maintain test coverage above 70%

### Commit Messages

Follow conventional commits:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `test:` Test additions/changes
- `refactor:` Code refactoring
- `chore:` Maintenance tasks
- `style:` Code style changes
- `perf:` Performance improvements

### Pull Requests

- All PRs must pass CI checks
- Code review required from at least one team member
- All tests must pass
- No decrease in code coverage
- SwiftLint warnings must be addressed

## Architecture

The app follows MVVM (Model-View-ViewModel) architecture:

- **Models**: Data structures (ExternalDrive, DJTrack, CuePoint, etc.)
- **ViewModels**: Business logic and state management (via `@StateObject`)
- **Views**: SwiftUI views for UI (MainView, FileBrowserView, etc.)
- **Managers**: Service classes (ExternalDriveManager, AudioMetadataExtractor, DJExportManager)

### Key Components

#### ExternalDriveManager
Handles external USB drive detection and file operations:
- Monitor for drive connection/disconnection
- Scan available drives
- Copy files with progress tracking
- Manage drive capacity

#### AudioMetadataExtractor
Extracts DJ-relevant metadata from audio files:
- BPM detection using autocorrelation algorithm
- Musical key detection (Krumhansl-Schmuckler)
- Waveform generation for visualization
- ID3 tag extraction

#### DJExportManager
Exports track metadata to DJ software formats:
- Rekordbox XML
- Serato CSV
- Traktor NML
- Virtual DJ XML
- Engine Prime JSON

## Troubleshooting

### External Drive Not Detected

1. Ensure drive is properly connected via adapter
2. Check drive format (exFAT recommended)
3. Verify drive is mounted in Files app
4. Check app permissions in Settings
5. Try unplugging and reconnecting the drive

### BPM Detection Inaccurate

- Ensure audio file is not corrupted
- Try files with clear, consistent beats
- Check audio quality (higher quality = better detection)
- Verify BPM is within supported range (60-200 BPM)

### Share Extension Not Appearing

1. Ensure Share Extension target is included in build
2. Check Info.plist configuration for supported file types
3. Verify file types are compatible (MP3, WAV, AIFF, FLAC, M4A)
4. Restart device if needed
5. Check that app is installed and opened at least once

### Build Errors

- Clean build folder: Product → Clean Build Folder (Cmd+Shift+K)
- Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Resolve package dependencies: `swift package resolve`
- Update to latest Xcode version

## Performance Optimization

- Audio processing runs on background threads
- File operations use async/await for non-blocking execution
- Waveform downsampling reduces memory usage
- Drive monitoring uses efficient polling (2-second intervals)

## Security & Privacy

- All file operations respect iOS sandbox restrictions
- No data is transmitted to external servers
- User consent required for microphone and photo library access
- External drive access follows iOS security policies

## Roadmap

- [ ] Cloud sync integration (iCloud, Dropbox)
- [ ] Advanced waveform analysis (beat detection, phrases)
- [ ] Auto-BPM grid alignment
- [ ] Playlist management
- [ ] Wi-Fi file transfer support
- [ ] Integration with streaming services
- [ ] Advanced mixing features (EQ, effects)

## License

[Your License Here - e.g., MIT, Apache 2.0]

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Support

For issues and questions:
- Open an issue on GitHub
- Email: support@wavedrop.app
- Documentation: https://docs.wavedrop.app

## Acknowledgments

- AudioKit team for the excellent audio processing library
- ID3TagEditor for ID3 tag support
- Alamofire for networking capabilities
- The Swift community for continuous innovation

---

**Made with ❤️ for DJs worldwide**
