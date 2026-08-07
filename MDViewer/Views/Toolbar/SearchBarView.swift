import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var isVisible: Bool
    @ObservedObject var renderVM: RenderViewModel

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { renderVM.searchNext() }

            // Match count indicator: "3/12", or "0/0" when nothing matches.
            if !searchText.isEmpty {
                Text("\(renderVM.searchCurrentIndex)/\(renderVM.searchMatchCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(renderVM.searchMatchCount == 0 ? .red : .secondary)
            }

            Button {
                renderVM.searchPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(renderVM.searchMatchCount == 0)
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .help("Previous Match (⇧⌘G)")

            Button {
                renderVM.searchNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(renderVM.searchMatchCount == 0)
            .keyboardShortcut("g", modifiers: .command)
            .help("Next Match (⌘G)")

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
        .onChange(of: searchText) { _, newValue in
            renderVM.search(newValue)
        }
        .onAppear {
            // Defer focus a runloop tick so the field is in the responder chain;
            // setting it synchronously in onAppear can be dropped.
            DispatchQueue.main.async { isFocused = true }
            if !searchText.isEmpty { renderVM.search(searchText) }
        }
        .onDisappear {
            renderVM.clearSearch()
        }
    }
}
