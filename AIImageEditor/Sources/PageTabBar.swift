import SwiftUI
import AIImageEditorCore

struct PageTabBar: View {
    @ObservedObject var document: ProjectDocument

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(document.document.pages, id: \.id) { page in
                    PageTab(
                        page: page,
                        isSelected: page.id == document.selectedPageId,
                        onSelect: { document.selectedPageId = page.id; document.selectedLayerId = nil },
                        onRename: { newName in
                            document.mutate(.renamePage(id: page.id, name: newName))
                        },
                        onDuplicate: {
                            // Duplicate: add a new page with the same canvas, then copy layers.
                            duplicate(page: page)
                        },
                        onDelete: {
                            document.mutate(.removePage(id: page.id))
                        })
                }
                Button {
                    addPage()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("New page (⌘N)")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func addPage() {
        document.mutate(.addPage(id: nil, name: nil, canvas: nil))
    }

    private func duplicate(page: Page) {
        // Add a new page inheriting the same canvas, then re-insert each layer.
        guard let result = document.mutate(.addPage(id: nil, name: page.name + " copy", canvas: page.canvas)),
              let newId = result.newPageId else { return }
        for layer in page.layers {
            document.mutate(.insertLayer(pageId: newId, layer: layer))
        }
    }
}

private struct PageTab: View {
    let page: Page
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editName = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
            if isEditing {
                TextField("name", text: $editName, onCommit: {
                    if !editName.isEmpty { onRename(editName) }
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .frame(minWidth: 80)
            } else {
                Text(page.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.gray.opacity(0.12))
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onTapGesture(count: 2) { editName = page.name; isEditing = true }
        .contextMenu {
            Button("Rename") { editName = page.name; isEditing = true }
            Button("Duplicate") { onDuplicate() }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Text("Delete") }
        }
    }
}
