import XCTest
@testable import WaveDrop

@MainActor
final class ExternalDriveManagerTests: XCTestCase {

    var sut: ExternalDriveManager!

    override func setUp() async throws {
        try await super.setUp()
        sut = ExternalDriveManager()
    }

    override func tearDown() async throws {
        sut.stopMonitoring()
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertNotNil(sut)
        XCTAssertFalse(sut.isMonitoring)
        XCTAssertTrue(sut.connectedDrives.isEmpty)
        XCTAssertNil(sut.lastError)
    }

    // MARK: - Monitoring Tests

    func testStartMonitoring() {
        sut.startMonitoring()
        XCTAssertTrue(sut.isMonitoring)
    }

    func testStopMonitoring() {
        sut.startMonitoring()
        XCTAssertTrue(sut.isMonitoring)

        sut.stopMonitoring()
        XCTAssertFalse(sut.isMonitoring)
    }

    func testStartMonitoringMultipleTimes() {
        sut.startMonitoring()
        sut.startMonitoring()
        sut.startMonitoring()

        XCTAssertTrue(sut.isMonitoring)
    }

    // MARK: - Drive Detection Tests

    func testScanForDrives() {
        sut.scanForDrives()
        // Note: In a real test environment, you would need to mock the file system
        // For now, we just verify the method doesn't crash
        XCTAssertNotNil(sut.connectedDrives)
    }

    // MARK: - File Operations Tests

    func testCopyFileWithInvalidDrive() async {
        let invalidDrive = ExternalDrive(
            id: "invalid",
            name: "Invalid Drive",
            url: nil,
            totalCapacity: 0,
            availableCapacity: 0,
            isEjectable: false
        )

        let sourceURL = URL(fileURLWithPath: "/tmp/test.mp3")

        do {
            _ = try await sut.copyFile(
                from: sourceURL,
                to: invalidDrive,
                progress: { _ in }
            )
            XCTFail("Should throw driveNotAvailable error")
        } catch let error as DriveError {
            XCTAssertEqual(error, DriveError.driveNotAvailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - ExternalDrive Model Tests

    func testExternalDriveFormattedCapacity() {
        let drive = ExternalDrive(
            id: "test",
            name: "Test Drive",
            url: URL(fileURLWithPath: "/Volumes/Test"),
            totalCapacity: 32_000_000_000, // 32 GB
            availableCapacity: 16_000_000_000, // 16 GB
            isEjectable: true
        )

        XCTAssertEqual(drive.usedCapacity, 16_000_000_000)
        XCTAssertFalse(drive.formattedTotalCapacity.isEmpty)
        XCTAssertFalse(drive.formattedAvailableCapacity.isEmpty)
    }

    func testExternalDriveEquality() {
        let drive1 = ExternalDrive(
            id: "test1",
            name: "Test Drive",
            url: URL(fileURLWithPath: "/Volumes/Test"),
            totalCapacity: 32_000_000_000,
            availableCapacity: 16_000_000_000,
            isEjectable: true
        )

        let drive2 = ExternalDrive(
            id: "test1",
            name: "Test Drive",
            url: URL(fileURLWithPath: "/Volumes/Test"),
            totalCapacity: 32_000_000_000,
            availableCapacity: 16_000_000_000,
            isEjectable: true
        )

        let drive3 = ExternalDrive(
            id: "test2",
            name: "Different Drive",
            url: URL(fileURLWithPath: "/Volumes/Different"),
            totalCapacity: 64_000_000_000,
            availableCapacity: 32_000_000_000,
            isEjectable: true
        )

        XCTAssertEqual(drive1, drive2)
        XCTAssertNotEqual(drive1, drive3)
    }

    // MARK: - DriveError Tests

    func testDriveErrorDescriptions() {
        let errors: [DriveError] = [
            .scanFailed("Test scan error"),
            .driveNotAvailable,
            .insufficientSpace,
            .copyFailed("Test copy error"),
            .deleteFailed("Test delete error")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }
}

// MARK: - DriveError Equatable Extension for Testing

extension DriveError: Equatable {
    public static func == (lhs: DriveError, rhs: DriveError) -> Bool {
        switch (lhs, rhs) {
        case (.driveNotAvailable, .driveNotAvailable):
            return true
        case (.insufficientSpace, .insufficientSpace):
            return true
        case (.scanFailed(let msg1), .scanFailed(let msg2)):
            return msg1 == msg2
        case (.copyFailed(let msg1), .copyFailed(let msg2)):
            return msg1 == msg2
        case (.deleteFailed(let msg1), .deleteFailed(let msg2)):
            return msg1 == msg2
        default:
            return false
        }
    }
}
