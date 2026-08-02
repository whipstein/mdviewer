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

                Button("Find…") {
                    NotificationCenter.default.post(name: .showSearchBar, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Increase Font Size") {
                    NotificationCenter.default.post(name: .increaseFontSize, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    NotificationCenter.default.post(name: .decreaseFontSize, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    NotificationCenter.default.post(name: .resetFontSize, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
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
    var body: some View {
        Button("Open…") {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.markdown, .plainText]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            if panel.runModal() == .OK, let url = panel.url {
                NSWorkspace.shared.open(url)
            }
        }
        .keyboardShortcut("o", modifiers: .command)
    }
}

// MARK: - Additional Notification names

extension Notification.Name {
    static let increaseFontSize = Notification.Name("MDViewer.increaseFontSize")
    static let decreaseFontSize = Notification.Name("MDViewer.decreaseFontSize")
    static let resetFontSize = Notification.Name("MDViewer.resetFontSize")
    static let exportPDF = Notification.Name("MDViewer.exportPDF")
    static let exportHTML = Notification.Name("MDViewer.exportHTML")
    static let pdfPageSizeChanged = Notification.Name("MDViewer.pdfPageSizeChanged")
}
