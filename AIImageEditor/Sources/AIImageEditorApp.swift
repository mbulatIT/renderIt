import SwiftUI
import UniformTypeIdentifiers
import AIImageEditorCore

extension UTType {
    static let aiproj = UTType(exportedAs: "io.tuist.AIImageEditor.aiproj")
}

@main
struct AIImageEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { ProjectDocument() }) { file in
            EditorView(document: file.document, fileURL: file.fileURL)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .commands {
            // Replace the default Cmd+N with "New Page" (in current project).
            // Move "New Project" to Cmd+Shift+N.
            CommandGroup(replacing: .newItem) {
                Button("New Page") {
                    NotificationCenter.default.post(name: .newPageRequested, object: nil)
                }
                .keyboardShortcut("N", modifiers: [.command])
                Button("New Project…") {
                    NSDocumentController.shared.newDocument(nil)
                }
                .keyboardShortcut("N", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NotificationCenter.default.post(name: .undoRequested, object: nil)
                }
                .keyboardShortcut("Z", modifiers: [.command])
                Button("Redo") {
                    NotificationCenter.default.post(name: .redoRequested, object: nil)
                }
                .keyboardShortcut("Z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { NotificationCenter.default.post(name: .cutRequested, object: nil) }
                    .keyboardShortcut("X", modifiers: [.command])
                Button("Copy") { NotificationCenter.default.post(name: .copyRequested, object: nil) }
                    .keyboardShortcut("C", modifiers: [.command])
                Button("Paste") { NotificationCenter.default.post(name: .pasteRequested, object: nil) }
                    .keyboardShortcut("V", modifiers: [.command])
                Button("Duplicate") { NotificationCenter.default.post(name: .duplicateRequested, object: nil) }
                    .keyboardShortcut("D", modifiers: [.command])
                Button("Delete") { NotificationCenter.default.post(name: .deleteRequested, object: nil) }
                    .keyboardShortcut(.delete, modifiers: [])
            }
            CommandMenu("Page") {
                Button("Next Page") { NotificationCenter.default.post(name: .nextPageRequested, object: nil) }
                    .keyboardShortcut("]", modifiers: [.command])
                Button("Previous Page") { NotificationCenter.default.post(name: .prevPageRequested, object: nil) }
                    .keyboardShortcut("[", modifiers: [.command])
            }
            CommandMenu("View") {
                Button("Zoom In") { NotificationCenter.default.post(name: .zoomInRequested, object: nil) }
                    .keyboardShortcut("=", modifiers: [.command])
                Button("Zoom Out") { NotificationCenter.default.post(name: .zoomOutRequested, object: nil) }
                    .keyboardShortcut("-", modifiers: [.command])
                Button("Actual Size") { NotificationCenter.default.post(name: .zoomActualRequested, object: nil) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Reset Zoom") { NotificationCenter.default.post(name: .zoomResetRequested, object: nil) }
                    .keyboardShortcut("0", modifiers: [.command])
            }
            CommandMenu("Arrange") {
                Button("Bring to Front") { NotificationCenter.default.post(name: .bringToFrontRequested, object: nil) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Bring Forward") { NotificationCenter.default.post(name: .bringForwardRequested, object: nil) }
                    .keyboardShortcut("]", modifiers: [.command, .option])
                Button("Send Backward") { NotificationCenter.default.post(name: .sendBackwardRequested, object: nil) }
                    .keyboardShortcut("[", modifiers: [.command, .option])
                Button("Send to Back") { NotificationCenter.default.post(name: .sendToBackRequested, object: nil) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Export PNG…") {
                    NotificationCenter.default.post(name: .exportRequested, object: nil)
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let exportRequested      = Notification.Name("exportRequested")
    static let undoRequested        = Notification.Name("undoRequested")
    static let redoRequested        = Notification.Name("redoRequested")
    static let copyRequested        = Notification.Name("copyRequested")
    static let cutRequested         = Notification.Name("cutRequested")
    static let pasteRequested       = Notification.Name("pasteRequested")
    static let deleteRequested      = Notification.Name("deleteRequested")
    static let duplicateRequested   = Notification.Name("duplicateRequested")
    static let newPageRequested     = Notification.Name("newPageRequested")
    static let nextPageRequested    = Notification.Name("nextPageRequested")
    static let prevPageRequested    = Notification.Name("prevPageRequested")

    static let zoomInRequested      = Notification.Name("zoomInRequested")
    static let zoomOutRequested     = Notification.Name("zoomOutRequested")
    static let zoomActualRequested  = Notification.Name("zoomActualRequested")
    static let zoomResetRequested   = Notification.Name("zoomResetRequested")

    static let bringToFrontRequested = Notification.Name("bringToFrontRequested")
    static let bringForwardRequested = Notification.Name("bringForwardRequested")
    static let sendBackwardRequested = Notification.Name("sendBackwardRequested")
    static let sendToBackRequested   = Notification.Name("sendToBackRequested")
}
