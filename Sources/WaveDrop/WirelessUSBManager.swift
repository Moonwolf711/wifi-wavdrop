// WirelessUSBManager.swift
// Manages wireless USB drive discovery and file operations
//
// Part of WaveDrop - Wireless USB Bridge MVP

import Foundation
import Network
import Combine

// MARK: - Models

/// Represents a wireless USB drive discovered on the network
struct WirelessUSBDrive: Identifiable, Equatable {
    let id: UUID
    let name: String
    let serviceType: String
    let endpoint: NWEndpoint
    var url: URL?

    // Drive information (fetched from API)
    var volumeLabel: String?
    var totalSpace: Int64?
    var freeSpace: Int64?
    var filesystem: String?
    var firmwareVersion: String?

    init(name: String, endpoint: NWEndpoint) {
        self.id = UUID()
        self.name = name
        self.serviceType = "_wavedrop-usb._tcp"
        self.endpoint = endpoint
    }

    static func == (lhs: WirelessUSBDrive, rhs: WirelessUSBDrive) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents a file on the wireless USB drive
struct USBFile: Identifiable {
    let id: UUID
    let name: String
    let size: Int64?
    let type: FileType
    let path: String
    let modified: Date?

    enum FileType: String, Codable {
        case file
        case directory
    }

    init(name: String, size: Int64? = nil, type: FileType, path: String, modified: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.size = size
        self.type = type
        self.path = path
        self.modified = modified
    }
}

/// File transfer operation
struct USBFileTransfer: Identifiable {
    let id: UUID
    let fileName: String
    let fileSize: Int64
    let deviceName: String
    var progress: Double
    var status: TransferStatus

    enum TransferStatus {
        case inProgress
        case completed
        case failed(String)
        case cancelled
    }
}

// MARK: - Manager

/// Manages wireless USB drive discovery and file operations
@MainActor
class WirelessUSBManager: ObservableObject {
    // MARK: - Published Properties

    @Published var discoveredDrives: [WirelessUSBDrive] = []
    @Published var selectedDrive: WirelessUSBDrive?
    @Published var currentFiles: [USBFile] = []
    @Published var currentPath: String = "/"
    @Published var activeTransfers: [USBFileTransfer] = []
    @Published var lastError: String?
    @Published var isDiscovering: Bool = false

    // MARK: - Private Properties

    private var browser: NWBrowser?
    private var urlSession: URLSession
    private let serviceType = "_wavedrop-usb._tcp"

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Discovery

    /// Start discovering wireless USB drives on the network
    func startDiscovery() {
        guard browser == nil else { return }

        isDiscovering = true
        discoveredDrives.removeAll()

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)

        browser?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                switch newState {
                case .ready:
                    print("🔍 Wireless USB discovery started")
                case .failed(let error):
                    print("❌ Discovery failed: \\(error)")
                    self?.lastError = "Discovery failed: \\(error.localizedDescription)"
                    self?.isDiscovering = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results: results, changes: changes)
            }
        }

        browser?.start(queue: .main)
    }

    /// Stop discovering drives
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isDiscovering = false
        print("🛑 Wireless USB discovery stopped")
    }

    private func handleBrowseResults(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                addDiscoveredDrive(result: result)
            case .removed(let result):
                removeDiscoveredDrive(result: result)
            default:
                break
            }
        }
    }

    private func addDiscoveredDrive(result: NWBrowser.Result) {
        guard case .service(let name, let type, let domain, _) = result.endpoint else { return }

        var drive = WirelessUSBDrive(name: name, endpoint: result.endpoint)

        // Extract URL from endpoint
        if case .hostPort(let host, let port) = result.endpoint {
            let urlString = "http://\\(host):\\(port)"
            drive.url = URL(string: urlString)
        }

        if !discoveredDrives.contains(where: { $0.name == name }) {
            discoveredDrives.append(drive)
            print("✓ Discovered: \\(name) at \\(type).\\(domain)")

            // Fetch drive info asynchronously
            Task {
                if let updatedDrive = try? await fetchDriveInfo(drive) {
                    if let index = discoveredDrives.firstIndex(where: { $0.id == drive.id }) {
                        discoveredDrives[index] = updatedDrive
                    }
                }
            }
        }
    }

    private func removeDiscoveredDrive(result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }

        discoveredDrives.removeAll { $0.name == name }
        print("✗ Removed: \\(name)")
    }

    // MARK: - Drive Information

    /// Fetch drive information from API
    func fetchDriveInfo(_ drive: WirelessUSBDrive) async throws -> WirelessUSBDrive {
        guard let baseURL = drive.url else {
            throw URLError(.badURL)
        }

        let infoURL = baseURL.appendingPathComponent("/api/info")

        let (data, _) = try await urlSession.data(from: infoURL)
        let json = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        var updatedDrive = drive
        updatedDrive.volumeLabel = json["volume_label"]?.stringValue
        updatedDrive.totalSpace = json["total_space"]?.int64Value
        updatedDrive.freeSpace = json["free_space"]?.int64Value
        updatedDrive.filesystem = json["filesystem"]?.stringValue
        updatedDrive.firmwareVersion = json["firmware_version"]?.stringValue

        return updatedDrive
    }

    // MARK: - File Operations

    /// List files at specified path
    func listFiles(drive: WirelessUSBDrive, path: String = "/") async throws -> [USBFile] {
        guard let baseURL = drive.url else {
            throw URLError(.badURL)
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("/api/files"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)]

        guard let filesURL = components.url else {
            throw URLError(.badURL)
        }

        let (data, _) = try await urlSession.data(from: filesURL)
        let response = try JSONDecoder().decode(FilesResponse.self, from: data)

        return response.files.map { fileData in
            USBFile(
                name: fileData.name,
                size: fileData.size,
                type: fileData.type == "file" ? .file : .directory,
                path: "\\(response.path)/\\(fileData.name)",
                modified: fileData.modified
            )
        }
    }

    /// Download file from wireless USB drive
    func downloadFile(drive: WirelessUSBDrive, file: USBFile, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let baseURL = drive.url else {
            throw URLError(.badURL)
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("/api/download"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: file.path)]

        guard let downloadURL = components.url else {
            throw URLError(.badURL)
        }

        // Create transfer tracking
        var transfer = USBFileTransfer(
            id: UUID(),
            fileName: file.name,
            fileSize: file.size ?? 0,
            deviceName: drive.name,
            progress: 0.0,
            status: .inProgress
        )

        activeTransfers.append(transfer)

        do {
            let (tempURL, _) = try await urlSession.download(from: downloadURL)

            // Move to app documents
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsURL.appendingPathComponent(file.name)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            // Update transfer status
            if let index = activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                activeTransfers[index].status = .completed
                activeTransfers[index].progress = 1.0
            }

            return destinationURL
        } catch {
            // Update transfer with error
            if let index = activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                activeTransfers[index].status = .failed(error.localizedDescription)
            }
            throw error
        }
    }

    /// Cancel active transfer
    func cancelTransfer(_ transferId: UUID) {
        if let index = activeTransfers.firstIndex(where: { $0.id == transferId }) {
            activeTransfers[index].status = .cancelled
        }
    }
}

// MARK: - Helper Types

private struct FilesResponse: Codable {
    let path: String
    let files: [FileData]

    struct FileData: Codable {
        let name: String
        let size: Int64?
        let type: String
        let modified: Date?
    }
}

// AnyCodable helper for flexible JSON decoding
private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int64.self) {
            value = int
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int64 {
            try container.encode(int)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        }
    }

    var stringValue: String? { value as? String }
    var int64Value: Int64? { value as? Int64 }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
}
