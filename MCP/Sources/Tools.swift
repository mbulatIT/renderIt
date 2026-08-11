import Foundation
import AIImageEditorCore

/// One MCP tool definition.
struct MCPTool {
    let name: String
    let description: String
    let inputSchema: JSONValue
    /// Invoked with the parsed `arguments` object.
    let run: (JSONValue) throws -> JSONValue
}

enum Tools {
    static func all() -> [MCPTool] {
        return [
            // Discovery
            tool("list_presets",
                 desc: "List built-in canvas presets (App Store sizes etc).",
                 schema: schema(props: [:], required: [])) { _ in
                let arr = PresetCatalog.all.map { p -> JSONValue in
                    .object([
                        "id": .string(p.id),
                        "title": .string(p.title),
                        "width": .integer(p.width),
                        "height": .integer(p.height),
                    ])
                }
                return textResult(JSONValue.array(arr).pretty)
            },

            tool("list_bezels",
                 desc: "List device bezels with their color variants.",
                 schema: schema(props: [:], required: [])) { _ in
                let arr = DeviceBezelCatalog.all.map { b -> JSONValue in
                    let colors: JSONValue = b.colors.isEmpty
                        ? .array([])
                        : .array(b.colors.map { .string($0) })
                    return .object([
                        "id": .string(b.id),
                        "title": .string(b.title),
                        "family": .string(b.family.rawValue),
                        "aspect": .number(b.aspect),
                        "colors": colors,
                    ])
                }
                return textResult(JSONValue.array(arr).pretty)
            },

            tool("list_fonts",
                 desc: "List installed font family names.",
                 schema: schema(props: [:], required: [])) { _ in
                let arr = FontCatalog.availableFamilies().map { JSONValue.string($0) }
                return textResult(JSONValue.array(arr).pretty)
            },

            tool("new",
                 desc: "Create a new .aiproj project. Provide either `preset` OR (`width` AND `height`).",
                 schema: schema(props: [
                    "project": stringSchema("Path of .aiproj to create."),
                    "preset": stringSchema("Optional preset id (see list_presets)."),
                    "width": integerSchema("Canvas width in px."),
                    "height": integerSchema("Canvas height in px."),
                    "background": stringSchema("Canvas background as #RRGGBB / #RRGGBBAA / transparent."),
                 ], required: ["project"])) { args in
                let path = try requireString(args, "project")
                var canvas: Canvas
                if let preset = args.objectValue?["preset"]?.stringValue, let p = PresetCatalog.find(id: preset) {
                    canvas = Canvas(width: p.width, height: p.height)
                } else if let w = args.objectValue?["width"]?.intValue, let h = args.objectValue?["height"]?.intValue {
                    canvas = Canvas(width: w, height: h)
                } else {
                    throw EditorError.usage("provide preset or (width, height)")
                }
                if let bg = args.objectValue?["background"]?.stringValue {
                    canvas.background = try Color(hex: bg)
                }
                let doc = Document(canvas: canvas)
                try DocumentCodec.save(doc, to: URL(fileURLWithPath: path))
                return textResult("created \(path) (\(canvas.width)x\(canvas.height))")
            },

            tool("inspect",
                 desc: "Return the project JSON for an .aiproj file.",
                 schema: schema(props: ["project": stringSchema("Path to project.")],
                                required: ["project"])) { args in
                let path = try requireString(args, "project")
                let doc = try DocumentCodec.load(from: URL(fileURLWithPath: path))
                let data = try DocumentCodec.encode(doc)
                let text = String(data: data, encoding: .utf8) ?? ""
                return textResult(text)
            },

            tool("list_layers",
                 desc: "List layers in z-order for an .aiproj.",
                 schema: schema(props: ["project": stringSchema("Path to project.")],
                                required: ["project"])) { args in
                let path = try requireString(args, "project")
                let doc = try DocumentCodec.load(from: URL(fileURLWithPath: path))
                var lines: [String] = ["canvas \(doc.canvas.width)x\(doc.canvas.height) bg=\(doc.canvas.background.hex)"]
                for l in doc.renderOrder {
                    lines.append(" z=\(l.zIndex)  \(l.kind.rawValue)  \(l.id)  frame=[\(l.frame.x),\(l.frame.y),\(l.frame.w),\(l.frame.h)]\(l.visible ? "" : "  (hidden)")")
                }
                return textResult(lines.joined(separator: "\n"))
            },

            tool("render",
                 desc: "Render the project to PNG, write it to disk, AND return the image inline so the LLM can see it.",
                 schema: schema(props: [
                    "project": stringSchema("Path to project."),
                    "output":  stringSchema("Output PNG path."),
                    "scale":   integerSchema("1, 2, or 3."),
                 ], required: ["project", "output"])) { args in
                let path = try requireString(args, "project")
                let outPath = try requireString(args, "output")
                let scale = args.objectValue?["scale"]?.intValue ?? 1
                let url = URL(fileURLWithPath: path)
                let doc = try DocumentCodec.load(from: url)
                let r = Renderer(baseDirectory: url.deletingLastPathComponent())
                let data = try r.renderPNG(doc, scale: scale)
                try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
                return imageResult(message: "rendered \(outPath) (\(doc.canvas.width * scale)x\(doc.canvas.height * scale))",
                                   data: data)
            },

            tool("set_background",
                 desc: "Set canvas background color (hex).",
                 schema: schema(props: [
                    "project": stringSchema(),
                    "color": stringSchema("#RRGGBB / #RRGGBBAA / transparent"),
                 ], required: ["project", "color"])) { args in
                try mutate(args) { doc in
                    let c = try Color(hex: try requireString(args, "color"))
                    _ = try CommandEngine.apply(.setBackground(pageId: args.objectValue?["page"]?.stringValue, color: c), to: &doc)
                }
            },

            tool("set_canvas",
                 desc: "Resize the canvas.",
                 schema: schema(props: [
                    "project": stringSchema(),
                    "width":  integerSchema(),
                    "height": integerSchema(),
                 ], required: ["project", "width", "height"])) { args in
                try mutate(args) { doc in
                    let w = try requireInt(args, "width")
                    let h = try requireInt(args, "height")
                    _ = try CommandEngine.apply(.setCanvas(pageId: args.objectValue?["page"]?.stringValue, width: w, height: h), to: &doc)
                }
            },

            tool("add_asset",
                 desc: "Register an image asset (PNG/JPEG) at the given path.",
                 schema: schema(props: [
                    "project": stringSchema(),
                    "path": stringSchema("Path to the asset file."),
                    "id":   stringSchema("Optional asset id; auto-generated from filename otherwise."),
                 ], required: ["project", "path"])) { args in
                try mutate(args) { doc in
                    let p = try requireString(args, "path")
                    let id = args.objectValue?["id"]?.stringValue ?? CLIHelpers.autoAssetId(in: doc, path: p)
                    _ = try CommandEngine.apply(.addAsset(id: id, path: p), to: &doc)
                }
            },

            tool("add_text",
                 desc: "Add a text layer.",
                 schema: schema(props: textSchema(), required: ["project", "text"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    let text = try requireString(args, "text")
                    let payload = TextLayerPayload(
                        text: text,
                        font: args.objectValue?["font"]?.stringValue ?? "SF Pro Display",
                        fontSize: args.objectValue?["font_size"]?.doubleValue ?? 72,
                        fontWeight: FontWeight(rawValue: args.objectValue?["font_weight"]?.stringValue ?? "regular") ?? .regular,
                        italic: args.objectValue?["italic"]?.boolValue ?? false,
                        color: try (args.objectValue?["color"]?.stringValue).map { try Color(hex: $0) } ?? .white,
                        alignment: TextAlignment(rawValue: args.objectValue?["align"]?.stringValue ?? "center") ?? .center,
                        lineSpacing: args.objectValue?["line_spacing"]?.doubleValue ?? 0,
                        kerning: args.objectValue?["kerning"]?.doubleValue ?? 0)
                    let frame = try frameFromArgs(args: args, canvas: doc.canvas,
                                                  defaultSize: (Double(doc.canvas.width) * 0.84,
                                                                max(payload.fontSize * 1.4, 80)))
                    let r = try CommandEngine.apply(
                        .addText(pageId: args.objectValue?["page"]?.stringValue, id: args.objectValue?["id"]?.stringValue,
                                 payload: payload, frame: frame,
                                 z: args.objectValue?["z"]?.doubleValue),
                        to: &doc)
                    try applyCornerRadiusArg(args, doc: &doc, layerId: r.newLayerId)
                    try applyShadowArg(args, doc: &doc, layerId: r.newLayerId)
                    return r
                }
            },

            tool("add_image",
                 desc: "Add an image layer (asset must exist OR provide asset_path). By default the layer's frame matches the image's natural pixel size (capped to the canvas), and contentMode defaults to `stretch` so the image follows any later resize.",
                 schema: schema(props: imageSchema(), required: ["project"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    var assetId: String
                    var assetPath: String?
                    if let a = args.objectValue?["asset"]?.stringValue {
                        guard let asset = doc.assets[a] else { throw EditorError.assetNotFound(a) }
                        assetId = a
                        assetPath = asset.path
                    } else if let p = args.objectValue?["asset_path"]?.stringValue {
                        assetId = CLIHelpers.autoAssetId(in: doc, path: p)
                        _ = try CommandEngine.apply(.addAsset(id: assetId, path: p), to: &doc)
                        assetPath = p
                    } else {
                        throw EditorError.usage("asset or asset_path required")
                    }
                    let projectURL = URL(fileURLWithPath: try requireString(args, "project"))
                    let defaultSize = MCPHelpers.naturalImageDefaultSize(assetPath: assetPath,
                                                                        projectURL: projectURL,
                                                                        canvas: doc.canvas)
                    let frame = try frameFromArgs(args: args, canvas: doc.canvas, defaultSize: defaultSize)
                    let mode = ContentMode(rawValue: args.objectValue?["content_mode"]?.stringValue ?? "stretch") ?? .stretch
                    let r = try CommandEngine.apply(
                        .addImage(pageId: args.objectValue?["page"]?.stringValue, id: args.objectValue?["id"]?.stringValue,
                                  assetId: assetId, frame: frame, contentMode: mode,
                                  z: args.objectValue?["z"]?.doubleValue),
                        to: &doc)
                    try applyCornerRadiusArg(args, doc: &doc, layerId: r.newLayerId)
                    try applyShadowArg(args, doc: &doc, layerId: r.newLayerId)
                    return r
                }
            },

            tool("add_rect",
                 desc: "Add a rectangle layer.",
                 schema: schema(props: shapeSchema(includeRadius: true), required: ["project"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    let payload = try shapePayloadFromArgs(args, ellipse: false)
                    let frame = try frameFromArgs(args: args, canvas: doc.canvas, defaultSize: (200, 200))
                    let r = try CommandEngine.apply(
                        .addRect(pageId: args.objectValue?["page"]?.stringValue, id: args.objectValue?["id"]?.stringValue,
                                 payload: payload, frame: frame,
                                 z: args.objectValue?["z"]?.doubleValue),
                        to: &doc)
                    // For add_rect, "radius" is a legacy alias for "corner_radius".
                    try applyCornerRadiusArg(args, doc: &doc, layerId: r.newLayerId, aliases: ["radius"])
                    try applyShadowArg(args, doc: &doc, layerId: r.newLayerId)
                    return r
                }
            },

            tool("add_ellipse",
                 desc: "Add an ellipse layer.",
                 schema: schema(props: shapeSchema(includeRadius: false), required: ["project"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    let payload = try shapePayloadFromArgs(args, ellipse: true)
                    let frame = try frameFromArgs(args: args, canvas: doc.canvas, defaultSize: (200, 200))
                    let r = try CommandEngine.apply(
                        .addEllipse(pageId: args.objectValue?["page"]?.stringValue, id: args.objectValue?["id"]?.stringValue,
                                    payload: payload, frame: frame,
                                    z: args.objectValue?["z"]?.doubleValue),
                        to: &doc)
                    try applyShadowArg(args, doc: &doc, layerId: r.newLayerId)
                    // cornerRadius is intentionally not applied on ellipses — they're already curved.
                    return r
                }
            },

            tool("add_line",
                 desc: "Add a line layer. Start/end points are normalized 0..1 within the layer's frame. Optional arrowheads on either end.",
                 schema: schema(props: lineSchema(), required: ["project"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    let color: Color = try (args.objectValue?["color"]?.stringValue).map { try Color(hex: $0) } ?? .white
                    let width = args.objectValue?["width"]?.doubleValue ?? 6
                    let (sx, sy) = try point(args.objectValue?["start"]?.stringValue) ?? (0, 0.5)
                    let (ex, ey) = try point(args.objectValue?["end"]?.stringValue) ?? (1, 0.5)
                    let arrowKind = args.objectValue?["arrow"]?.stringValue?.lowercased() ?? "none"
                    let startArrow = (arrowKind == "start" || arrowKind == "both")
                    let endArrow = (arrowKind == "end" || arrowKind == "both")
                    let arrowSize = args.objectValue?["arrow_size"]?.doubleValue ?? 4
                    let payload = LineLayerPayload(color: color, width: width,
                                                   startX: sx, startY: sy, endX: ex, endY: ey,
                                                   startArrow: startArrow, endArrow: endArrow,
                                                   arrowSize: arrowSize)
                    let frame = try frameFromArgs(args: args, canvas: doc.canvas,
                                                  defaultSize: (Double(doc.canvas.width) * 0.6, max(width, 8)))
                    let r = try CommandEngine.apply(
                        .addLine(pageId: args.objectValue?["page"]?.stringValue,
                                 id: args.objectValue?["id"]?.stringValue,
                                 payload: payload, frame: frame,
                                 z: args.objectValue?["z"]?.doubleValue),
                        to: &doc)
                    try applyCornerRadiusArg(args, doc: &doc, layerId: r.newLayerId)
                    try applyShadowArg(args, doc: &doc, layerId: r.newLayerId)
                    return r
                }
            },

            tool("add_polygon",
                 desc: "Add a regular N-sided polygon (sides ≥ 3) inscribed in the frame.",
                 schema: schema(props: polygonSchema(), required: ["project", "sides"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    let sides = args.objectValue?["sides"]?.intValue ?? 6
                    let fill: Color = try (args.objectValue?["fill"]?.stringValue).map { try Color(hex: $0) } ?? .white
                    let stroke = try strokeFromArgs(args)
                    let payload = PolygonLayerPayload(sides: sides, fill: fill, stroke: stroke)
                    let frame = try frameFromArgs(args: args, canvas: doc.canvas, defaultSize: (300, 300))
                    let r = try CommandEngine.apply(
                        .addPolygon(pageId: args.objectValue?["page"]?.stringValue,
                                    id: args.objectValue?["id"]?.stringValue,
                                    payload: payload, frame: frame,
                                    z: args.objectValue?["z"]?.doubleValue),
                        to: &doc)
                    try applyCornerRadiusArg(args, doc: &doc, layerId: r.newLayerId)
                    try applyShadowArg(args, doc: &doc, layerId: r.newLayerId)
                    return r
                }
            },

            tool("add_star",
                 desc: "Add an N-pointed star inscribed in the frame.",
                 schema: schema(props: starSchema(), required: ["project"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    let points = args.objectValue?["points"]?.intValue ?? 5
                    let inner = args.objectValue?["inner_radius"]?.doubleValue ?? 0.4
                    let fill: Color = try (args.objectValue?["fill"]?.stringValue).map { try Color(hex: $0) } ?? .white
                    let stroke = try strokeFromArgs(args)
                    let payload = StarLayerPayload(points: points, innerRadius: inner, fill: fill, stroke: stroke)
                    let frame = try frameFromArgs(args: args, canvas: doc.canvas, defaultSize: (300, 300))
                    let r = try CommandEngine.apply(
                        .addStar(pageId: args.objectValue?["page"]?.stringValue,
                                 id: args.objectValue?["id"]?.stringValue,
                                 payload: payload, frame: frame,
                                 z: args.objectValue?["z"]?.doubleValue),
                        to: &doc)
                    try applyCornerRadiusArg(args, doc: &doc, layerId: r.newLayerId)
                    try applyShadowArg(args, doc: &doc, layerId: r.newLayerId)
                    return r
                }
            },

            simpleMutator("set_gradient",
                          desc: "Set or clear a layer's gradient fill mask (turns any layer into a gradient-filled version of itself). Provide gradient params inline, or `clear: true`.",
                          extra: [
                            "type": stringSchema("linear or radial (default linear)"),
                            "stops": .object([
                                "type": .string("array"),
                                "items": .object([
                                    "type": .string("object"),
                                    "properties": .object([
                                        "color": stringSchema("#RRGGBB(AA)"),
                                        "at": numberSchema("0..1"),
                                    ]),
                                ]),
                            ]),
                            "start": stringSchema("\"x,y\" normalized 0..1"),
                            "end":   stringSchema("\"x,y\" normalized 0..1"),
                            "clear": boolSchema("If true, clears the gradient."),
                          ],
                          required: ["project", "id"]) { args, doc, id in
                let g: GradientLayerPayload?
                if args.objectValue?["clear"]?.boolValue == true {
                    g = nil
                } else {
                    g = try gradientPayloadFromArgs(args)
                }
                _ = try CommandEngine.apply(
                    .setLayerGradient(pageId: args.objectValue?["page"]?.stringValue, id: id, gradient: g),
                    to: &doc)
            },

            tool("group",
                 desc: "Bundle existing layers into a new group. Provide `ids` as a JSON array of layer ids.",
                 schema: schema(props: [
                    "project": stringSchema("Path to .aiproj"),
                    "ids": .object([
                        "type": .string("array"),
                        "description": .string("Layer ids to bundle into the group."),
                        "items": stringSchema(),
                    ]),
                    "id": stringSchema("Optional id for the new group layer."),
                    "name": stringSchema("Optional display name."),
                    "page": stringSchema("Page id; default = active page."),
                 ], required: ["project", "ids"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    guard let raw = args.objectValue?["ids"]?.arrayValue else {
                        throw EditorError.usage("`ids` must be a JSON array of layer ids")
                    }
                    let ids = raw.compactMap { $0.stringValue }
                    guard !ids.isEmpty else { throw EditorError.usage("`ids` must list at least one layer id") }
                    return try CommandEngine.apply(
                        .addGroup(pageId: args.objectValue?["page"]?.stringValue,
                                  id: args.objectValue?["id"]?.stringValue,
                                  name: args.objectValue?["name"]?.stringValue,
                                  childIds: ids),
                        to: &doc)
                }
            },

            simpleMutator("ungroup",
                          desc: "Replace a group layer with its children promoted to the page's layer list.",
                          extra: [:],
                          required: ["project", "id"]) { args, doc, id in
                _ = try CommandEngine.apply(.ungroup(pageId: args.objectValue?["page"]?.stringValue, id: id), to: &doc)
            },

            simpleMutator("set_group_clip",
                          desc: "Crop a group's children to its frame bounds. Trims rotated children, fill-mode images, overflowing text and shadows that spill past the box. Combine with set_corner_radius for a rounded crop.",
                          extra: ["value": boolSchema("true = crop children to the group's bounds (default); false = no clipping.")],
                          required: ["project", "id", "value"]) { args, doc, id in
                _ = try CommandEngine.apply(
                    .setGroupClipsToBounds(pageId: args.objectValue?["page"]?.stringValue,
                                           id: id, value: args.objectValue?["value"]?.boolValue ?? true),
                    to: &doc)
            },

            simpleMutator("set_corner_radius",
                          desc: "Set or clear a layer's corner radius. Use `0` to disable.",
                          extra: ["value": numberSchema("Corner radius in canvas pixels (≥ 0).")],
                          required: ["project", "id", "value"]) { args, doc, id in
                let v = try requireDouble(args, "value")
                _ = try CommandEngine.apply(
                    .setCornerRadius(pageId: args.objectValue?["page"]?.stringValue, id: id, value: v),
                    to: &doc)
            },

            simpleMutator("set_corner_style",
                          desc: "Set a layer's corner-radius shape: arc (default quarter-circles), continuous (iOS squircle), or cut (45° chamfer).",
                          extra: ["style": stringSchema("arc | continuous | cut")],
                          required: ["project", "id", "style"]) { args, doc, id in
                let raw = try requireString(args, "style").lowercased()
                guard let style = CornerStyle(rawValue: raw) else {
                    throw EditorError.usage("`style` expects arc | continuous | cut")
                }
                _ = try CommandEngine.apply(
                    .setCornerStyle(pageId: args.objectValue?["page"]?.stringValue, id: id, style: style),
                    to: &doc)
            },

            simpleMutator("set_corners",
                          desc: "Choose which corners the cornerRadius rounds. Pass `corners` as a JSON array of any of: topLeft, topRight, bottomLeft, bottomRight (empty array = no corners rounded). Omit a corner to leave it square. No effect when cornerRadius is 0.",
                          extra: ["corners": .object([
                              "type": .string("array"),
                              "description": .string("Corner names to round: topLeft/topRight/bottomLeft/bottomRight."),
                              "items": stringSchema(),
                          ])],
                          required: ["project", "id", "corners"]) { args, doc, id in
                guard let arr = args.objectValue?["corners"]?.arrayValue else {
                    throw EditorError.usage("`corners` must be a JSON array of corner names")
                }
                let corners = RectCorners(names: arr.compactMap { $0.stringValue })
                _ = try CommandEngine.apply(
                    .setRoundedCorners(pageId: args.objectValue?["page"]?.stringValue, id: id, corners: corners),
                    to: &doc)
            },

            simpleMutator("set_layer_background",
                          desc: "Set or clear a layer's background fill (solid color OR gradient). Pass `color`, gradient fields (`type`/`stops`/`start`/`end`), or `clear: true`.",
                          extra: [
                            "color": stringSchema("#RRGGBB(AA) — for a solid-colour background."),
                            "type": stringSchema("linear or radial — for a gradient background."),
                            "stops": .object([
                                "type": .string("array"),
                                "items": .object([
                                    "type": .string("object"),
                                    "properties": .object([
                                        "color": stringSchema("#RRGGBB(AA)"),
                                        "at": numberSchema("0..1"),
                                    ]),
                                ]),
                            ]),
                            "start": stringSchema("\"x,y\" normalized 0..1"),
                            "end":   stringSchema("\"x,y\" normalized 0..1"),
                            "clear": boolSchema("If true, removes the background."),
                          ],
                          required: ["project", "id"]) { args, doc, id in
                let bg: LayerBackground?
                if args.objectValue?["clear"]?.boolValue == true {
                    bg = nil
                } else if let hex = args.objectValue?["color"]?.stringValue {
                    bg = .color(try Color(hex: hex))
                } else if args.objectValue?["stops"] != nil
                          || args.objectValue?["type"] != nil
                          || args.objectValue?["start"] != nil
                          || args.objectValue?["end"] != nil {
                    bg = .gradient(try gradientPayloadFromArgs(args))
                } else {
                    throw EditorError.usage("provide `color`, gradient fields (type/stops/start/end), or `clear: true`")
                }
                _ = try CommandEngine.apply(
                    .setLayerBackground(pageId: args.objectValue?["page"]?.stringValue, id: id, background: bg),
                    to: &doc)
            },

            simpleMutator("set_shadow",
                          desc: "Set or clear a layer's drop shadow. Provide `shadow: \"color,dx,dy,blur\"` or `clear: true`.",
                          extra: [
                            "shadow": stringSchema("\"#RRGGBBAA,dx,dy,blur\""),
                            "clear": boolSchema("If true, removes the shadow."),
                          ],
                          required: ["project", "id"]) { args, doc, id in
                let shadow: Shadow?
                if args.objectValue?["clear"]?.boolValue == true {
                    shadow = nil
                } else if let s = parseShadow(args.objectValue?["shadow"]?.stringValue) {
                    shadow = s
                } else {
                    throw EditorError.usage("provide `shadow` (\"color,dx,dy,blur\") or `clear: true`")
                }
                _ = try CommandEngine.apply(
                    .setShadow(pageId: args.objectValue?["page"]?.stringValue, id: id, shadow: shadow),
                    to: &doc)
            },

            tool("add_gradient",
                 desc: "Add a gradient layer (linear or radial). Provide stops as an array of {color, at}.",
                 schema: schema(props: gradientSchema(), required: ["project"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    let payload = try gradientPayloadFromArgs(args)
                    let frame = try frameFromArgs(args: args, canvas: doc.canvas,
                                                  defaultSize: (Double(doc.canvas.width), Double(doc.canvas.height)))
                    let r = try CommandEngine.apply(
                        .addGradient(pageId: args.objectValue?["page"]?.stringValue,
                                     id: args.objectValue?["id"]?.stringValue,
                                     payload: payload, frame: frame,
                                     z: args.objectValue?["z"]?.doubleValue),
                        to: &doc)
                    try applyCornerRadiusArg(args, doc: &doc, layerId: r.newLayerId)
                    try applyShadowArg(args, doc: &doc, layerId: r.newLayerId)
                    return r
                }
            },

            tool("add_blur",
                 desc: "Add a Gaussian blur layer that frosts whatever sits underneath it. Provide `stops` as an array of {radius, at} to enable a variable-radius blur driven by keypoints (then `radius` is unused — each stop carries its own).",
                 schema: schema(props: blurSchema(), required: ["project"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    let radius = args.objectValue?["radius"]?.doubleValue ?? 24
                    let tint: Color? = try (args.objectValue?["tint"]?.stringValue).map { try Color(hex: $0) }
                    let stops: [BlurStop]? = try blurStopsFromArgs(args)
                    let typeStr = args.objectValue?["type"]?.stringValue?.lowercased() ?? "linear"
                    guard let gradientType = GradientType(rawValue: typeStr) else {
                        throw EditorError.usage("`type` expects linear or radial")
                    }
                    let (sx, sy) = try point(args.objectValue?["start"]?.stringValue) ?? (0, 0)
                    let (ex, ey) = try point(args.objectValue?["end"]?.stringValue)   ?? (0, 1)
                    let payload = BlurLayerPayload(radius: radius, tint: tint,
                                                   stops: stops, gradientType: gradientType,
                                                   startX: sx, startY: sy, endX: ex, endY: ey)
                    let frame = try frameFromArgs(args: args, canvas: doc.canvas, defaultSize: (400, 400))
                    let r = try CommandEngine.apply(
                        .addBlur(pageId: args.objectValue?["page"]?.stringValue,
                                 id: args.objectValue?["id"]?.stringValue,
                                 payload: payload, frame: frame,
                                 z: args.objectValue?["z"]?.doubleValue),
                        to: &doc)
                    try applyCornerRadiusArg(args, doc: &doc, layerId: r.newLayerId)
                    return r
                }
            },

            tool("add_bezel",
                 desc: "Add a device bezel (optionally with a screenshot inside).",
                 schema: schema(props: bezelSchema(), required: ["project", "device"])) { args in
                try mutateReturnId(args) { doc -> EditorCommandResult in
                    let device = try requireString(args, "device")
                    guard let bezel = DeviceBezelCatalog.find(id: device) else {
                        throw EditorError.unknownBezel(device)
                    }
                    var screenshotAssetId: String? = nil
                    if let a = args.objectValue?["screenshot_asset"]?.stringValue {
                        guard doc.assets[a] != nil else { throw EditorError.assetNotFound(a) }
                        screenshotAssetId = a
                    } else if let p = args.objectValue?["screenshot_path"]?.stringValue {
                        let id = CLIHelpers.autoAssetId(in: doc, path: p)
                        _ = try CommandEngine.apply(.addAsset(id: id, path: p), to: &doc)
                        screenshotAssetId = id
                    }
                    let chrome = try (args.objectValue?["chrome_color"]?.stringValue).map { try Color(hex: $0) }
                    let payload = DeviceBezelPayload(device: device,
                                                     screenshotAssetId: screenshotAssetId,
                                                     chromeColor: chrome)
                    let frame: Frame
                    if let s = args.objectValue?["frame"]?.stringValue {
                        frame = try Frame.parse(s)
                    } else {
                        let h = args.objectValue?["height"]?.doubleValue ?? Double(doc.canvas.height) * 0.6
                        let w = h * bezel.aspect
                        let token = args.objectValue?["at"]?.stringValue ?? "center"
                        let anchor = AnchorPosition(token: token) ?? .center
                        frame = anchor.frame(layerSize: (w, h), canvas: doc.canvas)
                    }
                    let r = try CommandEngine.apply(
                        .addDeviceBezel(pageId: args.objectValue?["page"]?.stringValue, id: args.objectValue?["id"]?.stringValue,
                                        payload: payload, frame: frame,
                                        z: args.objectValue?["z"]?.doubleValue),
                        to: &doc)
                    try applyShadowArg(args, doc: &doc, layerId: r.newLayerId)
                    return r
                }
            },

            // edits

            simpleMutator("move", desc: "Move a layer.",
                          extra: ["to": stringSchema("\"x,y\""), "dx": numberSchema(), "dy": numberSchema(), "at": stringSchema("anchor token")],
                          required: ["project", "id"]) { args, doc, id in
                guard let layer = doc.layer(id: id) else { throw EditorError.layerNotFound(id) }
                let to: (Double, Double)
                if let s = args.objectValue?["to"]?.stringValue {
                    let parts = s.split(whereSeparator: { ",x ".contains($0) }).compactMap { Double($0) }
                    guard parts.count == 2 else { throw EditorError.usage("`to` expects 'x,y'") }
                    to = (parts[0], parts[1])
                } else if let token = args.objectValue?["at"]?.stringValue,
                          let anchor = AnchorPosition(token: token) {
                    let f = anchor.frame(layerSize: (layer.frame.w, layer.frame.h), canvas: doc.canvas)
                    to = (f.x, f.y)
                } else if let dx = args.objectValue?["dx"]?.doubleValue,
                          let dy = args.objectValue?["dy"]?.doubleValue {
                    to = (layer.frame.x + dx, layer.frame.y + dy)
                } else {
                    throw EditorError.usage("provide to, at, or (dx,dy)")
                }
                _ = try CommandEngine.apply(.move(pageId: args.objectValue?["page"]?.stringValue, id: id, to: to), to: &doc)
            },

            simpleMutator("resize", desc: "Resize a layer.",
                          extra: ["width": numberSchema(), "height": numberSchema()],
                          required: ["project", "id"]) { args, doc, id in
                _ = try CommandEngine.apply(.resize(pageId: args.objectValue?["page"]?.stringValue, id: id,
                                                    w: args.objectValue?["width"]?.doubleValue,
                                                    h: args.objectValue?["height"]?.doubleValue),
                                            to: &doc)
            },

            simpleMutator("set_frame", desc: "Set the layer frame.",
                          extra: ["frame": stringSchema("\"x,y,w,h\"")],
                          required: ["project", "id", "frame"]) { args, doc, id in
                let f = try Frame.parse(try requireString(args, "frame"))
                _ = try CommandEngine.apply(.setFrame(pageId: args.objectValue?["page"]?.stringValue, id: id, frame: f), to: &doc)
            },

            simpleMutator("rotate", desc: "Rotate a layer (absolute degrees).",
                          extra: ["degrees": numberSchema()],
                          required: ["project", "id", "degrees"]) { args, doc, id in
                _ = try CommandEngine.apply(.rotate(pageId: args.objectValue?["page"]?.stringValue, id: id, degrees: try requireDouble(args, "degrees")), to: &doc)
            },

            simpleMutator("set_opacity", desc: "Set layer opacity 0..1.",
                          extra: ["value": numberSchema()],
                          required: ["project", "id", "value"]) { args, doc, id in
                _ = try CommandEngine.apply(.setOpacity(pageId: args.objectValue?["page"]?.stringValue, id: id, value: try requireDouble(args, "value")), to: &doc)
            },

            simpleMutator("set_visible", desc: "Show / hide a layer.",
                          extra: ["value": boolSchema()],
                          required: ["project", "id", "value"]) { args, doc, id in
                _ = try CommandEngine.apply(.setVisible(pageId: args.objectValue?["page"]?.stringValue, id: id, value: args.objectValue?["value"]?.boolValue ?? true), to: &doc)
            },

            simpleMutator("set_blend", desc: "Set blend mode.",
                          extra: ["mode": stringSchema("normal/multiply/screen/...")],
                          required: ["project", "id", "mode"]) { args, doc, id in
                let m = BlendMode(rawValue: try requireString(args, "mode")) ?? .normal
                _ = try CommandEngine.apply(.setBlendMode(pageId: args.objectValue?["page"]?.stringValue, id: id, mode: m), to: &doc)
            },

            simpleMutator("rename", desc: "Rename a layer.",
                          extra: ["name": stringSchema()],
                          required: ["project", "id", "name"]) { args, doc, id in
                _ = try CommandEngine.apply(.rename(pageId: args.objectValue?["page"]?.stringValue, id: id, name: try requireString(args, "name")), to: &doc)
            },

            simpleMutator("duplicate", desc: "Duplicate a layer.",
                          extra: ["new_id": stringSchema()],
                          required: ["project", "id"]) { args, doc, id in
                _ = try CommandEngine.apply(.duplicate(pageId: args.objectValue?["page"]?.stringValue, id: id, newId: args.objectValue?["new_id"]?.stringValue), to: &doc)
            },

            simpleMutator("remove", desc: "Remove a layer.", extra: [:],
                          required: ["project", "id"]) { args, doc, id in
                _ = try CommandEngine.apply(.remove(pageId: args.objectValue?["page"]?.stringValue, id: id), to: &doc)
            },

            // text edits

            simpleMutator("set_text", desc: "Set text content of a text layer.",
                          extra: ["text": stringSchema()],
                          required: ["project", "id", "text"]) { args, doc, id in
                _ = try CommandEngine.apply(.setText(pageId: args.objectValue?["page"]?.stringValue, id: id, text: try requireString(args, "text")), to: &doc)
            },

            simpleMutator("set_font", desc: "Change font properties of a text layer.",
                          extra: ["font": stringSchema(), "font_size": numberSchema(),
                                  "font_weight": stringSchema(), "italic": boolSchema()],
                          required: ["project", "id"]) { args, doc, id in
                let weight = (args.objectValue?["font_weight"]?.stringValue).flatMap { FontWeight(rawValue: $0) }
                _ = try CommandEngine.apply(.setFont(pageId: args.objectValue?["page"]?.stringValue, 
                    id: id,
                    family: args.objectValue?["font"]?.stringValue,
                    size: args.objectValue?["font_size"]?.doubleValue,
                    weight: weight,
                    italic: args.objectValue?["italic"]?.boolValue), to: &doc)
            },

            simpleMutator("set_color", desc: "Set color of a text/shape/bezel layer.",
                          extra: ["color": stringSchema("#RRGGBB")],
                          required: ["project", "id", "color"]) { args, doc, id in
                let c = try Color(hex: try requireString(args, "color"))
                _ = try CommandEngine.apply(.setColor(pageId: args.objectValue?["page"]?.stringValue, id: id, color: c), to: &doc)
            },

            simpleMutator("set_alignment", desc: "Set text alignment.",
                          extra: ["align": stringSchema("left/center/right/justified")],
                          required: ["project", "id", "align"]) { args, doc, id in
                let a = TextAlignment(rawValue: try requireString(args, "align")) ?? .center
                _ = try CommandEngine.apply(.setAlignment(pageId: args.objectValue?["page"]?.stringValue, id: id, alignment: a), to: &doc)
            },

            simpleMutator("set_bezel_color",
                          desc: "Set the color variant of a device bezel layer (image-backed devices only).",
                          extra: ["color": stringSchema("Color label as listed by list_bezels for this device. Omit to reset to default.")],
                          required: ["project", "id"]) { args, doc, id in
                let color = args.objectValue?["color"]?.stringValue
                _ = try CommandEngine.apply(.setBezelColor(pageId: args.objectValue?["page"]?.stringValue, id: id, color: color), to: &doc)
            },

            simpleMutator("set_bezel_screenshot",
                          desc: "Set the screenshot image placed inside a device bezel. Supply `asset` (existing id), `asset_path` (auto-import), or `clear: true`.",
                          extra: [
                            "asset": stringSchema("Existing asset id."),
                            "asset_path": stringSchema("File path to auto-import as a new asset and use."),
                            "clear": boolSchema("If true, removes any screenshot from the bezel."),
                          ],
                          required: ["project", "id"]) { args, doc, id in
                let page = args.objectValue?["page"]?.stringValue
                let assetId: String?
                if args.objectValue?["clear"]?.boolValue == true {
                    assetId = nil
                } else if let a = args.objectValue?["asset"]?.stringValue {
                    guard doc.assets[a] != nil else { throw EditorError.assetNotFound(a) }
                    assetId = a
                } else if let p = args.objectValue?["asset_path"]?.stringValue {
                    let newId = CLIHelpers.autoAssetId(in: doc, path: p)
                    _ = try CommandEngine.apply(.addAsset(id: newId, path: p), to: &doc)
                    assetId = newId
                } else {
                    throw EditorError.usage("provide asset, asset_path, or clear: true")
                }
                _ = try CommandEngine.apply(.setBezelScreenshot(pageId: page, id: id, assetId: assetId), to: &doc)
            },

            // z

            simpleMutator("set_z", desc: "Set zIndex.",
                          extra: ["value": numberSchema()],
                          required: ["project", "id", "value"]) { args, doc, id in
                _ = try CommandEngine.apply(.setZIndex(pageId: args.objectValue?["page"]?.stringValue, id: id, value: try requireDouble(args, "value")), to: &doc)
            },
            simpleMutator("bring_to_front", desc: "Move layer above all others.", extra: [:], required: ["project", "id"]) { args, doc, id in
                _ = try CommandEngine.apply(.bringToFront(pageId: args.objectValue?["page"]?.stringValue, id: id), to: &doc)
            },
            simpleMutator("send_to_back", desc: "Move layer below all others.", extra: [:], required: ["project", "id"]) { args, doc, id in
                _ = try CommandEngine.apply(.sendToBack(pageId: args.objectValue?["page"]?.stringValue, id: id), to: &doc)
            },
            simpleMutator("move_forward", desc: "Move layer one step forward.", extra: [:], required: ["project", "id"]) { args, doc, id in
                _ = try CommandEngine.apply(.moveForward(pageId: args.objectValue?["page"]?.stringValue, id: id), to: &doc)
            },
            simpleMutator("move_backward", desc: "Move layer one step backward.", extra: [:], required: ["project", "id"]) { args, doc, id in
                _ = try CommandEngine.apply(.moveBackward(pageId: args.objectValue?["page"]?.stringValue, id: id), to: &doc)
            },

            // MARK: - Pages

            tool("list_pages",
                 desc: "List pages of a project.",
                 schema: schema(props: ["project": stringSchema()], required: ["project"])) { args in
                let path = try requireString(args, "project")
                let doc = try DocumentCodec.load(from: URL(fileURLWithPath: path))
                var lines: [String] = []
                for p in doc.pages {
                    let marker = p.id == doc.activePage.id ? "*" : " "
                    lines.append("\(marker) \(p.id) '\(p.name)'  \(p.canvas.width)x\(p.canvas.height)  previews=\(p.previews.count) spacing=\(Int(p.layout.spacing)) preview=\(Int(p.layout.previewWidth))x\(Int(p.layout.previewHeight))")
                }
                return textResult(lines.joined(separator: "\n"))
            },

            tool("add_page",
                 desc: "Add a new page. Inherits the active page's canvas if not specified.",
                 schema: schema(props: [
                    "project": stringSchema(),
                    "id": stringSchema("Optional page id."),
                    "name": stringSchema("Display name."),
                    "preset": stringSchema("Optional canvas preset (see list_presets)."),
                    "width": integerSchema(),
                    "height": integerSchema(),
                 ], required: ["project"])) { args in
                try mutate(args) { doc in
                    var canvas: Canvas? = nil
                    if let p = args.objectValue?["preset"]?.stringValue,
                       let preset = PresetCatalog.find(id: p) {
                        canvas = Canvas(width: preset.width, height: preset.height)
                    } else if let w = args.objectValue?["width"]?.intValue,
                              let h = args.objectValue?["height"]?.intValue {
                        canvas = Canvas(width: w, height: h)
                    }
                    _ = try CommandEngine.apply(
                        .addPage(id: args.objectValue?["id"]?.stringValue,
                                 name: args.objectValue?["name"]?.stringValue,
                                 canvas: canvas), to: &doc)
                }
            },

            tool("remove_page",
                 desc: "Remove a page (a fresh empty page is recreated if you remove the last one).",
                 schema: schema(props: ["project": stringSchema(), "id": stringSchema()],
                                required: ["project", "id"])) { args in
                try mutate(args) { doc in
                    let id = try requireString(args, "id")
                    _ = try CommandEngine.apply(.removePage(id: id), to: &doc)
                }
            },

            tool("rename_page",
                 desc: "Rename a page.",
                 schema: schema(props: ["project": stringSchema(),
                                        "id": stringSchema(),
                                        "name": stringSchema()],
                                required: ["project", "id", "name"])) { args in
                try mutate(args) { doc in
                    let id = try requireString(args, "id")
                    let name = try requireString(args, "name")
                    _ = try CommandEngine.apply(.renamePage(id: id, name: name), to: &doc)
                }
            },

            tool("select_page",
                 desc: "Set the active page (used as default by other commands when `page` is omitted).",
                 schema: schema(props: ["project": stringSchema(), "id": stringSchema()],
                                required: ["project", "id"])) { args in
                try mutate(args) { doc in
                    let id = try requireString(args, "id")
                    _ = try CommandEngine.apply(.selectPage(id: id), to: &doc)
                }
            },

            tool("set_layout",
                 desc: "Configure a page's preview defaults (count / size / spacing). Auto-relayouts.",
                 schema: schema(props: [
                    "project": stringSchema(),
                    "page": stringSchema("Page id; default = active page."),
                    "count": integerSchema("Number of previews on this page."),
                    "preview_width": numberSchema(),
                    "preview_height": numberSchema(),
                    "spacing": numberSchema(),
                 ], required: ["project"])) { args in
                try mutate(args) { doc in
                    let pid = args.objectValue?["page"]?.stringValue ?? doc.activePage.id
                    guard let page = doc.page(id: pid) else {
                        throw EditorError.layerNotFound("page:\(pid)")
                    }
                    let w = args.objectValue?["preview_width"]?.doubleValue  ?? page.layout.previewWidth
                    let h = args.objectValue?["preview_height"]?.doubleValue ?? page.layout.previewHeight
                    if w != page.layout.previewWidth || h != page.layout.previewHeight {
                        _ = try CommandEngine.apply(.setPreviewSize(pageId: pid, width: w, height: h), to: &doc)
                    }
                    if let sp = args.objectValue?["spacing"]?.doubleValue {
                        _ = try CommandEngine.apply(.setPreviewSpacing(pageId: pid, spacing: sp), to: &doc)
                    }
                    if let n = args.objectValue?["count"]?.intValue {
                        _ = try CommandEngine.apply(.setPreviewCount(pageId: pid, count: n), to: &doc)
                    }
                }
            },

            tool("list_previews",
                 desc: "List previews on a page.",
                 schema: schema(props: [
                    "project": stringSchema(),
                    "page": stringSchema("Page id; default = active page."),
                 ], required: ["project"])) { args in
                let path = try requireString(args, "project")
                let doc = try DocumentCodec.load(from: URL(fileURLWithPath: path))
                let pid = args.objectValue?["page"]?.stringValue ?? doc.activePage.id
                guard let page = doc.page(id: pid) else { throw EditorError.layerNotFound("page:\(pid)") }
                var lines: [String] = []
                for p in page.previews {
                    lines.append("\(p.id)  '\(p.name)'  frame=[\(Int(p.frame.x)),\(Int(p.frame.y)),\(Int(p.frame.w)),\(Int(p.frame.h))]  bg=\(p.background.hex)")
                }
                return textResult(lines.joined(separator: "\n"))
            },

            simpleMutator("add_preview", desc: "Add a new preview to the page.",
                          extra: ["name": stringSchema(), "background": stringSchema("#RRGGBB")],
                          required: ["project"]) { args, doc, _ in
                let page = args.objectValue?["page"]?.stringValue
                let name = args.objectValue?["name"]?.stringValue
                let bg = try (args.objectValue?["background"]?.stringValue).map { try Color(hex: $0) }
                _ = try CommandEngine.apply(.addPreview(pageId: page, id: nil, name: name, background: bg), to: &doc)
            },

            simpleMutator("remove_preview", desc: "Remove a preview by id.", extra: [:],
                          required: ["project", "id"]) { args, doc, id in
                _ = try CommandEngine.apply(.removePreview(pageId: args.objectValue?["page"]?.stringValue, id: id), to: &doc)
            },

            simpleMutator("rename_preview", desc: "Rename a preview.",
                          extra: ["name": stringSchema()],
                          required: ["project", "id", "name"]) { args, doc, id in
                let name = try requireString(args, "name")
                _ = try CommandEngine.apply(.renamePreview(pageId: args.objectValue?["page"]?.stringValue, id: id, name: name), to: &doc)
            },

            simpleMutator("set_preview_background", desc: "Set a preview's background colour.",
                          extra: ["color": stringSchema("#RRGGBB")],
                          required: ["project", "id", "color"]) { args, doc, id in
                let c = try Color(hex: try requireString(args, "color"))
                _ = try CommandEngine.apply(.setPreviewBackground(pageId: args.objectValue?["page"]?.stringValue, id: id, color: c), to: &doc)
            },

            tool("render_preview",
                 desc: "Render one preview as a PNG (cropped to its frame) and write to disk.",
                 schema: schema(props: [
                    "project": stringSchema(),
                    "page": stringSchema("Page id; default = active page."),
                    "preview": stringSchema("Preview id."),
                    "output": stringSchema("Output PNG path."),
                    "scale": integerSchema("1, 2 or 3."),
                 ], required: ["project", "preview", "output"])) { args in
                let path = try requireString(args, "project")
                let outPath = try requireString(args, "output")
                let previewId = try requireString(args, "preview")
                let scale = args.objectValue?["scale"]?.intValue ?? 1
                let url = URL(fileURLWithPath: path)
                let doc = try DocumentCodec.load(from: url)
                let r = Renderer(baseDirectory: url.deletingLastPathComponent())
                let data = try r.renderPreviewPNG(doc,
                                                  pageId: args.objectValue?["page"]?.stringValue,
                                                  previewId: previewId,
                                                  scale: scale)
                try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
                return imageResult(message: "rendered preview \(previewId) → \(outPath)", data: data)
            },
        ]
    }

    // MARK: - Tool building

    private static func tool(_ name: String, desc: String, schema: JSONValue,
                             run: @escaping (JSONValue) throws -> JSONValue) -> MCPTool {
        MCPTool(name: name, description: desc, inputSchema: schema, run: run)
    }

    private static func simpleMutator(_ name: String, desc: String,
                                      extra: [String: JSONValue],
                                      required: [String],
                                      body: @escaping (JSONValue, inout Document, String) throws -> Void) -> MCPTool {
        var props: [String: JSONValue] = [
            "project": stringSchema("Path to .aiproj"),
            "id": stringSchema("Layer id."),
            "page": stringSchema("Page id (defaults to active page)."),
        ]
        for (k, v) in extra { props[k] = v }
        return MCPTool(name: name, description: desc,
                       inputSchema: schema(props: props, required: required)) { args in
            try mutate(args) { doc in
                let id = try requireString(args, "id")
                try body(args, &doc, id)
            }
        }
    }

    // MARK: - Schema builders

    private static func schema(props: [String: JSONValue], required: [String]) -> JSONValue {
        var dict: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(props),
        ]
        if !required.isEmpty {
            dict["required"] = .array(required.map { .string($0) })
        }
        return .object(dict)
    }

    private static func stringSchema(_ desc: String? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string("string")]
        if let d = desc { o["description"] = .string(d) }
        return .object(o)
    }
    private static func numberSchema(_ desc: String? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string("number")]
        if let d = desc { o["description"] = .string(d) }
        return .object(o)
    }
    private static func integerSchema(_ desc: String? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string("integer")]
        if let d = desc { o["description"] = .string(d) }
        return .object(o)
    }
    private static func boolSchema(_ desc: String? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string("boolean")]
        if let d = desc { o["description"] = .string(d) }
        return .object(o)
    }

    /// Schema fragment for the layer-level `shadow` arg accepted by every `add_*` tool.
    private static var shadowProp: JSONValue {
        stringSchema("\"color,dx,dy,blur\" — optional drop shadow attached on creation.")
    }

    /// Schema fragment for the layer-level `corner_radius` arg accepted by every `add_*` tool.
    private static var cornerRadiusProp: JSONValue {
        numberSchema("Rounded-corner radius in canvas pixels. No effect on ellipse/deviceBezel.")
    }

    private static func textSchema() -> [String: JSONValue] {
        [
            "project": stringSchema("Path to .aiproj"),
            "text": stringSchema("Text content."),
            "font": stringSchema("Font family. Default SF Pro Display."),
            "font_size": numberSchema("Font size in px."),
            "font_weight": stringSchema("ultraLight/thin/light/regular/medium/semibold/bold/heavy/black"),
            "italic": boolSchema("Italic?"),
            "color": stringSchema("#RRGGBB"),
            "align": stringSchema("left/center/right/justified"),
            "line_spacing": numberSchema(),
            "kerning": numberSchema(),
            "frame": stringSchema("\"x,y,w,h\" — overrides at/size."),
            "at": stringSchema("Anchor token: center, top-center, etc."),
            "size": stringSchema("\"w,h\" used with `at`."),
            "z": numberSchema(),
            "id": stringSchema("Optional layer id."),
            "shadow": shadowProp,
            "corner_radius": cornerRadiusProp,
        ]
    }

    private static func imageSchema() -> [String: JSONValue] {
        [
            "project": stringSchema("Path to .aiproj"),
            "asset": stringSchema("Existing asset id."),
            "asset_path": stringSchema("File path; auto-registered if asset omitted."),
            "content_mode": stringSchema("fit/fill/stretch"),
            "frame": stringSchema("\"x,y,w,h\""),
            "at": stringSchema("Anchor."),
            "size": stringSchema("\"w,h\""),
            "z": numberSchema(),
            "id": stringSchema(),
            "shadow": shadowProp,
            "corner_radius": cornerRadiusProp,
        ]
    }

    private static func shapeSchema(includeRadius: Bool) -> [String: JSONValue] {
        var d: [String: JSONValue] = [
            "project": stringSchema("Path to .aiproj"),
            "fill": stringSchema("#RRGGBB"),
            "stroke": stringSchema("\"color,width\""),
            "frame": stringSchema("\"x,y,w,h\""),
            "at": stringSchema(),
            "size": stringSchema(),
            "z": numberSchema(),
            "id": stringSchema(),
            "shadow": shadowProp,
            "corner_radius": cornerRadiusProp,
        ]
        if includeRadius { d["radius"] = numberSchema("Corner radius.") }
        return d
    }

    private static func lineSchema() -> [String: JSONValue] {
        [
            "project": stringSchema("Path to .aiproj"),
            "color": stringSchema("#RRGGBB"),
            "width": numberSchema("Stroke width in px."),
            "start": stringSchema("\"x,y\" normalized 0..1 (default 0,0.5)"),
            "end":   stringSchema("\"x,y\" normalized 0..1 (default 1,0.5)"),
            "arrow": stringSchema("none|start|end|both"),
            "arrow_size": numberSchema("Arrowhead size as a multiple of line width."),
            "frame": stringSchema("\"x,y,w,h\""),
            "at": stringSchema(),
            "size": stringSchema(),
            "z": numberSchema(),
            "id": stringSchema(),
            "shadow": stringSchema("\"color,dx,dy,blur\" — optional drop shadow."),
            "corner_radius": cornerRadiusProp,
        ]
    }

    private static func polygonSchema() -> [String: JSONValue] {
        [
            "project": stringSchema("Path to .aiproj"),
            "sides": integerSchema("Number of sides (≥ 3)."),
            "fill": stringSchema("#RRGGBB"),
            "stroke": stringSchema("\"color,width\""),
            "frame": stringSchema("\"x,y,w,h\""),
            "at": stringSchema(),
            "size": stringSchema(),
            "z": numberSchema(),
            "id": stringSchema(),
            "shadow": stringSchema("\"color,dx,dy,blur\" — optional drop shadow."),
            "corner_radius": cornerRadiusProp,
        ]
    }

    private static func starSchema() -> [String: JSONValue] {
        [
            "project": stringSchema("Path to .aiproj"),
            "points": integerSchema("Number of star points (≥ 3, default 5)."),
            "inner_radius": numberSchema("Inner-radius fraction (0..1, default 0.4)."),
            "fill": stringSchema("#RRGGBB"),
            "stroke": stringSchema("\"color,width\""),
            "frame": stringSchema("\"x,y,w,h\""),
            "at": stringSchema(),
            "size": stringSchema(),
            "z": numberSchema(),
            "id": stringSchema(),
            "shadow": stringSchema("\"color,dx,dy,blur\" — optional drop shadow."),
            "corner_radius": cornerRadiusProp,
        ]
    }

    /// Parse a `"color,dx,dy,blur"` shadow spec. Returns nil if `s` is nil or malformed.
    private static func parseShadow(_ s: String?) -> Shadow? {
        guard let raw = s else { return nil }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4,
              let color = try? Color(hex: parts[0]),
              let dx = Double(parts[1]), let dy = Double(parts[2]), let blur = Double(parts[3]) else {
            return nil
        }
        return Shadow(color: color, offsetX: dx, offsetY: dy, blur: blur)
    }

    /// Reads optional `shadow` from args and attaches it to the just-created layer.
    private static func applyShadowArg(_ args: JSONValue, doc: inout Document, layerId: String?) throws {
        guard let id = layerId, let shadow = parseShadow(args.objectValue?["shadow"]?.stringValue) else { return }
        _ = try CommandEngine.apply(
            .setShadow(pageId: args.objectValue?["page"]?.stringValue, id: id, shadow: shadow),
            to: &doc)
    }

    private static func strokeFromArgs(_ args: JSONValue) throws -> Stroke? {
        guard let s = args.objectValue?["stroke"]?.stringValue else { return nil }
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let c = try? Color(hex: parts[0]), let w = Double(parts[1]) else {
            throw EditorError.usage("`stroke` expects 'color,width'")
        }
        return Stroke(color: c, width: w)
    }

    private static func gradientSchema() -> [String: JSONValue] {
        [
            "project": stringSchema("Path to .aiproj"),
            "type": stringSchema("linear or radial (default linear)"),
            "stops": .object([
                "type": .string("array"),
                "description": .string("Color stops. Each entry: {\"color\": \"#RRGGBB\", \"at\": 0..1}."),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "color": stringSchema("#RRGGBB or #RRGGBBAA"),
                        "at": numberSchema("0..1"),
                    ]),
                    "required": .array([.string("color"), .string("at")]),
                ]),
            ]),
            "start": stringSchema("\"x,y\" normalized 0..1 (default 0,0)"),
            "end": stringSchema("\"x,y\" normalized 0..1 (default 0,1)"),
            "corner_radius": numberSchema(),
            "frame": stringSchema("\"x,y,w,h\""),
            "at": stringSchema(),
            "size": stringSchema(),
            "z": numberSchema(),
            "id": stringSchema(),
            "shadow": shadowProp,
            "corner_radius": cornerRadiusProp,
        ]
    }

    private static func blurSchema() -> [String: JSONValue] {
        [
            "project": stringSchema("Path to .aiproj"),
            "radius": numberSchema("Gaussian blur radius in px (default 24). Ignored when `stops` is set."),
            "corner_radius": numberSchema("Rounded-corner mask radius."),
            "tint": stringSchema("Optional #RRGGBBAA tint overlay drawn on top of the blur."),
            "stops": .object([
                "type": .string("array"),
                "description": .string("Variable-radius keypoints. Each entry: {\"radius\": px, \"at\": 0..1}. Two or more entries enable gradient blur."),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "radius": numberSchema("Blur radius at this stop, in canvas pixels."),
                        "at": numberSchema("Normalized position along the gradient (0..1)."),
                    ]),
                    "required": .array([.string("radius"), .string("at")]),
                ]),
            ]),
            "type": stringSchema("Gradient direction for variable blur: linear (default) or radial."),
            "start": stringSchema("\"x,y\" normalized 0..1 — gradient start point. Defaults to 0,0."),
            "end":   stringSchema("\"x,y\" normalized 0..1 — gradient end point. Defaults to 0,1."),
            "frame": stringSchema("\"x,y,w,h\""),
            "at": stringSchema("Anchor token, e.g. \"center\" (this is the top-level frame anchor; the per-stop position is `stops[i].at`)."),
            "size": stringSchema(),
            "z": numberSchema(),
            "id": stringSchema(),
        ]
    }

    /// Parse `stops: [{ radius, at }, ...]` from MCP args. Returns nil if absent or empty.
    private static func blurStopsFromArgs(_ args: JSONValue) throws -> [BlurStop]? {
        guard let raw = args.objectValue?["stops"]?.arrayValue, !raw.isEmpty else { return nil }
        var stops: [BlurStop] = []
        for (i, entry) in raw.enumerated() {
            guard let obj = entry.objectValue else {
                throw EditorError.usage("stop \(i) must be an object")
            }
            guard let r = obj["radius"]?.doubleValue, r >= 0 else {
                throw EditorError.usage("stop \(i) needs a non-negative `radius`")
            }
            let at: Double
            if let v = obj["at"]?.doubleValue { at = v }
            else if raw.count == 1 { at = 0 }
            else { at = Double(i) / Double(raw.count - 1) }
            stops.append(.init(radius: r, at: at))
        }
        return stops
    }

    private static func gradientPayloadFromArgs(_ args: JSONValue) throws -> GradientLayerPayload {
        let typeStr = args.objectValue?["type"]?.stringValue?.lowercased() ?? "linear"
        guard let type = GradientType(rawValue: typeStr) else {
            throw EditorError.usage("`type` must be linear or radial")
        }
        var stops: [GradientStop] = []
        if let raw = args.objectValue?["stops"]?.arrayValue {
            for (i, entry) in raw.enumerated() {
                guard let obj = entry.objectValue,
                      let hex = obj["color"]?.stringValue else {
                    throw EditorError.usage("stop \(i) missing `color`")
                }
                let color = try Color(hex: hex)
                let at: Double
                if let n = obj["at"]?.doubleValue { at = n }
                else if raw.count == 1 { at = 0 }
                else { at = Double(i) / Double(raw.count - 1) }
                stops.append(.init(color: color, at: at))
            }
        }
        if stops.isEmpty {
            stops = [.init(color: .black, at: 0), .init(color: .white, at: 1)]
        }
        let (sx, sy) = try point(args.objectValue?["start"]?.stringValue) ?? (0, 0)
        let (ex, ey) = try point(args.objectValue?["end"]?.stringValue) ?? (0, 1)
        return GradientLayerPayload(type: type, stops: stops,
                                    startX: sx, startY: sy,
                                    endX: ex, endY: ey)
    }

    private static func point(_ s: String?) throws -> (Double, Double)? {
        guard let s = s else { return nil }
        let parts = s.split(whereSeparator: { ",x ".contains($0) }).compactMap { Double($0) }
        guard parts.count == 2 else { throw EditorError.usage("expected 'x,y' got '\(s)'") }
        return (parts[0], parts[1])
    }

    private static func bezelSchema() -> [String: JSONValue] {
        [
            "project": stringSchema("Path to .aiproj"),
            "device": stringSchema("Device id (see list_bezels)."),
            "color": stringSchema("Color variant label (see list_bezels). Default = device default."),
            "screenshot_asset": stringSchema("Existing asset id."),
            "screenshot_path": stringSchema("File path to import + use."),
            "chrome_color": stringSchema("#RRGGBB override (programmatic bezels only)."),
            "frame": stringSchema("\"x,y,w,h\""),
            "at": stringSchema(),
            "height": numberSchema("Outer height; width is derived from device aspect."),
            "z": numberSchema(),
            "id": stringSchema(),
            "shadow": shadowProp,
            "corner_radius": cornerRadiusProp,
        ]
    }

    // MARK: - Argument helpers

    private static func requireString(_ args: JSONValue, _ key: String) throws -> String {
        guard let s = args.objectValue?[key]?.stringValue else {
            throw EditorError.usage("missing `\(key)`")
        }
        return s
    }
    private static func requireInt(_ args: JSONValue, _ key: String) throws -> Int {
        guard let n = args.objectValue?[key]?.intValue else { throw EditorError.usage("missing `\(key)`") }
        return n
    }
    private static func requireDouble(_ args: JSONValue, _ key: String) throws -> Double {
        guard let n = args.objectValue?[key]?.doubleValue else { throw EditorError.usage("missing `\(key)`") }
        return n
    }

    private static func frameFromArgs(args: JSONValue, canvas: Canvas, defaultSize: (Double, Double)) throws -> Frame {
        if let s = args.objectValue?["frame"]?.stringValue {
            return try Frame.parse(s)
        }
        var size = defaultSize
        if let s = args.objectValue?["size"]?.stringValue {
            let parts = s.split(whereSeparator: { ",x ".contains($0) }).compactMap { Double($0) }
            if parts.count == 2 { size = (parts[0], parts[1]) }
        }
        let token = args.objectValue?["at"]?.stringValue ?? "center"
        let anchor = AnchorPosition(token: token) ?? .center
        return anchor.frame(layerSize: size, canvas: canvas)
    }

    private static func shapePayloadFromArgs(_ args: JSONValue, ellipse: Bool) throws -> ShapeLayerPayload {
        let fill: Color = try (args.objectValue?["fill"]?.stringValue).map { try Color(hex: $0) } ?? .white
        var stroke: Stroke? = nil
        if let s = args.objectValue?["stroke"]?.stringValue {
            let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let c = try? Color(hex: parts[0]), let w = Double(parts[1]) else {
                throw EditorError.usage("`stroke` expects 'color,width'")
            }
            stroke = Stroke(color: c, width: w)
        }
        return ShapeLayerPayload(fill: fill, stroke: stroke)
    }

    /// `radius` is the legacy `add_rect` alias for `corner_radius`. After-add helper applies
    /// whichever was supplied as the layer-level cornerRadius.
    private static func applyCornerRadiusArg(_ args: JSONValue, doc: inout Document,
                                             layerId: String?,
                                             aliases: [String] = []) throws {
        guard let id = layerId else { return }
        var value: Double? = args.objectValue?["corner_radius"]?.doubleValue
        if value == nil {
            for k in aliases {
                if let v = args.objectValue?[k]?.doubleValue { value = v; break }
            }
        }
        guard let radius = value, radius > 0 else { return }
        _ = try CommandEngine.apply(
            .setCornerRadius(pageId: args.objectValue?["page"]?.stringValue, id: id, value: radius),
            to: &doc)
    }

    // MARK: - Mutate helpers

    private static func mutate(_ args: JSONValue, _ body: (inout Document) throws -> Void) throws -> JSONValue {
        let path = try requireString(args, "project")
        let url = URL(fileURLWithPath: path)
        var doc = try DocumentCodec.load(from: url)
        try body(&doc)
        try DocumentCodec.save(doc, to: url)
        return textResult("ok")
    }

    private static func mutateReturnId(_ args: JSONValue, _ body: (inout Document) throws -> EditorCommandResult) throws -> JSONValue {
        let path = try requireString(args, "project")
        let url = URL(fileURLWithPath: path)
        var doc = try DocumentCodec.load(from: url)
        let r = try body(&doc)
        try DocumentCodec.save(doc, to: url)
        return textResult(r.newLayerId ?? r.message)
    }
}

enum CLIHelpers {
    static func autoAssetId(in doc: Document, path: String) -> String {
        let stem = (path as NSString).lastPathComponent.replacingOccurrences(of: " ", with: "_")
        var base = (stem as NSString).deletingPathExtension
        if base.isEmpty { base = "asset" }
        if doc.assets[base] == nil { return base }
        var i = 2
        while doc.assets["\(base)-\(i)"] != nil { i += 1 }
        return "\(base)-\(i)"
    }
}

enum MCPHelpers {
    /// Read the asset's pixel dimensions and downscale uniformly so neither side exceeds the
    /// canvas. Returns the canvas-relative fallback if the asset can't be loaded.
    static func naturalImageDefaultSize(assetPath: String?, projectURL: URL, canvas: Canvas) -> (Double, Double) {
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
}

// MARK: - Result helpers

func textResult(_ text: String) -> JSONValue {
    .object([
        "content": .array([
            .object(["type": .string("text"), "text": .string(text)])
        ])
    ])
}

func imageResult(message: String, data: Data) -> JSONValue {
    let b64 = data.base64EncodedString()
    return .object([
        "content": .array([
            .object(["type": .string("text"), "text": .string(message)]),
            .object([
                "type": .string("image"),
                "data": .string(b64),
                "mimeType": .string("image/png"),
            ]),
        ])
    ])
}

func errorResult(_ message: String) -> JSONValue {
    .object([
        "content": .array([
            .object(["type": .string("text"), "text": .string("error: " + message)])
        ]),
        "isError": .bool(true),
    ])
}

// MARK: - JSONValue pretty
extension JSONValue {
    var pretty: String {
        (try? JSONSerialization.data(withJSONObject: self.anyObject,
                                     options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
