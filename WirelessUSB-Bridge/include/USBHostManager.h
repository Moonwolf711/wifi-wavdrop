/**
 * USBHostManager.h
 * Manages USB Host Mass Storage devices on ESP32-S3
 *
 * Uses ESP-IDF usb_host_msc component for real USB drive access
 */

#ifndef USB_HOST_MANAGER_H
#define USB_HOST_MANAGER_H

#include <esp_vfs_fat.h>
#include <usb/usb_host.h>
#include <msc_host.h>
#include <msc_host_vfs.h>
#include <string>
#include <vector>
#include <functional>

// USB Drive information
struct USBDriveInfo {
    bool mounted;
    std::string volumeLabel;
    std::string filesystem;
    uint64_t totalBytes;
    uint64_t freeBytes;
    std::string mountPoint;
};

// File/Directory entry
struct FileEntry {
    std::string name;
    std::string path;
    bool isDirectory;
    size_t size;
    time_t modified;
};

// USB Event callback types
using USBConnectionCallback = std::function<void(bool connected)>;
using USBMountCallback = std::function<void(bool mounted, const std::string& error)>;

class USBHostManager {
public:
    USBHostManager();
    ~USBHostManager();

    // Initialize USB Host
    bool begin();

    // Stop USB Host
    void end();

    // Check if USB drive is mounted
    bool isMounted() const { return driveInfo.mounted; }

    // Get drive information
    USBDriveInfo getDriveInfo() const { return driveInfo; }

    // List files in directory
    std::vector<FileEntry> listFiles(const std::string& path);

    // Read file contents
    std::vector<uint8_t> readFile(const std::string& path);

    // Check if file exists
    bool fileExists(const std::string& path);

    // Get file size
    size_t getFileSize(const std::string& path);

    // Set callbacks
    void setConnectionCallback(USBConnectionCallback cb) { connectionCallback = cb; }
    void setMountCallback(USBMountCallback cb) { mountCallback = cb; }

    // Task loop (call periodically)
    void handleEvents();

private:
    // USB Host callbacks
    static void usbHostLibEventHandler(const usb_host_lib_info_t *info, void *user_ctx);
    static void mscEventCallback(const msc_host_event_t *event, void *arg);

    // Mount/unmount
    bool mountDrive();
    void unmountDrive();

    // Update drive info
    void updateDriveInfo();

    // Helper functions
    std::string getFullPath(const std::string& path);

    // Member variables
    USBDriveInfo driveInfo;
    msc_host_device_handle_t mscDevice;
    msc_host_vfs_handle_t vfsHandle;
    bool initialized;

    // Callbacks
    USBConnectionCallback connectionCallback;
    USBMountCallback mountCallback;

    // Constants
    static constexpr const char* MOUNT_POINT = "/usb";
    static constexpr size_t MAX_READ_SIZE = 1024 * 1024; // 1MB max file read
};

#endif // USB_HOST_MANAGER_H
