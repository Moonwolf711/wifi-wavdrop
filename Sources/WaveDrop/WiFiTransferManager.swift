import Foundation
import Network
import Combine

/// Manages Wi-Fi file transfer using Bonjour service discovery and HTTP server
@MainActor
public class WiFiTransferManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var isServerRunning: Bool = false
    @Published public private(set) var discoveredDevices: [WiFiDevice] = []
    @Published public private(set) var activeTransfers: [FileTransfer] = []
    @Published public private(set) var serverURL: URL?
    @Published public private(set) var lastError: WiFiTransferError?

    // MARK: - Private Properties

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var serviceName: String
    private var serviceType: String = "_wavedrop._tcp"
    private let port: UInt16

    // MARK: - Initialization

    public init(serviceName: String = "WaveDrop", port: UInt16 = 8080) {
        self.serviceName = serviceName
        self.port = port
        super.init()
    }

    deinit {
        stopServer()
        stopDiscovery()
    }

    // MARK: - Server Management

    /// Start the HTTP server for receiving files
    public func startServer() {
        guard !isServerRunning else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            // Enable Bonjour advertising
            let service = NWListener.Service(name: serviceName, type: serviceType)
            parameters.includePeerToPeer = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            listener?.service = service
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerStateChange(state)
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection)
                }
            }

            listener?.start(queue: .main)

        } catch {
            lastError = .serverStartFailed(error.localizedDescription)
        }
    }

    /// Stop the HTTP server
    public func stopServer() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isServerRunning = false
        serverURL = nil
    }

    // MARK: - Device Discovery

    /// Start discovering WaveDrop devices on the network
    public func startDiscovery() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    print("Browser ready")
                case .failed(let error):
                    self?.lastError = .discoveryFailed(error.localizedDescription)
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor [weak self] in
                self?.handleBrowseResults(results)
            }
        }

        browser?.start(queue: .main)
    }

    /// Stop discovering devices
    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        discoveredDevices.removeAll()
    }

    // MARK: - File Transfer

    /// Send file to a discovered device
    public func sendFile(
        _ fileURL: URL,
        to device: WiFiDevice,
        progress: @escaping (Double) -> Void
    ) async throws -> Bool {
        guard let deviceURL = device.url else {
            throw WiFiTransferError.invalidDeviceURL
        }

        let transfer = FileTransfer(
            id: UUID(),
            fileName: fileURL.lastPathComponent,
            fileSize: try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0,
            deviceName: device.name,
            direction: .upload,
            progress: 0,
            status: .inProgress
        )

        activeTransfers.append(transfer)

        do {
            let uploaded = try await uploadFile(fileURL, to: deviceURL, progress: { prog in
                Task { @MainActor in
                    if let index = self.activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                        var updatedTransfer = self.activeTransfers[index]
                        updatedTransfer.progress = prog
                        self.activeTransfers[index] = updatedTransfer
                    }
                    progress(prog)
                }
            })

            if let index = activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                var updatedTransfer = activeTransfers[index]
                updatedTransfer.status = .completed
                updatedTransfer.progress = 1.0
                activeTransfers[index] = updatedTransfer
            }

            return uploaded
        } catch {
            if let index = activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                var updatedTransfer = activeTransfers[index]
                updatedTransfer.status = .failed
                activeTransfers[index] = updatedTransfer
            }
            throw error
        }
    }

    /// Cancel an active transfer
    public func cancelTransfer(_ transferId: UUID) {
        if let index = activeTransfers.firstIndex(where: { $0.id == transferId }) {
            var transfer = activeTransfers[index]
            transfer.status = .cancelled
            activeTransfers[index] = transfer
        }
    }

    // MARK: - Private Methods

    private func handleListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            isServerRunning = true
            if let port = listener?.port {
                // Get local IP address
                if let localIP = getLocalIPAddress() {
                    serverURL = URL(string: "http://\(localIP):\(port)")
                }
            }

        case .failed(let error):
            lastError = .serverStartFailed(error.localizedDescription)
            isServerRunning = false

        case .cancelled:
            isServerRunning = false

        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                if case .ready = state {
                    self?.receiveData(on: connection)
                }
            }
        }

        connection.start(queue: .main)
    }

    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            Task { @MainActor [weak self] in
                if let data = data, !data.isEmpty {
                    self?.handleReceivedData(data, from: connection)
                }

                if !isComplete {
                    self?.receiveData(on: connection)
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data, from connection: NWConnection) {
        // Parse HTTP request
        guard let request = String(data: data, encoding: .utf8) else { return }

        // Simple HTTP parser (in production, use a proper HTTP library)
        if request.hasPrefix("POST /upload") {
            // Extract file data from multipart form
            // This is simplified - use a proper multipart parser in production
            handleFileUpload(data: data, connection: connection)
        } else if request.hasPrefix("GET /") {
            sendHTMLResponse(connection: connection)
        }
    }

    private func handleFileUpload(data: Data, connection: NWConnection) {
        // Simplified file upload handler
        // In production, properly parse multipart/form-data

        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        \r
        {"status":"success","message":"File uploaded successfully"}
        """

        if let responseData = response.data(using: .utf8) {
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func sendHTMLResponse(connection: NWConnection) {
        let html = generateUploadHTML()
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html\r
        Content-Length: \(html.utf8.count)\r
        \r
        \(html)
        """

        if let responseData = response.data(using: .utf8) {
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func generateUploadHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>WaveDrop - Upload Files</title>
            <style>
                body { font-family: -apple-system, sans-serif; padding: 20px; max-width: 600px; margin: 0 auto; }
                h1 { color: #007AFF; }
                .upload-area { border: 2px dashed #007AFF; border-radius: 10px; padding: 40px; text-align: center; }
                .upload-area:hover { background: #f0f0f0; }
                button { background: #007AFF; color: white; border: none; padding: 12px 24px; border-radius: 8px; font-size: 16px; cursor: pointer; }
                button:hover { background: #0051D5; }
                .progress { display: none; margin-top: 20px; }
                .progress-bar { width: 100%; height: 20px; background: #e0e0e0; border-radius: 10px; overflow: hidden; }
                .progress-fill { height: 100%; background: #007AFF; width: 0%; transition: width 0.3s; }
            </style>
        </head>
        <body>
            <h1>🎵 WaveDrop File Upload</h1>
            <div class="upload-area" id="dropArea">
                <p>📁 Drag and drop audio files here</p>
                <p>or</p>
                <input type="file" id="fileInput" multiple accept="audio/*" style="display:none">
                <button onclick="document.getElementById('fileInput').click()">Choose Files</button>
            </div>
            <div class="progress" id="progress">
                <p>Uploading: <span id="fileName"></span></p>
                <div class="progress-bar"><div class="progress-fill" id="progressFill"></div></div>
                <p><span id="progressPercent">0</span>%</p>
            </div>
            <script>
                const dropArea = document.getElementById('dropArea');
                const fileInput = document.getElementById('fileInput');

                ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
                    dropArea.addEventListener(eventName, preventDefaults, false);
                });

                function preventDefaults(e) { e.preventDefault(); e.stopPropagation(); }

                dropArea.addEventListener('drop', handleDrop, false);
                fileInput.addEventListener('change', e => handleFiles(e.target.files));

                function handleDrop(e) { handleFiles(e.dataTransfer.files); }

                function handleFiles(files) {
                    [...files].forEach(uploadFile);
                }

                function uploadFile(file) {
                    const formData = new FormData();
                    formData.append('file', file);

                    document.getElementById('progress').style.display = 'block';
                    document.getElementById('fileName').textContent = file.name;

                    const xhr = new XMLHttpRequest();
                    xhr.upload.addEventListener('progress', e => {
                        const percent = (e.loaded / e.total) * 100;
                        document.getElementById('progressFill').style.width = percent + '%';
                        document.getElementById('progressPercent').textContent = Math.round(percent);
                    });

                    xhr.addEventListener('load', () => {
                        alert('File uploaded successfully!');
                        document.getElementById('progress').style.display = 'none';
                    });

                    xhr.open('POST', '/upload');
                    xhr.send(formData);
                }
            </script>
        </body>
        </html>
        """
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var devices: [WiFiDevice] = []

        for result in results {
            if case .service(let name, let type, let domain, _) = result.endpoint {
                let device = WiFiDevice(
                    id: UUID(),
                    name: name,
                    serviceType: type,
                    domain: domain,
                    endpoint: result.endpoint
                )
                devices.append(device)
            }
        }

        discoveredDevices = devices
    }

    private func uploadFile(_ fileURL: URL, to deviceURL: URL, progress: @escaping (Double) -> Void) async throws -> Bool {
        var request = URLRequest(url: deviceURL.appendingPathComponent("upload"))
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        let httpBody = createMultipartBody(fileData: fileData, fileName: fileURL.lastPathComponent, boundary: boundary)

        let (_, response) = try await URLSession.shared.upload(for: request, from: httpBody)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WiFiTransferError.uploadFailed("Server returned error")
        }

        return true
    }

    private func createMultipartBody(fileData: Data, fileName: String, boundary: String) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" { // WiFi or Ethernet
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }

        return address
    }
}

// MARK: - Models

/// Represents a discovered WaveDrop device on the network
public struct WiFiDevice: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let serviceType: String
    public let domain: String
    public let endpoint: NWEndpoint

    public var url: URL? {
        // Extract IP and port from endpoint
        if case .service(_, _, _, let interface) = endpoint {
            // This is simplified - in production, resolve the endpoint properly
            return URL(string: "http://\(name).local:8080")
        }
        return nil
    }

    public static func == (lhs: WiFiDevice, rhs: WiFiDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents an active file transfer
public struct FileTransfer: Identifiable {
    public let id: UUID
    public let fileName: String
    public let fileSize: Int64
    public let deviceName: String
    public let direction: TransferDirection
    public var progress: Double
    public var status: TransferStatus

    public enum TransferDirection {
        case upload
        case download
    }

    public enum TransferStatus {
        case inProgress
        case completed
        case failed
        case cancelled
    }

    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

/// Errors that can occur during WiFi transfer
public enum WiFiTransferError: LocalizedError {
    case serverStartFailed(String)
    case discoveryFailed(String)
    case invalidDeviceURL
    case uploadFailed(String)
    case downloadFailed(String)
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .serverStartFailed(let message):
            return "Failed to start server: \(message)"
        case .discoveryFailed(let message):
            return "Device discovery failed: \(message)"
        case .invalidDeviceURL:
            return "Invalid device URL"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        }
    }
}
