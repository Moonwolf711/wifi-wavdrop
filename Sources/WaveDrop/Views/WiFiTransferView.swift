import SwiftUI

/// WiFi transfer interface for wireless file sharing
public struct WiFiTransferView: View {
    @StateObject private var wifiManager = WiFiTransferManager()
    @State private var selectedDevice: WiFiDevice?
    @State private var showingQRCode = false
    @State private var showingDevicePicker = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Server Status Card
                    serverStatusCard

                    // Active Transfers
                    if !wifiManager.activeTransfers.isEmpty {
                        activeTransfersSection
                    }

                    // Discovered Devices
                    if wifiManager.isServerRunning {
                        discoveredDevicesSection
                    }

                    // Instructions
                    instructionsSection
                }
                .padding()
            }
            .navigationTitle("Wi-Fi Transfer")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if wifiManager.isServerRunning {
                            Button {
                                showingQRCode = true
                            } label: {
                                Label("Show QR Code", systemImage: "qrcode")
                            }

                            Button(role: .destructive) {
                                wifiManager.stopServer()
                                wifiManager.stopDiscovery()
                            } label: {
                                Label("Stop Server", systemImage: "stop.circle")
                            }
                        } else {
                            Button {
                                wifiManager.startServer()
                                wifiManager.startDiscovery()
                            } label: {
                                Label("Start Server", systemImage: "play.circle")
                            }
                        }

                        Divider()

                        Button {
                            wifiManager.startDiscovery()
                        } label: {
                            Label("Scan for Devices", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingQRCode) {
                if let url = wifiManager.serverURL {
                    QRCodeView(url: url)
                }
            }
            .sheet(isPresented: $showingDevicePicker) {
                DevicePickerView(
                    devices: wifiManager.discoveredDevices,
                    selectedDevice: $selectedDevice
                )
            }
        }
    }

    // MARK: - View Components

    private var serverStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: wifiManager.isServerRunning ? "wifi" : "wifi.slash")
                    .font(.system(size: 60))
                    .foregroundStyle(wifiManager.isServerRunning ? .green : .gray)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(wifiManager.isServerRunning ? "Server Running" : "Server Stopped")
                        .font(.headline)
                        .foregroundStyle(wifiManager.isServerRunning ? .primary : .secondary)

                    if let url = wifiManager.serverURL {
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if wifiManager.isServerRunning {
                VStack(spacing: 12) {
                    Button {
                        wifiManager.stopServer()
                        wifiManager.stopDiscovery()
                    } label: {
                        Label("Stop Server", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .cornerRadius(12)
                    }

                    Button {
                        showingQRCode = true
                    } label: {
                        Label("Show QR Code", systemImage: "qrcode")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(12)
                    }
                }
            } else {
                Button {
                    wifiManager.startServer()
                    wifiManager.startDiscovery()
                } label: {
                    Label("Start Server", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .foregroundStyle(.green)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private var activeTransfersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Transfers")
                .font(.headline)

            ForEach(wifiManager.activeTransfers) { transfer in
                TransferRow(transfer: transfer) {
                    wifiManager.cancelTransfer(transfer.id)
                }
            }
        }
    }

    private var discoveredDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discovered Devices")
                    .font(.headline)

                Spacer()

                Button {
                    wifiManager.startDiscovery()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.blue)
                }
            }

            if wifiManager.discoveredDevices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)

                    Text("No devices found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Make sure other devices are running WaveDrop")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                ForEach(wifiManager.discoveredDevices) { device in
                    DeviceRow(device: device) {
                        selectedDevice = device
                        showingDevicePicker = true
                    }
                }
            }
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to Transfer Files")
                .font(.headline)

            InstructionCard(
                icon: "1.circle.fill",
                title: "Start Server",
                description: "Tap 'Start Server' to begin receiving files"
            )

            InstructionCard(
                icon: "2.circle.fill",
                title: "Connect Devices",
                description: "Ensure both devices are on the same Wi-Fi network"
            )

            InstructionCard(
                icon: "3.circle.fill",
                title: "Transfer Files",
                description: "Open the server URL in a browser or use another WaveDrop device"
            )

            InstructionCard(
                icon: "4.circle.fill",
                title: "QR Code",
                description: "Share the QR code for easy connection"
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Supporting Views

struct TransferRow: View {
    let transfer: FileTransfer
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: transfer.direction == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(transfer.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("\(transfer.deviceName) • \(transfer.formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if transfer.status == .inProgress {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                } else {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                }
            }

            if transfer.status == .inProgress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 4)
                            .cornerRadius(2)

                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * transfer.progress, height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)

                Text("\(Int(transfer.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var statusIcon: String {
        switch transfer.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .inProgress: return "arrow.clockwise.circle.fill"
        }
    }

    private var statusColor: Color {
        switch transfer.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .inProgress: return .blue
        }
    }
}

struct DeviceRow: View {
    let device: WiFiDevice
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(device.serviceType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct InstructionCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct QRCodeView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Scan to Connect")
                    .font(.title2)
                    .fontWeight(.bold)

                // QR Code placeholder (implement actual QR code generation)
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(width: 280, height: 280)

                    Image(systemName: "qrcode")
                        .font(.system(size: 200))
                        .foregroundStyle(.black)
                }
                .shadow(radius: 8)

                VStack(spacing: 8) {
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = url.absoluteString
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DevicePickerView: View {
    let devices: [WiFiDevice]
    @Binding var selectedDevice: WiFiDevice?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(devices) { device in
                Button {
                    selectedDevice = device
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "iphone")
                        Text(device.name)
                        Spacer()
                        if selectedDevice?.id == device.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WiFiTransferView()
}
