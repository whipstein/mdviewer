import AppKit
import SwiftUI

struct ContentView: View {
    let document: MarkdownDocument
    var fileURL: URL?

    @Environment(\.openWindow) private var openWindow
    
    @StateObject private var documentVM = DocumentViewModel()
    @StateObject private var sidebarVM = SidebarViewModel()
    @StateObject private var renderVM = RenderViewModel()
    @StateObject private var exportVM = ExportViewModel()

    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @AppStorage("isSidebarVisible") private var isSidebarVisible: Bool = true
    @AppStorage("isEditorMode") private var isEditorMode: Bool = false

    @State private var editorWidth: Double? = nil
    
    private func drainPendingOpens() {
        let urls = PendingOpen.shared.urls
        PendingOpen.shared.urls.removeAll()
        for url in urls {
            openWindow(value: url)
        }
    }
    
    var body: some View {
        NavigationSplitView(
            sidebar: {
                SidebarView(sidebarVM: sidebarVM, renderVM: renderVM)
                    .frame(minWidth: 180, idealWidth: sidebarWidth, maxWidth: 400)
            },
            detail: {
                GeometryReader { geo in
                    Group {
                        if documentVM.text.isEmpty, documentVM.fileURL == nil {
                            WelcomeView(documentVM: documentVM)
                        } else {
                            let total = geo.size.width
                            let editorW = editorWidth ?? total / 2
                            HStack(spacing: 0) {
                                // Preview — ALWAYS mounted, single instance, never moves between branches
                                MarkdownRenderView(documentVM: documentVM, renderVM: renderVM, sidebarVM: sidebarVM)
                                    .frame(minWidth: 250, maxWidth: .infinity)

                                if isEditorMode {
                                    // Divider
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 6)
                                        .onHover { inside in
                                            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                        }
                                        .gesture(
                                            DragGesture()
                                                .onChanged { value in
                                                    let newEditorW = editorW - value.translation.width
                                                    editorWidth = min(max(250, newEditorW), total - 250)
                                                }
                                        )

                                    MarkdownEditorView(documentVM: documentVM)
                                        .frame(width: max(250, editorW))
                                }
                            }
                            .onChange(of: isEditorMode) { _, on in
                                if on { editorWidth = total / 2 }
                            }
                        }
                    }
                }
            }
        )
        .background(WindowCloseInterceptor(documentVM: documentVM))
        .toolbar {
            MainToolbar(documentVM: documentVM, renderVM: renderVM,
                        exportVM: exportVM, isEditorMode: isEditorMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pendingOpenChanged)) { _ in
            drainPendingOpens()
        }
        .onAppear {
            print("IMG-DEBUG fileURL = \(String(describing: fileURL))")
            if let url = fileURL {
                documentVM.load(url: url)
            }
            drainPendingOpens()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadFile)) { _ in
            documentVM.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
            documentVM.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditorMode)) { _ in
            isEditorMode.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            // NavigationSplitView handles its own sidebar toggle
        }
        // Keyboard shortcuts via Commands are declared in MDViewerApp
        .navigationTitle(documentVM.fileURL?.lastPathComponent ?? "MDViewer")
        .frame(minWidth: 800, minHeight: 600)
        .alert("Error", isPresented: Binding(
            get: { documentVM.errorMessage != nil },
            set: { if !$0 { documentVM.errorMessage = nil } }
        )) {
            Button("OK") { documentVM.errorMessage = nil }
        } message: {
            Text(documentVM.errorMessage ?? "")
        }
    }
}

// MARK: - Window close interceptor

/// NSViewRepresentable that attaches an NSWindowDelegate to block window close when there are unsaved changes.
private struct WindowCloseInterceptor: NSViewRepresentable {
    let documentVM: DocumentViewModel

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.documentVM = documentVM
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            documentVM.hostWindow = window
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(documentVM: documentVM)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var documentVM: DocumentViewModel

        init(documentVM: DocumentViewModel) {
            self.documentVM = documentVM
        }

        func windowShouldClose(_: NSWindow) -> Bool {
            guard documentVM.isDirty else { return true }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("unsaved_changes_title", comment: "")
            alert.informativeText = NSLocalizedString("unsaved_changes_message", comment: "")
            alert.addButton(withTitle: NSLocalizedString("save_button", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("discard_button", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: ""))
            alert.alertStyle = .warning

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                documentVM.save()
                return documentVM.errorMessage == nil
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Welcome screen

struct WelcomeView: View {
    let documentVM: DocumentViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("MDViewer")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Open a Markdown file to get started")
                .foregroundColor(.secondary)

            Button("Open File…") {
                documentVM.openFile()
            }
            .keyboardShortcut("o", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.markdown, .plainText, .fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadFileRepresentation(forTypeIdentifier: "public.file-url") { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    documentVM.load(url: url)
                }
            }
            return true
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openFile = Notification.Name("MDViewer.openFile")
    static let reloadFile = Notification.Name("MDViewer.reloadFile")
    static let saveFile = Notification.Name("MDViewer.saveFile")
    static let toggleSidebar = Notification.Name("MDViewer.toggleSidebar")
    static let toggleEditorMode = Notification.Name("MDViewer.toggleEditorMode")
}
