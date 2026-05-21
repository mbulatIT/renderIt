import SwiftUI
import AppKit
import AIImageEditorCore

struct InspectorPanel: View {
    @ObservedObject var document: ProjectDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let id = document.selectedLayerId,
                   let layer = document.selectedPage.layer(id: id) {
                    layerSection(layer: layer)
                } else {
                    pageSection
                }
            }
            .padding(12)
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
                TextField("", value: Binding(
                    get: { page.layout.spacing },
                    set: { v in document.mutate(.setPreviewSpacing(pageId: pageId, spacing: v)) }),
                                format: .number)
            }
            HStack {
                Text("Preview W × H")
                TextField("w", value: Binding(
                    get: { page.layout.previewWidth },
                    set: { v in
                        document.mutate(.setPreviewSize(pageId: pageId,
                                                        width: v > 0 ? v : page.layout.previewWidth,
                                                        height: page.layout.previewHeight))
                    }), format: .number)
                TextField("h", value: Binding(
                    get: { page.layout.previewHeight },
                    set: { v in
                        document.mutate(.setPreviewSize(pageId: pageId,
                                                        width: page.layout.previewWidth,
                                                        height: v > 0 ? v : page.layout.previewHeight))
                    }), format: .number)
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
        Text(layer.name).font(.title3)
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
            case .group: EmptyView()
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
        HStack {
            Text("Rotation")
            Slider(value: Binding(
                get: { layer.rotation },
                set: { document.mutate(.rotate(pageId: pageId, id: layer.id, degrees: $0)) }),
                in: -180...180)
            Text("\(Int(layer.rotation))°").monospacedDigit().frame(width: 40)
        }
        HStack {
            Text("Opacity")
            Slider(value: Binding(
                get: { layer.opacity },
                set: { document.mutate(.setOpacity(pageId: pageId, id: layer.id, value: $0)) }),
                in: 0...1)
            Text(String(format: "%.0f%%", layer.opacity * 100)).monospacedDigit().frame(width: 40)
        }
        HStack {
            Text("Z")
            TextField("", value: Binding(
                get: { layer.zIndex },
                set: { document.mutate(.setZIndex(pageId: pageId, id: layer.id, value: $0)) }),
                                format: .number)
        }
        HStack {
            Button("Front")   { document.mutate(.bringToFront(pageId: pageId, id: layer.id)) }
            Button("Forward") { document.mutate(.moveForward(pageId: pageId, id: layer.id)) }
            Button("Back")    { document.mutate(.moveBackward(pageId: pageId, id: layer.id)) }
            Button("Bottom")  { document.mutate(.sendToBack(pageId: pageId, id: layer.id)) }
        }
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
            TextField("", value: Binding(
                get: { payload.fontSize },
                set: { document.mutate(.setFont(pageId: pageId, id: layer.id, family: nil, size: $0, weight: nil, italic: nil)) }
            ), format: .number)
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
        HStack { Text(label); TextField("", value: value, format: .number) }
    }
    private func stepperDouble(_ label: String, value: Binding<Double>) -> some View {
        HStack { Text(label); TextField("", value: value, format: .number) }
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

    private func applyCanvas(width: Int?, height: Int?) {
        let page = document.selectedPage
        let w = width ?? page.canvas.width
        let h = height ?? page.canvas.height
        document.mutate(.setCanvas(pageId: pageId, width: w, height: h))
    }

}
