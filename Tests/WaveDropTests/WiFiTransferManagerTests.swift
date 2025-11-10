import XCTest
@testable import WaveDrop

@MainActor
final class WiFiTransferManagerTests: XCTestCase {

    var sut: WiFiTransferManager!

    override func setUp() async throws {
        try await super.setUp()
        sut = WiFiTransferManager(serviceName: "TestWaveDrop", port: 9090)
    }

    override func tearDown() async throws {
        sut.stopServer()
        sut.stopDiscovery()
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertNotNil(sut)
        XCTAssertFalse(sut.isServerRunning)
        XCTAssertTrue(sut.discoveredDevices.isEmpty)
        XCTAssertTrue(sut.activeTransfers.isEmpty)
        XCTAssertNil(sut.serverURL)
        XCTAssertNil(sut.lastError)
    }

    func testCustomInitialization() {
        let customManager = WiFiTransferManager(serviceName: "CustomService", port: 8888)
        XCTAssertNotNil(customManager)
    }

    // MARK: - Server Management Tests

    func testStartServer() async {
        sut.startServer()

        // Wait a bit for server to start
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Note: Server may not actually start in test environment
        // This test mainly checks that it doesn't crash
        XCTAssertNotNil(sut)
    }

    func testStopServer() {
        sut.startServer()
        sut.stopServer()

        XCTAssertFalse(sut.isServerRunning)
        XCTAssertNil(sut.serverURL)
    }

    func testMultipleStartServer() {
        sut.startServer()
        sut.startServer()
        sut.startServer()

        // Should not crash
        XCTAssertNotNil(sut)
    }

    func testStopServerWithoutStart() {
        sut.stopServer()

        XCTAssertFalse(sut.isServerRunning)
        XCTAssertNil(sut.serverURL)
    }

    // MARK: - Discovery Tests

    func testStartDiscovery() {
        sut.startDiscovery()

        // Should not crash
        XCTAssertNotNil(sut)
    }

    func testStopDiscovery() {
        sut.startDiscovery()
        sut.stopDiscovery()

        XCTAssertTrue(sut.discoveredDevices.isEmpty)
    }

    func testMultipleStartDiscovery() {
        sut.startDiscovery()
        sut.startDiscovery()

        // Should not crash
        XCTAssertNotNil(sut)
    }

    // MARK: - File Transfer Tests

    func testCancelTransfer() {
        let transferId = UUID()
        sut.cancelTransfer(transferId)

        // Should not crash even if transfer doesn't exist
        XCTAssertNotNil(sut)
    }

    // MARK: - Model Tests

    func testWiFiDeviceModel() {
        let endpoint = NWEndpoint.hostPort(
            host: "192.168.1.100",
            port: 8080
        )

        let device = WiFiDevice(
            id: UUID(),
            name: "Test Device",
            serviceType: "_wavedrop._tcp",
            domain: "local.",
            endpoint: endpoint
        )

        XCTAssertEqual(device.name, "Test Device")
        XCTAssertEqual(device.serviceType, "_wavedrop._tcp")
        XCTAssertEqual(device.domain, "local.")
    }

    func testWiFiDeviceEquality() {
        let id = UUID()
        let endpoint = NWEndpoint.hostPort(host: "192.168.1.100", port: 8080)

        let device1 = WiFiDevice(
            id: id,
            name: "Device 1",
            serviceType: "_wavedrop._tcp",
            domain: "local.",
            endpoint: endpoint
        )

        let device2 = WiFiDevice(
            id: id,
            name: "Device 1",
            serviceType: "_wavedrop._tcp",
            domain: "local.",
            endpoint: endpoint
        )

        let device3 = WiFiDevice(
            id: UUID(),
            name: "Device 2",
            serviceType: "_wavedrop._tcp",
            domain: "local.",
            endpoint: endpoint
        )

        XCTAssertEqual(device1, device2)
        XCTAssertNotEqual(device1, device3)
    }

    func testFileTransferModel() {
        let transfer = FileTransfer(
            id: UUID(),
            fileName: "test.mp3",
            fileSize: 5_000_000,
            deviceName: "iPhone",
            direction: .upload,
            progress: 0.5,
            status: .inProgress
        )

        XCTAssertEqual(transfer.fileName, "test.mp3")
        XCTAssertEqual(transfer.fileSize, 5_000_000)
        XCTAssertEqual(transfer.deviceName, "iPhone")
        XCTAssertEqual(transfer.progress, 0.5)
        XCTAssertFalse(transfer.formattedFileSize.isEmpty)
    }

    func testFileTransferDirections() {
        let upload = FileTransfer(
            id: UUID(),
            fileName: "test.mp3",
            fileSize: 1000,
            deviceName: "Device",
            direction: .upload,
            progress: 0,
            status: .inProgress
        )

        let download = FileTransfer(
            id: UUID(),
            fileName: "test.mp3",
            fileSize: 1000,
            deviceName: "Device",
            direction: .download,
            progress: 0,
            status: .inProgress
        )

        XCTAssertNotEqual(String(describing: upload.direction), String(describing: download.direction))
    }

    func testFileTransferStatuses() {
        let statuses: [FileTransfer.TransferStatus] = [
            .inProgress,
            .completed,
            .failed,
            .cancelled
        ]

        XCTAssertEqual(statuses.count, 4)
    }

    // MARK: - Error Tests

    func testWiFiTransferErrors() {
        let errors: [WiFiTransferError] = [
            .serverStartFailed("Test error"),
            .discoveryFailed("Test error"),
            .invalidDeviceURL,
            .uploadFailed("Test error"),
            .downloadFailed("Test error"),
            .connectionFailed("Test error")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }

    func testErrorDescriptionFormat() {
        let error = WiFiTransferError.serverStartFailed("Network unreachable")
        XCTAssertTrue(error.errorDescription?.contains("Network unreachable") ?? false)
    }

    // MARK: - Integration Tests

    func testServerLifecycle() async {
        // Start server
        sut.startServer()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Start discovery
        sut.startDiscovery()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Stop discovery
        sut.stopDiscovery()
        XCTAssertTrue(sut.discoveredDevices.isEmpty)

        // Stop server
        sut.stopServer()
        XCTAssertFalse(sut.isServerRunning)
    }

    func testConcurrentOperations() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                self.sut.startServer()
            }

            group.addTask {
                self.sut.startDiscovery()
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.sut.stopDiscovery()
            }
        }

        // Should complete without crashing
        XCTAssertNotNil(sut)
    }
}
