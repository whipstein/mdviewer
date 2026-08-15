import Combine
import SwiftUI
import WebKit

@MainActor
final class RenderViewModel: ObservableObject {
    @Published var theme: MarkdownTheme = .githubLight
    @Published var fontSize: Double = 16
    @Published var hoveredURL: String = ""

    /// Safari-style page zoom for the rendered preview (1.0 = 100%). Applied via
    /// WKWebView.pageZoom, which scales all page content (text, images, code, diagrams).
    @Published var zoom: Double = 1.0

    /// A request from the preview to move the editor to a source line (click-to-locate).
    /// The `id` lets the editor detect a new request even if the same line is clicked twice.
    struct EditorScrollRequest: Equatable {
        let line: Int
        let id: Int
    }
    @Published var editorScrollRequest: EditorScrollRequest?
    private var editorScrollCounter = 0

    func requestEditorScroll(toLine line: Int) {
        editorScrollCounter += 1
        editorScrollRequest = EditorScrollRequest(line: line, id: editorScrollCounter)
    }

    /// Whether the search bar is visible in this window. Per-window state so a
    /// Find command only affects the focused document, not every open window.
    @Published var isSearchVisible: Bool = false

    /// In-page search results reported by the renderer: total matches and the
    /// 1-based index of the current match (0 when there are none).
    @Published var searchMatchCount: Int = 0
    @Published var searchCurrentIndex: Int = 0

    func search(_ query: String) {
        webView?.evaluateJavaScript("MDViewer.search('\(escapeForJS(query))')", completionHandler: nil)
    }

    func searchNext() {
        webView?.evaluateJavaScript("MDViewer.searchNext()", completionHandler: nil)
    }

    func searchPrevious() {
        webView?.evaluateJavaScript("MDViewer.searchPrev()", completionHandler: nil)
    }

    func clearSearch() {
        webView?.evaluateJavaScript("MDViewer.clearSearch()", completionHandler: nil)
        searchMatchCount = 0
        searchCurrentIndex = 0
    }

    func updateSearchResult(count: Int, current: Int) {
        searchMatchCount = count
        searchCurrentIndex = current
    }

    @AppStorage("selectedThemeId") private var storedThemeId: String = MarkdownTheme.githubLight.id
    @AppStorage("fontSize") private var storedFontSize: Double = 16
    @AppStorage("previewZoom") private var storedZoom: Double = 1.0
    @AppStorage("pdfPageSize") private var storedPDFPageSize: String = PDFPageSize.a4.rawValue

    weak var webView: WKWebView?
    weak var schemeHandler: LocalSchemeHandler?

    private(set) var isRendererReady = false
    private var pendingMarkdown: String?
    private var pendingBaseURL: URL?
    private var cancellables = Set<AnyCancellable>()

    private var pendingDocumentPath: String?

    func setDocumentPath(_ path: String) {
        guard isRendererReady else { pendingDocumentPath = path; return }
        webView?.evaluateJavaScript("MDViewer.setDocumentPath('\(escapeForJS(path))')", completionHandler: nil)
    }

    func collapseAllSections() {
        webView?.evaluateJavaScript("MDViewer.collapseAll()", completionHandler: nil)
    }

    func expandAllSections() {
        webView?.evaluateJavaScript("MDViewer.expandAll()", completionHandler: nil)
    }
    
    init() {
        if let saved = MarkdownTheme.all.first(where: { $0.id == storedThemeId }) {
            theme = saved
        }
        fontSize = storedFontSize
        zoom = storedZoom

        NotificationCenter.default
            .publisher(for: .pdfPageSizeChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyPDFPageSize() }
            .store(in: &cancellables)
    }

    func setTheme(_ newTheme: MarkdownTheme) {
        theme = newTheme
        storedThemeId = newTheme.id
        webView?.evaluateJavaScript("MDViewer.setTheme('\(newTheme.cssFileName)')", completionHandler: nil)
    }

    func setFontSize(_ size: Double) {
        let clamped = min(max(size, 10), 32)
        fontSize = clamped
        storedFontSize = clamped
        webView?.evaluateJavaScript("MDViewer.setFontSize(\(Int(clamped)))", completionHandler: nil)
    }

    func increaseFontSize() {
        setFontSize(fontSize + 2)
    }

    func decreaseFontSize() {
        setFontSize(fontSize - 2)
    }

    func resetFontSize() {
        setFontSize(16)
    }

    // MARK: - Page zoom (Safari-style ⌘+/⌘-/⌘0)

    func setZoom(_ value: Double) {
        let clamped = min(max(value, 0.5), 3.0)
        // Round to the nearest 10% so values stay clean (e.g. 1.1, 1.2).
        zoom = (clamped * 10).rounded() / 10
        storedZoom = zoom
        webView?.pageZoom = zoom
    }

    func zoomIn() {
        setZoom(zoom + 0.1)
    }

    func zoomOut() {
        setZoom(zoom - 0.1)
    }

    func resetZoom() {
        setZoom(1.0)
    }

    func setBaseURL(_ directoryURL: URL) {
        // The Markdown file's directory is served to the WebView through the
        // custom mdviewer-local:// scheme handler, which enforces path security.
        schemeHandler?.baseDirectory = directoryURL.standardizedFileURL
        guard isRendererReady else { pendingBaseURL = directoryURL; return }
        applyBaseURL()
    }

    private func applyBaseURL() {
        // Relative resource URLs in the rendered HTML resolve against this base,
        // so `image.png` becomes `mdviewer-local://localhost/image.png`.
        webView?.evaluateJavaScript("MDViewer.setBaseURL('mdviewer-local://localhost/')", completionHandler: nil)
    }

    func renderMarkdown(_ markdown: String) {
        guard isRendererReady else { pendingMarkdown = markdown; return }
        let escaped = escapeForJS(markdown)
        webView?.evaluateJavaScript("MDViewer.setContent('\(escaped)')", completionHandler: nil)
    }

    func rendererDidLoad() {
        isRendererReady = true
        applyCurrentThemeAndFontSize()
        applyPDFPageSize()
        webView?.pageZoom = zoom
        if let path = pendingDocumentPath {
            pendingDocumentPath = nil
            webView?.evaluateJavaScript("MDViewer.setDocumentPath('\(escapeForJS(path))')", completionHandler: nil)
        }
        if pendingBaseURL != nil {
            pendingBaseURL = nil
            applyBaseURL()
        }
        if let md = pendingMarkdown {
            pendingMarkdown = nil
            let escaped = escapeForJS(md)
            webView?.evaluateJavaScript("MDViewer.setContent('\(escaped)')", completionHandler: nil)
        }
    }

    func scrollToAnchor(_ anchor: String) {
        let escaped = anchor.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("MDViewer.scrollToAnchor('\(escaped)')", completionHandler: nil)
    }

    var pdfPageSize: PDFPageSize {
        PDFPageSize(rawValue: storedPDFPageSize) ?? .a4
    }

    func setPDFPageSize(_ size: PDFPageSize) {
        storedPDFPageSize = size.rawValue
        applyPDFPageSize(size)
    }

    func applyPDFPageSize(_ size: PDFPageSize? = nil) {
        let s = size ?? pdfPageSize
        let css = "@page { size: \(s.cssSize); margin: 15mm; }"
        let js = """
        (function() {
            var el = document.getElementById('mdviewer-page-style');
            if (!el) { el = document.createElement('style'); el.id = 'mdviewer-page-style'; document.head.appendChild(el); }
            el.textContent = '\(css)';
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func applyCurrentThemeAndFontSize() {
        webView?.evaluateJavaScript("MDViewer.setTheme('\(theme.cssFileName)')", completionHandler: nil)
        webView?.evaluateJavaScript("MDViewer.setFontSize(\(Int(fontSize)))", completionHandler: nil)
    }

    func applySystemAppearance(isDark: Bool) {
        if storedThemeId == MarkdownTheme.githubLight.id, isDark {
            setTheme(.githubDark)
        } else if storedThemeId == MarkdownTheme.githubDark.id, !isDark {
            setTheme(.githubLight)
        }
    }

    private func escapeForJS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "</", with: "<\\/")
    }
}
