import SwiftUI

/// Main view of the WaveDrop app
public struct MainView: View {
    @StateObject private var driveManager = ExternalDriveManager()
    @State private var selectedDrive: ExternalDrive?
    @State private var showingFileBrowser = false
    @State private var showingSettings = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                headerView

                if driveManager.connectedDrives.isEmpty {
                    emptyStateView
                } else {
                    driveListView
                }

                Spacer()

                statusView
            }
            .padding()
            .navigationTitle("WaveDrop")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingFileBrowser) {
                if let drive = selectedDrive {
                    FileBrowserView(drive: drive, driveManager: driveManager)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                driveManager.startMonitoring()
            }
            .onDisappear {
                driveManager.stopMonitoring()
            }
        }
    }

    // MARK: - View Components

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.fill.badge.wifi")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("WaveDrop")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Professional DJ Workflow")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 80))
                .foregroundStyle(.gray)

            Text("No External Drive Connected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect a USB drive via Lightning or USB-C adapter")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                InstructionRow(icon: "1.circle.fill", text: "Connect USB adapter to iPhone")
                InstructionRow(icon: "2.circle.fill", text: "Plug in your USB drive")
                InstructionRow(icon: "3.circle.fill", text: "Wait for drive to appear")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
    }

    private var driveListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(driveManager.connectedDrives) { drive in
                    DriveCard(drive: drive) {
                        selectedDrive = drive
                        showingFileBrowser = true
                    }
                }
            }
        }
    }

    private var statusView: some View {
        VStack(spacing: 8) {
            if driveManager.isMonitoring {
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)

                    Text("Monitoring for drives")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Supporting Views

struct DriveCard: View {
    let drive: ExternalDrive
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "externaldrive.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(drive.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("\(drive.formattedAvailableCapacity) available of \(drive.formattedTotalCapacity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }

                // Capacity bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 6)
                            .cornerRadius(3)

                        Rectangle()
                            .fill(.blue)
                            .frame(
                                width: geometry.size.width * CGFloat(drive.usedCapacity) / CGFloat(drive.totalCapacity),
                                height: 6
                            )
                            .cornerRadius(3)
                    }
                }
                .frame(height: 6)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)

            Spacer()
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Export Settings") {
                    Toggle("Auto-detect BPM", isOn: .constant(true))
                    Toggle("Auto-detect Key", isOn: .constant(true))
                    Toggle("Generate Waveforms", isOn: .constant(true))
                }

                Section("DJ Software") {
                    Toggle("Rekordbox", isOn: .constant(true))
                    Toggle("Serato", isOn: .constant(true))
                    Toggle("Traktor", isOn: .constant(false))
                    Toggle("Virtual DJ", isOn: .constant(false))
                    Toggle("Engine Prime", isOn: .constant(false))
                }

                Section("Advanced") {
                    Stepper("Waveform Samples: 1000", value: .constant(1000), in: 100...5000, step: 100)
                    Picker("BPM Range", selection: .constant(0)) {
                        Text("60-200 BPM").tag(0)
                        Text("80-180 BPM").tag(1)
                        Text("100-160 BPM").tag(2)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link("GitHub Repository", destination: URL(string: "https://github.com")!)
                }
            }
            .navigationTitle("Settings")
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

// MARK: - Preview

#Preview {
    MainView()
}
