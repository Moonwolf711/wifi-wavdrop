#!/bin/bash
# Build and upload MVP firmware (Arduino framework with simulated USB)
# Quick testing - no real USB drive required

set -e

echo "=================================="
echo "WaveDrop Wireless USB Bridge - MVP"
echo "=================================="
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

# Ensure we're using Arduino config
if [ ! -f platformio.ini ] || ! grep -q "framework = arduino" platformio.ini; then
    echo "📝 Switching to Arduino config..."
    cp platformio.ini platformio.ini.backup 2>/dev/null || true
    # Default platformio.ini should be Arduino
fi

echo "🔧 Building MVP firmware (Arduino framework)..."
echo ""

# Build
pio run -e esp32s3

echo ""
echo "✓ Build complete!"
echo ""
echo "Next steps:"
echo "1. Connect ESP32-S3 via USB-C"
echo "2. Run: pio run -e esp32s3 --target upload"
echo "3. Monitor: pio device monitor"
echo ""
echo "Or run: ./upload-mvp.sh"
