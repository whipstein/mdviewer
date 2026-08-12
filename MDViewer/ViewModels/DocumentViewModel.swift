import Combine
import SwiftUI

@MainActor
final class DocumentViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var fileURL: URL?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isDirty: Bool = false
    weak var hostWindow: NSWindow?

    private let fileWatcher = FileWatcher()

    init() {
        fileWatcher.onChange = { [weak self] in
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        // Allow selecting any file; it's read as UTF-8 text.
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    func load(url: URL) {
        isLoading = true
        errorMessage = nil

        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            text = contents
            isDirty = false
            fileWatcher.start(url: url)
            BookmarkManager.shared.save(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Reload the file from disk.
    /// - Parameter confirmIfDirty: When true (manual reload) the user is asked before
    ///   discarding unsaved edits. When false (file-watcher auto-reload) unsaved edits
    ///   are never silently clobbered — the reload is skipped instead.
    func reload(confirmIfDirty: Bool = false) {
        guard let url = fileURL else { return }

        if isDirty {
            guard confirmIfDirty else { return }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("unsaved_changes_title", comment: "")
            alert.informativeText = NSLocalizedString("unsaved_changes_message", comment: "")
            alert.addButton(withTitle: NSLocalizedString("save_button", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("discard_button", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: ""))
            alert.alertStyle = .warning

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                // Save keeps the current edits; disk already matches, nothing to reload.
                save()
                return
            case .alertSecondButtonReturn:
                break // Discard and fall through to reload from disk.
            default:
                return // Cancel.
            }
        }

        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            isDirty = false
            text = contents
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateText(_ newText: String) {
        guard text != newText else { return }
        isDirty = true
        text = newText
    }

    func save() {
        guard let url = fileURL else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
