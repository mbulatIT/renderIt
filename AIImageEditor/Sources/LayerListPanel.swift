import SwiftUI
import AIImageEditorCore

struct LayerListPanel: View {
    @ObservedObject var document: ProjectDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Text("· \(document.selectedPage.name)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Bring to Front") { applyToSelected { .bringToFront(pageId: pageId(), id: $0) } }
                    Button("Send to Back")   { applyToSelected { .sendToBack(pageId: pageId(), id: $0) } }
                    Button("Forward")        { applyToSelected { .moveForward(pageId: pageId(), id: $0) } }
                    Button("Backward")       { applyToSelected { .moveBackward(pageId: pageId(), id: $0) } }
                    Divider()
                    Button("Duplicate") {
                        if let id = document.selectedLayerId {
                            let r = document.mutate(.duplicate(pageId: pageId(), id: id, newId: nil))
                            document.selectedLayerId = r?.newLayerId
                        }
                    }
                    Button(role: .destructive) {
                        applyToSelected { .remove(pageId: pageId(), id: $0) }
                        document.selectedLayerId = nil
                    } label: { Text("Delete") }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            .padding(8)
            Divider()
            List(selection: $document.selectedLayerId) {
                ForEach(document.selectedPage.renderOrder.reversed(), id: \.id) { layer in
                    LayerListRow(
                        layer: layer,
                        onToggleVisible: { id, vis in
                            document.mutate(.setVisible(pageId: pageId(), id: id, value: vis))
                        })
                    .tag(layer.id)
                }
                .onMove(perform: move)
            }
            .listStyle(.inset)
        }
    }

    private func pageId() -> String { document.selectedPageId }

    private func applyToSelected(_ build: (String) -> EditorCommand) {
        guard let id = document.selectedLayerId else { return }
        document.mutate(build(id))
    }

    private func move(from src: IndexSet, to dst: Int) {
        var reversed = document.selectedPage.renderOrder.reversed().map { $0 }
        reversed.move(fromOffsets: src, toOffset: dst)
        // Re-stamp zIndex top-to-bottom via a single undo-grouped edit.
        document.beginUndoableEdit()
        var working = document.document
        if let idx = working.pageIndex(id: pageId()) {
            for (i, layer) in reversed.enumerated() {
                if let lIdx = working.pages[idx].layers.firstIndex(where: { $0.id == layer.id }) {
                    working.pages[idx].layers[lIdx].zIndex = Double(reversed.count - i)
                }
            }
        }
        document.objectWillChange.send()
        document.document = working
    }
}

struct LayerListRow: View {
    let layer: Layer
    let onToggleVisible: (String, Bool) -> Void

    var body: some View {
        HStack {
            Image(systemName: iconName).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(layer.name).lineLimit(1)
                Text(layer.kind.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { onToggleVisible(layer.id, !layer.visible) } label: {
                Image(systemName: layer.visible ? "eye" : "eye.slash")
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch layer.kind {
        case .image:       return "photo"
        case .text:        return "textformat"
        case .rect:        return "rectangle"
        case .ellipse:     return "circle"
        case .deviceBezel: return "iphone"
        case .group:       return "folder"
        }
    }
}
