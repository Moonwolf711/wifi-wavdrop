#!/bin/bash
# Quick PlatformIO Installation Script for WSL/Debian
# Run this to install Python and PlatformIO in one command

set -e

echo "=========================================="
echo "PlatformIO Quick Install"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
   echo "❌ Don't run as root! Run as regular user (it will ask for sudo password when needed)"
   exit 1
fi

echo "📦 Installing Python 3 and pip..."
echo "   (You'll need to enter your sudo password)"
echo ""

sudo apt update
sudo apt install -y python3 python3-pip python3-venv

echo ""
echo "✓ Python installed: $(python3 --version)"
echo ""

echo "📦 Installing PlatformIO..."
echo ""

pip3 install --user platformio

echo ""
echo "✓ PlatformIO installed!"
echo ""

# Add to PATH
if ! grep -q ".local/bin" ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    echo "✓ Added PlatformIO to PATH in ~/.bashrc"
fi

echo ""
echo "=========================================="
echo "✓ Installation Complete!"
echo "=========================================="
echo ""
echo "Run this command to update your current shell:"
echo "  source ~/.bashrc"
echo ""
echo "Or close and reopen your terminal."
echo ""
echo "Then verify:"
echo "  pio --version"
echo ""
echo "Next steps:"
echo "  1. Configure WiFi in include/Config.h"
echo "  2. Run ./build-mvp.sh"
echo ""
