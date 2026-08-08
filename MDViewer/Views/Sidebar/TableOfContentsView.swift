import SwiftUI

struct TableOfContentsView: View {
    @ObservedObject var sidebarVM: SidebarViewModel
    let onSelect: (String) -> Void

    // Collapse state is keyed by the heading anchor (a stable slug) rather than the
    // item's UUID, which is regenerated on every parse. This lets the expand/collapse
    // state survive reloads and live edits.
    @State private var collapsed: Set<String> = []
    @State private var didInitialCollapse = false

    var body: some View {
        if sidebarVM.tocItems.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet.indent")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No headings found")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(sidebarVM.tocItems) { item in
                    TOCRow(item: item, collapsed: $collapsed, onSelect: onSelect)
                }
            }
            .listStyle(.sidebar)
            .onAppear { collapseAllOnFirstLoad() }
            .onChange(of: sidebarVM.tocItems) { _, _ in collapseAllOnFirstLoad() }
        }
    }

    /// Collapse every section, but only the first time a document's TOC appears.
    /// Reloads and edits re-parse the document, yet the collapse state is preserved
    /// because it is keyed by the (stable) anchor.
    private func collapseAllOnFirstLoad() {
        guard !didInitialCollapse, !sidebarVM.tocItems.isEmpty else { return }
        var anchors: Set<String> = []
        func walk(_ node: TOCItem) {
            if !node.children.isEmpty { anchors.insert(node.anchor) }
            node.children.forEach(walk)
        }
        sidebarVM.tocItems.forEach(walk)
        collapsed = anchors
        didInitialCollapse = true
    }
}

private struct TOCRow: View {
    let item: TOCItem
    @Binding var collapsed: Set<String>
    let onSelect: (String) -> Void

    private var isCollapsed: Bool { collapsed.contains(item.anchor) }
    private var hasChildren: Bool { !item.children.isEmpty }

    private func setSubtree(_ node: TOCItem, collapsed value: Bool) {
        var newSet = collapsed
        func apply(_ n: TOCItem) {
            if !n.children.isEmpty {
                if value { newSet.insert(n.anchor) } else { newSet.remove(n.anchor) }
            }
            for child in n.children { apply(child) }
        }
        apply(node)          // ← start at the clicked node itself, not its children
        collapsed = newSet
    }

    var body: some View {
        HStack(spacing: 4) {
            Spacer().frame(width: CGFloat((item.level - 1) * 12))

            // Disclosure chevron (only if this heading has sub-headings).
            // The glyph stays small but the tappable area is a full 22×22 region
            // (contentShape makes the transparent padding hittable too).
            if hasChildren {
                Button {
                    if isCollapsed { collapsed.remove(item.anchor) }
                    else { collapsed.insert(item.anchor) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 22)
            }

            Button {
                onSelect(item.anchor)
            } label: {
                Text(item.title)
                    .font(fontForLevel(item.level))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            // In TOCRow, attach to the HStack (the row content):
            .contextMenu {
                if hasChildren {
                    Button("Expand All in Section") {
                        setSubtree(item, collapsed: false)
                    }
                    Button("Collapse All in Section") {
                        setSubtree(item, collapsed: true)
                    }
                }
            }
        }
        .padding(.vertical, 2)

        if hasChildren, !isCollapsed {
            ForEach(item.children) { child in
                TOCRow(item: child, collapsed: $collapsed, onSelect: onSelect)
            }
        }
    }

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 1: .headline
        case 2: .subheadline
        default: .caption
        }
    }
}
