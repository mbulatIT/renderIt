import Foundation
import AIImageEditorCore

enum CLI {
    static func run(argv: [String]) -> Int32 {
        guard let cmd = argv.first else { printUsage(); return 64 }
        let rest = Array(argv.dropFirst())
        do {
            switch cmd {
            case "new":       try cmdNew(rest)
            case "presets":   cmdPresets()
            case "bezels":    cmdBezels()
            case "fonts":     cmdFonts()
            case "inspect":   try cmdInspect(rest)
            case "list":      try cmdList(rest)
            case "render":    try cmdRender(rest)
            case "bg", "set-background": try cmdBackground(rest)
            case "set-canvas":           try cmdSetCanvas(rest)
            case "set-layout":           try cmdSetLayout(rest)
            case "add-image":            try cmdAddImage(rest)
            case "add-text":             try cmdAddText(rest)
            case "add-rect":             try cmdAddRect(rest)
            case "add-ellipse":          try cmdAddEllipse(rest)
            case "add-bezel":            try cmdAddBezel(rest)
            case "move":                 try cmdMove(rest)
            case "resize":               try cmdResize(rest)
            case "set-frame":            try cmdSetFrame(rest)
            case "rotate":               try cmdRotate(rest)
            case "opacity":              try cmdOpacity(rest)
            case "visible":              try cmdVisible(rest)
            case "blend":                try cmdBlend(rest)
            case "rename":               try cmdRename(rest)
            case "duplicate":            try cmdDuplicate(rest)
            case "remove":               try cmdRemove(rest)
            case "set-text":             try cmdSetText(rest)
            case "set-font":             try cmdSetFont(rest)
            case "set-color":            try cmdSetColor(rest)
            case "set-alignment":        try cmdSetAlignment(rest)
            case "set-bezel-color":      try cmdSetBezelColor(rest)
            case "set-bezel-screenshot": try cmdSetBezelScreenshot(rest)
            case "previews":             try cmdPreviews(rest)
            case "z", "set-z":           try cmdSetZ(rest)
            case "front", "bring-to-front": try cmdFront(rest)
            case "back", "send-to-back":    try cmdBack(rest)
            case "forward", "move-forward": try cmdForward(rest)
            case "backward", "move-backward": try cmdBackward(rest)
            case "assets":               try cmdAssets(rest)
            case "pages":                try cmdPages(rest)
            case "-h", "--help", "help": printUsage()
            default:
                FileHandle.standardError.write(Data("unknown command: \(cmd)\n".utf8))
                printUsage()
                return 64
            }
            return 0
        } catch let e as CLIError {
            FileHandle.standardError.write(Data("error: \(e.localizedDescription ?? "usage")\n".utf8))
            return 64
        } catch let e as EditorError {
            FileHandle.standardError.write(Data("error: \(e.errorDescription ?? "engine")\n".utf8))
            return 65
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            return 74
        }
    }

    // MARK: - Helpers

    private static func loadDoc(_ args: Args) throws -> (Document, URL) {
        let p = try args.required("project")
        let url = URL(fileURLWithPath: p)
        return (try DocumentCodec.load(from: url), url)
    }

    private static func saveDoc(_ doc: Document, to url: URL) throws {
        try DocumentCodec.save(doc, to: url)
    }

    private static func ok(_ s: String) { print(s) }

    /// Resolve `--page` against the document. Returns the active page id if omitted.
    private static func pageId(_ args: Args, doc: Document) -> String {
        args.string("page") ?? doc.activePage.id
    }

    private static func canvasForFrame(_ args: Args, doc: Document) -> Canvas {
        if let pid = args.string("page"), let page = doc.page(id: pid) { return page.canvas }
        return doc.activePage.canvas
    }

    // MARK: - Listings

    private static func cmdPresets() {
        for p in PresetCatalog.all {
            print("\(p.id.padding(toLength: 20, withPad: " ", startingAt: 0)) \(p.width)x\(p.height)  \(p.title)")
        }
    }
    private static func cmdBezels() {
        for b in DeviceBezelCatalog.all {
            let colorSuffix = b.colors.isEmpty ? "" : "  colors=[\(b.colors.joined(separator: ", "))]"
            print("\(b.id.padding(toLength: 22, withPad: " ", startingAt: 0)) \(b.family.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0))  \(b.title)\(colorSuffix)")
        }
    }
    private static func cmdFonts() {
        for f in FontCatalog.availableFamilies() { print(f) }
    }

    // MARK: - new / inspect / list

    private static func cmdNew(_ argv: [String]) throws {
        let args = Args(argv)
        let outPath = try args.required("output")
        var canvas: Canvas
        if let p = args.string("preset") {
            guard let preset = PresetCatalog.find(id: p) else { throw EditorError.unknownPreset(p) }
            canvas = Canvas(width: preset.width, height: preset.height)
        } else if let w = try args.int("width"), let h = try args.int("height") {
            canvas = Canvas(width: w, height: h)
        } else {
            throw EditorError.usage("provide --preset OR --width and --height")
        }
        if let bg = args.string("background") {
            canvas.background = try Color(hex: bg)
        }
        let doc = Document(canvas: canvas)
        try saveDoc(doc, to: URL(fileURLWithPath: outPath))
        ok("created \(outPath) (\(canvas.width)x\(canvas.height))")
    }

    private static func cmdInspect(_ argv: [String]) throws {
        let args = Args(argv)
        let (doc, _) = try loadDoc(args)
        let data = try DocumentCodec.encode(doc)
        if let s = String(data: data, encoding: .utf8) { print(s) }
    }

    private static func cmdList(_ argv: [String]) throws {
        let args = Args(argv)
        let (doc, _) = try loadDoc(args)
        print("document version=\(doc.version)  pages=\(doc.pages.count)  active=\(doc.activePage.id)")
        for page in doc.pages {
            let marker = page.id == doc.activePage.id ? "*" : " "
            print("\(marker) page \(page.id)  '\(page.name)'  \(page.canvas.width)x\(page.canvas.height) bg=\(page.canvas.background.hex)  previews=\(page.previews.count) spacing=\(Int(page.layout.spacing)) preview=\(Int(page.layout.previewWidth))x\(Int(page.layout.previewHeight))")
            for l in page.renderOrder {
                let f = l.frame
                print("    z=\(l.zIndex)  \(l.kind.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0))  \(l.id.padding(toLength: 24, withPad: " ", startingAt: 0))  frame=[\(f.x),\(f.y),\(f.w),\(f.h)]\(l.visible ? "" : "  (hidden)")")
            }
        }
    }

    private static func cmdRender(_ argv: [String]) throws {
        let args = Args(argv)
        let (doc, projectURL) = try loadDoc(args)
        let outPath = try args.required("output")
        let scale = (try args.int("scale")) ?? 1
        let pid = args.string("page")
        let previewId = args.string("preview")
        let r = Renderer(baseDirectory: projectURL.deletingLastPathComponent())
        if let previewId = previewId {
            let data = try r.renderPreviewPNG(doc, pageId: pid, previewId: previewId, scale: scale)
            try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
            let page = pid.flatMap { doc.page(id: $0) } ?? doc.activePage
            guard let p = page.preview(id: previewId) else {
                throw EditorError.layerNotFound("preview:\(previewId)")
            }
            ok("rendered preview \(previewId) → \(outPath) (\(Int(p.frame.w) * scale)x\(Int(p.frame.h) * scale), \(data.count / 1024) KB)")
            return
        }
        let mode: Renderer.Mode = args.string("mode") == "editor" ? .editor : .export
        let data = try r.renderPNG(doc, scale: scale, pageId: pid, mode: mode)
        try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
        let page = pid.flatMap { doc.page(id: $0) } ?? doc.activePage
        ok("rendered work-area \(outPath) (\(page.canvas.width * scale)x\(page.canvas.height * scale), \(data.count / 1024) KB, mode=\(mode == .editor ? "editor" : "export"))")
    }

    private static func cmdPreviews(_ argv: [String]) throws {
        guard let sub = argv.first else {
            throw EditorError.usage("previews requires: list | add | remove | rename | set-background | export")
        }
        let rest = Array(argv.dropFirst())
        let args = Args(rest)
        switch sub {
        case "list":
            let (doc, _) = try loadDoc(args)
            let pid = pageId(args, doc: doc)
            guard let page = doc.page(id: pid) else { throw EditorError.layerNotFound("page:\(pid)") }
            for p in page.previews {
                print("\(p.id.padding(toLength: 24, withPad: " ", startingAt: 0))  '\(p.name)'  frame=[\(Int(p.frame.x)),\(Int(p.frame.y)),\(Int(p.frame.w)),\(Int(p.frame.h))]  bg=\(p.background.hex)")
            }
        case "add":
            var (doc, url) = try loadDoc(args)
            let bg = try Parse.optionalColor(args: args, key: "background")
            _ = try CommandEngine.apply(.addPreview(pageId: args.string("page"),
                                                    id: args.string("id"),
                                                    name: args.string("name"),
                                                    background: bg), to: &doc)
            try saveDoc(doc, to: url)
            ok("added preview")
        case "remove":
            var (doc, url) = try loadDoc(args)
            let id = try args.required("id")
            _ = try CommandEngine.apply(.removePreview(pageId: args.string("page"), id: id), to: &doc)
            try saveDoc(doc, to: url)
            ok("removed preview \(id)")
        case "rename":
            var (doc, url) = try loadDoc(args)
            let id = try args.required("id")
            let name = try args.required("name")
            _ = try CommandEngine.apply(.renamePreview(pageId: args.string("page"), id: id, name: name), to: &doc)
            try saveDoc(doc, to: url)
            ok("renamed preview \(id) → \(name)")
        case "set-background":
            var (doc, url) = try loadDoc(args)
            let id = try args.required("id")
            let color = try Color(hex: try args.required("color"))
            _ = try CommandEngine.apply(.setPreviewBackground(pageId: args.string("page"), id: id, color: color), to: &doc)
            try saveDoc(doc, to: url)
            ok("preview bg \(id) → \(color.hex)")
        case "export":
            // Export every preview on the (selected) page to a directory.
            let (doc, projectURL) = try loadDoc(args)
            let dirPath = try args.required("output")
            let pid = pageId(args, doc: doc)
            guard let page = doc.page(id: pid) else { throw EditorError.layerNotFound("page:\(pid)") }
            let scale = (try args.int("scale")) ?? 1
            let outDir = URL(fileURLWithPath: dirPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let r = Renderer(baseDirectory: projectURL.deletingLastPathComponent())
            for preview in page.previews {
                let data = try r.renderPreviewPNG(doc, pageId: pid, previewId: preview.id, scale: scale)
                let outURL = outDir.appendingPathComponent("\(preview.name).png")
                try data.write(to: outURL, options: .atomic)
                ok("wrote \(outURL.lastPathComponent) (\(data.count / 1024) KB)")
            }
        default:
            throw EditorError.usage("unknown previews subcommand '\(sub)'")
        }
    }

    // MARK: - canvas / bg / layout

    private static func cmdBackground(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let color = try Color(hex: try args.required("color"))
        _ = try CommandEngine.apply(.setBackground(pageId: args.string("page"), color: color), to: &doc)
        try saveDoc(doc, to: url)
        ok("background \(color.hex)")
    }

    private static func cmdSetCanvas(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let w = try (args.int("width") ?? -1)
        let h = try (args.int("height") ?? -1)
        guard w > 0, h > 0 else { throw EditorError.usage("--width and --height required") }
        _ = try CommandEngine.apply(.setCanvas(pageId: args.string("page"), width: w, height: h), to: &doc)
        try saveDoc(doc, to: url)
        ok("canvas \(w)x\(h)")
    }

    private static func cmdSetLayout(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let pid = pageId(args, doc: doc)
        guard let page = doc.page(id: pid) else { throw EditorError.layerNotFound("page:\(pid)") }
        let w = (try args.double("preview-width"))  ?? page.layout.previewWidth
        let h = (try args.double("preview-height")) ?? page.layout.previewHeight
        if w != page.layout.previewWidth || h != page.layout.previewHeight {
            _ = try CommandEngine.apply(.setPreviewSize(pageId: pid, width: w, height: h), to: &doc)
        }
        if let sp = try args.double("spacing") {
            _ = try CommandEngine.apply(.setPreviewSpacing(pageId: pid, spacing: sp), to: &doc)
        }
        if let count = try args.int("count") {
            _ = try CommandEngine.apply(.setPreviewCount(pageId: pid, count: count), to: &doc)
        }
        try saveDoc(doc, to: url)
        let p = doc.page(id: pid)!
        ok("set layout on \(pid) (previews=\(p.previews.count), spacing=\(p.layout.spacing), preview=\(Int(p.layout.previewWidth))x\(Int(p.layout.previewHeight)))")
    }

    // MARK: - pages

    private static func cmdPages(_ argv: [String]) throws {
        guard let sub = argv.first else { throw EditorError.usage("pages requires: list | add | remove | rename | select") }
        let rest = Array(argv.dropFirst())
        let args = Args(rest)
        switch sub {
        case "list":
            let (doc, _) = try loadDoc(args)
            for p in doc.pages {
                let marker = p.id == doc.activePage.id ? "*" : " "
                print("\(marker) \(p.id.padding(toLength: 20, withPad: " ", startingAt: 0)) '\(p.name)'  \(p.canvas.width)x\(p.canvas.height)")
            }
        case "add":
            var (doc, url) = try loadDoc(args)
            var canvas: Canvas? = nil
            if let p = args.string("preset"), let pp = PresetCatalog.find(id: p) {
                canvas = Canvas(width: pp.width, height: pp.height)
            } else if let w = try args.int("width"), let h = try args.int("height") {
                canvas = Canvas(width: w, height: h)
            }
            let r = try CommandEngine.apply(.addPage(id: args.string("id"), name: args.string("name"), canvas: canvas), to: &doc)
            try saveDoc(doc, to: url)
            ok(r.newPageId ?? r.message)
        case "remove":
            var (doc, url) = try loadDoc(args)
            let id = try args.required("id")
            _ = try CommandEngine.apply(.removePage(id: id), to: &doc)
            try saveDoc(doc, to: url)
            ok("removed page \(id)")
        case "rename":
            var (doc, url) = try loadDoc(args)
            let id = try args.required("id")
            let name = try args.required("name")
            _ = try CommandEngine.apply(.renamePage(id: id, name: name), to: &doc)
            try saveDoc(doc, to: url)
            ok("renamed page \(id) → \(name)")
        case "select":
            var (doc, url) = try loadDoc(args)
            let id = try args.required("id")
            _ = try CommandEngine.apply(.selectPage(id: id), to: &doc)
            try saveDoc(doc, to: url)
            ok("selected page \(id)")
        default:
            throw EditorError.usage("unknown pages subcommand '\(sub)'")
        }
    }

    // MARK: - assets

    private static func cmdAssets(_ argv: [String]) throws {
        guard let sub = argv.first else { throw EditorError.usage("assets requires: add | list | remove") }
        let rest = Array(argv.dropFirst())
        let args = Args(rest)
        switch sub {
        case "add":
            var (doc, url) = try loadDoc(args)
            let path = try args.required("path")
            let id = args.string("id") ?? autoAssetId(in: doc, path: path)
            _ = try CommandEngine.apply(.addAsset(id: id, path: path), to: &doc)
            try saveDoc(doc, to: url)
            ok("added asset \(id)  \(path)")
        case "remove":
            var (doc, url) = try loadDoc(args)
            let id = try args.required("id")
            _ = try CommandEngine.apply(.removeAsset(id: id), to: &doc)
            try saveDoc(doc, to: url)
            ok("removed asset \(id)")
        case "list":
            let (doc, _) = try loadDoc(args)
            for (id, asset) in doc.assets.sorted(by: { $0.key < $1.key }) {
                print("\(id.padding(toLength: 20, withPad: " ", startingAt: 0))  \(asset.path)")
            }
        default:
            throw EditorError.usage("unknown assets subcommand '\(sub)'")
        }
    }

    private static func autoAssetId(in doc: Document, path: String) -> String {
        let stem = (path as NSString).lastPathComponent.replacingOccurrences(of: " ", with: "_")
        var base = (stem as NSString).deletingPathExtension
        if base.isEmpty { base = "asset" }
        if doc.assets[base] == nil { return base }
        var i = 2
        while doc.assets["\(base)-\(i)"] != nil { i += 1 }
        return "\(base)-\(i)"
    }

    // MARK: - add-*

    private static func cmdAddImage(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        var assetId: String
        if let a = args.string("asset") {
            guard doc.assets[a] != nil else { throw EditorError.assetNotFound(a) }
            assetId = a
        } else if let path = args.string("asset-path") {
            assetId = autoAssetId(in: doc, path: path)
            _ = try CommandEngine.apply(.addAsset(id: assetId, path: path), to: &doc)
        } else {
            throw EditorError.usage("--asset <id> or --asset-path <file>")
        }
        let canvas = canvasForFrame(args, doc: doc)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (Double(canvas.width) * 0.6, Double(canvas.height) * 0.3))
        let mode = Parse.contentMode(args: args)
        let r = try CommandEngine.apply(
            .addImage(pageId: args.string("page"), id: args.string("id"), assetId: assetId, frame: frame, contentMode: mode, z: try args.double("z")),
            to: &doc)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdAddText(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let text = try args.required("text")
        let size = (try args.double("font-size")) ?? 72
        let payload = TextLayerPayload(
            text: text,
            font: args.string("font", default: "SF Pro Display"),
            fontSize: size,
            fontWeight: Parse.weight(args: args),
            italic: args.bool("italic"),
            color: Parse.color(args: args, key: "color", default: .white),
            alignment: Parse.alignment(args: args),
            lineSpacing: (try args.double("line-spacing")) ?? 0,
            kerning: (try args.double("kerning")) ?? 0,
            shadow: Parse.shadow(args: args))
        let canvas = canvasForFrame(args, doc: doc)
        let estW = Double(canvas.width) * 0.84
        let estH = max(size * 1.4, 80)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (estW, estH))
        let r = try CommandEngine.apply(
            .addText(pageId: args.string("page"), id: args.string("id"), payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdAddRect(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let fill = Parse.color(args: args, key: "fill", default: .white)
        var stroke: Stroke? = nil
        if let s = args.string("stroke") {
            let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let c = try? Color(hex: parts[0]), let w = Double(parts[1]) else {
                throw EditorError.usage("--stroke expects 'color,width'")
            }
            stroke = Stroke(color: c, width: w)
        }
        let radius = (try args.double("radius")) ?? 0
        let canvas = canvasForFrame(args, doc: doc)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (200, 200))
        let payload = ShapeLayerPayload(fill: fill, stroke: stroke, cornerRadius: radius)
        let r = try CommandEngine.apply(
            .addRect(pageId: args.string("page"), id: args.string("id"), payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdAddEllipse(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let fill = Parse.color(args: args, key: "fill", default: .white)
        var stroke: Stroke? = nil
        if let s = args.string("stroke") {
            let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let c = try? Color(hex: parts[0]), let w = Double(parts[1]) else {
                throw EditorError.usage("--stroke expects 'color,width'")
            }
            stroke = Stroke(color: c, width: w)
        }
        let canvas = canvasForFrame(args, doc: doc)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (200, 200))
        let payload = ShapeLayerPayload(fill: fill, stroke: stroke, cornerRadius: 0)
        let r = try CommandEngine.apply(
            .addEllipse(pageId: args.string("page"), id: args.string("id"), payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdAddBezel(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let device = try args.required("device")
        guard let bezel = DeviceBezelCatalog.find(id: device) else { throw EditorError.unknownBezel(device) }
        var screenshotAssetId: String? = nil
        if let a = args.string("screenshot-asset") {
            guard doc.assets[a] != nil else { throw EditorError.assetNotFound(a) }
            screenshotAssetId = a
        } else if let path = args.string("screenshot-path") {
            let id = autoAssetId(in: doc, path: path)
            _ = try CommandEngine.apply(.addAsset(id: id, path: path), to: &doc)
            screenshotAssetId = id
        }
        let chrome = try Parse.optionalColor(args: args, key: "chrome-color")
        let payload = DeviceBezelPayload(device: device,
                                         screenshotAssetId: screenshotAssetId,
                                         chromeColor: chrome,
                                         color: args.string("color"))
        let canvas = canvasForFrame(args, doc: doc)
        let frame: Frame
        if let s = args.string("frame") {
            frame = try Frame.parse(s)
        } else {
            let h = (try args.double("height")) ?? (Double(canvas.height) * 0.6)
            let w = h * bezel.aspect
            let anchor = AnchorPosition(token: args.string("at") ?? "center") ?? .center
            frame = anchor.frame(layerSize: (w, h), canvas: canvas)
        }
        let r = try CommandEngine.apply(
            .addDeviceBezel(pageId: args.string("page"), id: args.string("id"), payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    // MARK: - edits

    private static func cmdMove(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let pid = pageId(args, doc: doc)
        guard let layer = doc.page(id: pid)?.layer(id: id) else { throw EditorError.layerNotFound(id) }
        let canvas = canvasForFrame(args, doc: doc)
        let to: (Double, Double)
        if let s = args.string("to") {
            let parts = s.split(whereSeparator: { ",x ".contains($0) }).compactMap { Double($0) }
            guard parts.count == 2 else { throw EditorError.usage("--to expects 'x,y'") }
            to = (parts[0], parts[1])
        } else if let token = args.string("at"), let anchor = AnchorPosition(token: token) {
            let f = anchor.frame(layerSize: (layer.frame.w, layer.frame.h), canvas: canvas)
            to = (f.x, f.y)
        } else if let dx = try args.double("dx"), let dy = try args.double("dy") {
            to = (layer.frame.x + dx, layer.frame.y + dy)
        } else {
            throw EditorError.usage("--to / --at / --dx --dy required")
        }
        _ = try CommandEngine.apply(.move(pageId: pid, id: id, to: to), to: &doc)
        try saveDoc(doc, to: url)
        ok("moved \(id) → (\(to.0),\(to.1))")
    }

    private static func cmdResize(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let w = try args.double("width")
        let h = try args.double("height")
        guard w != nil || h != nil else { throw EditorError.usage("--width and/or --height required") }
        _ = try CommandEngine.apply(.resize(pageId: args.string("page"), id: id, w: w, h: h), to: &doc)
        try saveDoc(doc, to: url)
        ok("resized \(id)")
    }

    private static func cmdSetFrame(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let f = try Frame.parse(try args.required("frame"))
        _ = try CommandEngine.apply(.setFrame(pageId: args.string("page"), id: id, frame: f), to: &doc)
        try saveDoc(doc, to: url)
        ok("set frame on \(id)")
    }

    private static func cmdRotate(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let deg = (try args.double("degrees")) ?? 0
        _ = try CommandEngine.apply(.rotate(pageId: args.string("page"), id: id, degrees: deg), to: &doc)
        try saveDoc(doc, to: url)
        ok("rotated \(id) → \(deg)°")
    }

    private static func cmdOpacity(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let v = (try args.double("value")) ?? 1
        _ = try CommandEngine.apply(.setOpacity(pageId: args.string("page"), id: id, value: v), to: &doc)
        try saveDoc(doc, to: url)
        ok("opacity \(id) → \(v)")
    }

    private static func cmdVisible(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let v = (try args.boolValue("value")) ?? true
        _ = try CommandEngine.apply(.setVisible(pageId: args.string("page"), id: id, value: v), to: &doc)
        try saveDoc(doc, to: url)
        ok("visible \(id) → \(v)")
    }

    private static func cmdBlend(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let modeStr = try args.required("mode")
        guard let mode = BlendMode(rawValue: modeStr) else { throw EditorError.usage("unknown blend mode: \(modeStr)") }
        _ = try CommandEngine.apply(.setBlendMode(pageId: args.string("page"), id: id, mode: mode), to: &doc)
        try saveDoc(doc, to: url)
        ok("blend \(id) → \(modeStr)")
    }

    private static func cmdRename(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let name = try args.required("name")
        _ = try CommandEngine.apply(.rename(pageId: args.string("page"), id: id, name: name), to: &doc)
        try saveDoc(doc, to: url)
        ok("renamed \(id) → \(name)")
    }

    private static func cmdDuplicate(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let r = try CommandEngine.apply(.duplicate(pageId: args.string("page"), id: id, newId: args.string("new-id")), to: &doc)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdRemove(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        _ = try CommandEngine.apply(.remove(pageId: args.string("page"), id: id), to: &doc)
        try saveDoc(doc, to: url)
        ok("removed \(id)")
    }

    private static func cmdSetText(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let text = try args.required("text")
        _ = try CommandEngine.apply(.setText(pageId: args.string("page"), id: id, text: text), to: &doc)
        try saveDoc(doc, to: url)
        ok("set text on \(id)")
    }

    private static func cmdSetFont(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let weight: FontWeight? = args.string("font-weight").flatMap { FontWeight(rawValue: $0) }
        let italic = try args.boolValue("italic")
        _ = try CommandEngine.apply(.setFont(pageId: args.string("page"), id: id,
                                             family: args.string("font"),
                                             size: try args.double("font-size"),
                                             weight: weight,
                                             italic: italic), to: &doc)
        try saveDoc(doc, to: url)
        ok("set font on \(id)")
    }

    private static func cmdSetColor(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let color = try Color(hex: try args.required("color"))
        _ = try CommandEngine.apply(.setColor(pageId: args.string("page"), id: id, color: color), to: &doc)
        try saveDoc(doc, to: url)
        ok("set color on \(id) → \(color.hex)")
    }

    private static func cmdSetBezelColor(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let color = args.string("color") // nil → reset to device default
        _ = try CommandEngine.apply(.setBezelColor(pageId: args.string("page"), id: id, color: color), to: &doc)
        try saveDoc(doc, to: url)
        ok("bezel color \(id) → \(color ?? "default")")
    }

    private static func cmdSetBezelScreenshot(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let assetId: String?
        if args.has("clear") {
            assetId = nil
        } else if let a = args.string("asset") {
            guard doc.assets[a] != nil else { throw EditorError.assetNotFound(a) }
            assetId = a
        } else if let path = args.string("asset-path") {
            let newId = autoAssetId(in: doc, path: path)
            _ = try CommandEngine.apply(.addAsset(id: newId, path: path), to: &doc)
            assetId = newId
        } else {
            throw EditorError.usage("--asset <id> | --asset-path <file> | --clear")
        }
        _ = try CommandEngine.apply(.setBezelScreenshot(pageId: args.string("page"), id: id, assetId: assetId), to: &doc)
        try saveDoc(doc, to: url)
        ok("bezel screenshot \(id) → \(assetId ?? "(cleared)")")
    }

    private static func cmdSetAlignment(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let alignStr = try args.required("align")
        guard let align = TextAlignment(rawValue: alignStr) else { throw EditorError.usage("unknown alignment: \(alignStr)") }
        _ = try CommandEngine.apply(.setAlignment(pageId: args.string("page"), id: id, alignment: align), to: &doc)
        try saveDoc(doc, to: url)
        ok("alignment \(id) → \(alignStr)")
    }

    private static func cmdSetZ(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let v = (try args.double("value")) ?? 0
        _ = try CommandEngine.apply(.setZIndex(pageId: args.string("page"), id: id, value: v), to: &doc)
        try saveDoc(doc, to: url)
        ok("zIndex \(id) → \(v)")
    }
    private static func cmdFront(_ argv: [String]) throws {
        let args = Args(argv); var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        _ = try CommandEngine.apply(.bringToFront(pageId: args.string("page"), id: id), to: &doc)
        try saveDoc(doc, to: url); ok("front \(id)")
    }
    private static func cmdBack(_ argv: [String]) throws {
        let args = Args(argv); var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        _ = try CommandEngine.apply(.sendToBack(pageId: args.string("page"), id: id), to: &doc)
        try saveDoc(doc, to: url); ok("back \(id)")
    }
    private static func cmdForward(_ argv: [String]) throws {
        let args = Args(argv); var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        _ = try CommandEngine.apply(.moveForward(pageId: args.string("page"), id: id), to: &doc)
        try saveDoc(doc, to: url); ok("forward \(id)")
    }
    private static func cmdBackward(_ argv: [String]) throws {
        let args = Args(argv); var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        _ = try CommandEngine.apply(.moveBackward(pageId: args.string("page"), id: id), to: &doc)
        try saveDoc(doc, to: url); ok("backward \(id)")
    }

    // MARK: - usage

    static func printUsage() {
        let text = """
        aiimageeditor-cli — App Store image editor for macOS.

        USAGE
          aiimageeditor-cli <command> [--project file.aiproj] [--page <id>] [args]

        DISCOVERY
          presets / bezels / fonts                  list catalogs
          list      --project <p>                   list pages, previews, layers
          inspect   --project <p>                   pretty-print project JSON

        PROJECT / PAGES
          new       --output <p.aiproj> (--preset <id> | --width W --height H)
                    [--background "#RRGGBB"|transparent]            (default: white)
          pages list      --project <p>
          pages add       --project <p> [--id <id>] [--name "..."]
                          [--preset <id> | --width W --height H]
          pages remove    --project <p> --id <id>
          pages rename    --project <p> --id <id> --name "..."
          pages select    --project <p> --id <id>
          bg              --project <p> [--page <id>] --color "#RRGGBB"|transparent
          set-layout      --project <p> [--page <id>]
                          [--count N] [--preview-width W] [--preview-height H]
                          [--spacing N]

        PREVIEWS  (one PNG per preview at export)
          previews list           --project <p>
          previews add            --project <p> [--id <id>] [--name "..."] [--background "#RRGGBB"]
          previews remove         --project <p> --id <id>
          previews rename         --project <p> --id <id> --name "..."
          previews set-background --project <p> --id <id> --color "#RRGGBB"
          previews export         --project <p> --output <dir> [--scale 1|2|3]

        ASSETS  (document-wide, shared across pages)
          assets add    --project <p> --path <file> [--id <id>]
          assets list   --project <p>
          assets remove --project <p> --id <id>

        LAYERS  (every command takes optional --page <id>; default = active page)
          add-image    --project <p> (--asset <id>|--asset-path <file>)
                       (--frame "x,y,w,h"|--at <pos> [--size "w,h"])
                       [--content-mode fit|fill|stretch] [--z N] [--id <id>]
          add-text     --project <p> --text "..."
                       (--frame "x,y,w,h"|--at <pos> [--size "w,h"])
                       [--font <name>] [--font-size N] [--font-weight w] [--italic]
                       [--color "#RRGGBB"] [--align left|center|right|justified]
                       [--line-spacing N] [--kerning N] [--shadow "color,dx,dy,blur"]
                       [--z N] [--id <id>]
          add-rect     --project <p> (--frame ...|--at ... [--size ...])
                       [--fill "#RRGGBB"] [--stroke "color,width"] [--radius N]
                       [--z N] [--id <id>]
          add-ellipse  --project <p> (--frame ...|--at ...)
                       [--fill ...] [--stroke ...] [--z N] [--id <id>]
          add-bezel    --project <p> --device <id> [--color "<Label>"]
                       [--screenshot-asset <id>|--screenshot-path <file>]
                       [--frame ...|--at <pos> --height N]
                       [--chrome-color "#RRGGBB"] [--z N] [--id <id>]

        EDITING LAYERS  (every command takes --project <p> --id <layerId>, optional --page)
          move           --to "x,y" | --at <pos> | --dx N --dy N
          resize         --width N --height N
          set-frame      --frame "x,y,w,h"
          rotate         --degrees N
          opacity        --value 0..1
          visible        --value true|false
          blend          --mode normal|multiply|screen|overlay|softLight|hardLight|darken|lighten
          rename         --name "..."
          duplicate      [--new-id <id>]
          remove
          set-text       --text "..."
          set-font       [--font ...] [--font-size N] [--font-weight w] [--italic true|false]
          set-color      --color "#RRGGBB"
          set-alignment  --align left|center|right|justified
          set-bezel-color      --color "<Label>"
          set-bezel-screenshot (--asset <id> | --asset-path <file> | --clear)

        Z-ORDER
          z|set-z              --id <id> --value N
          front|bring-to-front --id <id>
          back|send-to-back    --id <id>
          forward|move-forward --id <id>
          backward|move-backward --id <id>

        RENDER
          render --project <p> --output <png>
                 [--scale 1|2|3] [--page <id>]
                 [--preview <id>]         per-preview output (clipped to that frame)
                 [--mode editor|export]   default = export

        POSITION TOKENS  (for --at)
          top-left top-center top-right
          center-left center center-right
          bottom-left bottom-center bottom-right

        EXIT CODES
          0 ok   64 usage error   65 data error   74 I/O error

        Full reference: docs/CLI_GUIDE.md and docs/COMMAND_REFERENCE.md
        """
        print(text)
    }
}
