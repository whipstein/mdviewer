import SwiftUI

struct TableOfContentsView: View {
    @ObservedObject var sidebarVM: SidebarViewModel
    let onSelect: (String) -> Void

    @State private var collapsed: Set<UUID> = []

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
        }
    }
}

private struct TOCRow: View {
    let item: TOCItem
    @Binding var collapsed: Set<UUID>
    let onSelect: (String) -> Void

    private var isCollapsed: Bool { collapsed.contains(item.id) }
    private var hasChildren: Bool { !item.children.isEmpty }

    private func setSubtree(_ node: TOCItem, collapsed value: Bool) {
        var newSet = collapsed
        func apply(_ n: TOCItem) {
            if !n.children.isEmpty {
                if value { newSet.insert(n.id) } else { newSet.remove(n.id) }
            }
            for child in n.children { apply(child) }
        }
        apply(node)          // ← start at the clicked node itself, not its children
        collapsed = newSet
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Spacer().frame(width: CGFloat((item.level - 1) * 12))

            // Disclosure chevron (only if this heading has sub-headings)
            if hasChildren {
                Button {
                    if isCollapsed { collapsed.remove(item.id) }
                    else { collapsed.insert(item.id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 12)
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
