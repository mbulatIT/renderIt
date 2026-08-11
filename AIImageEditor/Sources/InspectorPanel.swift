import SwiftUI
import AppKit
import AIImageEditorCore

struct InspectorPanel: View {
    @ObservedObject var document: ProjectDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch document.selectedLayerIds.count {
                case 0:
                    pageSection
                case 1:
                    if let id = document.selectedLayerIds.first,
                       let layer = lookupLayer(id) {
                        layerSection(layer: layer)
                    } else {
                        pageSection
                    }
                default:
                    multiSelectionSummary
                }
            }
            .padding(12)
        }
    }

    /// Recursive layer lookup (top-level OR nested in any group's children).
    private func lookupLayer(_ id: String) -> Layer? {
        func search(_ layers: [Layer]) -> Layer? {
            for l in layers {
                if l.id == id { return l }
                if case .group(let g) = l.payload, let f = search(g.children) { return f }
            }
            return nil
        }
        return search(document.selectedPage.layers)
    }

    /// Hint panel shown when more than one layer is selected. Most editing actions are routed
    /// through the layer-list context menu or canvas gestures while multi-selected.
    private var multiSelectionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(document.selectedLayerIds.count) layers selected")
                .font(.title3)
            Text("Drag any selected layer on the canvas to move them together. Right-click in the layer list to group, duplicate, or delete the selection.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("Clear selection") { document.selectedLayerIds = [] }
        }
    }

    private var pageId: String { document.selectedPageId }

    // MARK: - Page settings

    private var pageSection: some View {
        let page = document.selectedPage
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Page").font(.title3)
                Spacer()
                Text(page.id).font(.caption2).foregroundStyle(.tertiary).monospaced()
            }
            HStack {
                Text("Name")
                TextField("", text: Binding(
                    get: { page.name },
                    set: { document.mutate(.renamePage(id: page.id, name: $0)) }))
            }

            Divider()
            Text("Work area").font(.headline)
            Text("\(page.canvas.width) × \(page.canvas.height) px (derived from previews)")
                .font(.caption).foregroundStyle(.secondary)
                .monospaced()
            colorRow("Background (gaps)", color: Binding(
                get: { page.canvas.background },
                set: { document.mutate(.setBackground(pageId: pageId, color: $0)) }))

            Divider()
            Text("Previews").font(.headline)
            Text("Each preview is an export viewport. Exporting writes one PNG per preview.")
                .font(.caption2).foregroundStyle(.secondary)

            HStack {
                Text("Count")
                Stepper(value: Binding(
                    get: { page.previews.count },
                    set: { v in document.mutate(.setPreviewCount(pageId: pageId, count: max(0, v))) }),
                        in: 0...30) {
                    Text("\(page.previews.count)").monospacedDigit()
                }
            }
            HStack {
                Text("Spacing")
                CommitDoubleField(title: "", value: Binding(
                    get: { page.layout.spacing },
                    set: { v in document.mutate(.setPreviewSpacing(pageId: pageId, spacing: v)) }))
            }
            HStack {
                Text("Preview W × H")
                CommitDoubleField(title: "w", value: Binding(
                    get: { page.layout.previewWidth },
                    set: { v in
                        document.mutate(.setPreviewSize(pageId: pageId,
                                                        width: v > 0 ? v : page.layout.previewWidth,
                                                        height: page.layout.previewHeight))
                    }))
                CommitDoubleField(title: "h", value: Binding(
                    get: { page.layout.previewHeight },
                    set: { v in
                        document.mutate(.setPreviewSize(pageId: pageId,
                                                        width: page.layout.previewWidth,
                                                        height: v > 0 ? v : page.layout.previewHeight))
                    }))
            }
            Picker("Preset", selection: Binding<String>(
                get: { "" },
                set: { id in
                    if let p = PresetCatalog.find(id: id) {
                        document.mutate(.setPreviewSize(pageId: pageId,
                                                        width: Double(p.width),
                                                        height: Double(p.height)))
                    }
                })) {
                Text("Choose preview size…").tag("")
                ForEach(PresetCatalog.all, id: \.id) { Text($0.title).tag($0.id) }
            }

            // Per-preview list with rename + per-preview background.
            if !page.previews.isEmpty {
                Divider()
                Text("Per-preview overrides").font(.subheadline)
                ForEach(page.previews, id: \.id) { preview in
                    HStack(spacing: 6) {
                        TextField("name", text: Binding(
                            get: { preview.name },
                            set: { document.mutate(.renamePreview(pageId: pageId, id: preview.id, name: $0)) }))
                            .textFieldStyle(.roundedBorder)
                        ColorPicker("", selection: Binding(
                            get: {
                                let c = preview.background
                                return SwiftUI.Color(red: c.r, green: c.g, blue: c.b, opacity: c.a)
                            },
                            set: { swui in
                                let ns = NSColor(swui).usingColorSpace(.sRGB) ?? .white
                                let c = AIImageEditorCore.Color(
                                    r: Double(ns.redComponent),
                                    g: Double(ns.greenComponent),
                                    b: Double(ns.blueComponent),
                                    a: Double(ns.alphaComponent))
                                document.mutate(.setPreviewBackground(pageId: pageId, id: preview.id, color: c))
                            }), supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 36)
                        Button(role: .destructive) {
                            document.mutate(.removePreview(pageId: pageId, id: preview.id))
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    // MARK: - Layer

    @ViewBuilder
    private func layerSection(layer: Layer) -> some View {
        // Editable name — works for any layer, including groups. Commits on Enter / focus loss.
        CommitTextField(title: "Name", value: Binding(
            get: { layer.name },
            set: { document.mutate(.rename(pageId: pageId, id: layer.id, name: $0)) }))
            .font(.title3)
            .textFieldStyle(.roundedBorder)
        Text(layer.kind.rawValue).font(.caption).foregroundStyle(.secondary)
        Divider()
        Group {
            frameSection(layer: layer)
            commonSection(layer: layer)
            switch layer.payload {
            case .text(let p): textSection(layer: layer, payload: p)
            case .rect(let p): shapeSection(layer: layer, payload: p, ellipse: false)
            case .ellipse(let p): shapeSection(layer: layer, payload: p, ellipse: true)
            case .image: imageSection(layer: layer)
            case .deviceBezel(let p): bezelSection(layer: layer, payload: p)
            case .gradient(let p): gradientSection(layer: layer, payload: p)
            case .blur(let p): blurSection(layer: layer, payload: p)
            case .line(let p): lineSection(layer: layer, payload: p)
            case .polygon(let p): polygonSection(layer: layer, payload: p)
            case .star(let p): starSection(layer: layer, payload: p)
            case .group(let p): groupSection(layer: layer, payload: p)
            }
            // Layer-level gradient fill (turns the layer into a gradient-filled version of itself).
            if gradientFillApplies(layer) {
                layerGradientSection(layer: layer)
            }
            // Background fill (solid or gradient) drawn behind the layer's main content.
            if layerBackgroundApplies(layer) {
                layerBackgroundSection(layer: layer)
            }
            // Shadow applies to every kind except blur (which samples, doesn't draw).
            if case .blur = layer.payload {} else {
                shadowSection(layer: layer)
            }
        }
    }

    @ViewBuilder
    private func frameSection(layer: Layer) -> some View {
        Text("Frame").font(.headline)
        HStack {
            stepperDouble("X", value: Binding(
                get: { layer.frame.x },
                set: { setFrame(layer: layer, change: { $0.x = $1 }, to: $0) }))
            stepperDouble("Y", value: Binding(
                get: { layer.frame.y },
                set: { setFrame(layer: layer, change: { $0.y = $1 }, to: $0) }))
        }
        // For device bezels we link W and H so they're never editable off-aspect.
        let aspect = bezelAspect(layer: layer)
        HStack {
            stepperDouble("W", value: Binding(
                get: { layer.frame.w },
                set: { newW in
                    var f = layer.frame
                    f.w = newW
                    if let a = aspect, a > 0 { f.h = newW / a }
                    document.mutate(.setFrame(pageId: pageId, id: layer.id, frame: f))
                }))
            stepperDouble("H", value: Binding(
                get: { layer.frame.h },
                set: { newH in
                    var f = layer.frame
                    f.h = newH
                    if let a = aspect, a > 0 { f.w = newH * a }
                    document.mutate(.setFrame(pageId: pageId, id: layer.id, frame: f))
                }))
        }
        if aspect != nil {
            Text("Aspect ratio is locked to the device. Resizing one dimension updates the other.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Returns the device aspect (w/h) for a device-bezel layer, or nil for everything else.
    private func bezelAspect(layer: Layer) -> Double? {
        guard case .deviceBezel(let p) = layer.payload,
              let bezel = DeviceBezelCatalog.find(id: p.device) else { return nil }
        return bezel.aspect
    }

    @ViewBuilder
    private func commonSection(layer: Layer) -> some View {
        Divider()
        CommitSlider(title: "Rotation",
                     value: Binding(
                        get: { layer.rotation },
                        set: { document.mutate(.rotate(pageId: pageId, id: layer.id, degrees: $0)) }),
                     range: -180...180)
        CommitSlider(title: "Opacity",
                     value: Binding(
                        get: { layer.opacity * 100 },
                        set: { document.mutate(.setOpacity(pageId: pageId, id: layer.id, value: max(0, min(1, $0 / 100)))) }),
                     range: 0...100)
        // Corner radius: applies to any layer where it makes sense. Skipped for ellipse (already
        // curved) and deviceBezel (defines its own shape).
        if cornerRadiusApplies(layer) {
            let maxRadius = max(64, min(layer.frame.w, layer.frame.h) / 2)
            CommitSlider(title: "Corner radius",
                         value: Binding(
                            get: { layer.cornerRadius },
                            set: { document.mutate(.setCornerRadius(pageId: pageId, id: layer.id, value: max(0, $0))) }),
                         range: 0...maxRadius)
            if layer.cornerRadius > 0 {
                Picker("Corner style", selection: Binding(
                    get: { layer.cornerStyle },
                    set: { document.mutate(.setCornerStyle(pageId: pageId, id: layer.id, style: $0)) }
                )) {
                    ForEach(CornerStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                cornerSelector(layer: layer)
            }
        }
        HStack {
            Text("Z")
            CommitDoubleField(title: "", value: Binding(
                get: { layer.zIndex },
                set: { document.mutate(.setZIndex(pageId: pageId, id: layer.id, value: $0)) }))
        }
        HStack {
            Button("Front")   { document.mutate(.bringToFront(pageId: pageId, id: layer.id)) }
            Button("Forward") { document.mutate(.moveForward(pageId: pageId, id: layer.id)) }
            Button("Back")    { document.mutate(.moveBackward(pageId: pageId, id: layer.id)) }
            Button("Bottom")  { document.mutate(.sendToBack(pageId: pageId, id: layer.id)) }
        }
    }

    private func cornerRadiusApplies(_ layer: Layer) -> Bool {
        switch layer.payload {
        case .ellipse, .deviceBezel: return false
        default: return true
        }
    }

    /// 2×2 grid of toggles letting the user pick which corners the radius rounds, plus All/None.
    @ViewBuilder
    private func cornerSelector(layer: Layer) -> some View {
        let c = layer.roundedCorners
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Rounded corners").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("All")  { setCorners(layer, .all) }.buttonStyle(.borderless).font(.caption)
                Button("None") { setCorners(layer, []) }.buttonStyle(.borderless).font(.caption)
            }
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    cornerToggle(layer, .topLeft,     "TL", c.contains(.topLeft))
                    cornerToggle(layer, .topRight,    "TR", c.contains(.topRight))
                }
                HStack(spacing: 4) {
                    cornerToggle(layer, .bottomLeft,  "BL", c.contains(.bottomLeft))
                    cornerToggle(layer, .bottomRight, "BR", c.contains(.bottomRight))
                }
            }
        }
    }

    private func cornerToggle(_ layer: Layer, _ corner: RectCorners, _ label: String, _ on: Bool) -> some View {
        Button {
            var next = layer.roundedCorners
            if on { next.remove(corner) } else { next.insert(corner) }
            setCorners(layer, next)
        } label: {
            Text(label)
                .font(.caption).monospaced()
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(on ? Color.accentColor.opacity(0.75) : Color.gray.opacity(0.18))
                .foregroundStyle(on ? Color.white : Color.primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func setCorners(_ layer: Layer, _ corners: RectCorners) {
        document.mutate(.setRoundedCorners(pageId: pageId, id: layer.id, corners: corners))
    }

    @ViewBuilder
    private func textSection(layer: Layer, payload: TextLayerPayload) -> some View {
        Divider()
        Text("Text").font(.headline)
        TextEditor(text: Binding(
            get: { payload.text },
            set: { document.mutate(.setText(pageId: pageId, id: layer.id, text: $0)) }))
            .frame(minHeight: 80)
            .border(Color.gray.opacity(0.3))
        HStack {
            Text("Font")
            Picker("", selection: Binding(
                get: { payload.font },
                set: { document.mutate(.setFont(pageId: pageId, id: layer.id, family: $0, size: nil, weight: nil, italic: nil)) }
            )) {
                ForEach(FontCatalog.availableFamilies().prefix(60), id: \.self) { f in Text(f).tag(f) }
            }
            .labelsHidden()
        }
        HStack {
            Text("Size")
            CommitDoubleField(title: "", value: Binding(
                get: { payload.fontSize },
                set: { document.mutate(.setFont(pageId: pageId, id: layer.id, family: nil, size: $0, weight: nil, italic: nil)) }))
            Picker("Weight", selection: Binding(
                get: { payload.fontWeight },
                set: { document.mutate(.setFont(pageId: pageId, id: layer.id, family: nil, size: nil, weight: $0, italic: nil)) }
            )) {
                ForEach(FontWeight.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
        }
        Toggle("Italic", isOn: Binding(
            get: { payload.italic },
            set: { document.mutate(.setFont(pageId: pageId, id: layer.id, family: nil, size: nil, weight: nil, italic: $0)) }))
        colorRow("Color", color: Binding(
            get: { payload.color },
            set: { document.mutate(.setColor(pageId: pageId, id: layer.id, color: $0)) }))
        Picker("Align", selection: Binding(
            get: { payload.alignment },
            set: { document.mutate(.setAlignment(pageId: pageId, id: layer.id, alignment: $0)) }
        )) {
            ForEach(TextAlignment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
    }

    @ViewBuilder
    private func shapeSection(layer: Layer, payload: ShapeLayerPayload, ellipse: Bool) -> some View {
        Divider()
        colorRow("Fill", color: Binding(
            get: { payload.fill },
            set: { document.mutate(.setColor(pageId: pageId, id: layer.id, color: $0)) }))
    }

    @ViewBuilder
    private func imageSection(layer: Layer) -> some View {
        Divider()
        Text("Image layer").font(.headline)
        if case .image(let p) = layer.payload {
            Text("Asset: \(p.assetId)").font(.caption)
        }
    }

    @ViewBuilder
    private func groupSection(layer: Layer, payload: GroupPayload) -> some View {
        Divider()
        Text("Group").font(.headline)
        Toggle("Crop children to bounds", isOn: Binding(
            get: { payload.clipsToBounds },
            set: { document.mutate(.setGroupClipsToBounds(pageId: pageId, id: layer.id, value: $0)) }))
        Text("Clips everything inside the group to its frame — crops rotated children, overflowing text and images, and shadows. Set a Corner radius above for a rounded crop.")
            .font(.caption2).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func bezelSection(layer: Layer, payload: DeviceBezelPayload) -> some View {
        Divider()
        Text("Device bezel").font(.headline)
        if let device = DeviceBezelCatalog.find(id: payload.device) {
            Text(device.title).font(.caption)
            if !device.colors.isEmpty {
                Picker("Color", selection: Binding(
                    get: { payload.color ?? deviceDefaultColor(device: device) },
                    set: { newColor in
                        document.mutate(.setBezelColor(pageId: pageId, id: layer.id, color: newColor))
                    }
                )) {
                    ForEach(device.colors, id: \.self) { c in Text(c).tag(c) }
                }
            }
        } else {
            Text(payload.device).font(.caption)
        }

        Divider()
        Text("Screenshot").font(.headline)
        screenshotPreview(layer: layer, payload: payload)
        HStack {
            Button(payload.screenshotAssetId == nil ? "Choose…" : "Replace…") {
                pickScreenshot(for: layer)
            }
            if payload.screenshotAssetId != nil {
                Button(role: .destructive) {
                    document.mutate(.setBezelScreenshot(pageId: pageId, id: layer.id, assetId: nil))
                } label: { Text("Remove") }
            }
            Spacer()
        }
        Text("Drag an image onto the canvas to drop it into this bezel.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func screenshotPreview(layer: Layer, payload: DeviceBezelPayload) -> some View {
        if let assetId = payload.screenshotAssetId,
           let nsImage = loadAssetThumbnail(assetId: assetId) {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 120)
                    .background(Color.black)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(assetId).font(.caption).monospaced()
                    if let path = document.document.assets[assetId]?.path {
                        Text((path as NSString).lastPathComponent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        } else {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, height: 120)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4])))
                Text("No screenshot yet").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func pickScreenshot(for layer: Layer) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as screenshot"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        attachScreenshot(layerId: layer.id, fileURL: url)
    }

    /// Registers the given file as an asset and assigns it to the named bezel layer.
    /// Made internal so the CanvasView drag-and-drop handler can call into it.
    func attachScreenshot(layerId: String, fileURL: URL) {
        // Pick / reuse an asset id.
        let assetId = ProjectAssetHelper.autoAssetId(in: document.document, path: fileURL.path)
        if document.document.assets[assetId] == nil {
            _ = document.mutate(.addAsset(id: assetId, path: fileURL.path))
        }
        document.mutate(.setBezelScreenshot(pageId: pageId, id: layerId, assetId: assetId))
    }

    private func loadAssetThumbnail(assetId: String) -> NSImage? {
        guard let asset = document.document.assets[assetId] else { return nil }
        let url: URL
        if (asset.path as NSString).isAbsolutePath {
            url = URL(fileURLWithPath: asset.path)
        } else {
            // Relative paths aren't routable here without the project URL; just bail.
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func deviceDefaultColor(device: DeviceBezel) -> String {
        // Mirror BezelImageStore's preferred order.
        let preferred = ["Silver", "White", "Cloud white", "Light gold", "Sage", "Lavender",
                         "Mist blue", "Sky blue", "Deep blue", "Space grey", "Space black",
                         "Black", "Cosmic orange", "Default"]
        return preferred.first(where: { device.colors.contains($0) }) ?? device.colors.first ?? "Default"
    }

    // MARK: - Helpers

    private func setFrame(layer: Layer, change: (inout Frame, Double) -> Void, to value: Double) {
        var f = layer.frame
        change(&f, value)
        document.mutate(.setFrame(pageId: pageId, id: layer.id, frame: f))
    }

    private func stepperInt(_ label: String, value: Binding<Int>) -> some View {
        HStack { Text(label); CommitIntField(title: "", value: value) }
    }
    private func stepperDouble(_ label: String, value: Binding<Double>) -> some View {
        HStack { Text(label); CommitDoubleField(title: "", value: value) }
    }

    private func colorRow(_ label: String, color: Binding<AIImageEditorCore.Color>) -> some View {
        HStack {
            Text(label)
            ColorPicker("", selection: Binding(
                get: {
                    let c = color.wrappedValue
                    return SwiftUI.Color(red: c.r, green: c.g, blue: c.b, opacity: c.a)
                },
                set: { swui in
                    let ns = NSColor(swui).usingColorSpace(.sRGB) ?? .white
                    color.wrappedValue = AIImageEditorCore.Color(
                        r: Double(ns.redComponent),
                        g: Double(ns.greenComponent),
                        b: Double(ns.blueComponent),
                        a: Double(ns.alphaComponent))
                }
            ), supportsOpacity: true)
            .labelsHidden()
            Text(color.wrappedValue.hex).font(.caption).monospaced()
        }
    }

    // MARK: - Layer-level gradient fill

    private func gradientFillApplies(_ layer: Layer) -> Bool {
        switch layer.payload {
        case .blur, .deviceBezel, .gradient: return false
        default: return true
        }
    }

    @ViewBuilder
    private func layerGradientSection(layer: Layer) -> some View {
        Divider()
        HStack {
            Text("Gradient fill").font(.headline)
            Spacer()
            Toggle("", isOn: Binding(
                get: { layer.gradient != nil },
                set: { on in
                    let next: GradientLayerPayload? = on
                        ? (layer.gradient ?? GradientLayerPayload(
                            type: .linear,
                            stops: [.init(color: AIImageEditorCore.Color(r: 1, g: 0.42, b: 0.38), at: 0),
                                    .init(color: AIImageEditorCore.Color(r: 0.45, g: 0.38, b: 1),  at: 1)],
                            startX: 0, startY: 0, endX: 1, endY: 1))
                        : nil
                    document.mutate(.setLayerGradient(pageId: pageId, id: layer.id, gradient: next))
                }))
            .labelsHidden()
        }
        if let g = layer.gradient {
            Picker("Type", selection: Binding(
                get: { g.type },
                set: { newType in
                    var copy = g; copy.type = newType
                    document.mutate(.setLayerGradient(pageId: pageId, id: layer.id, gradient: copy))
                }
            )) {
                ForEach(GradientType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Text("Start")
                stepperDouble("x", value: Binding(
                    get: { g.startX },
                    set: { v in
                        var copy = g; copy.startX = v
                        document.mutate(.setLayerGradient(pageId: pageId, id: layer.id, gradient: copy))
                    }))
                stepperDouble("y", value: Binding(
                    get: { g.startY },
                    set: { v in
                        var copy = g; copy.startY = v
                        document.mutate(.setLayerGradient(pageId: pageId, id: layer.id, gradient: copy))
                    }))
            }
            HStack {
                Text("End  ")
                stepperDouble("x", value: Binding(
                    get: { g.endX },
                    set: { v in
                        var copy = g; copy.endX = v
                        document.mutate(.setLayerGradient(pageId: pageId, id: layer.id, gradient: copy))
                    }))
                stepperDouble("y", value: Binding(
                    get: { g.endY },
                    set: { v in
                        var copy = g; copy.endY = v
                        document.mutate(.setLayerGradient(pageId: pageId, id: layer.id, gradient: copy))
                    }))
            }
            ForEach(Array(g.stops.enumerated()), id: \.offset) { idx, stop in
                HStack(spacing: 6) {
                    ColorPicker("", selection: Binding(
                        get: {
                            SwiftUI.Color(red: stop.color.r, green: stop.color.g, blue: stop.color.b, opacity: stop.color.a)
                        },
                        set: { swui in
                            let ns = NSColor(swui).usingColorSpace(.sRGB) ?? .white
                            var copy = g
                            copy.stops[idx].color = AIImageEditorCore.Color(
                                r: Double(ns.redComponent),
                                g: Double(ns.greenComponent),
                                b: Double(ns.blueComponent),
                                a: Double(ns.alphaComponent))
                            document.mutate(.setLayerGradient(pageId: pageId, id: layer.id, gradient: copy))
                        }), supportsOpacity: true)
                        .labelsHidden()
                        .frame(width: 36)
                    CommitDoubleField(title: "at", value: Binding(
                        get: { stop.at },
                        set: { v in
                            var copy = g
                            copy.stops[idx].at = max(0, min(1, v))
                            document.mutate(.setLayerGradient(pageId: pageId, id: layer.id, gradient: copy))
                        }), fractionDigits: 2)
                        .frame(width: 60)
                    Button(role: .destructive) {
                        guard g.stops.count > 2 else { return }
                        var copy = g
                        copy.stops.remove(at: idx)
                        document.mutate(.setLayerGradient(pageId: pageId, id: layer.id, gradient: copy))
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .disabled(g.stops.count <= 2)
                }
            }
            Button {
                var copy = g
                let lastAt = copy.stops.last?.at ?? 1
                copy.stops.append(.init(color: .white, at: min(1, lastAt + 0.1)))
                document.mutate(.setLayerGradient(pageId: pageId, id: layer.id, gradient: copy))
            } label: { Label("Add stop", systemImage: "plus") }
            .buttonStyle(.borderless)
            Text("The gradient is masked by this layer's drawn pixels — gradient text, gradient shapes, etc.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Layer background

    /// True for layer kinds where a layer-level background fill is meaningful. Blur samples
    /// existing pixels so a background would just be overdrawn; deviceBezel defines its own
    /// fill (chrome + screenshot).
    private func layerBackgroundApplies(_ layer: Layer) -> Bool {
        switch layer.payload {
        case .blur, .deviceBezel: return false
        default: return true
        }
    }

    @ViewBuilder
    private func layerBackgroundSection(layer: Layer) -> some View {
        Divider()
        HStack {
            Text("Background").font(.headline)
            Spacer()
            Picker("", selection: Binding(
                get: { backgroundMode(for: layer) },
                set: { applyBackgroundMode($0, layer: layer) }
            )) {
                Text("None").tag(BackgroundMode.none)
                Text("Color").tag(BackgroundMode.color)
                Text("Gradient").tag(BackgroundMode.gradient)
            }
            .labelsHidden()
            .frame(width: 140)
        }
        switch layer.background {
        case .none:
            EmptyView()
        case .color(let c):
            colorRow("Fill", color: Binding(
                get: { c },
                set: { newC in
                    document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: .color(newC)))
                }))
        case .gradient(let g):
            Picker("Type", selection: Binding(
                get: { g.type },
                set: { newType in
                    var copy = g; copy.type = newType
                    document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: .gradient(copy)))
                }
            )) {
                ForEach(GradientType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                stepperDouble("sx", value: Binding(
                    get: { g.startX },
                    set: { v in
                        var copy = g; copy.startX = v
                        document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: .gradient(copy)))
                    }))
                stepperDouble("sy", value: Binding(
                    get: { g.startY },
                    set: { v in
                        var copy = g; copy.startY = v
                        document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: .gradient(copy)))
                    }))
                stepperDouble("ex", value: Binding(
                    get: { g.endX },
                    set: { v in
                        var copy = g; copy.endX = v
                        document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: .gradient(copy)))
                    }))
                stepperDouble("ey", value: Binding(
                    get: { g.endY },
                    set: { v in
                        var copy = g; copy.endY = v
                        document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: .gradient(copy)))
                    }))
            }
            ForEach(Array(g.stops.enumerated()), id: \.offset) { idx, stop in
                HStack(spacing: 6) {
                    ColorPicker("", selection: Binding(
                        get: { SwiftUI.Color(red: stop.color.r, green: stop.color.g, blue: stop.color.b, opacity: stop.color.a) },
                        set: { swui in
                            let ns = NSColor(swui).usingColorSpace(.sRGB) ?? .white
                            var copy = g
                            copy.stops[idx].color = AIImageEditorCore.Color(
                                r: Double(ns.redComponent), g: Double(ns.greenComponent),
                                b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
                            document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: .gradient(copy)))
                        }), supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 36)
                    CommitDoubleField(title: "at", value: Binding(
                        get: { stop.at },
                        set: { v in
                            var copy = g; copy.stops[idx].at = max(0, min(1, v))
                            document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: .gradient(copy)))
                        }), fractionDigits: 2)
                    .frame(width: 60)
                    Button(role: .destructive) {
                        guard g.stops.count > 2 else { return }
                        var copy = g
                        copy.stops.remove(at: idx)
                        document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: .gradient(copy)))
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .disabled(g.stops.count <= 2)
                }
            }
            Button {
                var copy = g
                let lastAt = copy.stops.last?.at ?? 1
                copy.stops.append(.init(color: .white, at: min(1, lastAt + 0.1)))
                document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: .gradient(copy)))
            } label: { Label("Add stop", systemImage: "plus") }
            .buttonStyle(.borderless)
        }
    }

    private enum BackgroundMode { case none, color, gradient }

    private func backgroundMode(for layer: Layer) -> BackgroundMode {
        switch layer.background {
        case .none: return .none
        case .color: return .color
        case .gradient: return .gradient
        }
    }

    private func applyBackgroundMode(_ mode: BackgroundMode, layer: Layer) {
        let new: LayerBackground?
        switch mode {
        case .none:
            new = nil
        case .color:
            // Reuse the layer's existing gradient first stop if upgrading from a gradient,
            // else default to a translucent neutral.
            if case .gradient(let g) = layer.background, let first = g.stops.first {
                new = .color(first.color)
            } else if case .color = layer.background {
                return  // already a color
            } else {
                new = .color(AIImageEditorCore.Color(r: 0.1, g: 0.12, b: 0.18, a: 0.85))
            }
        case .gradient:
            if case .gradient = layer.background { return }
            let stops: [GradientStop]
            if case .color(let c) = layer.background {
                // Seed the gradient with the previous solid colour fading to white.
                stops = [.init(color: c, at: 0), .init(color: .white, at: 1)]
            } else {
                stops = [.init(color: AIImageEditorCore.Color(r: 1, g: 0.42, b: 0.38), at: 0),
                         .init(color: AIImageEditorCore.Color(r: 0.45, g: 0.38, b: 1),  at: 1)]
            }
            new = .gradient(GradientLayerPayload(
                type: .linear, stops: stops,
                startX: 0, startY: 0, endX: 1, endY: 1))
        }
        document.mutate(.setLayerBackground(pageId: pageId, id: layer.id, background: new))
    }

    // MARK: - Shadow

    @ViewBuilder
    private func shadowSection(layer: Layer) -> some View {
        Divider()
        HStack {
            Text("Shadow").font(.headline)
            Spacer()
            Toggle("", isOn: Binding(
                get: { layer.shadow != nil },
                set: { on in
                    let next: Shadow? = on
                        ? (layer.shadow ?? Shadow(color: AIImageEditorCore.Color(r: 0, g: 0, b: 0, a: 0.45),
                                                  offsetX: 0, offsetY: 8, blur: 24))
                        : nil
                    document.mutate(.setShadow(pageId: pageId, id: layer.id, shadow: next))
                }))
            .labelsHidden()
        }
        if let s = layer.shadow {
            colorRow("Color", color: Binding(
                get: { s.color },
                set: { c in
                    var sh = s; sh.color = c
                    document.mutate(.setShadow(pageId: pageId, id: layer.id, shadow: sh))
                }))
            HStack {
                stepperDouble("dx", value: Binding(
                    get: { s.offsetX },
                    set: { v in
                        var sh = s; sh.offsetX = v
                        document.mutate(.setShadow(pageId: pageId, id: layer.id, shadow: sh))
                    }))
                stepperDouble("dy", value: Binding(
                    get: { s.offsetY },
                    set: { v in
                        var sh = s; sh.offsetY = v
                        document.mutate(.setShadow(pageId: pageId, id: layer.id, shadow: sh))
                    }))
            }
            CommitSlider(title: "Blur",
                         value: Binding(
                            get: { s.blur },
                            set: { v in
                                var sh = s; sh.blur = max(0, v)
                                document.mutate(.setShadow(pageId: pageId, id: layer.id, shadow: sh))
                            }),
                         range: 0...120)
        }
    }

    // MARK: - Line / Polygon / Star

    @ViewBuilder
    private func lineSection(layer: Layer, payload: LineLayerPayload) -> some View {
        Divider()
        Text("Line").font(.headline)
        colorRow("Color", color: Binding(
            get: { payload.color },
            set: { document.mutate(.setColor(pageId: pageId, id: layer.id, color: $0)) }))
        HStack {
            Text("Width")
            CommitDoubleField(title: "", value: Binding(
                get: { payload.width },
                set: { v in
                    var p = payload; p.width = max(0.5, v)
                    replacePayload(layer: layer, payload: .line(p))
                }))
        }
        HStack {
            Toggle("Start arrow", isOn: Binding(
                get: { payload.startArrow },
                set: { on in
                    var p = payload; p.startArrow = on
                    replacePayload(layer: layer, payload: .line(p))
                }))
            Toggle("End arrow", isOn: Binding(
                get: { payload.endArrow },
                set: { on in
                    var p = payload; p.endArrow = on
                    replacePayload(layer: layer, payload: .line(p))
                }))
        }
        Text("Endpoints are normalized 0…1 within the frame. Default = horizontal centered.")
            .font(.caption2).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func polygonSection(layer: Layer, payload: PolygonLayerPayload) -> some View {
        Divider()
        Text("Polygon").font(.headline)
        HStack {
            Text("Sides")
            Stepper(value: Binding(
                get: { payload.sides },
                set: { v in
                    var p = payload; p.sides = max(3, v)
                    replacePayload(layer: layer, payload: .polygon(p))
                }), in: 3...32) {
                Text("\(payload.sides)").monospacedDigit()
            }
        }
        colorRow("Fill", color: Binding(
            get: { payload.fill },
            set: { document.mutate(.setColor(pageId: pageId, id: layer.id, color: $0)) }))
    }

    @ViewBuilder
    private func starSection(layer: Layer, payload: StarLayerPayload) -> some View {
        Divider()
        Text("Star").font(.headline)
        HStack {
            Text("Points")
            Stepper(value: Binding(
                get: { payload.points },
                set: { v in
                    var p = payload; p.points = max(3, v)
                    replacePayload(layer: layer, payload: .star(p))
                }), in: 3...20) {
                Text("\(payload.points)").monospacedDigit()
            }
        }
        CommitSlider(title: "Inner",
                     value: Binding(
                        get: { payload.innerRadius },
                        set: { v in
                            var p = payload; p.innerRadius = max(0.05, min(0.95, v))
                            replacePayload(layer: layer, payload: .star(p))
                        }),
                     range: 0.05...0.95,
                     fractionDigits: 2)
        colorRow("Fill", color: Binding(
            get: { payload.fill },
            set: { document.mutate(.setColor(pageId: pageId, id: layer.id, color: $0)) }))
    }

    /// Replace a layer's payload in place (same id, same frame/z/etc) by writing through the
    /// document directly. Used for sub-properties that don't have dedicated commands.
    private func replacePayload(layer: Layer, payload: LayerPayload) {
        document.beginUndoableEdit()
        var working = document.document
        if let pIdx = working.pageIndex(id: pageId),
           let lIdx = working.pages[pIdx].layers.firstIndex(where: { $0.id == layer.id }) {
            working.pages[pIdx].layers[lIdx].payload = payload
        }
        document.objectWillChange.send()
        document.document = working
    }

    // MARK: - Gradient

    @ViewBuilder
    private func gradientSection(layer: Layer, payload: GradientLayerPayload) -> some View {
        Divider()
        Text("Gradient").font(.headline)
        Picker("Type", selection: Binding(
            get: { payload.type },
            set: { newType in
                var p = payload; p.type = newType
                updateGradient(layer: layer, payload: p)
            }
        )) {
            ForEach(GradientType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }

        HStack {
            VStack(alignment: .leading) {
                Text("Start").font(.caption)
                HStack {
                    CommitDoubleField(title: "x", value: Binding(
                        get: { payload.startX },
                        set: { v in
                            var p = payload; p.startX = v
                            updateGradient(layer: layer, payload: p)
                        }), fractionDigits: 2)
                    CommitDoubleField(title: "y", value: Binding(
                        get: { payload.startY },
                        set: { v in
                            var p = payload; p.startY = v
                            updateGradient(layer: layer, payload: p)
                        }), fractionDigits: 2)
                }
            }
            VStack(alignment: .leading) {
                Text("End").font(.caption)
                HStack {
                    CommitDoubleField(title: "x", value: Binding(
                        get: { payload.endX },
                        set: { v in
                            var p = payload; p.endX = v
                            updateGradient(layer: layer, payload: p)
                        }), fractionDigits: 2)
                    CommitDoubleField(title: "y", value: Binding(
                        get: { payload.endY },
                        set: { v in
                            var p = payload; p.endY = v
                            updateGradient(layer: layer, payload: p)
                        }), fractionDigits: 2)
                }
            }
        }
        Text("Points are normalized 0…1 within the layer's frame.")
            .font(.caption2).foregroundStyle(.secondary)

        Divider()
        Text("Stops").font(.subheadline)
        ForEach(Array(payload.stops.enumerated()), id: \.offset) { idx, stop in
            HStack(spacing: 6) {
                ColorPicker("", selection: Binding(
                    get: {
                        SwiftUI.Color(red: stop.color.r, green: stop.color.g, blue: stop.color.b, opacity: stop.color.a)
                    },
                    set: { swui in
                        let ns = NSColor(swui).usingColorSpace(.sRGB) ?? .white
                        var p = payload
                        p.stops[idx].color = AIImageEditorCore.Color(
                            r: Double(ns.redComponent),
                            g: Double(ns.greenComponent),
                            b: Double(ns.blueComponent),
                            a: Double(ns.alphaComponent))
                        updateGradient(layer: layer, payload: p)
                    }), supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 36)
                CommitDoubleField(title: "at", value: Binding(
                    get: { stop.at },
                    set: { v in
                        var p = payload
                        p.stops[idx].at = max(0, min(1, v))
                        updateGradient(layer: layer, payload: p)
                    }), fractionDigits: 2)
                    .frame(width: 60)
                Button(role: .destructive) {
                    guard payload.stops.count > 2 else { return }
                    var p = payload
                    p.stops.remove(at: idx)
                    updateGradient(layer: layer, payload: p)
                } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .disabled(payload.stops.count <= 2)
            }
        }
        Button {
            var p = payload
            let lastAt = p.stops.last?.at ?? 1
            p.stops.append(.init(color: .white, at: min(1, lastAt + 0.1)))
            updateGradient(layer: layer, payload: p)
        } label: { Label("Add stop", systemImage: "plus") }
        .buttonStyle(.borderless)
    }

    private func updateGradient(layer: Layer, payload: GradientLayerPayload) {
        document.mutate(.setGradientPayload(pageId: pageId, id: layer.id, payload: payload))
    }

    // MARK: - Blur

    @ViewBuilder
    private func blurSection(layer: Layer, payload: BlurLayerPayload) -> some View {
        Divider()
        Text("Blur").font(.headline)
        CommitSlider(title: "Radius",
                     value: Binding(
                        get: { payload.radius },
                        set: { v in
                            var p = payload; p.radius = max(0, v)
                            updateBlur(layer: layer, payload: p)
                        }),
                     range: 0...120)
        HStack {
            Toggle("Tint", isOn: Binding(
                get: { payload.tint != nil },
                set: { on in
                    var p = payload
                    p.tint = on ? (p.tint ?? AIImageEditorCore.Color(r: 1, g: 1, b: 1, a: 0.25)) : nil
                    updateBlur(layer: layer, payload: p)
                }))
            if payload.tint != nil {
                ColorPicker("", selection: Binding(
                    get: {
                        let c = payload.tint ?? .clear
                        return SwiftUI.Color(red: c.r, green: c.g, blue: c.b, opacity: c.a)
                    },
                    set: { swui in
                        let ns = NSColor(swui).usingColorSpace(.sRGB) ?? .white
                        var p = payload
                        p.tint = AIImageEditorCore.Color(
                            r: Double(ns.redComponent),
                            g: Double(ns.greenComponent),
                            b: Double(ns.blueComponent),
                            a: Double(ns.alphaComponent))
                        updateBlur(layer: layer, payload: p)
                    }), supportsOpacity: true)
                    .labelsHidden()
            }
        }
        Text("Blur samples whatever is drawn beneath this layer. Rotation is ignored.")
            .font(.caption2).foregroundStyle(.secondary)

        Divider()
        gradientBlurSection(layer: layer, payload: payload)
    }

    @ViewBuilder
    private func gradientBlurSection(layer: Layer, payload: BlurLayerPayload) -> some View {
        let hasStops = (payload.stops?.count ?? 0) >= 2
        HStack {
            Text("Gradient blur").font(.headline)
            Spacer()
            Toggle("", isOn: Binding(
                get: { hasStops },
                set: { on in
                    var p = payload
                    if on, (p.stops?.count ?? 0) < 2 {
                        // Seed with a sensible "sharp at top, fully blurred at bottom" gradient.
                        p.stops = [
                            .init(radius: 0,             at: 0),
                            .init(radius: max(p.radius, 24), at: 1),
                        ]
                        p.gradientType = .linear
                        p.startX = 0; p.startY = 0
                        p.endX   = 0; p.endY   = 1
                    } else if !on {
                        p.stops = nil
                    }
                    updateBlur(layer: layer, payload: p)
                }))
            .labelsHidden()
        }
        if hasStops, let stops = payload.stops {
            Picker("Type", selection: Binding(
                get: { payload.gradientType },
                set: { newType in
                    var p = payload; p.gradientType = newType
                    updateBlur(layer: layer, payload: p)
                }
            )) {
                ForEach(GradientType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Text("Start")
                stepperDouble("x", value: Binding(
                    get: { payload.startX },
                    set: { v in var p = payload; p.startX = v; updateBlur(layer: layer, payload: p) }))
                stepperDouble("y", value: Binding(
                    get: { payload.startY },
                    set: { v in var p = payload; p.startY = v; updateBlur(layer: layer, payload: p) }))
            }
            HStack {
                Text("End  ")
                stepperDouble("x", value: Binding(
                    get: { payload.endX },
                    set: { v in var p = payload; p.endX = v; updateBlur(layer: layer, payload: p) }))
                stepperDouble("y", value: Binding(
                    get: { payload.endY },
                    set: { v in var p = payload; p.endY = v; updateBlur(layer: layer, payload: p) }))
            }
            Text("Stops").font(.subheadline)
            ForEach(Array(stops.enumerated()), id: \.offset) { idx, stop in
                HStack(spacing: 6) {
                    Text("r")
                    CommitDoubleField(title: "", value: Binding(
                        get: { stop.radius },
                        set: { v in
                            var p = payload
                            p.stops?[idx].radius = max(0, v)
                            updateBlur(layer: layer, payload: p)
                        }))
                    .frame(width: 60)
                    Text("@")
                    CommitDoubleField(title: "", value: Binding(
                        get: { stop.at },
                        set: { v in
                            var p = payload
                            p.stops?[idx].at = max(0, min(1, v))
                            updateBlur(layer: layer, payload: p)
                        }), fractionDigits: 2)
                    .frame(width: 60)
                    Button(role: .destructive) {
                        guard (payload.stops?.count ?? 0) > 2 else { return }
                        var p = payload
                        p.stops?.remove(at: idx)
                        updateBlur(layer: layer, payload: p)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .disabled((payload.stops?.count ?? 0) <= 2)
                }
            }
            Button {
                var p = payload
                let lastAt = p.stops?.last?.at ?? 1
                let lastR  = p.stops?.last?.radius ?? 24
                p.stops?.append(.init(radius: lastR, at: min(1, lastAt + 0.1)))
                updateBlur(layer: layer, payload: p)
            } label: { Label("Add stop", systemImage: "plus") }
            .buttonStyle(.borderless)
            Text("Each stop's radius (px) is interpolated along the start→end direction. The mask is normalized against the largest radius.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func updateBlur(layer: Layer, payload: BlurLayerPayload) {
        document.mutate(.setBlurPayload(pageId: pageId, id: layer.id, payload: payload))
    }

    private func applyCanvas(width: Int?, height: Int?) {
        let page = document.selectedPage
        let w = width ?? page.canvas.width
        let h = height ?? page.canvas.height
        document.mutate(.setCanvas(pageId: pageId, width: w, height: h))
    }

}
