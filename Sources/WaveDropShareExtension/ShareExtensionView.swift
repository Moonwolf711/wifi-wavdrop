import UIKit
import SwiftUI

protocol ShareExtensionViewDelegate: AnyObject {
    func didRequestSave(files: [URL], to drive: ExternalDrive)
    func didRequestCancel()
}

/// SwiftUI view for Share Extension UI
class ShareExtensionView: UIViewController {

    weak var delegate: ShareExtensionViewDelegate?

    private var sharedFiles: [URL] = []
    private var hostingController: UIHostingController<ShareExtensionContentView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
    }

    private func setupUI() {
        let contentView = ShareExtensionContentView(
            sharedFiles: sharedFiles,
            onSave: { [weak self] drive in
                guard let self = self else { return }
                self.delegate?.didRequestSave(files: self.sharedFiles, to: drive)
            },
            onCancel: { [weak self] in
                self?.delegate?.didRequestCancel()
            }
        )

        let hostingController = UIHostingController(rootView: contentView)
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.didMove(toParent: self)
    }

    func updateSharedFiles(_ files: [URL]) {
        sharedFiles = files
        setupUI()
    }

    func showError(_ message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.delegate?.didRequestCancel()
        })
        present(alert, animated: true)
    }
}

// MARK: - SwiftUI Content View

struct ShareExtensionContentView: View {
    let sharedFiles: [URL]
    let onSave: (ExternalDrive) -> Void
    let onCancel: () -> Void

    @StateObject private var driveManager = ExternalDriveManager()
    @State private var selectedDrive: ExternalDrive?
    @State private var destinationPath: String = "WaveDrop"

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                headerView

                // Shared files
                sharedFilesSection

                // Drive selection
                driveSelectionSection

                Spacer()

                // Action buttons
                actionButtons
            }
            .padding()
            .navigationTitle("Save to Drive")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                driveManager.startMonitoring()
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text("Save Files to External Drive")
                .font(.headline)

            Text("\(sharedFiles.count) file\(sharedFiles.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var sharedFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Files")
                .font(.headline)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sharedFiles, id: \.self) { url in
                        HStack {
                            Image(systemName: iconForFile(url))
                                .foregroundStyle(.blue)

                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }

    private var driveSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Destination")
                .font(.headline)

            if driveManager.connectedDrives.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.xmark")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)

                    Text("No external drive connected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Connect a USB drive to continue")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(driveManager.connectedDrives) { drive in
                        Button {
                            selectedDrive = drive
                        } label: {
                            HStack {
                                Image(systemName: "externaldrive.fill")
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(drive.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    Text("\(drive.formattedAvailableCapacity) available")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedDrive?.id == drive.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding()
                            .background(
                                selectedDrive?.id == drive.id
                                    ? Color.blue.opacity(0.1)
                                    : Color(.systemGray6)
                            )
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Destination path
                VStack(alignment: .leading, spacing: 8) {
                    Text("Folder")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Destination folder", text: $destinationPath)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .cornerRadius(12)
            }

            Button {
                if let drive = selectedDrive {
                    onSave(drive)
                }
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedDrive != nil ? Color.blue : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(selectedDrive == nil)
        }
    }

    private func iconForFile(_ url: URL) -> String {
        let audioExtensions = ["mp3", "wav", "aiff", "aif", "flac", "m4a", "aac", "ogg"]
        if audioExtensions.contains(url.pathExtension.lowercased()) {
            return "music.note"
        }
        return "doc"
    }
}

// MARK: - Preview

#Preview {
    ShareExtensionContentView(
        sharedFiles: [
            URL(fileURLWithPath: "/test/song1.mp3"),
            URL(fileURLWithPath: "/test/song2.wav")
        ],
        onSave: { _ in },
        onCancel: {}
    )
}
