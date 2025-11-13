// Wireless USB Bridge - Configuration
#ifndef CONFIG_H
#define CONFIG_H

// Device Information
#define DEVICE_NAME "WaveDrop-USB-Bridge"
#define FIRMWARE_VERSION "1.0.0"
#define SERVICE_TYPE "_wavedrop-usb._tcp"

// WiFi Configuration
#define WIFI_SSID "YourWiFiSSID"          // Change this
#define WIFI_PASSWORD "YourWiFiPassword"  // Change this
#define WIFI_AP_SSID "WaveDrop-USB-Setup"
#define WIFI_AP_PASSWORD "wavedrop123"
#define WIFI_TIMEOUT_MS 20000

// Network Configuration
#define HTTP_SERVER_PORT 8081
#define MDNS_HOSTNAME "wavedrop-usb"

// USB Configuration
#define USB_MOUNT_PATH "/usb"
#define MAX_FILE_SIZE_MB 500
#define BUFFER_SIZE 4096

// LED Pins (adjust for your ESP32-S3 board)
#define LED_POWER 10   // Blue - Power ON
#define LED_WIFI 11    // Green - WiFi Connected
#define LED_USB 12     // Yellow - USB Drive Mounted
#define LED_ERROR 13   // Red - Error State

// Timeouts
#define USB_CHECK_INTERVAL_MS 2000
#define WIFI_RECONNECT_INTERVAL_MS 5000

// API Paths
#define API_INFO "/api/info"
#define API_FILES "/api/files"
#define API_DOWNLOAD "/api/download"
#define API_ROOT "/"

// Debug
#ifdef WU_DEBUG
  #define DEBUG_PRINT(x) Serial.print(x)
  #define DEBUG_PRINTLN(x) Serial.println(x)
  #define DEBUG_PRINTF(fmt, ...) Serial.printf(fmt, ##__VA_ARGS__)
#else
  #define DEBUG_PRINT(x)
  #define DEBUG_PRINTLN(x)
  #define DEBUG_PRINTF(fmt, ...)
#endif

#endif // CONFIG_H
