import SwiftUI
import WebKit

struct MarkdownRenderView: View {
    @ObservedObject var documentVM: DocumentViewModel
    @ObservedObject var renderVM: RenderViewModel
    @ObservedObject var sidebarVM: SidebarViewModel
    
    @State private var isSearchVisible: Bool = false
    @State private var searchText: String = ""
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .bottomLeading) {
                WebRendererView(renderVM: renderVM, sidebarVM: sidebarVM)
                
                if !renderVM.hoveredURL.isEmpty {
                    Text(renderVM.hoveredURL)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                        .transition(.opacity)
                }
            }
            .onReceive(documentVM.$text) { _ in
                renderCurrentDocument()
            }
            .onChange(of: colorScheme) { _, newScheme in
                renderVM.applySystemAppearance(isDark: newScheme == .dark)
            }
            
            if isSearchVisible {
                SearchBarView(
                    searchText: $searchText,
                    isVisible: $isSearchVisible,
                    webView: renderVM.webView
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if documentVM.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.7))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSearchVisible)
        .onAppear {
            renderVM.applyCurrentThemeAndFontSize()
            renderCurrentDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSearchBar)) { _ in
            withAnimation { isSearchVisible = true }
        }
    }
    
    // MARK: - Rendering
    
    private func renderCurrentDocument() {
        guard !documentVM.text.isEmpty else { return }
        if let fileURL = documentVM.fileURL {
            renderVM.setDocumentPath(fileURL.path)
            renderVM.setBaseURL(fileURL.deletingLastPathComponent())
        }
        renderVM.renderMarkdown(documentVM.text)
        sidebarVM.extractTOC(from: documentVM.text)
    }
}

extension Notification.Name {
    static let showSearchBar = Notification.Name("MDViewer.showSearchBar")
}
