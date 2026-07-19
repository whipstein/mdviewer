import SwiftUI
import WebKit

struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var isVisible: Bool
    weak var webView: WKWebView?

    @FocusState private var isFocused: Bool          // ← 1

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)                 // ← 2
                .onSubmit { performSearch() }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Done") {
                withAnimation { isVisible = false }
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onChange(of: searchText) { _, _ in
            performSearch()
        }
        .onAppear { isFocused = true }               // ← 3
    }

    private func performSearch() {
        guard let webView else { return }
        // Use WKFindConfiguration-based search (available macOS 13+)
        if !searchText.isEmpty {
            let config = WKFindConfiguration()
            config.caseSensitive = false
            config.wraps = true
            webView.find(searchText, configuration: config) { _ in }
        }
    }
}
