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
            case "add-gradient":         try cmdAddGradient(rest)
            case "add-blur":             try cmdAddBlur(rest)
            case "add-line":             try cmdAddLine(rest)
            case "add-polygon":          try cmdAddPolygon(rest)
            case "add-star":             try cmdAddStar(rest)
            case "set-shadow":           try cmdSetShadow(rest)
            case "set-corner-radius":    try cmdSetCornerRadius(rest)
            case "set-corner-style":     try cmdSetCornerStyle(rest)
            case "set-corners":          try cmdSetCorners(rest)
            case "set-layer-bg",
                 "set-layer-background": try cmdSetLayerBackground(rest)
            case "set-gradient":         try cmdSetLayerGradient(rest)
            case "group":                try cmdGroup(rest)
            case "ungroup":              try cmdUngroup(rest)
            case "set-group-clip",
                 "crop-to-bounds":       try cmdSetGroupClip(rest)
            case "move-layer":           try cmdMoveLayer(rest)
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
        var assetPath: String?
        if let a = args.string("asset") {
            guard let asset = doc.assets[a] else { throw EditorError.assetNotFound(a) }
            assetId = a
            assetPath = asset.path
        } else if let path = args.string("asset-path") {
            assetId = autoAssetId(in: doc, path: path)
            _ = try CommandEngine.apply(.addAsset(id: assetId, path: path), to: &doc)
            assetPath = path
        } else {
            throw EditorError.usage("--asset <id> or --asset-path <file>")
        }
        let canvas = canvasForFrame(args, doc: doc)
        // Default frame size = the image's natural pixel dimensions (capped so it doesn't
        // exceed the canvas). Falls back to the historic 60%×30% rectangle only when the
        // asset can't be loaded.
        let defaultSize = naturalImageDefaultSize(assetPath: assetPath, projectURL: url, canvas: canvas)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: defaultSize)
        // Default contentMode = .stretch so that any subsequent resize of the frame follows
        // the image exactly. Users who want aspect-locked fit/fill can opt in via --content-mode.
        let mode = Parse.contentMode(args: args, default: .stretch)
        let r = try CommandEngine.apply(
            .addImage(pageId: args.string("page"), id: args.string("id"), assetId: assetId, frame: frame, contentMode: mode, z: try args.double("z")),
            to: &doc)
        try applyCornerRadiusFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try applyShadowFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    /// Read the asset's pixel dimensions, downscale uniformly so neither side exceeds the
    /// canvas. Returns the canvas-relative fallback if the asset can't be loaded.
    private static func naturalImageDefaultSize(assetPath: String?, projectURL: URL, canvas: Canvas) -> (Double, Double) {
        let fallback = (Double(canvas.width) * 0.6, Double(canvas.height) * 0.3)
        guard let path = assetPath else { return fallback }
        let url: URL
        if (path as NSString).isAbsolutePath {
            url = URL(fileURLWithPath: path)
        } else {
            url = projectURL.deletingLastPathComponent().appendingPathComponent(path)
        }
        guard let cg = CGImageCache.shared.image(at: url) else { return fallback }
        let imgW = Double(cg.width), imgH = Double(cg.height)
        guard imgW > 0, imgH > 0 else { return fallback }
        let maxW = Double(canvas.width), maxH = Double(canvas.height)
        let s = min(maxW / imgW, maxH / imgH, 1.0)
        return (imgW * s, imgH * s)
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
            kerning: (try args.double("kerning")) ?? 0)
        let canvas = canvasForFrame(args, doc: doc)
        let estW = Double(canvas.width) * 0.84
        let estH = max(size * 1.4, 80)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (estW, estH))
        let r = try CommandEngine.apply(
            .addText(pageId: args.string("page"), id: args.string("id"), payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try applyCornerRadiusFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try applyShadowFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    /// If `--shadow "color,dx,dy,blur"` was provided and we have a new layer id, apply it.
    private static func applyShadowFlag(args: Args, doc: inout Document, layerId: String?) throws {
        guard let id = layerId, let shadow = Parse.shadow(args: args) else { return }
        _ = try CommandEngine.apply(.setShadow(pageId: args.string("page"), id: id, shadow: shadow), to: &doc)
    }

    /// If `--corner-radius N` (or any of the supplied legacy aliases like `--radius`) was
    /// provided and we have a new layer id, apply it as the layer-level corner radius.
    private static func applyCornerRadiusFlag(args: Args, doc: inout Document, layerId: String?,
                                              aliases: [String] = []) throws {
        guard let id = layerId else { return }
        var value: Double? = try args.double("corner-radius")
        if value == nil {
            for k in aliases {
                if let v = try args.double(k) { value = v; break }
            }
        }
        guard let radius = value, radius > 0 else { return }
        _ = try CommandEngine.apply(.setCornerRadius(pageId: args.string("page"), id: id, value: radius), to: &doc)
    }

    private static func cmdAddRect(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let fill = Parse.color(args: args, key: "fill", default: .white)
        let stroke = try Parse.stroke(args: args)
        let canvas = canvasForFrame(args, doc: doc)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (200, 200))
        let payload = ShapeLayerPayload(fill: fill, stroke: stroke)
        let r = try CommandEngine.apply(
            .addRect(pageId: args.string("page"), id: args.string("id"), payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try applyCornerRadiusFlag(args: args, doc: &doc, layerId: r.newLayerId, aliases: ["radius"])
        try applyShadowFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdAddEllipse(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let fill = Parse.color(args: args, key: "fill", default: .white)
        let stroke = try Parse.stroke(args: args)
        let canvas = canvasForFrame(args, doc: doc)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (200, 200))
        let payload = ShapeLayerPayload(fill: fill, stroke: stroke)
        let r = try CommandEngine.apply(
            .addEllipse(pageId: args.string("page"), id: args.string("id"), payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try applyShadowFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdAddGradient(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let payload = try Parse.gradientPayload(args: args)
        let canvas = canvasForFrame(args, doc: doc)
        let defaultSize = (Double(canvas.width), Double(canvas.height))
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: defaultSize)
        let r = try CommandEngine.apply(
            .addGradient(pageId: args.string("page"), id: args.string("id"),
                         payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try applyCornerRadiusFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try applyShadowFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdAddBlur(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let radius = (try args.double("radius")) ?? 24
        let tint = try Parse.optionalColor(args: args, key: "tint")
        // Optional dynamic blur keypoints — `--stops "radius@pos,radius@pos,…"`. When provided,
        // the layer becomes a gradient blur driven by these stops.
        let stops = try Parse.blurStops(args: args)
        let typeStr = args.string("type")?.lowercased()
        let gradientType: GradientType
        if let t = typeStr {
            guard let g = GradientType(rawValue: t) else {
                throw EditorError.usage("--type expects linear or radial")
            }
            gradientType = g
        } else {
            gradientType = .linear
        }
        let (sx, sy) = try Parse.normalizedPoint(args: args, key: "start") ?? (0, 0)
        let (ex, ey) = try Parse.normalizedPoint(args: args, key: "end")   ?? (0, 1)
        let payload = BlurLayerPayload(radius: radius, tint: tint,
                                       stops: stops, gradientType: gradientType,
                                       startX: sx, startY: sy, endX: ex, endY: ey)
        let canvas = canvasForFrame(args, doc: doc)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (400, 400))
        let r = try CommandEngine.apply(
            .addBlur(pageId: args.string("page"), id: args.string("id"),
                     payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try applyCornerRadiusFlag(args: args, doc: &doc, layerId: r.newLayerId)
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
        try applyShadowFlag(args: args, doc: &doc, layerId: r.newLayerId)
        // cornerRadius is intentionally not threaded on device bezels — they define their own shape.
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    // MARK: - new shapes

    private static func cmdAddLine(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let color = Parse.color(args: args, key: "color", default: .white)
        let width = (try args.double("width")) ?? 6
        let (sx, sy) = try Parse.normalizedPoint(args: args, key: "start") ?? (0, 0.5)
        let (ex, ey) = try Parse.normalizedPoint(args: args, key: "end") ?? (1, 0.5)
        let arrowsRaw = args.string("arrow")?.lowercased() ?? "none"
        let startArrow = (arrowsRaw == "start" || arrowsRaw == "both")
        let endArrow = (arrowsRaw == "end" || arrowsRaw == "both")
        let arrowSize = (try args.double("arrow-size")) ?? 4
        let payload = LineLayerPayload(color: color, width: width,
                                       startX: sx, startY: sy, endX: ex, endY: ey,
                                       startArrow: startArrow, endArrow: endArrow,
                                       arrowSize: arrowSize)
        let canvas = canvasForFrame(args, doc: doc)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (Double(canvas.width) * 0.6, max(width, 8)))
        let r = try CommandEngine.apply(
            .addLine(pageId: args.string("page"), id: args.string("id"),
                     payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try applyCornerRadiusFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try applyShadowFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdAddPolygon(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let sides = (try args.int("sides")) ?? 6
        let fill = Parse.color(args: args, key: "fill", default: .white)
        let stroke = try Parse.stroke(args: args)
        let payload = PolygonLayerPayload(sides: sides, fill: fill, stroke: stroke)
        let canvas = canvasForFrame(args, doc: doc)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (300, 300))
        let r = try CommandEngine.apply(
            .addPolygon(pageId: args.string("page"), id: args.string("id"),
                        payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try applyCornerRadiusFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try applyShadowFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdAddStar(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let points = (try args.int("points")) ?? 5
        let inner = (try args.double("inner-radius")) ?? 0.4
        let fill = Parse.color(args: args, key: "fill", default: .white)
        let stroke = try Parse.stroke(args: args)
        let payload = StarLayerPayload(points: points, innerRadius: inner, fill: fill, stroke: stroke)
        let canvas = canvasForFrame(args, doc: doc)
        let frame = try Parse.frame(args: args, canvas: canvas, defaultSize: (300, 300))
        let r = try CommandEngine.apply(
            .addStar(pageId: args.string("page"), id: args.string("id"),
                     payload: payload, frame: frame, z: try args.double("z")),
            to: &doc)
        try applyCornerRadiusFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try applyShadowFlag(args: args, doc: &doc, layerId: r.newLayerId)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    private static func cmdSetLayerGradient(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let gradient: GradientLayerPayload?
        if args.has("clear") {
            gradient = nil
        } else {
            gradient = try Parse.gradientPayload(args: args)
        }
        _ = try CommandEngine.apply(.setLayerGradient(pageId: args.string("page"), id: id, gradient: gradient), to: &doc)
        try saveDoc(doc, to: url)
        ok("gradient \(id) → \(gradient == nil ? "(cleared)" : "set")")
    }

    private static func cmdGroup(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let raw = try args.required("ids")
        let ids = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !ids.isEmpty else { throw EditorError.usage("--ids must list at least one layer id") }
        let r = try CommandEngine.apply(
            .addGroup(pageId: args.string("page"), id: args.string("id"),
                      name: args.string("name"), childIds: ids),
            to: &doc)
        try saveDoc(doc, to: url)
        ok(r.newLayerId ?? r.message)
    }

    /// `move-layer --id <layerId> [--into <groupId>] [--before <siblingId>]`
    /// Use `--into` with no value (or omit it) to promote the layer back to the page's top level.
    private static func cmdMoveLayer(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let intoGroupId = args.string("into")
        let beforeLayerId = args.string("before")
        let r = try CommandEngine.apply(
            .moveLayer(pageId: args.string("page"), layerId: id,
                       intoGroupId: intoGroupId, beforeLayerId: beforeLayerId),
            to: &doc)
        try saveDoc(doc, to: url)
        ok(r.message)
    }

    private static func cmdUngroup(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let r = try CommandEngine.apply(.ungroup(pageId: args.string("page"), id: id), to: &doc)
        try saveDoc(doc, to: url)
        ok(r.message)
    }

    /// `set-group-clip --id <groupId> [--value true|false]` — crop the group's children to its
    /// bounds. Value defaults to true. Combine with `set-corner-radius` for a rounded crop.
    private static func cmdSetGroupClip(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let v = (try args.boolValue("value")) ?? true
        _ = try CommandEngine.apply(.setGroupClipsToBounds(pageId: args.string("page"), id: id, value: v), to: &doc)
        try saveDoc(doc, to: url)
        ok("clipToBounds \(id) → \(v)")
    }

    private static func cmdSetCornerRadius(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let value = try (args.double("value") ?? args.double("corner-radius")) ?? 0
        _ = try CommandEngine.apply(.setCornerRadius(pageId: args.string("page"), id: id, value: value), to: &doc)
        try saveDoc(doc, to: url)
        ok("cornerRadius \(id) → \(value)")
    }

    private static func cmdSetCornerStyle(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let raw = try args.required("style").lowercased()
        guard let style = CornerStyle(rawValue: raw) else {
            throw EditorError.usage("--style expects arc | continuous | cut")
        }
        _ = try CommandEngine.apply(.setCornerStyle(pageId: args.string("page"), id: id, style: style), to: &doc)
        try saveDoc(doc, to: url)
        ok("cornerStyle \(id) → \(style.rawValue)")
    }

    /// `set-corners --id <id> --corners <spec>` where spec is `all`, `none`, or a comma/space list
    /// of corners: `topLeft`/`tl`, `topRight`/`tr`, `bottomLeft`/`bl`, `bottomRight`/`br`, or the
    /// edge shortcuts `top`, `bottom`, `left`, `right`.
    private static func cmdSetCorners(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let corners = parseCorners(try args.required("corners"))
        _ = try CommandEngine.apply(.setRoundedCorners(pageId: args.string("page"), id: id, corners: corners), to: &doc)
        try saveDoc(doc, to: url)
        let label = corners == .all ? "all" : (corners.isEmpty ? "none" : corners.names.joined(separator: ","))
        ok("roundedCorners \(id) → \(label)")
    }

    private static func parseCorners(_ raw: String) -> RectCorners {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if lower == "all" { return .all }
        if lower == "none" || lower.isEmpty { return [] }
        var result: RectCorners = []
        for tok in lower.split(whereSeparator: { ",|+ ".contains($0) }) {
            switch tok {
            case "tl", "topleft", "top-left":         result.insert(.topLeft)
            case "tr", "topright", "top-right":       result.insert(.topRight)
            case "bl", "bottomleft", "bottom-left":   result.insert(.bottomLeft)
            case "br", "bottomright", "bottom-right": result.insert(.bottomRight)
            case "top":    result.formUnion([.topLeft, .topRight])
            case "bottom": result.formUnion([.bottomLeft, .bottomRight])
            case "left":   result.formUnion([.topLeft, .bottomLeft])
            case "right":  result.formUnion([.topRight, .bottomRight])
            default: break
            }
        }
        return result
    }

    /// `set-layer-bg --id <id> (--color "#hex" | gradient flags | --clear)`
    /// Gradient flags reuse the same set accepted by `add-gradient` (`--stops`, `--type`,
    /// `--start`, `--end`).
    private static func cmdSetLayerBackground(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let background: LayerBackground?
        if args.has("clear") {
            background = nil
        } else if let hex = args.string("color") {
            background = .color(try Color(hex: hex))
        } else if args.string("stops") != nil || args.string("start") != nil
                  || args.string("end") != nil || args.string("type") != nil {
            background = .gradient(try Parse.gradientPayload(args: args))
        } else {
            throw EditorError.usage("provide --color \"#hex\", gradient flags, or --clear")
        }
        _ = try CommandEngine.apply(.setLayerBackground(pageId: args.string("page"), id: id, background: background), to: &doc)
        try saveDoc(doc, to: url)
        ok("background \(id) → \(background == nil ? "(cleared)" : "set")")
    }

    private static func cmdSetShadow(_ argv: [String]) throws {
        let args = Args(argv)
        var (doc, url) = try loadDoc(args)
        let id = try args.required("id")
        let shadow: Shadow?
        if args.has("clear") {
            shadow = nil
        } else if let s = Parse.shadow(args: args) {
            shadow = s
        } else {
            throw EditorError.usage("--shadow \"color,dx,dy,blur\" or --clear")
        }
        _ = try CommandEngine.apply(.setShadow(pageId: args.string("page"), id: id, shadow: shadow), to: &doc)
        try saveDoc(doc, to: url)
        ok("shadow \(id) → \(shadow == nil ? "(cleared)" : "set")")
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
          add-gradient --project <p> (--frame ...|--at ... [--size ...])
                       [--type linear|radial] [--stops "#000@0,#FFF@1"]
                       [--start "x,y"] [--end "x,y"] (normalized 0..1)
                       [--corner-radius N] [--z N] [--id <id>]
          add-blur     --project <p> (--frame ...|--at ... [--size ...])
                       [--radius N] [--corner-radius N] [--tint "#RRGGBBAA"]
                       [--z N] [--id <id>]
          add-line     --project <p> (--frame ...|--at ... [--size ...])
                       [--color "#RRGGBB"] [--width N]
                       [--start "x,y"] [--end "x,y"] (normalized 0..1)
                       [--arrow none|start|end|both] [--arrow-size N]
                       [--z N] [--id <id>]
          add-polygon  --project <p> --sides N (--frame ...|--at ... [--size ...])
                       [--fill "#RRGGBB"] [--stroke "color,width"]
                       [--z N] [--id <id>]
          add-star     --project <p> [--points N] [--inner-radius 0..1]
                       (--frame ...|--at ... [--size ...])
                       [--fill "#RRGGBB"] [--stroke "color,width"]
                       [--z N] [--id <id>]

        SHADOW
          set-shadow   --project <p> --id <layerId>
                       (--shadow "color,dx,dy,blur" | --clear)
          Every add-* command also accepts --shadow to attach a drop shadow on creation.

        CORNERS  (--project <p> --id <layerId>, optional --page)
          set-corner-radius  --value N            rounded-corner radius in px (0 = off)
          set-corner-style   --style arc|continuous|cut
          set-corners        --corners <spec>     which corners round; spec is all | none |
                             a list of topLeft/topRight/bottomLeft/bottomRight (or tl,tr,bl,br)
                             or edges top|bottom|left|right, e.g. --corners "top" or "tl,tr"

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

        GROUPS
          group          --ids "a,b,c" [--id <gid>] [--name "..."]
          ungroup        --id <gid>
          move-layer     --id <layerId> [--into <gid>] [--before <siblingId>]
          set-group-clip --id <gid> [--value true|false]   crop children to the group bounds
                         (alias: crop-to-bounds; combine with set-corner-radius for rounded crop)

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
