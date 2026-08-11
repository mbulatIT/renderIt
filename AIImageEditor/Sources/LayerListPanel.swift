import SwiftUI
import UniformTypeIdentifiers
import AIImageEditorCore

/// One row in the flattened layer-tree view: a layer plus its nesting depth.
private struct LayerRowItem: Identifiable {
    let layer: Layer
    let depth: Int
    var id: String { layer.id }
}

struct LayerListPanel: View {
    @ObservedObject var document: ProjectDocument
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Text("· \(document.selectedPage.name)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    actionsMenu(forContextRow: nil)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            .padding(8)
            Divider()
            List(selection: $document.selectedLayerIds) {
                ForEach(flattenedRows) { row in
                    LayerListRow(
                        layer: row.layer,
                        depth: row.depth,
                        isExpanded: expandedGroups.contains(row.layer.id),
                        onToggleExpand: { toggleExpand(row.layer.id) },
                        onToggleVisible: { id, vis in
                            document.mutate(.setVisible(pageId: pageId, id: id, value: vis))
                        })
                    .tag(row.layer.id)
                    .contentShape(Rectangle())
                    .contextMenu { actionsMenu(forContextRow: row.layer.id) }
                    .draggable(row.layer.id) {
                        // Drag preview shown while the cursor moves with the held item.
                        Label(row.layer.name, systemImage: iconName(for: row.layer))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.25))
                            .cornerRadius(6)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let dragged = items.first, !dragged.isEmpty else { return false }
                        handleDrop(draggedId: dragged, target: row.layer)
                        return true
                    }
                }
                // Sentinel "root" drop zone — drop here to pop a layer out of its group and
                // back to the page's top level even when no top-level row is available.
                RootDropZone()
                    .dropDestination(for: String.self) { items, _ in
                        guard let dragged = items.first, !dragged.isEmpty else { return false }
                        document.mutate(.moveLayer(pageId: pageId, layerId: dragged,
                                                   intoGroupId: nil, beforeLayerId: nil))
                        return true
                    }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Tree flattening

    /// Build the flat list of rows in display order (top→bottom). Groups whose id is in
    /// `expandedGroups` reveal their children indented one level deeper.
    private var flattenedRows: [LayerRowItem] {
        var rows: [LayerRowItem] = []
        // renderOrder is sorted by zIndex ascending; the list shows top z first.
        appendRows(document.selectedPage.renderOrder.reversed(), depth: 0, into: &rows)
        return rows
    }

    private func appendRows(_ layers: [Layer], depth: Int, into rows: inout [LayerRowItem]) {
        for layer in layers {
            rows.append(LayerRowItem(layer: layer, depth: depth))
            if case .group(let g) = layer.payload, expandedGroups.contains(layer.id) {
                // Children draw in array order at the group's z; reverse so top-of-stack first.
                appendRows(g.children.reversed(), depth: depth + 1, into: &rows)
            }
        }
    }

    // MARK: - Actions

    private var pageId: String { document.selectedPageId }

    /// Builds the action menu items targeting the right-clicked row OR the current selection.
    /// macOS convention: if the right-click target IS part of the selection (or the menu is
    /// triggered from the header without a row context), the actions apply to every selected
    /// layer. If it's a row outside the current selection, only that row is acted on.
    @ViewBuilder
    private func actionsMenu(forContextRow rowId: String?) -> some View {
        let targetIds = effectiveTargets(rowId: rowId)
        let count = targetIds.count
        let countLabel = count > 1 ? " (\(count))" : ""
        Group {
            Button("Bring to Front" + countLabel) {
                for id in targetIds { document.mutate(.bringToFront(pageId: pageId, id: id)) }
            }
            Button("Send to Back" + countLabel) {
                for id in targetIds { document.mutate(.sendToBack(pageId: pageId, id: id)) }
            }
            Button("Forward" + countLabel) {
                for id in targetIds { document.mutate(.moveForward(pageId: pageId, id: id)) }
            }
            Button("Backward" + countLabel) {
                for id in targetIds { document.mutate(.moveBackward(pageId: pageId, id: id)) }
            }
            Divider()
            Button(count > 1 ? "Group \(count) layers" : "Wrap in Group") {
                let r = document.mutate(.addGroup(pageId: pageId, id: nil, name: nil,
                                                  childIds: Array(targetIds)))
                if let newId = r?.newLayerId { document.selectedLayerIds = [newId] }
            }
            .disabled(targetIds.isEmpty)
            // "Ungroup" only when every target is itself a group.
            if !targetIds.isEmpty, targetIds.allSatisfy({ isGroup($0) }) {
                Button("Ungroup" + countLabel) {
                    for id in targetIds { document.mutate(.ungroup(pageId: pageId, id: id)) }
                    document.selectedLayerIds = []
                }
            }
            // "Move to top level" — show if any target is nested.
            if targetIds.contains(where: { !isTopLevel($0) }) {
                Button("Move to top level" + countLabel) {
                    for id in targetIds {
                        document.mutate(.moveLayer(pageId: pageId, layerId: id,
                                                   intoGroupId: nil, beforeLayerId: nil))
                    }
                }
            }
            Divider()
            Button("Duplicate" + countLabel) {
                var newIds: Set<String> = []
                for id in targetIds {
                    if let r = document.mutate(.duplicate(pageId: pageId, id: id, newId: nil)),
                       let nid = r.newLayerId {
                        newIds.insert(nid)
                    }
                }
                if !newIds.isEmpty { document.selectedLayerIds = newIds }
            }
            Button(role: .destructive) {
                for id in targetIds { document.mutate(.remove(pageId: pageId, id: id)) }
                document.selectedLayerIds.subtract(targetIds)
            } label: { Text("Delete" + countLabel) }
        }
        .disabled(targetIds.isEmpty)
    }

    /// Resolve "what does this menu actually operate on?" — see the comment on actionsMenu.
    private func effectiveTargets(rowId: String?) -> Set<String> {
        let sel = document.selectedLayerIds
        if let row = rowId {
            return sel.contains(row) ? sel : [row]
        }
        return sel
    }

    private func isGroup(_ id: String) -> Bool {
        if case .group = findLayerInTree(id, in: document.selectedPage.layers)?.payload { return true }
        return false
    }

    private func findLayerInTree(_ id: String, in layers: [Layer]) -> Layer? {
        for l in layers {
            if l.id == id { return l }
            if case .group(let g) = l.payload, let f = findLayerInTree(id, in: g.children) { return f }
        }
        return nil
    }

    private func isTopLevel(_ id: String) -> Bool {
        document.selectedPage.layers.contains(where: { $0.id == id })
    }

    private func toggleExpand(_ id: String) {
        if expandedGroups.contains(id) { expandedGroups.remove(id) }
        else { expandedGroups.insert(id) }
    }

    /// Drop handler invoked by the per-row delegate. If the drop target is a group, the dragged
    /// layer is moved INTO that group (appended). Otherwise it's moved to BEFORE this row at
    /// the row's parent context.
    private func handleDrop(draggedId: String, target: Layer) {
        guard draggedId != target.id else { return }
        let intoGroupId: String?
        let beforeLayerId: String?
        if case .group = target.payload {
            // Dropped onto a group → nest as child (appended, so it appears at the bottom of
            // the group in display order, which is the top of the children array reversed).
            intoGroupId = target.id
            beforeLayerId = nil
            // Auto-expand to reveal the new child.
            expandedGroups.insert(target.id)
        } else {
            // Dropped onto a non-group → insert before this row, in its parent context.
            let parent = findParent(of: target.id)
            intoGroupId = parent
            beforeLayerId = target.id
        }
        document.mutate(.moveLayer(pageId: pageId, layerId: draggedId,
                                   intoGroupId: intoGroupId, beforeLayerId: beforeLayerId))
    }

    /// Returns the id of the group that owns `layerId`, or nil if the layer lives at the page's
    /// top level. Searches recursively.
    private func findParent(of layerId: String) -> String? {
        func search(_ layers: [Layer]) -> String?? {
            // Outer Optional: result; inner Optional: the parent group id (nil = top-level).
            for layer in layers {
                if layer.id == layerId { return .some(nil) }
                if case .group(let g) = layer.payload {
                    if g.children.contains(where: { $0.id == layerId }) {
                        return .some(layer.id)
                    }
                    if let nested = search(g.children) { return nested }
                }
            }
            return nil
        }
        return search(document.selectedPage.layers).flatMap { $0 }
    }
}

// MARK: - Row view

struct LayerListRow: View {
    let layer: Layer
    let depth: Int
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleVisible: (String, Bool) -> Void

    private var isGroup: Bool {
        if case .group = layer.payload { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 4) {
            // Indent for nested rows.
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * 14)
            }
            // Disclosure chevron — only on groups.
            if isGroup {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            } else {
                // Reserve the same horizontal slot so layer icons line up across rows.
                Spacer().frame(width: 12)
            }
            Image(systemName: iconName).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(layer.name).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { onToggleVisible(layer.id, !layer.visible) } label: {
                Image(systemName: layer.visible ? "eye" : "eye.slash")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if case .group(let g) = layer.payload {
            return "group · \(g.children.count) child\(g.children.count == 1 ? "" : "ren")"
        }
        return layer.kind.rawValue
    }

    private var iconName: String {
        switch layer.kind {
        case .image:       return "photo"
        case .text:        return "textformat"
        case .rect:        return "rectangle"
        case .ellipse:     return "circle"
        case .deviceBezel: return "iphone"
        case .group:       return "folder"
        case .gradient:    return "square.righthalf.filled"
        case .blur:        return "drop.halffull"
        case .line:        return "line.diagonal"
        case .polygon:     return "hexagon"
        case .star:        return "star"
        }
    }
}

// MARK: - Root drop zone

/// Trailing row in the list that accepts drops to move a layer out of any group and back to
/// the page's top level. Mirrors the Finder behaviour of dragging a file out of a folder window.
private struct RootDropZone: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray")
                .foregroundStyle(.secondary)
            Text("Drop here to move to top level")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
        .listRowSeparator(.hidden)
    }
}

// MARK: - Free-function helpers

/// SF Symbol used for each layer kind. Free-floating so both the row view and the drag preview
/// can use it without going through the LayerListRow instance.
private func iconName(for layer: Layer) -> String {
    switch layer.kind {
    case .image:       return "photo"
    case .text:        return "textformat"
    case .rect:        return "rectangle"
    case .ellipse:     return "circle"
    case .deviceBezel: return "iphone"
    case .group:       return "folder"
    case .gradient:    return "square.righthalf.filled"
    case .blur:        return "drop.halffull"
    case .line:        return "line.diagonal"
    case .polygon:     return "hexagon"
    case .star:        return "star"
    }
}
