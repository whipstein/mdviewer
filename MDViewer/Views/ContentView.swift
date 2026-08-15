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
    @State private var isEditorMode: Bool = false

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

                                    MarkdownEditorView(documentVM: documentVM, renderVM: renderVM)
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
                        exportVM: exportVM, isEditorMode: $isEditorMode)
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
            documentVM.reload(confirmIfDirty: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
            documentVM.save()
        }
        // Remove: .onReceive(NotificationCenter.default.publisher(for: .toggleEditorMode)) { _ in isEditorMode.toggle() }

        // Add this modifier to the body (e.g. near .toolbar):
        .focusedSceneValue(\.editorToggle, EditorToggleAction(toggle: { isEditorMode.toggle() }))
        .focusedSceneValue(\.showSearch, ShowSearchAction(show: { renderVM.isSearchVisible = true }))
        .focusedSceneValue(\.previewScale, PreviewScaleActions(
            zoomIn: { renderVM.zoomIn() },
            zoomOut: { renderVM.zoomOut() },
            zoomReset: { renderVM.resetZoom() },
            fontIncrease: { renderVM.increaseFontSize() },
            fontDecrease: { renderVM.decreaseFontSize() },
            fontReset: { renderVM.resetFontSize() }
        ))
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
            // Restore/persist this document's window frame keyed by its file path.
            context.coordinator.bind(window: window, fileURL: documentVM.fileURL)
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

        private weak var boundWindow: NSWindow?
        private var fileURL: URL?
        private var didRestore = false
        private var frameObservers: [NSObjectProtocol] = []

        init(documentVM: DocumentViewModel) {
            self.documentVM = documentVM
        }

        deinit {
            frameObservers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        // MARK: Per-document window frame persistence

        private var frameKey: String? {
            guard let path = fileURL?.standardizedFileURL.path, !path.isEmpty else { return nil }
            return "windowFrame:\(path)"
        }

        /// Restore this document's saved window frame once, and keep it saved as the
        /// window is resized/moved/closed. Keyed by the document's file path so each
        /// document reopens at the size it was last left.
        func bind(window: NSWindow, fileURL: URL?) {
            self.fileURL = fileURL

            if boundWindow !== window {
                frameObservers.forEach { NotificationCenter.default.removeObserver($0) }
                frameObservers.removeAll()
                boundWindow = window

                let center = NotificationCenter.default
                for name in [NSWindow.didEndLiveResizeNotification,
                             NSWindow.didMoveNotification,
                             NSWindow.willCloseNotification] {
                    frameObservers.append(
                        center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                            self?.saveFrame()
                        }
                    )
                }
            }

            restoreFrameIfNeeded()
        }

        private func restoreFrameIfNeeded() {
            guard !didRestore, let window = boundWindow, let key = frameKey else { return }
            didRestore = true
            if let saved = UserDefaults.standard.string(forKey: key) {
                window.setFrame(NSRectFromString(saved), display: true)
            }
        }

        private func saveFrame() {
            guard let window = boundWindow, let key = frameKey else { return }
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: key)
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
