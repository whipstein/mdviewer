import SwiftUI
import WebKit

extension Notification.Name {
    static let openLocalDocument = Notification.Name("MDViewer.openLocalDocument")
}

final class MDWebView: WKWebView {
    weak var renderVM: RenderViewModel?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        menu.addItem(.separator())

        let expandItem = NSMenuItem(title: "Expand This Section", action: #selector(expandThisSection), keyEquivalent: "")
        expandItem.target = self
        menu.addItem(expandItem)

        let collapseItem = NSMenuItem(title: "Collapse This Section", action: #selector(collapseThisSection), keyEquivalent: "")
        collapseItem.target = self
        menu.addItem(collapseItem)

        let expandItems = NSMenuItem(title: "Expand All Sections", action: #selector(handleExpandAll), keyEquivalent: "")
        expandItems.target = self
        menu.addItem(expandItems)

        let collapseItems = NSMenuItem(title: "Collapse All Sections", action: #selector(handleCollapseAll), keyEquivalent: "")
        collapseItems.target = self
        menu.addItem(collapseItems)
    }

    @objc private func expandThisSection() {
        evaluateJavaScript("MDViewer.expandSection(MDViewer._lastContextAnchor)", completionHandler: nil)
    }

    @objc private func collapseThisSection() {
        evaluateJavaScript("MDViewer.collapseSection(MDViewer._lastContextAnchor)", completionHandler: nil)
    }

    @objc private func handleExpandAll() {
        renderVM?.expandAllSections()
    }

    @objc private func handleCollapseAll() {
        renderVM?.collapseAllSections()
    }
}

struct WebRendererView: NSViewRepresentable {
    @ObservedObject var renderVM: RenderViewModel
    @ObservedObject var sidebarVM: SidebarViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(renderVM: renderVM, sidebarVM: sidebarVM)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Register JS message handlers
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "headingsExtracted")
        contentController.add(context.coordinator, name: "renderComplete")
        contentController.add(context.coordinator, name: "scrollPositionChanged")
        contentController.add(context.coordinator, name: "linkHovered")
        contentController.add(context.coordinator, name: "linkClicked")
        config.userContentController = contentController

        // Register custom scheme for local images
        config.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: "mdviewer-local")

        // Allow local file access
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = MDWebView(frame: .zero, configuration: config)
        webView.renderVM = renderVM
        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        context.coordinator.webView = webView
        renderVM.webView = webView
        renderVM.schemeHandler = context.coordinator.schemeHandler

        loadRenderer(webView: webView)

        return webView
    }

    func updateNSView(_: WKWebView, context _: Context) {
        // Content updates are driven by RenderViewModel, not SwiftUI updates
    }

    private func loadRenderer(webView: WKWebView) {
        guard let rendererURL = HTMLBuilder.rendererURL(),
              let resourcesDir = HTMLBuilder.webResourcesDirectory()
        else { return }

        webView.loadFileURL(rendererURL, allowingReadAccessTo: resourcesDir)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let renderVM: RenderViewModel
        let sidebarVM: SidebarViewModel
        let schemeHandler = LocalSchemeHandler()
        weak var webView: WKWebView?

        init(renderVM: RenderViewModel, sidebarVM: SidebarViewModel) {
            self.renderVM = renderVM
            self.sidebarVM = sidebarVM
        }

        /// Called when the renderer HTML finishes loading — push initial content
        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "headingsExtracted":
                handleHeadingsExtracted(message.body)
            case "renderComplete":
                handleRenderComplete()
            case "scrollPositionChanged":
                break
            case "linkHovered":
                let url = message.body as? String ?? ""
                Task { @MainActor in self.renderVM.hoveredURL = url }
            case "linkClicked":
                guard let urlString = message.body as? String,
                      let url = URL(string: urlString) else { break }
                Task { @MainActor in
                    if url.scheme == "file",
                       ["md", "markdown"].contains(url.pathExtension.lowercased())
                    {
                        NotificationCenter.default.post(name: .openLocalDocument, object: url)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                }
            default:
                break
            }
        }

        private func handleHeadingsExtracted(_ body: Any) {
            guard let array = body as? [[String: Any]] else { return }
            var items: [TOCItem] = []
            for dict in array {
                guard
                    let level = dict["level"] as? Int,
                    let title = dict["title"] as? String,
                    let anchor = dict["anchor"] as? String
                else { continue }
                items.append(TOCItem(level: level, title: title, anchor: anchor))
            }
            Task { @MainActor in
                self.sidebarVM.setTOCFromFlat(items)
            }
        }

        private func handleRenderComplete() {}

        // MARK: - WKUIDelegate

        // MARK: - WKNavigationDelegate

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            Task { @MainActor in
                self.renderVM.rendererDidLoad()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            // Fragment-only navigation stays in-page
            if url.fragment != nil,
               url.scheme == webView.url?.scheme,
               url.host == webView.url?.host
            {
                decisionHandler(.allow)
                return
            }

            // Local Markdown file → open in MDViewer
            if url.scheme == "file",
               ["md", "markdown"].contains(url.pathExtension.lowercased())
            {
                NotificationCenter.default.post(name: .openLocalDocument, object: url)
                decisionHandler(.cancel)
                return
            }

            // http / https / mailto → open in default app
            if let scheme = url.scheme,
               ["http", "https", "mailto"].contains(scheme)
            {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
