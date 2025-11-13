#!/bin/bash
# Build and upload Production firmware (ESP-IDF with real USB Host)
# Requires USB drive for testing

set -e

echo "=========================================="
echo "WaveDrop Wireless USB Bridge - Production"
echo "=========================================="
echo ""

# Check if PlatformIO is installed
if ! command -v pio &> /dev/null; then
    echo "❌ PlatformIO not installed!"
    echo ""
    echo "Install with: pip install platformio"
    echo "Or see: PLATFORMIO_SETUP.md"
    exit 1
fi

echo "✓ PlatformIO found: $(pio --version)"
echo ""

# Navigate to project directory
cd "$(dirname "$0")"

# Backup current config
if [ -f platformio.ini ]; then
    cp platformio.ini platformio.ini.backup
    echo "📝 Backed up current platformio.ini"
fi

# Switch to ESP-IDF config
echo "📝 Switching to ESP-IDF configuration..."
cp platformio-espidf.ini platformio.ini

echo "🧹 Cleaning previous build..."
pio run --target clean
rm -rf .pio

echo ""
echo "🔧 Building Production firmware (ESP-IDF framework)..."
echo "   ⚠️  First build may take 5-10 minutes"
echo ""

# Build
pio run -e esp32s3-usb-host

echo ""
echo "✓ Build complete!"
echo ""
echo "Next steps:"
echo "1. Connect ESP32-S3 via USB-C"
echo "2. Run: pio run -e esp32s3-usb-host --target upload"
echo "3. Monitor: pio device monitor"
echo "4. Plug in FAT32 USB drive"
echo "5. Check yellow LED turns on"
echo ""
echo "Or run: ./upload-production.sh"
