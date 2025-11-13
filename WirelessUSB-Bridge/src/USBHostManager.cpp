/**
 * USBHostManager.cpp
 * Implementation of USB Host Mass Storage management
 */

#include "USBHostManager.h"
#include <esp_log.h>
#include <sys/stat.h>
#include <dirent.h>
#include <cstring>

static const char *TAG = "USBHostManager";

// Static member initialization
constexpr const char* USBHostManager::MOUNT_POINT;

USBHostManager::USBHostManager()
    : mscDevice(nullptr)
    , vfsHandle(nullptr)
    , initialized(false)
{
    driveInfo.mounted = false;
    driveInfo.mountPoint = MOUNT_POINT;
}

USBHostManager::~USBHostManager() {
    end();
}

bool USBHostManager::begin() {
    if (initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return true;
    }

    ESP_LOGI(TAG, "Initializing USB Host...");

    // Install USB Host driver
    const usb_host_config_t host_config = {
        .skip_phy_setup = false,
        .intr_flags = ESP_INTR_FLAG_LEVEL1,
    };

    esp_err_t err = usb_host_install(&host_config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to install USB Host: %s", esp_err_to_name(err));
        return false;
    }

    // Initialize MSC host
    const msc_host_driver_config_t msc_config = {
        .create_backround_task = true,
        .task_priority = 5,
        .stack_size = 4096,
        .callback = mscEventCallback,
        .callback_arg = this,
    };

    err = msc_host_install(&msc_config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to install MSC Host: %s", esp_err_to_name(err));
        usb_host_uninstall();
        return false;
    }

    initialized = true;
    ESP_LOGI(TAG, "✓ USB Host initialized");

    return true;
}

void USBHostManager::end() {
    if (!initialized) return;

    unmountDrive();

    msc_host_uninstall();
    usb_host_uninstall();

    initialized = false;
    ESP_LOGI(TAG, "USB Host stopped");
}

bool USBHostManager::mountDrive() {
    if (driveInfo.mounted) {
        ESP_LOGW(TAG, "Drive already mounted");
        return true;
    }

    ESP_LOGI(TAG, "Mounting USB drive...");

    // Wait for MSC device
    ESP_LOGI(TAG, "Waiting for MSC device...");

    msc_host_device_info_t info;
    esp_err_t err = msc_host_install_device(0, &mscDevice);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to install MSC device: %s", esp_err_to_name(err));
        if (mountCallback) {
            mountCallback(false, "Failed to detect USB device");
        }
        return false;
    }

    msc_host_print_descriptors(mscDevice);

    // Get device info
    err = msc_host_get_device_info(mscDevice, &info);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to get device info: %s", esp_err_to_name(err));
    }

    // Mount VFS
    const esp_vfs_fat_mount_config_t mount_config = {
        .format_if_mount_failed = false,
        .max_files = 5,
        .allocation_unit_size = 0,
    };

    err = msc_host_vfs_register(mscDevice, MOUNT_POINT, &mount_config, &vfsHandle);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to mount VFS: %s", esp_err_to_name(err));
        msc_host_uninstall_device(mscDevice);
        mscDevice = nullptr;

        if (mountCallback) {
            mountCallback(false, "Failed to mount filesystem");
        }
        return false;
    }

    driveInfo.mounted = true;
    updateDriveInfo();

    ESP_LOGI(TAG, "✓ USB drive mounted at %s", MOUNT_POINT);
    ESP_LOGI(TAG, "   Volume: %s", driveInfo.volumeLabel.c_str());
    ESP_LOGI(TAG, "   Total: %.2f GB", driveInfo.totalBytes / 1e9);
    ESP_LOGI(TAG, "   Free: %.2f GB", driveInfo.freeBytes / 1e9);

    if (mountCallback) {
        mountCallback(true, "");
    }

    return true;
}

void USBHostManager::unmountDrive() {
    if (!driveInfo.mounted) return;

    ESP_LOGI(TAG, "Unmounting USB drive...");

    if (vfsHandle) {
        msc_host_vfs_unregister(vfsHandle);
        vfsHandle = nullptr;
    }

    if (mscDevice) {
        msc_host_uninstall_device(mscDevice);
        mscDevice = nullptr;
    }

    driveInfo.mounted = false;
    driveInfo.volumeLabel.clear();
    driveInfo.totalBytes = 0;
    driveInfo.freeBytes = 0;

    ESP_LOGI(TAG, "✓ USB drive unmounted");
}

void USBHostManager::updateDriveInfo() {
    if (!driveInfo.mounted) return;

    // Get filesystem info using statvfs
    struct statvfs stat;
    if (statvfs(MOUNT_POINT, &stat) == 0) {
        driveInfo.totalBytes = (uint64_t)stat.f_blocks * stat.f_frsize;
        driveInfo.freeBytes = (uint64_t)stat.f_bfree * stat.f_frsize;
        driveInfo.filesystem = "FAT32"; // MSC driver uses FAT
    } else {
        ESP_LOGW(TAG, "Failed to get filesystem info");
    }

    // Try to read volume label from root
    std::string labelPath = std::string(MOUNT_POINT) + "/.volume_label";
    FILE* f = fopen(labelPath.c_str(), "r");
    if (f) {
        char label[256];
        if (fgets(label, sizeof(label), f)) {
            driveInfo.volumeLabel = label;
        }
        fclose(f);
    } else {
        driveInfo.volumeLabel = "USB_DRIVE";
    }
}

std::vector<FileEntry> USBHostManager::listFiles(const std::string& path) {
    std::vector<FileEntry> files;

    if (!driveInfo.mounted) {
        ESP_LOGW(TAG, "Drive not mounted");
        return files;
    }

    std::string fullPath = getFullPath(path);
    DIR* dir = opendir(fullPath.c_str());

    if (!dir) {
        ESP_LOGW(TAG, "Failed to open directory: %s", fullPath.c_str());
        return files;
    }

    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        // Skip . and ..
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }

        FileEntry fileEntry;
        fileEntry.name = entry->d_name;
        fileEntry.path = path + "/" + entry->d_name;
        fileEntry.isDirectory = (entry->d_type == DT_DIR);

        // Get file stats
        std::string entryFullPath = fullPath + "/" + entry->d_name;
        struct stat st;
        if (stat(entryFullPath.c_str(), &st) == 0) {
            fileEntry.size = st.st_size;
            fileEntry.modified = st.st_mtime;
        } else {
            fileEntry.size = 0;
            fileEntry.modified = 0;
        }

        files.push_back(fileEntry);
    }

    closedir(dir);

    ESP_LOGI(TAG, "Listed %d files in %s", files.size(), path.c_str());
    return files;
}

std::vector<uint8_t> USBHostManager::readFile(const std::string& path) {
    std::vector<uint8_t> data;

    if (!driveInfo.mounted) {
        ESP_LOGW(TAG, "Drive not mounted");
        return data;
    }

    std::string fullPath = getFullPath(path);

    // Check file size first
    size_t fileSize = getFileSize(path);
    if (fileSize == 0 || fileSize > MAX_READ_SIZE) {
        ESP_LOGW(TAG, "File size invalid or too large: %d bytes", fileSize);
        return data;
    }

    FILE* file = fopen(fullPath.c_str(), "rb");
    if (!file) {
        ESP_LOGW(TAG, "Failed to open file: %s", fullPath.c_str());
        return data;
    }

    // Allocate buffer
    data.resize(fileSize);

    // Read file
    size_t bytesRead = fread(data.data(), 1, fileSize, file);
    fclose(file);

    if (bytesRead != fileSize) {
        ESP_LOGW(TAG, "Read mismatch: expected %d, got %d", fileSize, bytesRead);
        data.resize(bytesRead);
    }

    ESP_LOGI(TAG, "Read %d bytes from %s", bytesRead, path.c_str());
    return data;
}

bool USBHostManager::fileExists(const std::string& path) {
    if (!driveInfo.mounted) return false;

    std::string fullPath = getFullPath(path);
    struct stat st;
    return (stat(fullPath.c_str(), &st) == 0);
}

size_t USBHostManager::getFileSize(const std::string& path) {
    if (!driveInfo.mounted) return 0;

    std::string fullPath = getFullPath(path);
    struct stat st;
    if (stat(fullPath.c_str(), &st) == 0) {
        return st.st_size;
    }
    return 0;
}

void USBHostManager::handleEvents() {
    if (!initialized) return;

    // USB Host Library handles events in background task
    // This function can be used for additional periodic checks
}

std::string USBHostManager::getFullPath(const std::string& path) {
    // Remove leading slash if present
    std::string cleanPath = path;
    if (!cleanPath.empty() && cleanPath[0] == '/') {
        cleanPath = cleanPath.substr(1);
    }

    // Combine mount point with path
    return std::string(MOUNT_POINT) + "/" + cleanPath;
}

// Static callbacks
void USBHostManager::usbHostLibEventHandler(const usb_host_lib_info_t *info, void *user_ctx) {
    // Handle USB Host Library events if needed
}

void USBHostManager::mscEventCallback(const msc_host_event_t *event, void *arg) {
    USBHostManager* manager = static_cast<USBHostManager*>(arg);
    if (!manager) return;

    switch (event->event) {
        case MSC_DEVICE_CONNECTED:
            ESP_LOGI(TAG, "MSC Device Connected");
            if (manager->connectionCallback) {
                manager->connectionCallback(true);
            }
            // Auto-mount on connection
            manager->mountDrive();
            break;

        case MSC_DEVICE_DISCONNECTED:
            ESP_LOGI(TAG, "MSC Device Disconnected");
            manager->unmountDrive();
            if (manager->connectionCallback) {
                manager->connectionCallback(false);
            }
            break;

        default:
            break;
    }
}
