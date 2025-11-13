#!/bin/bash
# Upload Production firmware and monitor serial output

set -e

echo "=========================================="
echo "Upload Production Firmware"
echo "=========================================="
echo ""

# Check PlatformIO
if ! command -v pio &> /dev/null; then
    echo "❌ PlatformIO not installed!"
    exit 1
fi

cd "$(dirname "$0")"

# Verify ESP-IDF config
if ! grep -q "framework = espidf" platformio.ini; then
    echo "⚠️  Not using ESP-IDF config!"
    echo "Run ./build-production.sh first"
    exit 1
fi

# Check for connected device
echo "🔍 Looking for ESP32-S3..."
pio device list

echo ""
echo "📤 Uploading firmware..."
pio run -e esp32s3-usb-host --target upload

echo ""
echo "✓ Upload complete!"
echo ""
echo "📋 Testing checklist:"
echo "  1. Green LED = WiFi connected"
echo "  2. Plug in USB drive (FAT32 formatted)"
echo "  3. Yellow LED = USB mounted"
echo "  4. Check serial monitor for mount confirmation"
echo ""
echo "📡 Starting serial monitor..."
echo "   (Press Ctrl+C to exit)"
echo ""
sleep 2

pio device monitor
