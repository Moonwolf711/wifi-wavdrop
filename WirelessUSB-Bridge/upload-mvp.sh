#!/bin/bash
# Upload MVP firmware and monitor serial output

set -e

echo "=================================="
echo "Upload MVP Firmware"
echo "=================================="
echo ""

# Check PlatformIO
if ! command -v pio &> /dev/null; then
    echo "❌ PlatformIO not installed!"
    exit 1
fi

cd "$(dirname "$0")"

# Check for connected device
echo "🔍 Looking for ESP32-S3..."
pio device list

echo ""
echo "📤 Uploading firmware..."
pio run -e esp32s3 --target upload

echo ""
echo "✓ Upload complete!"
echo ""
echo "📡 Starting serial monitor..."
echo "   (Press Ctrl+C to exit)"
echo ""
sleep 2

pio device monitor
