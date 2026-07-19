import Markdown
import SwiftUI

enum SidebarMode: String, CaseIterable {
    case toc
}

@MainActor
final class SidebarViewModel: ObservableObject {
    @Published var mode: SidebarMode = .toc
    @Published var tocItems: [TOCItem] = []
    @AppStorage("sidebarMode") private var storedMode: String = SidebarMode.toc.rawValue

    init() {
        if let saved = SidebarMode(rawValue: storedMode) {
            mode = saved
        }
    }

    func setMode(_ newMode: SidebarMode) {
        mode = newMode
        storedMode = newMode.rawValue
    }

    /// Parse headings from raw Markdown using swift-markdown
    func extractTOC(from markdown: String) {
        let document = Document(parsing: markdown)
        var flat: [TOCItem] = []
        collectHeadings(markup: document, into: &flat)
        tocItems = buildHierarchy(from: flat)
        for item in tocItems {
            print("ROOT: \(item.title) — children: \(item.children.count)")
        }
    }

    /// Nest a flat list of headings (e.g. from the JS renderer) into a tree,
    /// preserving each item's existing anchor/id.
    func setTOCFromFlat(_ flat: [TOCItem]) {
        tocItems = buildHierarchy(from: flat)
    }
    
    private func collectHeadings(markup: some Markup, into items: inout [TOCItem]) {
        for child in markup.children {
            if let heading = child as? Heading {
                let title = heading.plainText
                let anchor = slugify(title)
                items.append(TOCItem(level: heading.level, title: title, anchor: anchor))
            } else {
                collectHeadings(markup: child, into: &items)
            }
        }
    }

    /// Build a tree from a flat heading list (H1 > H2 > H3...)
    private func buildHierarchy(from flat: [TOCItem]) -> [TOCItem] {
        var roots: [TOCItem] = []
        // index path into the tree pointing at the current parent chain
        var stack: [(level: Int, id: UUID)] = []

        func appendChild(_ child: TOCItem, to nodes: inout [TOCItem], path: ArraySlice<UUID>) {
            if let firstID = path.first {
                if let idx = nodes.firstIndex(where: { $0.id == firstID }) {
                    appendChild(child, to: &nodes[idx].children, path: path.dropFirst())
                }
            } else {
                nodes.append(child)
            }
        }

        for item in flat {
            while let last = stack.last, last.level >= item.level {
                stack.removeLast()
            }
            let parentPath = stack.map(\.id)[...]
            appendChild(item, to: &roots, path: parentPath)
            stack.append((level: item.level, id: item.id))
        }

        return roots
    }

    private func slugify(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-")).inverted)
            .joined(separator: "-")
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// Provide plainText on Heading
private extension Heading {
    var plainText: String {
        children.compactMap { ($0 as? Markdown.Text)?.string }.joined()
    }
}
