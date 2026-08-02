import SwiftUI

struct MainToolbar: ToolbarContent {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var documentVM: DocumentViewModel
    @ObservedObject var renderVM: RenderViewModel
    @ObservedObject var exportVM: ExportViewModel
    @Binding var isEditorMode: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                if let url = FilePicker.pickMarkdownURL() {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open Markdown File (⌘O)")
        }

        ToolbarItem(placement: .navigation) {
            Button {
                NotificationCenter.default.post(name: .reloadFile, object: nil)
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Reload File (⌘R)")
        }
        
        ToolbarItemGroup(placement: .primaryAction) {
            // The Editor button:
            Button {
                isEditorMode.toggle()
            } label: {
                Label("Editor", systemImage: "pencil")
            }
            .foregroundColor(isEditorMode ? .accentColor : .primary)
            .help("Toggle Editor Mode (⌘E)")
            
            // Search button
            Button {
                NotificationCenter.default.post(name: .showSearchBar, object: nil)
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .help("Find (⌘F)")

            // Save button
            Button {
                NotificationCenter.default.post(name: .saveFile, object: nil)
            } label: {
                Label("Save", systemImage: "externaldrive")
            }
            .disabled(!documentVM.isDirty)
            .help("Save (⌘S)")

            Divider()

            // Font size controls
            HStack(spacing: 4) {
                Button {
                    renderVM.decreaseFontSize()
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .help("Decrease Font Size (⌘-)")

                Button {
                    renderVM.resetFontSize()
                } label: {
                    Text("\(Int(renderVM.fontSize))")
                        .font(.caption)
                        .frame(minWidth: 24)
                }
                .help("Reset Font Size (⌘0)")

                Button {
                    renderVM.increaseFontSize()
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help("Increase Font Size (⌘+)")
            }

            Divider()

            // Theme picker
            Menu {
                ForEach(MarkdownTheme.all) { theme in
                    Button(theme.displayName) {
                        renderVM.setTheme(theme)
                    }
                }
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
            .help("Select Theme")

            // Export menu
            Menu {
                Button("Export as PDF…") {
                    if let wv = renderVM.webView {
                        exportVM.exportToPDF(webView: wv, sourceURL: documentVM.fileURL)
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Export as HTML…") {
                    if let wv = renderVM.webView {
                        exportVM.exportToHTML(webView: wv, sourceURL: documentVM.fileURL)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Print…") {
                    if let wv = renderVM.webView {
                        exportVM.print(webView: wv)
                    }
                }
                .keyboardShortcut("p", modifiers: .command)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export or Print")
        }
    }
}
