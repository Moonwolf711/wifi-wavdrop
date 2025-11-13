// WirelessUSBView.swift
// SwiftUI interface for wireless USB drive browsing and downloads
//
// Part of WaveDrop - Wireless USB Bridge MVP

import SwiftUI

struct WirelessUSBView: View {
    @StateObject private var usbManager = WirelessUSBManager()
    @State private var selectedFiles: Set<UUID> = []
    @State private var isDownloading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Group {
                if let selectedDrive = usbManager.selectedDrive {
                    FileBrowserSection(
                        usbManager: usbManager,
                        drive: selectedDrive,
                        selectedFiles: $selectedFiles,
                        isDownloading: $isDownloading,
                        showError: $showError,
                        errorMessage: $errorMessage
                    )
                } else {
                    DriveDiscoverySection(usbManager: usbManager)
                }
            }
            .navigationTitle("Wireless USB")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if usbManager.selectedDrive != nil {
                        Button("Back") {
                            usbManager.selectedDrive = nil
                            usbManager.currentPath = "/"
                        }
                    } else {
                        Button(usbManager.isDiscovering ? "Stop" : "Scan") {
                            if usbManager.isDiscovering {
                                usbManager.stopDiscovery()
                            } else {
                                usbManager.startDiscovery()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if !usbManager.isDiscovering && usbManager.discoveredDrives.isEmpty {
                usbManager.startDiscovery()
            }
        }
        .onDisappear {
            usbManager.stopDiscovery()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Drive Discovery Section

struct DriveDiscoverySection: View {
    @ObservedObject var usbManager: WirelessUSBManager

    var body: some View {
        VStack(spacing: 20) {
            if usbManager.isDiscovering {
                ProgressView("Discovering wireless USB drives...")
                    .padding(.top, 40)
            }

            if usbManager.discoveredDrives.isEmpty && !usbManager.isDiscovering {
                EmptyStateView()
            } else {
                List(usbManager.discoveredDrives) { drive in
                    DriveRow(drive: drive)
                        .onTapGesture {
                            selectDrive(drive)
                        }
                }
            }

            if !usbManager.discoveredDrives.isEmpty {
                Text("\\(usbManager.discoveredDrives.count) drive(s) found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func selectDrive(_ drive: WirelessUSBDrive) {
        usbManager.selectedDrive = drive
        Task {
            do {
                let files = try await usbManager.listFiles(drive: drive, path: "/")
                await MainActor.run {
                    usbManager.currentFiles = files
                }
            } catch {
                print("Error listing files: \\(error)")
            }
        }
    }
}

// MARK: - Drive Row

struct DriveRow: View {
    let drive: WirelessUSBDrive

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(drive.volumeLabel ?? drive.name)
                        .font(.headline)

                    if let filesystem = drive.filesystem {
                        Text(filesystem)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }

            if let totalSpace = drive.totalSpace, let freeSpace = drive.freeSpace {
                HStack {
                    Text(formatBytes(totalSpace))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\\(formatBytes(freeSpace)) free")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - File Browser Section

struct FileBrowserSection: View {
    @ObservedObject var usbManager: WirelessUSBManager
    let drive: WirelessUSBDrive
    @Binding var selectedFiles: Set<UUID>
    @Binding var isDownloading: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String

    var body: some View {
        VStack(spacing: 0) {
            // Path breadcrumb
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(pathComponents, id: \\.self) { component in
                        Button(action: { navigateToPath(component) }) {
                            Text(component == "/" ? "Root" : component)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }

                        if component != pathComponents.last {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGray6))

            // File list
            List {
                ForEach(usbManager.currentFiles) { file in
                    FileRow(
                        file: file,
                        isSelected: selectedFiles.contains(file.id)
                    )
                    .onTapGesture {
                        handleFileTap(file)
                    }
                }
            }

            // Action bar
            if !selectedFiles.isEmpty {
                ActionBar(
                    selectedCount: selectedFiles.count,
                    onDownload: downloadSelectedFiles,
                    onCancel: clearSelection
                )
            }

            // Active transfers
            if !usbManager.activeTransfers.isEmpty {
                TransferListView(transfers: usbManager.activeTransfers)
            }
        }
    }

    private var pathComponents: [String] {
        let components = usbManager.currentPath.split(separator: "/").map(String.init)
        return ["/"] + components
    }

    private func navigateToPath(_ component: String) {
        // Navigate to clicked path component
        let index = pathComponents.firstIndex(of: component) ?? 0
        let newPath = index == 0 ? "/" : "/" + pathComponents[1...index].joined(separator: "/")

        usbManager.currentPath = newPath
        Task {
            do {
                let files = try await usbManager.listFiles(drive: drive, path: newPath)
                await MainActor.run {
                    usbManager.currentFiles = files
                }
            } catch {
                print("Error navigating: \\(error)")
            }
        }
    }

    private func handleFileTap(_ file: USBFile) {
        if file.type == .directory {
            // Navigate into directory
            Task {
                do {
                    let files = try await usbManager.listFiles(drive: drive, path: file.path)
                    await MainActor.run {
                        usbManager.currentPath = file.path
                        usbManager.currentFiles = files
                    }
                } catch {
                    errorMessage = "Failed to open folder: \\(error.localizedDescription)"
                    showError = true
                }
            }
        } else {
            // Toggle selection for files
            if selectedFiles.contains(file.id) {
                selectedFiles.remove(file.id)
            } else {
                selectedFiles.insert(file.id)
            }
        }
    }

    private func downloadSelectedFiles() {
        isDownloading = true

        let filesToDownload = usbManager.currentFiles.filter { selectedFiles.contains($0.id) }

        Task {
            for file in filesToDownload {
                do {
                    _ = try await usbManager.downloadFile(drive: drive, file: file) { progress in
                        // Progress updates handled by manager
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Download failed: \\(error.localizedDescription)"
                        showError = true
                    }
                }
            }

            await MainActor.run {
                isDownloading = false
                clearSelection()
            }
        }
    }

    private func clearSelection() {
        selectedFiles.removeAll()
    }
}

// MARK: - File Row

struct FileRow: View {
    let file: USBFile
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: file.type == .directory ? "folder.fill" : "doc.fill")
                .foregroundColor(file.type == .directory ? .blue : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.body)

                if let size = file.size, file.type == .file {
                    Text(formatBytes(size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            } else if file.type == .directory {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Action Bar

struct ActionBar: View {
    let selectedCount: Int
    let onDownload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .foregroundColor(.red)
            }
            .padding()

            Spacer()

            Text("\\(selectedCount) selected")
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onDownload) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Download")
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.trailing)
        }
        .background(Color(uiColor: .systemGray6))
    }
}

// MARK: - Transfer List View

struct TransferListView: View {
    let transfers: [USBFileTransfer]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Transfers")
                .font(.headline)
                .padding(.horizontal)

            ForEach(transfers) { transfer in
                TransferRow(transfer: transfer)
            }
        }
        .padding(.vertical)
        .background(Color(uiColor: .systemGray6))
    }
}

struct TransferRow: View {
    let transfer: USBFileTransfer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transfer.fileName)
                .font(.caption)

            ProgressView(value: transfer.progress)

            Text(statusText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }

    private var statusText: String {
        switch transfer.status {
        case .inProgress:
            return "Downloading... \\(Int(transfer.progress * 100))%"
        case .completed:
            return "Completed"
        case .failed(let error):
            return "Failed: \\(error)"
        case .cancelled:
            return "Cancelled"
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.wifi")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Wireless USB Drives Found")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Make sure your Wireless USB Bridge is powered on and connected to the same WiFi network.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: {}) {
                Text("Tap 'Scan' to search for devices")
                    .font(.caption)
            }
            .padding(.top, 10)
        }
        .padding()
    }
}

// MARK: - Preview

struct WirelessUSBView_Previews: PreviewProvider {
    static var previews: some View {
        WirelessUSBView()
    }
}
