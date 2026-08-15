import SwiftUI

struct EditorToggleAction {
    let toggle: () -> Void
}

struct EditorToggleKey: FocusedValueKey {
    typealias Value = EditorToggleAction
}

extension FocusedValues {
    var editorToggle: EditorToggleAction? {
        get { self[EditorToggleKey.self] }
        set { self[EditorToggleKey.self] = newValue }
    }
}

struct ShowSearchAction {
    let show: () -> Void
}

struct ShowSearchKey: FocusedValueKey {
    typealias Value = ShowSearchAction
}

extension FocusedValues {
    var showSearch: ShowSearchAction? {
        get { self[ShowSearchKey.self] }
        set { self[ShowSearchKey.self] = newValue }
    }
}

struct FocusedFindButton: View {
    @FocusedValue(\.showSearch) private var showSearch

    var body: some View {
        Button("Find…") {
            showSearch?.show()
        }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(showSearch == nil)
    }
}

struct FocusedEditorToggleButton: View {
    @FocusedValue(\.editorToggle) private var editorToggle

    var body: some View {
        Button("Toggle Editor Mode") {
            editorToggle?.toggle()
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(editorToggle == nil)
    }
}

/// Per-window preview scaling actions (zoom + font size), surfaced to menu commands
/// via the focused scene so ⌘+/⌘-/⌘0 (zoom) and ⌥⌘+/⌥⌘-/⌥⌘0 (font) target the
/// front document only.
struct PreviewScaleActions {
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let zoomReset: () -> Void
    let fontIncrease: () -> Void
    let fontDecrease: () -> Void
    let fontReset: () -> Void
}

struct PreviewScaleKey: FocusedValueKey {
    typealias Value = PreviewScaleActions
}

extension FocusedValues {
    var previewScale: PreviewScaleActions? {
        get { self[PreviewScaleKey.self] }
        set { self[PreviewScaleKey.self] = newValue }
    }
}

struct ScaleCommands: View {
    @FocusedValue(\.previewScale) private var scale

    var body: some View {
        Button("Zoom In") { scale?.zoomIn() }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(scale == nil)
        Button("Zoom Out") { scale?.zoomOut() }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(scale == nil)
        Button("Actual Size") { scale?.zoomReset() }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(scale == nil)

        Divider()

        Button("Increase Font Size") { scale?.fontIncrease() }
            .keyboardShortcut("+", modifiers: [.command, .option])
            .disabled(scale == nil)
        Button("Decrease Font Size") { scale?.fontDecrease() }
            .keyboardShortcut("-", modifiers: [.command, .option])
            .disabled(scale == nil)
        Button("Reset Font Size") { scale?.fontReset() }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .disabled(scale == nil)
    }
}

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }   // suppress default New, add nothing to toolbar

            CommandGroup(after: .newItem) {
                OpenFileCommand()
            }

            CommandGroup(after: .newItem) {
                Button("Reload") {
                    NotificationCenter.default.post(name: .reloadFile, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveFile, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandMenu("Document") {
                FocusedEditorToggleButton()

                Divider()

                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                FocusedFindButton()

                Divider()

                ScaleCommands()
            }

            CommandMenu("Export") {
                Button("Export as PDF…") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Export as HTML…") {
                    NotificationCenter.default.post(name: .exportHTML, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Settings {
            PreferencesView()
        }
    }
}

struct OpenFileCommand: View {
    @Environment(\.openDocument) private var openDocument

    var body: some View {
        Button("Open…") {
            let panel = NSOpenPanel()
            // Allow any file; MarkdownDocument reads it as UTF-8 text.
            panel.allowsOtherFileTypes = true
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            if panel.runModal() == .OK, let url = panel.url {
                Task { try? await openDocument(at: url) }
            }
        }
        .keyboardShortcut("o", modifiers: .command)
    }
}

// MARK: - Additional Notification names

extension Notification.Name {
    static let exportPDF = Notification.Name("MDViewer.exportPDF")
    static let exportHTML = Notification.Name("MDViewer.exportHTML")
    static let pdfPageSizeChanged = Notification.Name("MDViewer.pdfPageSizeChanged")
}
