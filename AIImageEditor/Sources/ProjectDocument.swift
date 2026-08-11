import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AIImageEditorCore

final class ProjectDocument: ReferenceFileDocument {
    typealias Snapshot = Document

    static var readableContentTypes: [UTType] { [.aiproj, .json] }

    @Published var document: Document {
        didSet {
            lastChangeAt = Date()
            // Monotonic change counter. The canvas render cache keys on this instead of a deep
            // `Page ==` comparison, so the hot-path cache check is O(1) rather than O(layers).
            revision &+= 1
        }
    }
    /// Increments on every assignment to `document` (commands, drag ticks, undo/redo). Used as
    /// a cheap render-cache key. Not `@Published` on purpose: every reader that needs it already
    /// observes `document`, so it's always read fresh after a change without a second signal.
    private(set) var revision: Int = 0
    /// Set of currently-selected layer ids. Multi-selection-aware: empty = nothing selected,
    /// one = single-layer selected, more = marquee/cmd-click multi-selection.
    @Published var selectedLayerIds: Set<String> = []
    @Published var selectedPageId: String

    /// Compatibility shim: behaves like the old single-selection field. Reads return the only
    /// selected layer (nil if zero or many); writes replace the entire selection.
    var selectedLayerId: String? {
        get {
            guard selectedLayerIds.count == 1 else { return nil }
            return selectedLayerIds.first
        }
        set {
            if let v = newValue { selectedLayerIds = [v] }
            else { selectedLayerIds = [] }
        }
    }

    /// True iff `id` is currently part of the selection.
    func isSelected(_ id: String) -> Bool { selectedLayerIds.contains(id) }

    /// Toggle `id` in/out of the selection. Used by Cmd-click on the canvas.
    func toggleSelection(_ id: String) {
        if selectedLayerIds.contains(id) { selectedLayerIds.remove(id) }
        else { selectedLayerIds.insert(id) }
    }

    // MARK: - Undo / redo

    /// Stack of *prior* document states. We push before every mutation.
    private var undoStack: [Document] = []
    private var redoStack: [Document] = []
    private let maxHistory = 200
    private var lastChangeAt = Date()

    init(document: Document? = nil) {
        let doc = document ?? Self.makeStarterDocument()
        self.document = doc
        self.selectedPageId = doc.activePage.id
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw EditorError.fileIO("empty file")
        }
        let doc = try DocumentCodec.decode(data)
        self.document = doc
        self.selectedPageId = doc.activePage.id
    }

    func snapshot(contentType: UTType) throws -> Document {
        var doc = document
        doc.activePageId = selectedPageId
        return doc
    }

    func fileWrapper(snapshot: Document, configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try DocumentCodec.encode(snapshot)
        return FileWrapper(regularFileWithContents: data)
    }

    // MARK: - Mutate with undo

    /// Apply an EditorCommand, pushing the prior state to the undo stack.
    @discardableResult
    func mutate(_ command: EditorCommand) -> EditorCommandResult? {
        let before = document
        var working = document
        do {
            let r = try CommandEngine.apply(command, to: &working)
            undoStack.append(before)
            if undoStack.count > maxHistory { undoStack.removeFirst() }
            redoStack.removeAll()
            objectWillChange.send()
            document = working
            if let pid = r.newPageId { selectedPageId = pid }
            return r
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    /// Push the current state and replace it with a freshly mutated version.
    /// Use when a command isn't expressible as a single EditorCommand (e.g. drag-to-move
    /// builds up small moves you only want to undo once).
    func beginUndoableEdit() {
        undoStack.append(document)
        if undoStack.count > maxHistory { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Apply a sequence of commands as a single undo step.
    @discardableResult
    func batchMutate(_ commands: [EditorCommand]) -> [EditorCommandResult] {
        let before = document
        var working = document
        var results: [EditorCommandResult] = []
        do {
            for cmd in commands {
                let r = try CommandEngine.apply(cmd, to: &working)
                results.append(r)
            }
            undoStack.append(before)
            if undoStack.count > maxHistory { undoStack.removeFirst() }
            redoStack.removeAll()
            objectWillChange.send()
            document = working
            if let pid = results.compactMap(\.newPageId).last { selectedPageId = pid }
        } catch {
            NSAlert(error: error).runModal()
        }
        return results
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let prior = undoStack.popLast() else { return }
        redoStack.append(document)
        objectWillChange.send()
        document = prior
        if document.page(id: selectedPageId) == nil { selectedPageId = document.activePage.id }
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        objectWillChange.send()
        document = next
        if document.page(id: selectedPageId) == nil { selectedPageId = document.activePage.id }
    }

    // MARK: - Selected page accessor

    var selectedPage: Page {
        document.page(id: selectedPageId) ?? document.activePage
    }

    // MARK: - Starter

    static func makeStarterDocument() -> Document {
        // Workspace defaults to white; the preview gets the project's accent dark background.
        let canvas = Canvas(width: 1290, height: 2796, background: .white)
        let previewBg = (try? Color(hex: "#0A0F2A")) ?? .black
        let preview = Preview(id: "page-1-preview-1", name: "Preview 1",
                              frame: Frame(0, 0, 1290, 2796),
                              background: previewBg)
        let page = Page(id: "page-1", name: "Page 1",
                        canvas: canvas,
                        layout: PageLayout(previewWidth: 1290, previewHeight: 2796, spacing: 80),
                        previews: [preview],
                        layers: [])
        return Document(version: 2, assets: [:], pages: [page], activePageId: page.id)
    }
}
