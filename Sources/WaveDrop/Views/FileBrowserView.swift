import SwiftUI
import UniformTypeIdentifiers

/// File browser for exploring external drive contents
public struct FileBrowserView: View {
    let drive: ExternalDrive
    let driveManager: ExternalDriveManager

    @State private var currentDirectory: URL
    @State private var files: [FileItem] = []
    @State private var isLoading = false
    @State private var selectedFiles: Set<UUID> = []
    @State private var showingExportOptions = false
    @State private var errorMessage: String?

    public init(drive: ExternalDrive, driveManager: ExternalDriveManager) {
        self.drive = drive
        self.driveManager = driveManager
        _currentDirectory = State(initialValue: drive.url ?? URL(fileURLWithPath: "/"))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Current path breadcrumb
                pathBreadcrumb

                Divider()

                // File list
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if files.isEmpty {
                    emptyFolderView
                } else {
                    fileListView
                }
            }
            .navigationTitle(drive.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingExportOptions = true
                        } label: {
                            Label("Export Selected", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selectedFiles.isEmpty)

                        Button {
                            selectedFiles.removeAll()
                        } label: {
                            Label("Clear Selection", systemImage: "xmark.circle")
                        }
                        .disabled(selectedFiles.isEmpty)

                        Divider()

                        Button {
                            refreshFiles()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingExportOptions) {
                ExportOptionsView(
                    selectedFiles: selectedAudioFiles,
                    drive: drive
                )
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
                refreshFiles()
            }
        }
    }

    // MARK: - View Components

    private var pathBreadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    if let driveURL = drive.url {
                        navigateTo(driveURL)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive.fill")
                        Text(drive.name)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }

                if let driveURL = drive.url,
                   currentDirectory.path != driveURL.path {
                    let pathComponents = currentDirectory.path
                        .replacingOccurrences(of: driveURL.path, with: "")
                        .split(separator: "/")

                    ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button {
                            var path = driveURL.path
                            for i in 0...index {
                                path += "/\(pathComponents[i])"
                            }
                            navigateTo(URL(fileURLWithPath: path))
                        } label: {
                            Text(String(component))
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var emptyFolderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 60))
                .foregroundStyle(.gray)

            Text("Empty Folder")
                .font(.title3)
                .fontWeight(.medium)

            Text("This folder contains no files")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileListView: some View {
        List {
            ForEach(files) { file in
                FileRow(
                    file: file,
                    isSelected: selectedFiles.contains(file.id)
                ) {
                    handleFileTap(file)
                } onSelect: {
                    toggleSelection(file)
                }
            }
        }
        .listStyle(.plain)
    }

    private var selectedAudioFiles: [FileItem] {
        files.filter { selectedFiles.contains($0.id) && $0.isAudioFile }
    }

    // MARK: - Actions

    private func refreshFiles() {
        isLoading = true
        Task { @MainActor in
            do {
                let urls = try driveManager.contentsOfDirectory(at: currentDirectory)
                let items = urls.map { FileItem(url: $0) }.sorted { file1, file2 in
                    // Directories first, then alphabetically
                    if file1.isDirectory != file2.isDirectory {
                        return file1.isDirectory
                    }
                    return file1.name < file2.name
                }
                files = items
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func navigateTo(_ url: URL) {
        currentDirectory = url
        selectedFiles.removeAll()
        refreshFiles()
    }

    private func handleFileTap(_ file: FileItem) {
        if file.isDirectory {
            navigateTo(file.url)
        } else if file.isAudioFile {
            toggleSelection(file)
        }
    }

    private func toggleSelection(_ file: FileItem) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
        } else {
            selectedFiles.insert(file.id)
        }
    }
}

// MARK: - Supporting Views

struct FileRow: View {
    let file: FileItem
    let isSelected: Bool
    let onTap: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if file.isAudioFile {
                Button {
                    onSelect()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .blue : .gray)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Image(systemName: file.icon)
                .foregroundStyle(file.iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body)

                if let formattedSize = file.formattedSize {
                    Text(formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

struct ExportOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    let selectedFiles: [FileItem]
    let drive: ExternalDrive

    @State private var selectedSoftware: Set<DJExportManager.DJSoftware> = [.rekordbox]
    @State private var isExporting = false
    @State private var exportProgress: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Selected Files") {
                    Text("\(selectedFiles.count) audio files")
                        .font(.headline)

                    ForEach(selectedFiles.prefix(5)) { file in
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundStyle(.blue)
                            Text(file.name)
                                .font(.caption)
                        }
                    }

                    if selectedFiles.count > 5 {
                        Text("...and \(selectedFiles.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Export To") {
                    ForEach([
                        DJExportManager.DJSoftware.rekordbox,
                        .serato,
                        .traktor,
                        .virtualDJ,
                        .enginePrime
                    ], id: \.self) { software in
                        Toggle(softwareName(software), isOn: Binding(
                            get: { selectedSoftware.contains(software) },
                            set: { isOn in
                                if isOn {
                                    selectedSoftware.insert(software)
                                } else {
                                    selectedSoftware.remove(software)
                                }
                            }
                        ))
                    }
                }

                if isExporting {
                    Section {
                        VStack(spacing: 12) {
                            ProgressView(value: exportProgress, total: 1.0)
                            Text("\(Int(exportProgress * 100))% Complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isExporting)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        startExport()
                    }
                    .disabled(selectedSoftware.isEmpty || isExporting)
                }
            }
        }
    }

    private func softwareName(_ software: DJExportManager.DJSoftware) -> String {
        switch software {
        case .rekordbox: return "Rekordbox"
        case .serato: return "Serato"
        case .traktor: return "Traktor"
        case .virtualDJ: return "Virtual DJ"
        case .enginePrime: return "Engine Prime"
        }
    }

    private func startExport() {
        isExporting = true
        // Export logic would go here
        Task {
            for i in 0...10 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    exportProgress = Double(i) / 10.0
                }
            }
            await MainActor.run {
                dismiss()
            }
        }
    }
}

// MARK: - Models

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let fileSize: Int64?

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue

        if !isDirectory,
           let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            self.fileSize = size
        } else {
            self.fileSize = nil
        }
    }

    var isAudioFile: Bool {
        let audioExtensions = ["mp3", "wav", "aiff", "aif", "flac", "m4a", "aac", "ogg"]
        return audioExtensions.contains(url.pathExtension.lowercased())
    }

    var icon: String {
        if isDirectory {
            return "folder.fill"
        } else if isAudioFile {
            return "music.note"
        } else {
            return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory {
            return .blue
        } else if isAudioFile {
            return .purple
        } else {
            return .gray
        }
    }

    var formattedSize: String? {
        guard let size = fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Preview

struct FileBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        let drive = ExternalDrive(
            id: "1",
            name: "USB Drive",
            url: URL(fileURLWithPath: "/Volumes/USB"),
            totalCapacity: 32_000_000_000,
            availableCapacity: 16_000_000_000,
            isEjectable: true
        )
        FileBrowserView(drive: drive, driveManager: ExternalDriveManager())
    }
}
