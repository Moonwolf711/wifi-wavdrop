/**
 * Wireless USB Bridge - Main Firmware (ESP-IDF with USB Host)
 *
 * This version uses real USB Host functionality to read from actual USB drives.
 *
 * Hardware: ESP32-S3 with USB OTG support
 * Framework: ESP-IDF
 */

#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "nvs_flash.h"
#include "mdns.h"
#include "esp_http_server.h"
#include "cJSON.h"

#include "Config.h"
#include "USBHostManager.h"

static const char *TAG = "WirelessUSB";

// ============================================================================
// Global Objects
// ============================================================================

static httpd_handle_t server = NULL;
static USBHostManager* usbManager = nullptr;
static bool wifiConnected = false;

// ============================================================================
// LED Control
// ============================================================================

void setup_leds() {
    gpio_reset_pin((gpio_num_t)LED_POWER);
    gpio_reset_pin((gpio_num_t)LED_WIFI);
    gpio_reset_pin((gpio_num_t)LED_USB);
    gpio_reset_pin((gpio_num_t)LED_ERROR);

    gpio_set_direction((gpio_num_t)LED_POWER, GPIO_MODE_OUTPUT);
    gpio_set_direction((gpio_num_t)LED_WIFI, GPIO_MODE_OUTPUT);
    gpio_set_direction((gpio_num_t)LED_USB, GPIO_MODE_OUTPUT);
    gpio_set_direction((gpio_num_t)LED_ERROR, GPIO_MODE_OUTPUT);

    // Power LED always on
    gpio_set_level((gpio_num_t)LED_POWER, 1);
    gpio_set_level((gpio_num_t)LED_WIFI, 0);
    gpio_set_level((gpio_num_t)LED_USB, 0);
    gpio_set_level((gpio_num_t)LED_ERROR, 0);
}

void update_leds() {
    gpio_set_level((gpio_num_t)LED_WIFI, wifiConnected ? 1 : 0);
    gpio_set_level((gpio_num_t)LED_USB, usbManager && usbManager->isMounted() ? 1 : 0);
}

// ============================================================================
// WiFi Event Handler
// ============================================================================

static void wifi_event_handler(void* arg, esp_event_base_t event_base,
                                int32_t event_id, void* event_data) {
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        ESP_LOGI(TAG, "WiFi disconnected, reconnecting...");
        wifiConnected = false;
        update_leds();
        esp_wifi_connect();
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t* event = (ip_event_got_ip_t*) event_data;
        ESP_LOGI(TAG, "✓ WiFi Connected! IP: " IPSTR, IP2STR(&event->ip_info.ip));
        wifiConnected = true;
        update_leds();
    }
}

// ============================================================================
// WiFi Initialization
// ============================================================================

void wifi_init() {
    ESP_LOGI(TAG, "Initializing WiFi...");

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL));

    wifi_config_t wifi_config = {};
    strcpy((char*)wifi_config.sta.ssid, WIFI_SSID);
    strcpy((char*)wifi_config.sta.password, WIFI_PASSWORD);
    wifi_config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());

    ESP_LOGI(TAG, "WiFi initialized, connecting to %s...", WIFI_SSID);
}

// ============================================================================
// mDNS Initialization
// ============================================================================

void mdns_init_service() {
    ESP_LOGI(TAG, "Starting mDNS service...");

    ESP_ERROR_CHECK(mdns_init());
    ESP_ERROR_CHECK(mdns_hostname_set(MDNS_HOSTNAME));
    ESP_LOGI(TAG, "mDNS hostname set to: %s.local", MDNS_HOSTNAME);

    // Add service
    ESP_ERROR_CHECK(mdns_service_add(NULL, SERVICE_TYPE, "_tcp", HTTP_SERVER_PORT, NULL, 0));

    // Add TXT records
    mdns_txt_item_t txt_data[3] = {
        {"version", FIRMWARE_VERSION},
        {"device", DEVICE_NAME},
        {"filesystem", "FAT32"}
    };
    ESP_ERROR_CHECK(mdns_service_txt_set(SERVICE_TYPE, "_tcp", txt_data, 3));

    ESP_LOGI(TAG, "✓ mDNS service started: %s", SERVICE_TYPE);
}

// ============================================================================
// HTTP Server Handlers
// ============================================================================

// GET /api/info
static esp_err_t info_handler(httpd_req_t *req) {
    ESP_LOGI(TAG, "API: /api/info");

    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "device_name", DEVICE_NAME);
    cJSON_AddStringToObject(root, "firmware_version", FIRMWARE_VERSION);

    if (usbManager) {
        USBDriveInfo info = usbManager->getDriveInfo();
        cJSON_AddStringToObject(root, "usb_status", info.mounted ? "mounted" : "not_mounted");
        cJSON_AddStringToObject(root, "filesystem", info.filesystem.c_str());
        cJSON_AddNumberToObject(root, "total_space", (double)info.totalBytes);
        cJSON_AddNumberToObject(root, "free_space", (double)info.freeBytes);
        cJSON_AddStringToObject(root, "volume_label", info.volumeLabel.c_str());
    } else {
        cJSON_AddStringToObject(root, "usb_status", "not_initialized");
    }

    const char *json_str = cJSON_Print(root);
    httpd_resp_set_type(req, "application/json");
    httpd_resp_sendstr(req, json_str);

    free((void*)json_str);
    cJSON_Delete(root);
    return ESP_OK;
}

// GET /api/files?path=/
static esp_err_t files_handler(httpd_req_t *req) {
    char path[256] = "/";

    // Get path parameter
    char query[512];
    if (httpd_req_get_url_query_str(req, query, sizeof(query)) == ESP_OK) {
        char param[256];
        if (httpd_query_key_value(query, "path", param, sizeof(param)) == ESP_OK) {
            strncpy(path, param, sizeof(path) - 1);
        }
    }

    ESP_LOGI(TAG, "API: /api/files?path=%s", path);

    if (!usbManager || !usbManager->isMounted()) {
        httpd_resp_set_status(req, "503 Service Unavailable");
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"error\":\"USB drive not mounted\"}");
        return ESP_OK;
    }

    // List files
    std::vector<FileEntry> files = usbManager->listFiles(path);

    // Build JSON response
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "path", path);

    cJSON *files_array = cJSON_AddArrayToObject(root, "files");
    for (const auto& file : files) {
        cJSON *file_obj = cJSON_CreateObject();
        cJSON_AddStringToObject(file_obj, "name", file.name.c_str());
        cJSON_AddStringToObject(file_obj, "type", file.isDirectory ? "directory" : "file");

        if (!file.isDirectory) {
            cJSON_AddNumberToObject(file_obj, "size", (double)file.size);
        } else {
            // Could add item_count here if we wanted to count subdirectory items
        }

        if (file.modified > 0) {
            char time_str[32];
            strftime(time_str, sizeof(time_str), "%Y-%m-%dT%H:%M:%SZ", gmtime(&file.modified));
            cJSON_AddStringToObject(file_obj, "modified", time_str);
        }

        cJSON_AddItemToArray(files_array, file_obj);
    }

    const char *json_str = cJSON_Print(root);
    httpd_resp_set_type(req, "application/json");
    httpd_resp_sendstr(req, json_str);

    free((void*)json_str);
    cJSON_Delete(root);
    return ESP_OK;
}

// GET /api/download?path=/file.mp3
static esp_err_t download_handler(httpd_req_t *req) {
    char path[256] = "";

    // Get path parameter
    char query[512];
    if (httpd_req_get_url_query_str(req, query, sizeof(query)) != ESP_OK) {
        httpd_resp_set_status(req, "400 Bad Request");
        httpd_resp_sendstr(req, "{\"error\":\"Missing path parameter\"}");
        return ESP_OK;
    }

    if (httpd_query_key_value(query, "path", path, sizeof(path)) != ESP_OK) {
        httpd_resp_set_status(req, "400 Bad Request");
        httpd_resp_sendstr(req, "{\"error\":\"Invalid path parameter\"}");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "API: /api/download?path=%s", path);

    if (!usbManager || !usbManager->isMounted()) {
        httpd_resp_set_status(req, "503 Service Unavailable");
        httpd_resp_sendstr(req, "{\"error\":\"USB drive not mounted\"}");
        return ESP_OK;
    }

    if (!usbManager->fileExists(path)) {
        httpd_resp_set_status(req, "404 Not Found");
        httpd_resp_sendstr(req, "{\"error\":\"File not found\"}");
        return ESP_OK;
    }

    // Read file
    std::vector<uint8_t> data = usbManager->readFile(path);
    if (data.empty()) {
        httpd_resp_set_status(req, "500 Internal Server Error");
        httpd_resp_sendstr(req, "{\"error\":\"Failed to read file\"}");
        return ESP_OK;
    }

    // Extract filename
    const char* filename = strrchr(path, '/');
    filename = filename ? filename + 1 : path;

    // Set headers
    httpd_resp_set_type(req, "application/octet-stream");

    char content_disp[512];
    snprintf(content_disp, sizeof(content_disp), "attachment; filename=\"%s\"", filename);
    httpd_resp_set_hdr(req, "Content-Disposition", content_disp);

    // Send file
    httpd_resp_send(req, (const char*)data.data(), data.size());

    ESP_LOGI(TAG, "Downloaded %d bytes: %s", data.size(), path);
    return ESP_OK;
}

// GET / - Root HTML page
static esp_err_t root_handler(httpd_req_t *req) {
    const char* html = "<!DOCTYPE html><html><head><title>WaveDrop USB Bridge</title></head>"
                       "<body><h1>WaveDrop Wireless USB Bridge</h1>"
                       "<p>Server is running. Access via WaveDrop iOS app.</p>"
                       "<h3>API Endpoints:</h3>"
                       "<ul><li>GET /api/info</li><li>GET /api/files?path=/</li>"
                       "<li>GET /api/download?path=/file.mp3</li></ul></body></html>";

    httpd_resp_set_type(req, "text/html");
    httpd_resp_sendstr(req, html);
    return ESP_OK;
}

// ============================================================================
// HTTP Server Initialization
// ============================================================================

void start_webserver() {
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.server_port = HTTP_SERVER_PORT;
    config.max_uri_handlers = 10;

    ESP_LOGI(TAG, "Starting HTTP server on port %d...", config.server_port);

    if (httpd_start(&server, &config) == ESP_OK) {
        // Register URI handlers
        httpd_uri_t info_uri = {
            .uri = "/api/info",
            .method = HTTP_GET,
            .handler = info_handler,
            .user_ctx = NULL
        };
        httpd_register_uri_handler(server, &info_uri);

        httpd_uri_t files_uri = {
            .uri = "/api/files",
            .method = HTTP_GET,
            .handler = files_handler,
            .user_ctx = NULL
        };
        httpd_register_uri_handler(server, &files_uri);

        httpd_uri_t download_uri = {
            .uri = "/api/download",
            .method = HTTP_GET,
            .handler = download_handler,
            .user_ctx = NULL
        };
        httpd_register_uri_handler(server, &download_uri);

        httpd_uri_t root_uri = {
            .uri = "/",
            .method = HTTP_GET,
            .handler = root_handler,
            .user_ctx = NULL
        };
        httpd_register_uri_handler(server, &root_uri);

        ESP_LOGI(TAG, "✓ HTTP server started");
    } else {
        ESP_LOGE(TAG, "Failed to start HTTP server");
    }
}

// ============================================================================
// Main Application
// ============================================================================

extern "C" void app_main(void) {
    ESP_LOGI(TAG, "======================================");
    ESP_LOGI(TAG, " Wireless USB Bridge - USB Host");
    ESP_LOGI(TAG, " Version: %s", FIRMWARE_VERSION);
    ESP_LOGI(TAG, "======================================");

    // Initialize NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Setup LEDs
    setup_leds();
    ESP_LOGI(TAG, "✓ LEDs initialized");

    // Initialize USB Host
    usbManager = new USBHostManager();

    usbManager->setConnectionCallback([](bool connected) {
        ESP_LOGI(TAG, "USB %s", connected ? "Connected" : "Disconnected");
        update_leds();
    });

    usbManager->setMountCallback([](bool mounted, const std::string& error) {
        if (mounted) {
            ESP_LOGI(TAG, "✓ USB Drive Mounted");
        } else {
            ESP_LOGE(TAG, "✗ USB Mount Failed: %s", error.c_str());
        }
        update_leds();
    });

    if (!usbManager->begin()) {
        ESP_LOGE(TAG, "Failed to initialize USB Host");
        gpio_set_level((gpio_num_t)LED_ERROR, 1);
    } else {
        ESP_LOGI(TAG, "✓ USB Host initialized");
    }

    // Initialize WiFi
    wifi_init();

    // Wait for WiFi connection
    vTaskDelay(pdMS_TO_TICKS(5000));

    if (wifiConnected) {
        // Start mDNS
        mdns_init_service();

        // Start HTTP server
        start_webserver();

        ESP_LOGI(TAG, "======================================");
        ESP_LOGI(TAG, " 🎉 System Ready!");
        ESP_LOGI(TAG, "======================================");
        ESP_LOGI(TAG, " Server URL: http://%s.local:%d", MDNS_HOSTNAME, HTTP_SERVER_PORT);
        ESP_LOGI(TAG, "======================================");
    } else {
        ESP_LOGE(TAG, "Failed to connect to WiFi");
        gpio_set_level((gpio_num_t)LED_ERROR, 1);
    }

    // Main loop
    while (1) {
        if (usbManager) {
            usbManager->handleEvents();
        }
        update_leds();
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}
