import Foundation
import AppKit
import XCTest
import AIImageEditorCore
@testable import AIImageEditor

final class AIImageEditorTests: XCTestCase {

    func test_color_hexRoundTrip() throws {
        let c = try Color(hex: "#1A2B3C")
        XCTAssertEqual(c.hex, "#1A2B3C")
        let withAlpha = try Color(hex: "#1A2B3C80")
        XCTAssertEqual(withAlpha.hex.uppercased().hasPrefix("#1A2B3C"), true)
    }

    func test_color_invalid_throws() {
        XCTAssertThrowsError(try Color(hex: "not a color"))
        XCTAssertThrowsError(try Color(hex: "#12"))
    }

    func test_frame_parse() throws {
        let f = try Frame.parse("10, 20, 300, 400")
        XCTAssertEqual(f.x, 10); XCTAssertEqual(f.h, 400)
        XCTAssertThrowsError(try Frame.parse("nope"))
    }

    func test_codec_roundTrip() throws {
        let canvas = Canvas(width: 100, height: 200, background: try Color(hex: "#112233"))
        let text = Layer(id: "t", kind: .text,
                         frame: Frame(0, 0, 100, 50),
                         payload: .text(.init(text: "hi", fontSize: 24, color: .white)))
        let doc = Document(canvas: canvas, layers: [text])
        let data = try DocumentCodec.encode(doc)
        let round = try DocumentCodec.decode(data)
        XCTAssertEqual(round.pages.count, 1)
        // Page.relayout pads with margins (1 preview width on each side, 0.5 preview height
        // top/bottom). For a 100×200 preview: canvas = (1+2)*100 × (0.5+1+0.5)*200 = 300×400.
        XCTAssertEqual(round.canvas.width, 300)
        XCTAssertEqual(round.canvas.height, 400)
        XCTAssertEqual(round.pages[0].previews.count, 1)
        XCTAssertEqual(round.pages[0].previews[0].frame.w, 100)
        XCTAssertEqual(round.layers.count, 1)
        XCTAssertEqual(round.layers[0].id, "t")
        XCTAssertEqual(round.version, 2)
    }

    func test_codec_v1_autoUpgrade() throws {
        let v1 = """
        {
          "version": 1,
          "canvas": { "width": 100, "height": 200, "background": "#000000" },
          "assets": {},
          "layers": [
            { "id": "t", "type": "text", "frame": [0,0,100,50], "text": "hi",
              "font": "Helvetica", "fontSize": 24, "fontWeight": "regular",
              "color": "#FFFFFF", "alignment": "center" }
          ]
        }
        """.data(using: .utf8)!
        let doc = try DocumentCodec.decode(v1)
        XCTAssertEqual(doc.version, 2)
        XCTAssertEqual(doc.pages.count, 1)
        XCTAssertEqual(doc.pages.first?.id, "page-1")
        XCTAssertEqual(doc.layers.count, 1)
    }

    func test_commandEngine_addAndMove() throws {
        var doc = Document(canvas: Canvas(width: 500, height: 500))
        let added = try CommandEngine.apply(
            .addText(pageId: nil, id: "title", payload: .init(text: "hi"),
                     frame: Frame(0, 0, 200, 50), z: nil),
            to: &doc)
        XCTAssertEqual(added.newLayerId, "title")
        XCTAssertEqual(doc.layers.count, 1)
        _ = try CommandEngine.apply(.move(pageId: nil, id: "title", to: (50, 60)), to: &doc)
        XCTAssertEqual(doc.layers[0].frame.x, 50)
    }

    func test_commandEngine_zOrder() throws {
        var doc = Document(canvas: Canvas(width: 500, height: 500))
        _ = try CommandEngine.apply(.addRect(pageId: nil, id: "a", payload: .init(), frame: Frame(0, 0, 10, 10), z: 1), to: &doc)
        _ = try CommandEngine.apply(.addRect(pageId: nil, id: "b", payload: .init(), frame: Frame(0, 0, 10, 10), z: 2), to: &doc)
        _ = try CommandEngine.apply(.addRect(pageId: nil, id: "c", payload: .init(), frame: Frame(0, 0, 10, 10), z: 3), to: &doc)
        _ = try CommandEngine.apply(.sendToBack(pageId: nil, id: "c"), to: &doc)
        XCTAssertEqual(doc.renderOrder.first?.id, "c")
    }

    func test_renderer_smoke() throws {
        var doc = Document(canvas: Canvas(width: 200, height: 200, background: try Color(hex: "#0000FF")))
        _ = try CommandEngine.apply(
            .addText(pageId: nil, id: "t", payload: .init(text: "Hi", fontSize: 40, color: .white),
                     frame: Frame(0, 60, 200, 80), z: nil),
            to: &doc)
        let png = try Renderer().renderPNG(doc, scale: 1)
        XCTAssertGreaterThan(png.count, 100)
    }

    func test_bezel_inProject() throws {
        var doc = Document(canvas: Canvas(width: 400, height: 800))
        _ = try CommandEngine.apply(
            .addDeviceBezel(pageId: nil, id: "p1",
                            payload: .init(device: "iphone16Pro"),
                            frame: Frame(50, 50, 300, 600), z: nil),
            to: &doc)
        let png = try Renderer().renderPNG(doc, scale: 1)
        XCTAssertGreaterThan(png.count, 100)
    }

    func test_unknownBezel_throws() {
        var doc = Document(canvas: Canvas(width: 100, height: 100))
        XCTAssertThrowsError(try CommandEngine.apply(
            .addDeviceBezel(pageId: nil, id: nil, payload: .init(device: "not-real"),
                            frame: Frame(0, 0, 50, 100), z: nil),
            to: &doc))
    }

    func test_unknownPreset() {
        XCTAssertNil(PresetCatalog.find(id: "made-up"))
        XCTAssertNotNil(PresetCatalog.find(id: "iphone-6.7"))
    }

    func test_pages_addRemoveSelect() throws {
        var doc = Document(canvas: Canvas(width: 100, height: 100))
        XCTAssertEqual(doc.pages.count, 1)
        _ = try CommandEngine.apply(.addPage(id: "p2", name: "Two", canvas: nil), to: &doc)
        XCTAssertEqual(doc.pages.count, 2)
        XCTAssertEqual(doc.activePageId, "p2")
        _ = try CommandEngine.apply(.selectPage(id: "page-1"), to: &doc)
        XCTAssertEqual(doc.activePageId, "page-1")
        _ = try CommandEngine.apply(.removePage(id: "p2"), to: &doc)
        XCTAssertEqual(doc.pages.count, 1)
    }

    func test_pages_layerIsolation() throws {
        var doc = Document(canvas: Canvas(width: 100, height: 100))
        _ = try CommandEngine.apply(.addPage(id: "p2", name: "Two", canvas: nil), to: &doc)
        // Add a text to page-1
        _ = try CommandEngine.apply(.addText(pageId: "page-1", id: "t1",
                                             payload: .init(text: "one"),
                                             frame: Frame(0, 0, 50, 20), z: nil), to: &doc)
        // Add a text to p2
        _ = try CommandEngine.apply(.addText(pageId: "p2", id: "t2",
                                             payload: .init(text: "two"),
                                             frame: Frame(0, 0, 50, 20), z: nil), to: &doc)
        XCTAssertEqual(doc.page(id: "page-1")?.layers.count, 1)
        XCTAssertEqual(doc.page(id: "p2")?.layers.count, 1)
        XCTAssertEqual(doc.page(id: "page-1")?.layers.first?.id, "t1")
        XCTAssertEqual(doc.page(id: "p2")?.layers.first?.id, "t2")
    }

    func test_setBezelScreenshot() throws {
        var doc = Document(canvas: Canvas(width: 400, height: 800))
        _ = try CommandEngine.apply(.addAsset(id: "shot", path: "/tmp/whatever.png"), to: &doc)
        _ = try CommandEngine.apply(.addDeviceBezel(pageId: nil, id: "p", payload: .init(device: "iphone16Pro"),
                                                    frame: Frame(0, 0, 200, 400), z: nil), to: &doc)
        _ = try CommandEngine.apply(.setBezelScreenshot(pageId: nil, id: "p", assetId: "shot"), to: &doc)
        if case .deviceBezel(let p)? = doc.layer(id: "p")?.payload {
            XCTAssertEqual(p.screenshotAssetId, "shot")
        } else { XCTFail("wrong payload") }
        // Clear
        _ = try CommandEngine.apply(.setBezelScreenshot(pageId: nil, id: "p", assetId: nil), to: &doc)
        if case .deviceBezel(let p)? = doc.layer(id: "p")?.payload {
            XCTAssertNil(p.screenshotAssetId)
        }
        // Unknown asset → error
        XCTAssertThrowsError(try CommandEngine.apply(
            .setBezelScreenshot(pageId: nil, id: "p", assetId: "does-not-exist"), to: &doc))
    }

    /// Render the same bezel-heavy scene 50 times in a row in one process. The first render
    /// builds the bezel composite cache; subsequent renders just blit it. Total time should
    /// be dominated by the first render plus cheap per-frame canvas work.
    func test_perf_bezelRenderCaching() throws {
        var doc = Document(canvas: Canvas(width: 1290, height: 2796, background: try Color(hex: "#000000")))
        _ = try CommandEngine.apply(.addDeviceBezel(pageId: nil, id: "p",
                                                    payload: .init(device: "iphone17Pro", color: "Silver"),
                                                    frame: Frame(200, 400, 880, 2000), z: nil),
                                    to: &doc)
        let renderer = Renderer()

        let startFirst = Date()
        _ = try renderer.renderPNG(doc, scale: 1)
        let firstMs = Int(Date().timeIntervalSince(startFirst) * 1000)

        let startBatch = Date()
        for _ in 0..<49 {
            _ = try renderer.renderPNG(doc, scale: 1)
        }
        let batchMs = Int(Date().timeIntervalSince(startBatch) * 1000)
        let avgWarmMs = Double(batchMs) / 49.0

        print("[perf] first render: \(firstMs) ms, 49 warm renders total: \(batchMs) ms, average warm: \(String(format: "%.1f", avgWarmMs)) ms")
        // Canvas now includes 1×previewWidth margins on each side and 0.5×previewHeight on
        // top/bottom — the workspace is ~4× the pixel area of just the preview, so the
        // renderer's allocate+fill+makeImage scales accordingly. Threshold accounts for the
        // Debug-build overhead; Release runs 3-4× faster.
        XCTAssertLessThan(avgWarmMs, 250, "Warm bezel renders should be cheap — got \(avgWarmMs)ms average")
    }

    func test_layout_setLayout() throws {
        var doc = Document(canvas: Canvas(width: 100, height: 100))
        let layout = PageLayout(previewWidth: 30, previewHeight: 60, spacing: 5)
        _ = try CommandEngine.apply(.setLayout(pageId: nil, layout: layout), to: &doc)
        XCTAssertEqual(doc.activePage.layout.previewWidth, 30)
        XCTAssertEqual(doc.activePage.layout.previewHeight, 60)
        XCTAssertEqual(doc.activePage.layout.spacing, 5)
    }

    func test_previews_countAndCanvasResize() throws {
        var doc = Document(canvas: Canvas(width: 100, height: 100))
        _ = try CommandEngine.apply(.setPreviewSize(pageId: nil, width: 200, height: 400), to: &doc)
        _ = try CommandEngine.apply(.setPreviewSpacing(pageId: nil, spacing: 10), to: &doc)
        _ = try CommandEngine.apply(.setPreviewCount(pageId: nil, count: 3), to: &doc)
        XCTAssertEqual(doc.activePage.previews.count, 3)
        // Canvas now includes margins: leftMargin = previewW = 200; rightMargin = 200;
        // topMargin = previewH/2 = 200; bottomMargin = 200.
        // width  = 200 (L) + 3*200 + 2*10 (content) + 200 (R) = 1020
        // height = 200 (T) +         400      + 200 (B) = 800
        XCTAssertEqual(doc.activePage.canvas.width, 1020)
        XCTAssertEqual(doc.activePage.canvas.height, 800)
        // Previews lined up horizontally, offset by leftMargin (200) and topMargin (200).
        XCTAssertEqual(doc.activePage.previews[0].frame.x, 200)
        XCTAssertEqual(doc.activePage.previews[1].frame.x, 410)
        XCTAssertEqual(doc.activePage.previews[2].frame.x, 620)
        XCTAssertEqual(doc.activePage.previews[0].frame.y, 200)
    }

    func test_canvas_defaultBackgroundIsWhite() {
        let canvas = Canvas(width: 100, height: 100)
        XCTAssertEqual(canvas.background.hex, "#FFFFFF")
    }

    func test_renderPreview_clipsToFrame() throws {
        var doc = Document(canvas: Canvas(width: 100, height: 100))
        _ = try CommandEngine.apply(.setPreviewSize(pageId: nil, width: 200, height: 400), to: &doc)
        _ = try CommandEngine.apply(.setPreviewCount(pageId: nil, count: 2), to: &doc)
        // Add a wide text spanning both previews — each preview should still render at 200x400.
        _ = try CommandEngine.apply(
            .addText(pageId: nil, id: "t",
                     payload: .init(text: "X", fontSize: 100, color: .white),
                     frame: Frame(0, 0, 1000, 400), z: nil),
            to: &doc)
        let id1 = doc.activePage.previews[0].id
        let id2 = doc.activePage.previews[1].id
        let r = Renderer()
        let p1 = try r.renderPreviewPNG(doc, previewId: id1)
        let p2 = try r.renderPreviewPNG(doc, previewId: id2)
        XCTAssertGreaterThan(p1.count, 100)
        XCTAssertGreaterThan(p2.count, 100)
    }

    // MARK: - Group crop-to-bounds

    func test_group_clipsToBounds_commandAndCodec() throws {
        var doc = Document(canvas: Canvas(width: 300, height: 300))
        _ = try CommandEngine.apply(.addRect(pageId: nil, id: "a", payload: .init(), frame: Frame(0, 0, 50, 50), z: nil), to: &doc)
        _ = try CommandEngine.apply(.addRect(pageId: nil, id: "b", payload: .init(), frame: Frame(100, 100, 50, 50), z: nil), to: &doc)
        _ = try CommandEngine.apply(.addGroup(pageId: nil, id: "g", name: nil, childIds: ["a", "b"]), to: &doc)

        // Off by default.
        guard case .group(let g0)? = doc.layers.first(where: { $0.id == "g" })?.payload else {
            return XCTFail("group not created")
        }
        XCTAssertFalse(g0.clipsToBounds)

        // Enabling the flag leaves the auto-recomputed frame as the union of the children.
        _ = try CommandEngine.apply(.setGroupClipsToBounds(pageId: nil, id: "g", value: true), to: &doc)
        let group = try XCTUnwrap(doc.layers.first(where: { $0.id == "g" }))
        guard case .group(let g1) = group.payload else { return XCTFail("not a group") }
        XCTAssertTrue(g1.clipsToBounds)
        XCTAssertEqual(group.frame.x, 0);   XCTAssertEqual(group.frame.y, 0)
        XCTAssertEqual(group.frame.w, 150); XCTAssertEqual(group.frame.h, 150)

        // Survives a codec round-trip.
        let round = try DocumentCodec.decode(try DocumentCodec.encode(doc))
        guard case .group(let g2)? = round.layers.first(where: { $0.id == "g" })?.payload else {
            return XCTFail("group missing after decode")
        }
        XCTAssertTrue(g2.clipsToBounds)

        // Toggling off (the default) decodes back to false.
        _ = try CommandEngine.apply(.setGroupClipsToBounds(pageId: nil, id: "g", value: false), to: &doc)
        let round2 = try DocumentCodec.decode(try DocumentCodec.encode(doc))
        guard case .group(let g3)? = round2.layers.first(where: { $0.id == "g" })?.payload else {
            return XCTFail("group missing after decode")
        }
        XCTAssertFalse(g3.clipsToBounds)
    }

    func test_group_clipsToBounds_cropsOverflow() throws {
        // A 45°-rotated red square whose drawn corners poke outside the group's frame (the
        // axis-aligned union of children's frames). Cropping to bounds should trim those corners,
        // so the clipped render has strictly fewer solid-red pixels than the unclipped one.
        func makeDoc(clip: Bool) throws -> Document {
            var doc = Document(canvas: Canvas(width: 200, height: 200, background: .white))
            _ = try CommandEngine.apply(
                .addRect(pageId: nil, id: "r",
                         payload: .init(fill: try Color(hex: "#FF0000")),
                         frame: Frame(50, 50, 100, 100), z: nil), to: &doc)
            _ = try CommandEngine.apply(.rotate(pageId: nil, id: "r", degrees: 45), to: &doc)
            _ = try CommandEngine.apply(.addGroup(pageId: nil, id: "g", name: nil, childIds: ["r"]), to: &doc)
            if clip {
                _ = try CommandEngine.apply(.setGroupClipsToBounds(pageId: nil, id: "g", value: true), to: &doc)
            }
            return doc
        }
        let redOff = try redPixelCount(Renderer().renderPNG(makeDoc(clip: false), scale: 1))
        let redOn  = try redPixelCount(Renderer().renderPNG(makeDoc(clip: true),  scale: 1))
        XCTAssertGreaterThan(redOn, 0, "the clipped group should still render the square inside its bounds")
        XCTAssertLessThan(redOn, redOff, "crop-to-bounds should remove the rotated corners that overflow the group frame")
    }

    // MARK: - Fractional render scale (editor display-resolution rendering)

    func test_renderer_fractionalPixelScale_dimensionsAndParity() throws {
        var doc = Document(canvas: Canvas(width: 200, height: 300, background: try Color(hex: "#3344FF")))
        _ = try CommandEngine.apply(
            .addRect(pageId: nil, id: "r", payload: .init(fill: try Color(hex: "#FFFFFF")),
                     frame: Frame(20, 20, 100, 100), z: nil), to: &doc)
        let canvas = doc.activePage.canvas
        let r = Renderer()

        // pixelScale 0.5 → half the pixels in each dimension.
        let half = try r.renderCGImage(doc, pixelScale: 0.5)
        XCTAssertEqual(half.width, Int((Double(canvas.width) * 0.5).rounded()))
        XCTAssertEqual(half.height, Int((Double(canvas.height) * 0.5).rounded()))

        // pixelScale 0.25 → quarter resolution, far fewer pixels (the editor's zoomed-out case).
        let quarter = try r.renderCGImage(doc, pixelScale: 0.25)
        XCTAssertEqual(quarter.width, Int((Double(canvas.width) * 0.25).rounded()))
        XCTAssertLessThan(quarter.width * quarter.height, half.width * half.height)

        // pixelScale 1.0 must match the integer scale:1 path exactly (export/CLI parity).
        let frac1 = try r.renderCGImage(doc, pixelScale: 1.0)
        let int1 = try r.renderCGImage(doc, scale: 1)
        XCTAssertEqual(frac1.width, int1.width)
        XCTAssertEqual(frac1.height, int1.height)
        XCTAssertEqual(frac1.width, canvas.width)
        XCTAssertEqual(frac1.height, canvas.height)
    }

    func test_canvasRenderer_renderScaleBuckets() {
        // Zoomed out → quantized-up crisp scale, capped at 1.0; idle scale is never below zoom.
        XCTAssertEqual(CanvasRenderer.renderScale(zoom: 0.25, interacting: false), 0.25, accuracy: 0.0001)
        XCTAssertEqual(CanvasRenderer.renderScale(zoom: 0.30, interacting: false), 0.50, accuracy: 0.0001)
        XCTAssertEqual(CanvasRenderer.renderScale(zoom: 1.50, interacting: false), 1.00, accuracy: 0.0001)
        XCTAssertEqual(CanvasRenderer.renderScale(zoom: 0.05, interacting: false), 0.25, accuracy: 0.0001)
        // During an interaction the draft scale is coarser than the crisp scale.
        XCTAssertLessThan(CanvasRenderer.renderScale(zoom: 0.25, interacting: true),
                          CanvasRenderer.renderScale(zoom: 0.25, interacting: false))
    }

    // MARK: - Per-corner rounding (roundedCorners)

    func test_roundedCorners_commandAndCodec() throws {
        var doc = Document(canvas: Canvas(width: 100, height: 100))
        _ = try CommandEngine.apply(.addRect(pageId: nil, id: "r", payload: .init(),
                                             frame: Frame(0, 0, 50, 50), z: nil), to: &doc)
        func corners(_ d: Document) -> RectCorners? { d.layers.first { $0.id == "r" }?.roundedCorners }

        // Default = all, and omitted from JSON for backward compatibility.
        XCTAssertEqual(corners(doc), .all)
        let json0 = try DocumentCodec.encode(doc)
        XCTAssertFalse(String(data: json0, encoding: .utf8)!.contains("roundedCorners"))
        XCTAssertEqual(corners(try DocumentCodec.decode(json0)), .all)

        // A subset round-trips through the codec.
        _ = try CommandEngine.apply(.setRoundedCorners(pageId: nil, id: "r",
                                                       corners: [.topLeft, .topRight]), to: &doc)
        XCTAssertEqual(corners(doc), [.topLeft, .topRight])
        XCTAssertEqual(corners(try DocumentCodec.decode(try DocumentCodec.encode(doc))), [.topLeft, .topRight])

        // Empty (every corner square) is preserved, not mistaken for the default-all.
        _ = try CommandEngine.apply(.setRoundedCorners(pageId: nil, id: "r", corners: []), to: &doc)
        XCTAssertEqual(corners(try DocumentCodec.decode(try DocumentCodec.encode(doc))), [])
    }

    func test_roundedCorners_perCornerRendering() throws {
        // A red square filling a white canvas, radius 80. Rounding a corner carves red away there;
        // squaring it keeps the red. So more squared corners ⇒ more red pixels survive.
        func redCount(_ corners: RectCorners) throws -> Int {
            var doc = Document(canvas: Canvas(width: 200, height: 200, background: .white))
            _ = try CommandEngine.apply(.addRect(pageId: nil, id: "r",
                payload: .init(fill: try Color(hex: "#FF0000")),
                frame: Frame(0, 0, 200, 200), z: nil), to: &doc)
            _ = try CommandEngine.apply(.setCornerRadius(pageId: nil, id: "r", value: 80), to: &doc)
            _ = try CommandEngine.apply(.setCornerStyle(pageId: nil, id: "r", style: .arc), to: &doc)
            _ = try CommandEngine.apply(.setRoundedCorners(pageId: nil, id: "r", corners: corners), to: &doc)
            return redPixelCount(try Renderer().renderPNG(doc, scale: 1))
        }
        let noneRounded = try redCount([])         // full square — most red
        let oneRounded  = try redCount([.topLeft]) // 3 square corners
        let allRounded  = try redCount(.all)       // 0 square corners — least red
        XCTAssertGreaterThan(noneRounded, oneRounded)
        XCTAssertGreaterThan(oneRounded, allRounded)
    }

    /// Count solid-red pixels in a PNG — used to measure how much of a red square survives a crop.
    private func redPixelCount(_ png: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: png) else { return -1 }
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent > 0.75, c.greenComponent < 0.25, c.blueComponent < 0.25 {
                    count += 1
                }
            }
        }
        return count
    }
}
