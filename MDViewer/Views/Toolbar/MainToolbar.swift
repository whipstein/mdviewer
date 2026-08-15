import SwiftUI

struct MainToolbar: ToolbarContent {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openDocument) private var openDocument
    @ObservedObject var documentVM: DocumentViewModel
    @ObservedObject var renderVM: RenderViewModel
    @ObservedObject var exportVM: ExportViewModel
    @Binding var isEditorMode: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                if let url = FilePicker.pickMarkdownURL() {
                    Task { try? await openDocument(at: url) }
                }
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open File (⌘O)")
        }

        ToolbarItem(placement: .navigation) {
            Button {
                NotificationCenter.default.post(name: .reloadFile, object: nil)
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Reload File (⌘R)")
        }

        // Zoom controls — grouped in a single ToolbarItem/HStack.
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 4) {
                Button {
                    renderVM.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom Out (⌘-)")

                Button {
                    renderVM.resetZoom()
                } label: {
                    Text("\(Int((renderVM.zoom * 100).rounded()))%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(minWidth: 40)
                }
                .help("Actual Size (⌘0)")

                Button {
                    renderVM.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom In (⌘+)")
            }
        }

        // Break the shared pill so zoom is its own section (macOS 26+ Liquid Glass).
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
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
                renderVM.isSearchVisible = true
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

            // Font size controls (value is an editable field)
            Button {
                renderVM.decreaseFontSize()
            } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .help("Decrease Font Size (⌥⌘-)")

            FontSizeField(renderVM: renderVM)

            Button {
                renderVM.increaseFontSize()
            } label: {
                Image(systemName: "textformat.size.larger")
            }
            .help("Increase Font Size (⌥⌘+)")
        }

        // Theme picker — its own section
        ToolbarItem(placement: .primaryAction) {
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
        }

        // Export menu — its own section
        ToolbarItem(placement: .primaryAction) {
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

/// Editable font-size field for the toolbar. Click to type a new size; commit with
/// Return. Reflects external changes (steppers, ⌥⌘±) when not being edited.
private struct FontSizeField: View {
    @ObservedObject var renderVM: RenderViewModel
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.caption)
            .monospacedDigit()
            .frame(width: 30)
            .focused($isFocused)
            .onSubmit(commit)
            .onAppear { text = String(Int(renderVM.fontSize)) }
            .onChange(of: renderVM.fontSize) { _, newValue in
                if !isFocused { text = String(Int(newValue)) }
            }
            .onChange(of: isFocused) { _, focused in
                // On blur without committing, restore the current value.
                if !focused { text = String(Int(renderVM.fontSize)) }
            }
            .help("Font Size (click to type, ⌥⌘0 to reset)")
    }

    private func commit() {
        if let value = Double(text) {
            renderVM.setFontSize(value)
        }
        text = String(Int(renderVM.fontSize))
        isFocused = false
    }
}
