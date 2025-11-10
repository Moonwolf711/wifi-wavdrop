import UIKit
import Social
import UniformTypeIdentifiers

/// Share Extension view controller for receiving files via share sheet
class ShareViewController: UIViewController {

    private var extensionContext: NSExtensionContext?
    private var shareView: ShareExtensionView?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        extensionContext = self.extensionContext

        // Setup share view
        let shareView = ShareExtensionView()
        shareView.delegate = self
        self.shareView = shareView

        // Add as child view controller
        addChild(shareView)
        view.addSubview(shareView.view)
        shareView.view.frame = view.bounds
        shareView.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shareView.didMove(toParent: self)

        // Process shared items
        processSharedItems()
    }

    private func processSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            shareView?.showError("No items to share")
            return
        }

        var sharedURLs: [URL] = []

        let dispatchGroup = DispatchGroup()

        for extensionItem in extensionItems {
            guard let attachments = extensionItem.attachments else { continue }

            for attachment in attachments {
                dispatchGroup.enter()

                if attachment.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.audio.identifier, options: nil) { [weak self] (item, error) in
                        defer { dispatchGroup.leave() }

                        if let error = error {
                            print("Error loading audio item: \(error)")
                            return
                        }

                        if let url = item as? URL {
                            sharedURLs.append(url)
                        } else if let data = item as? Data {
                            // Save data to temporary file
                            if let tempURL = self?.saveDataToTempFile(data, filename: "audio.m4a") {
                                sharedURLs.append(tempURL)
                            }
                        }
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                        defer { dispatchGroup.leave() }

                        if let error = error {
                            print("Error loading file URL: \(error)")
                            return
                        }

                        if let url = item as? URL {
                            sharedURLs.append(url)
                        }
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (item, error) in
                        defer { dispatchGroup.leave() }

                        if let error = error {
                            print("Error loading URL: \(error)")
                            return
                        }

                        if let url = item as? URL {
                            sharedURLs.append(url)
                        }
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .main) { [weak self] in
            if sharedURLs.isEmpty {
                self?.shareView?.showError("No compatible files found")
            } else {
                self?.shareView?.updateSharedFiles(sharedURLs)
            }
        }
    }

    private func saveDataToTempFile(_ data: Data, filename: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("Error saving data to temp file: \(error)")
            return nil
        }
    }
}

// MARK: - ShareExtensionViewDelegate

extension ShareViewController: ShareExtensionViewDelegate {
    func didRequestSave(files: [URL], to drive: ExternalDrive) {
        // Save files to external drive
        Task {
            do {
                let driveManager = ExternalDriveManager()

                for file in files {
                    _ = try await driveManager.copyFile(
                        from: file,
                        to: drive,
                        destinationPath: "WaveDrop",
                        progress: { _ in }
                    )
                }

                await MainActor.run {
                    self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
            } catch {
                await MainActor.run {
                    self.shareView?.showError("Failed to save files: \(error.localizedDescription)")
                }
            }
        }
    }

    func didRequestCancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.wavedrop.shareextension",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "User cancelled"]
        ))
    }
}
