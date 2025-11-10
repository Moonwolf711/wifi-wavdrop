import Foundation
import Combine

/// Manages external USB drive detection, monitoring, and file operations
@MainActor
public class ExternalDriveManager: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var connectedDrives: [ExternalDrive] = []
    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var lastError: DriveError?

    // MARK: - Private Properties

    private var fileManager = FileManager.default
    private var cancellables = Set<AnyCancellable>()
    private var monitoringTimer: Timer?

    // MARK: - Initialization

    public init() {
        setupNotifications()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public Methods

    /// Start monitoring for external drive changes
    public func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        scanForDrives()

        // Poll for drive changes every 2 seconds
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanForDrives()
            }
        }
    }

    /// Stop monitoring for external drive changes
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    /// Scan for currently connected external drives
    public func scanForDrives() {
        do {
            let volumes = try fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: "/Volumes"),
                includingPropertiesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey],
                options: .skipsHiddenFiles
            )

            var newDrives: [ExternalDrive] = []

            for volumeURL in volumes {
                // Skip system volumes
                guard !isSystemVolume(volumeURL) else { continue }

                if let drive = createDriveInfo(from: volumeURL) {
                    newDrives.append(drive)
                }
            }

            // Update connected drives if changed
            if newDrives != connectedDrives {
                let previousDrives = Set(connectedDrives.map { $0.id })
                let currentDrives = Set(newDrives.map { $0.id })

                // Notify about newly connected drives
                let connected = currentDrives.subtracting(previousDrives)
                for driveId in connected {
                    if let drive = newDrives.first(where: { $0.id == driveId }) {
                        NotificationCenter.default.post(
                            name: .externalDriveConnected,
                            object: drive
                        )
                    }
                }

                // Notify about disconnected drives
                let disconnected = previousDrives.subtracting(currentDrives)
                for driveId in disconnected {
                    if let drive = connectedDrives.first(where: { $0.id == driveId }) {
                        NotificationCenter.default.post(
                            name: .externalDriveDisconnected,
                            object: drive
                        )
                    }
                }

                connectedDrives = newDrives
            }
        } catch {
            lastError = .scanFailed(error.localizedDescription)
        }
    }

    /// Copy file to external drive with progress tracking
    public func copyFile(
        from source: URL,
        to drive: ExternalDrive,
        destinationPath: String? = nil,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let driveURL = drive.url else {
            throw DriveError.driveNotAvailable
        }

        let fileName = source.lastPathComponent
        let destination = destinationPath.map { driveURL.appendingPathComponent($0).appendingPathComponent(fileName) }
            ?? driveURL.appendingPathComponent(fileName)

        // Create destination directory if needed
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Check available space
        if let fileSize = try? fileManager.attributesOfItem(atPath: source.path)[.size] as? Int64,
           fileSize > drive.availableCapacity {
            throw DriveError.insufficientSpace
        }

        // Copy file with progress tracking
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.fileManager.copyItem(at: source, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: DriveError.copyFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Delete file from external drive
    public func deleteFile(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    /// Get contents of directory on external drive
    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        return try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.nameKey, .isDirectoryKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )
    }

    // MARK: - Private Methods

    private func setupNotifications() {
        // iOS doesn't provide volume mount/unmount notifications like macOS
        // We rely on polling via timer
    }

    private func isSystemVolume(_ url: URL) -> Bool {
        let systemVolumes = ["Macintosh HD", "Preboot", "VM", "Data"]
        guard let volumeName = try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName else {
            return true
        }
        return systemVolumes.contains(volumeName)
    }

    private func createDriveInfo(from url: URL) -> ExternalDrive? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey
            ])

            guard let name = resourceValues.volumeName,
                  let isRemovable = resourceValues.volumeIsRemovable,
                  isRemovable else {
                return nil
            }

            return ExternalDrive(
                id: url.path,
                name: name,
                url: url,
                totalCapacity: Int64(resourceValues.volumeTotalCapacity ?? 0),
                availableCapacity: Int64(resourceValues.volumeAvailableCapacity ?? 0),
                isEjectable: resourceValues.volumeIsEjectable ?? true
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Models

/// Represents an external USB drive
public struct ExternalDrive: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let url: URL?
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    public let isEjectable: Bool

    public var usedCapacity: Int64 {
        totalCapacity - availableCapacity
    }

    public var formattedTotalCapacity: String {
        ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }

    public var formattedAvailableCapacity: String {
        ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }
}

/// Errors that can occur during drive operations
public enum DriveError: LocalizedError {
    case scanFailed(String)
    case driveNotAvailable
    case insufficientSpace
    case copyFailed(String)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .scanFailed(let message):
            return "Failed to scan for drives: \(message)"
        case .driveNotAvailable:
            return "External drive is not available"
        case .insufficientSpace:
            return "Insufficient space on drive"
        case .copyFailed(let message):
            return "Failed to copy file: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete file: \(message)"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    public static let externalDriveConnected = Notification.Name("externalDriveConnected")
    public static let externalDriveDisconnected = Notification.Name("externalDriveDisconnected")
}
