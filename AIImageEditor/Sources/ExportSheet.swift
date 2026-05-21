import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AIImageEditorCore

struct ExportSheet: View {
    let document: Document
    let pageId: String
    let baseDirectory: URL?
    @Binding var isPresented: Bool

    @State private var scale: Int = 1
    @State private var status: String = ""
    @State private var scope: Scope = .currentPage

    private enum Scope: String, CaseIterable, Identifiable {
        case currentPage = "Current page"
        case allPages = "All pages"
        var id: String { rawValue }
    }

    private var page: Page { document.page(id: pageId) ?? document.activePage }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export previews").font(.title2)
            Text("One PNG per preview on the selected page(s).")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Scope")
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            HStack {
                Text("Scale")
                Picker("", selection: $scale) {
                    Text("1×").tag(1)
                    Text("2×").tag(2)
                    Text("3×").tag(3)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }

            Text(summaryText).font(.caption).foregroundStyle(.secondary)

            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.primary)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Export to folder…") { exportPNGs() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var summaryText: String {
        let pages = scope == .allPages ? document.pages : [page]
        let previews = pages.flatMap(\.previews)
        return "Will write \(previews.count) PNG\(previews.count == 1 ? "" : "s")."
    }

    private func exportPNGs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Export to folder"
        guard panel.runModal() == .OK, let dir = panel.url else { return }

        let pages = scope == .allPages ? document.pages : [page]
        let renderer = Renderer(baseDirectory: baseDirectory)
        var wrote = 0
        var bytes = 0

        do {
            for page in pages {
                for preview in page.previews {
                    let data = try renderer.renderPreviewPNG(document,
                                                             pageId: page.id,
                                                             previewId: preview.id,
                                                             scale: scale)
                    let safe = sanitize(preview.name)
                    let filename = pages.count > 1
                        ? "\(sanitize(page.name))-\(safe).png"
                        : "\(safe).png"
                    let url = dir.appendingPathComponent(filename)
                    try data.write(to: url, options: .atomic)
                    wrote += 1
                    bytes += data.count
                }
            }
            status = "Wrote \(wrote) PNG\(wrote == 1 ? "" : "s") (\(bytes / 1024) KB total) to \(dir.lastPathComponent)"
            isPresented = false
        } catch {
            status = "error: \(error.localizedDescription)"
        }
    }

    private func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_."))
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}
