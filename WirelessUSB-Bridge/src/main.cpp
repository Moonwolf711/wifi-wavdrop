/**
 * Wireless USB Bridge - Main Firmware
 *
 * Transforms any USB drive into a wireless drive accessible
 * from the WaveDrop iOS app over WiFi.
 *
 * Hardware: ESP32-S3 with USB OTG support
 * Framework: Arduino
 */

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <ESPAsyncWebServer.h>
#include <AsyncTCP.h>
#include <ArduinoJson.h>
#include <FS.h>
#include <USB.h>
#include "Config.h"

// ============================================================================
// Global Objects
// ============================================================================

AsyncWebServer server(HTTP_SERVER_PORT);
bool wifiConnected = false;
bool usbMounted = false;
unsigned long lastUSBCheck = 0;
unsigned long lastWiFiCheck = 0;

// USB drive info
String volumeLabel = "USB_DRIVE";
uint64_t totalSpace = 0;
uint64_t freeSpace = 0;

// ============================================================================
// LED Control
// ============================================================================

void setupLEDs() {
    pinMode(LED_POWER, OUTPUT);
    pinMode(LED_WIFI, OUTPUT);
    pinMode(LED_USB, OUTPUT);
    pinMode(LED_ERROR, OUTPUT);

    // Power LED always on
    digitalWrite(LED_POWER, HIGH);
    digitalWrite(LED_WIFI, LOW);
    digitalWrite(LED_USB, LOW);
    digitalWrite(LED_ERROR, LOW);
}

void updateLEDs() {
    digitalWrite(LED_WIFI, wifiConnected ? HIGH : LOW);
    digitalWrite(LED_USB, usbMounted ? HIGH : LOW);
}

void setError(bool error) {
    digitalWrite(LED_ERROR, error ? HIGH : LOW);
}

// ============================================================================
// WiFi Management
// ============================================================================

bool setupWiFi() {
    DEBUG_PRINTLN("\\n=== Starting WiFi ===");
    DEBUG_PRINTF("Connecting to: %s\\n", WIFI_SSID);

    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    unsigned long startTime = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - startTime < WIFI_TIMEOUT_MS) {
        delay(500);
        DEBUG_PRINT(".");
    }

    if (WiFi.status() == WL_CONNECTED) {
        wifiConnected = true;
        DEBUG_PRINTLN("\\n✓ WiFi Connected!");
        DEBUG_PRINTF("IP Address: %s\\n", WiFi.localIP().toString().c_str());
        DEBUG_PRINTF("SSID: %s\\n", WiFi.SSID().c_str());
        DEBUG_PRINTF("Signal: %d dBm\\n", WiFi.RSSI());
        return true;
    }

    DEBUG_PRINTLN("\\n✗ WiFi Connection Failed");
    wifiConnected = false;
    return false;
}

void reconnectWiFi() {
    if (WiFi.status() != WL_CONNECTED) {
        DEBUG_PRINTLN("WiFi disconnected, reconnecting...");
        wifiConnected = false;
        updateLEDs();
        WiFi.disconnect();
        delay(1000);
        setupWiFi();
    }
}

// ============================================================================
// mDNS / Bonjour Setup
// ============================================================================

bool setupMDNS() {
    DEBUG_PRINTLN("\\n=== Starting mDNS ===");

    if (!MDNS.begin(MDNS_HOSTNAME)) {
        DEBUG_PRINTLN("✗ mDNS Failed to start");
        return false;
    }

    // Add service
    MDNS.addService(SERVICE_TYPE, "tcp", HTTP_SERVER_PORT);

    // Add TXT records
    MDNS.addServiceTxt(SERVICE_TYPE, "tcp", "version", FIRMWARE_VERSION);
    MDNS.addServiceTxt(SERVICE_TYPE, "tcp", "device", DEVICE_NAME);

    if (usbMounted) {
        MDNS.addServiceTxt(SERVICE_TYPE, "tcp", "filesystem", "FAT32");
        MDNS.addServiceTxt(SERVICE_TYPE, "tcp", "volume", volumeLabel);
    }

    DEBUG_PRINTF("✓ mDNS started: %s.local\\n", MDNS_HOSTNAME);
    DEBUG_PRINTF("Service: %s on port %d\\n", SERVICE_TYPE, HTTP_SERVER_PORT);

    return true;
}

// ============================================================================
// USB Management (Simulated for MVP - Actual implementation needs USB Host)
// ============================================================================

bool mountUSB() {
    DEBUG_PRINTLN("\\n=== Mounting USB Drive ===");

    // NOTE: This is a simplified simulation for MVP
    // Real implementation would use ESP32-S3 USB Host libraries
    // to mount actual USB Mass Storage devices

    // Simulate USB mount
    usbMounted = true;
    volumeLabel = "DJ_MUSIC";
    totalSpace = 32000000000;  // 32GB
    freeSpace = 12000000000;   // 12GB free

    DEBUG_PRINTLN("✓ USB Drive Mounted (Simulated)");
    DEBUG_PRINTF("Volume: %s\\n", volumeLabel.c_str());
    DEBUG_PRINTF("Capacity: %.2f GB\\n", totalSpace / 1e9);
    DEBUG_PRINTF("Free: %.2f GB\\n", freeSpace / 1e9);

    return true;
}

void checkUSB() {
    // Periodically check USB drive status
    // In real implementation, check for USB device presence
    if (millis() - lastUSBCheck > USB_CHECK_INTERVAL_MS) {
        // Simulated check - always mounted for MVP
        if (!usbMounted) {
            mountUSB();
        }
        lastUSBCheck = millis();
    }
}

// ============================================================================
// HTTP API Handlers
// ============================================================================

// GET /api/info - Drive information
void handleInfo(AsyncWebServerRequest *request) {
    DEBUG_PRINTLN("API: /api/info");

    DynamicJsonDocument doc(512);
    doc["device_name"] = DEVICE_NAME;
    doc["firmware_version"] = FIRMWARE_VERSION;
    doc["usb_status"] = usbMounted ? "mounted" : "not_mounted";
    doc["filesystem"] = "FAT32";
    doc["total_space"] = totalSpace;
    doc["free_space"] = freeSpace;
    doc["volume_label"] = volumeLabel;
    doc["wifi_ssid"] = WiFi.SSID();
    doc["ip_address"] = WiFi.localIP().toString();

    String response;
    serializeJson(doc, response);

    request->send(200, "application/json", response);
}

// GET /api/files?path=/ - List files
void handleFiles(AsyncWebServerRequest *request) {
    String path = request->hasParam("path") ? request->getParam("path")->value() : "/";
    DEBUG_PRINTF("API: /api/files?path=%s\\n", path.c_str());

    if (!usbMounted) {
        request->send(503, "application/json", "{\"error\":\"USB drive not mounted\"}");
        return;
    }

    // Simulated file listing for MVP
    DynamicJsonDocument doc(4096);
    doc["path"] = path;

    JsonArray files = doc.createNestedArray("files");

    // Add some simulated files/folders
    if (path == "/") {
        JsonObject folder1 = files.createNestedObject();
        folder1["name"] = "Music";
        folder1["type"] = "directory";
        folder1["item_count"] = 42;

        JsonObject folder2 = files.createNestedObject();
        folder2["name"] = "DJ_Sets";
        folder2["type"] = "directory";
        folder2["item_count"] = 15;

        JsonObject file1 = files.createNestedObject();
        file1["name"] = "README.txt";
        file1["size"] = 1024;
        file1["type"] = "file";
        file1["modified"] = "2025-11-12T10:30:00Z";
    } else if (path == "/Music") {
        JsonObject file1 = files.createNestedObject();
        file1["name"] = "track001.mp3";
        file1["size"] = 8453210;
        file1["type"] = "file";
        file1["modified"] = "2025-11-10T15:20:00Z";

        JsonObject file2 = files.createNestedObject();
        file2["name"] = "track002.mp3";
        file2["size"] = 7234567;
        file2["type"] = "file";
        file2["modified"] = "2025-11-10T15:25:00Z";
    }

    String response;
    serializeJson(doc, response);

    request->send(200, "application/json", response);
}

// GET /api/download?path=... - Download file
void handleDownload(AsyncWebServerRequest *request) {
    if (!request->hasParam("path")) {
        request->send(400, "application/json", "{\"error\":\"Missing path parameter\"}");
        return;
    }

    String path = request->getParam("path")->value();
    DEBUG_PRINTF("API: /api/download?path=%s\\n", path.c_str());

    if (!usbMounted) {
        request->send(503, "application/json", "{\"error\":\"USB drive not mounted\"}");
        return;
    }

    // Simulated file download for MVP
    // Real implementation would read from USB drive and stream
    String filename = path.substring(path.lastIndexOf('/') + 1);

    // Send simulated file (small text file for demonstration)
    String fileContent = "This is a simulated file from Wireless USB Bridge MVP\\n";
    fileContent += "File: " + path + "\\n";
    fileContent += "Device: " + String(DEVICE_NAME) + "\\n";

    AsyncWebServerResponse *response = request->beginResponse(200, "application/octet-stream", fileContent);
    response->addHeader("Content-Disposition", "attachment; filename=\\"" + filename + "\\"");
    request->send(response);
}

// GET / - Root endpoint (HTML upload page)
void handleRoot(AsyncWebServerRequest *request) {
    DEBUG_PRINTLN("API: /");

    String html = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
    <title>WaveDrop USB Bridge</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            margin-top: 0;
        }
        .status {
            padding: 15px;
            margin: 20px 0;
            border-radius: 5px;
            background: #e8f5e9;
            border-left: 4px solid #4caf50;
        }
        .info-grid {
            display: grid;
            grid-template-columns: 150px 1fr;
            gap: 10px;
            margin: 20px 0;
        }
        .info-label {
            font-weight: bold;
            color: #666;
        }
        .api-doc {
            background: #f9f9f9;
            padding: 15px;
            border-radius: 5px;
            margin-top: 20px;
        }
        code {
            background: #333;
            color: #fff;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎵 WaveDrop Wireless USB Bridge</h1>

        <div class="status">
            ✓ Server is running and ready
        </div>

        <div class="info-grid">
            <div class="info-label">Device:</div>
            <div>)rawliteral" + String(DEVICE_NAME) + R"rawliteral(</div>

            <div class="info-label">Version:</div>
            <div>)rawliteral" + String(FIRMWARE_VERSION) + R"rawliteral(</div>

            <div class="info-label">IP Address:</div>
            <div>)rawliteral" + WiFi.localIP().toString() + R"rawliteral(</div>

            <div class="info-label">USB Status:</div>
            <div>)rawliteral" + String(usbMounted ? "✓ Mounted" : "✗ Not Mounted") + R"rawliteral(</div>
        </div>

        <div class="api-doc">
            <h3>API Endpoints:</h3>
            <p><code>GET /api/info</code> - Drive information</p>
            <p><code>GET /api/files?path=/</code> - List files</p>
            <p><code>GET /api/download?path=/file.mp3</code> - Download file</p>
        </div>

        <p style="margin-top: 30px; color: #666; text-align: center;">
            Access this device from the WaveDrop iOS app
        </p>
    </div>
</body>
</html>
)rawliteral";

    request->send(200, "text/html", html);
}

// ============================================================================
// HTTP Server Setup
// ============================================================================

void setupHTTPServer() {
    DEBUG_PRINTLN("\\n=== Starting HTTP Server ===");

    // API endpoints
    server.on(API_INFO, HTTP_GET, handleInfo);
    server.on(API_FILES, HTTP_GET, handleFiles);
    server.on(API_DOWNLOAD, HTTP_GET, handleDownload);
    server.on(API_ROOT, HTTP_GET, handleRoot);

    // 404 handler
    server.onNotFound([](AsyncWebServerRequest *request) {
        request->send(404, "application/json", "{\"error\":\"Not found\"}");
    });

    server.begin();

    DEBUG_PRINTF("✓ HTTP Server started on port %d\\n", HTTP_SERVER_PORT);
    DEBUG_PRINTF("Access at: http://%s.local:%d\\n", MDNS_HOSTNAME, HTTP_SERVER_PORT);
    DEBUG_PRINTF("Or: http://%s:%d\\n", WiFi.localIP().toString().c_str(), HTTP_SERVER_PORT);
}

// ============================================================================
// Setup & Main Loop
// ============================================================================

void setup() {
    Serial.begin(115200);
    delay(1000);

    DEBUG_PRINTLN("\\n\\n");
    DEBUG_PRINTLN("========================================");
    DEBUG_PRINTLN("  Wireless USB Bridge - MVP");
    DEBUG_PRINTLN("  Version: " + String(FIRMWARE_VERSION));
    DEBUG_PRINTLN("========================================");

    // Initialize LEDs
    setupLEDs();
    DEBUG_PRINTLN("✓ LEDs initialized");

    // Mount USB drive (simulated for MVP)
    mountUSB();
    updateLEDs();

    // Connect to WiFi
    if (setupWiFi()) {
        updateLEDs();

        // Start mDNS
        setupMDNS();

        // Start HTTP server
        setupHTTPServer();

        DEBUG_PRINTLN("\\n========================================");
        DEBUG_PRINTLN("  🎉 System Ready!");
        DEBUG_PRINTLN("========================================");
        DEBUG_PRINTF("  Server URL: http://%s.local:%d\\n", MDNS_HOSTNAME, HTTP_SERVER_PORT);
        DEBUG_PRINTF("  IP Address: http://%s:%d\\n", WiFi.localIP().toString().c_str(), HTTP_SERVER_PORT);
        DEBUG_PRINTLN("========================================\\n");
    } else {
        DEBUG_PRINTLN("\\n✗ Setup Failed - WiFi not connected");
        setError(true);
    }
}

void loop() {
    // Check WiFi connection
    if (millis() - lastWiFiCheck > WIFI_RECONNECT_INTERVAL_MS) {
        reconnectWiFi();
        updateLEDs();
        lastWiFiCheck = millis();
    }

    // Check USB drive
    checkUSB();
    updateLEDs();

    // Small delay to prevent watchdog issues
    delay(10);
}
