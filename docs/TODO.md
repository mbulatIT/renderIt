# TODO

Master checklist. Each top-level feature has its own sub-checklist.
Marked items are implemented and verified to compile. Unchecked = not started or in progress.

## v3.3 — Bezel mask via flood-filled chrome

The previous two attempts (luminance walk, then alpha walk with union/intersection bounding
boxes) both leaked at corners because the chrome PNG has a transparent outer area outside
the device silhouette, so the `destinationOut` step couldn't subtract there.

Final approach:
- [x] `BezelImageStore.filledChromeImage(deviceId:color:)` produces a derived CGImage by
       flood-filling from the four edges of the chrome PNG through transparent pixels,
       painting them opaque white. The screen well stays untouched because it's enclosed
       by chrome material. Cached per device+color.
- [x] Renderer uses the *filled-chrome* image as the `destinationOut` source. Both the
       chrome material AND the outer transparent corners are subtracted from the screenshot.
       Only the screen well survives.
- [x] Original chrome image is still drawn on top for the visible bezel.
- [x] Screen-rect detection is now used only for *positioning* the screenshot inside the
       well; mask shape comes entirely from the chrome PNG's own alpha pattern.

## v3.2 — Clip fix + resize handles

### Screen-rect detection
- [x] Switched from luminance (could not distinguish dark chrome material from transparent
       outer area on Deep blue / Space black / Cosmic orange devices) to alpha-channel
       detection. Walks outward from centre to the first opaque pixel — that's the chrome.
- [x] Sampled at 9 rows × 9 cols (every ~5%) and took the tightest extent, so Dynamic-Island
       cutouts narrow the rect rather than widening it.
- [x] Screenshot drawn into a strict rectangular clip (not rounded) — the chrome PNG's own
       opaque material covers the rounded corners, eliminating any chance of corner mismatch.

### Resize handles
- [x] Selection overlay now renders 8 handles around the selected layer:
       4 corner squares + 4 edge capsules.
- [x] Corner squares scale both axes; edge capsules scale a single axis (corner edges anchored).
- [x] Cmd held during a corner drag preserves the layer's starting aspect ratio
       (dominant axis governs).
- [x] Hit testing prefers handles over body, so dragging the layer edge resizes rather than moves.
- [x] Drag start pushes an undo snapshot; ⌘Z reverts the resize as a single step.
- [x] Active handle scales up 1.15× during drag for visual feedback.

## v3.1 — Bezel screenshot upload

- [x] Engine: `setBezelScreenshot(pageId, id, assetId?)` (typed command with auto-clear)
- [x] CLI: `set-bezel-screenshot` subcommand supporting `--asset`, `--asset-path`, `--clear`
- [x] MCP: `set_bezel_screenshot` tool (`asset` / `asset_path` / `clear: true`)
- [x] GUI: "Choose…" / "Replace…" / "Remove" buttons in the bezel inspector
- [x] GUI: live thumbnail preview of the current screenshot
- [x] GUI: drag-and-drop a file onto a bezel layer to attach it as the screenshot
       (drop on empty canvas adds a normal image layer instead)
- [x] Auto-reuse of asset ids — dropping the same file twice doesn't create a duplicate asset
- [x] Test: `test_setBezelScreenshot` (attach / clear / unknown-asset error)

## v3 — Image-backed bezels with color picker

- [x] Extract PNGs from user-provided SVG asset library (`extract` script, base64 decode)
- [x] Bundle as `AIImageEditorCore/Resources/Bezels/<deviceId>--<colorId>.png`
- [x] `manifest.json` describing device families, aspect ratios, color variants
- [x] `BezelImageStore` loads manifest + PNGs from any sibling
       `*_AIImageEditorCore.bundle` (works in app / tests / CLI / MCP)
- [x] Screen-rect auto-detection by scanning the loaded image for the dark display well
- [x] `DeviceBezel.Source` enum: `.imageBacked(defaultColor:)` and `.programmatic(...)`
- [x] Renderer dispatches on source kind — image-backed paints the screenshot under the chrome
- [x] `DeviceBezelPayload.color` field; `setBezelColor` command
- [x] CLI: `--color` on `add-bezel`, `set-bezel-color` subcommand, `bezels` lists variants
- [x] MCP: `color` arg on `add_bezel`, new `set_bezel_color` tool, `list_bezels` returns colors
- [x] GUI: Inspector shows a Color picker dropdown for image-backed bezel layers
- [x] Updated examples to use new device ids (iphone16Pro, iphone17Pro)
- [x] Updated `docs/DEVICE_BEZELS.md` catalog + integration guide

## v2 — Pages / undo / shortcuts

### Project / page model
- [x] `Page` type with own canvas + layout + layers
- [x] `Document` (== Project) holds `pages: [Page]` + shared `assets`
- [x] `PageLayout` (mode, previewCount, previewWidth/Height, spacing, columns)
- [x] v1 → v2 auto-migration (old docs read into a single default page)
- [x] Round-trip test for v2 + v1-upgrade test

### Renderer
- [x] `Renderer.renderPage(page:assets:scale:)` is the unit of work
- [x] Document-level render takes optional `pageId`, default = active

### Command engine
- [x] Page-level commands: `addPage`, `removePage`, `renamePage`, `selectPage`
- [x] Page settings: `setLayout`, `setCanvas`, `setBackground` (all take pageId)
- [x] Layer commands take optional `pageId` (default = active page)
- [x] `insertLayer` command — used for clipboard paste / page duplication

### CLI
- [x] `pages list / add / remove / rename / select`
- [x] `set-layout` subcommand for page settings
- [x] `--page <id>` flag on every layer / canvas command
- [x] `render --page <id>` picks which page to export

### MCP
- [x] page-level tools (`list_pages`, `add_page`, `remove_page`, `rename_page`, `select_page`)
- [x] `set_layout` tool
- [x] `page` argument on every layer / canvas tool

### GUI
- [x] Page tab bar across the top (click to switch, `+` to add, double-click to rename)
- [x] Inspector switches to **Page settings** when no layer is selected
       (canvas size, background, preset picker, layout mode, preview count/size/spacing)
- [x] "Auto-arrange previews" button in grid mode
- [x] Backspace / Delete removes the selected layer
- [x] Cmd+Z / Cmd+Shift+Z undo / redo via in-document history stack
- [x] Cmd+C copies the selected layer to the system pasteboard
- [x] Cmd+V pastes a layer
- [x] Cmd+D duplicates the selected layer
- [x] Cmd+N creates a new page in the current project
- [x] Cmd+Shift+N still creates a new document (NSDocumentController)
- [x] Cmd+[ / Cmd+] cycle pages
- [x] Click on empty canvas → clear selection → page settings inspector
- [x] Edit menu wired (Undo/Redo/Cut/Copy/Paste/Duplicate/Delete)
- [x] Page menu wired (Next/Previous Page)

## Project setup
- [x] Documentation map (CLAUDE.md as entrypoint)
- [x] Extend Tuist manifest with `AIImageEditorCore`, `aiimageeditor-cli`,
      `aiimageeditor-mcp` targets, plus `AIImageEditorCoreTests`
- [x] `tuist generate` succeeds
- [x] All targets compile with `xcodebuild`

## Core engine (`AIImageEditorCore`)

### Document model
- [x] `Canvas` (width, height, background color, dpi)
- [x] `Document` (canvas + ordered layers + asset table + metadata)
- [x] `LayerKind` enum (image, text, rect, ellipse, deviceBezel, group)
- [x] `Layer` struct with common props (id, frame, zIndex, rotation, opacity, visible, blendMode)
- [x] Type-specific payloads: `ImageLayerPayload`, `TextLayerPayload`,
      `ShapeLayerPayload`, `DeviceBezelPayload`, `GroupPayload`
- [x] `AssetTable` storing asset id → file path / inline base64
- [x] `Color` value object (hex round-trip)
- [x] Stable, human-readable layer IDs

### Persistence
- [x] `DocumentCodec.encode(_:)` → `Data` (pretty JSON)
- [x] `DocumentCodec.decode(_:)` → `Document`
- [x] Backwards-compat version field
- [x] Round-trip test

### Rendering
- [x] `Renderer.render(document:)` → `NSImage`
- [x] `Renderer.renderPNG(document:)` → `Data`
- [x] Per-layer drawing for image
- [x] Per-layer drawing for text (font, size, weight, color, alignment, multiline, line spacing)
- [x] Per-layer drawing for shape (rect / ellipse, fill, stroke, corner radius)
- [x] Per-layer drawing for device bezel (programmatic frames, screenshot inset)
- [x] Layer rotation around frame center
- [x] Layer opacity
- [x] Layer visibility toggle
- [x] zIndex ordering (lower drawn first)
- [x] Asset loading + caching
- [x] Background color or transparent

### Device bezels (programmatic, copyright-safe)
- [x] iPhone 15 Pro (Dynamic Island, rounded chrome)
- [x] iPhone 15 Pro Max
- [x] iPhone SE (home button era look-alike)
- [x] iPad Pro 12.9" (slim bezel)
- [x] iPad Pro 11"
- [x] MacBook Pro 14"
- [x] MacBook Pro 16"
- [x] Each bezel exposes `screenRect(in: bounds)` so the screenshot lays into it precisely
- [x] Each bezel registered in `DeviceBezelCatalog`

### Presets
- [x] iPhone 6.7" (1290×2796)
- [x] iPhone 6.5" (1284×2778)
- [x] iPhone 5.5" (1242×2208)
- [x] iPad Pro 13" (2064×2752)
- [x] iPad Pro 12.9" (2048×2732)
- [x] Mac (2880×1800)
- [x] Apple Watch Ultra (410×502)
- [x] Each preset registered in `PresetCatalog`

### Command engine (LLM API surface)
- [x] `Command` enum with typed payloads
- [x] `CommandEngine.apply(_:to:)` → updates Document, returns affected layer id(s)
- [x] Commands: `setCanvas`, `setBackground`
- [x] Commands: `addImage`, `addText`, `addRect`, `addEllipse`, `addDeviceBezel`
- [x] Commands: `move`, `resize`, `setFrame`, `rotate`, `setOpacity`,
      `setVisible`, `setBlendMode`, `setZIndex`, `bringToFront`, `sendToBack`,
      `moveForward`, `moveBackward`
- [x] Commands: `updateText`, `setFont`, `setColor`, `setAlignment`
- [x] Commands: `removeLayer`, `duplicateLayer`, `renameLayer`
- [x] Commands: `addAsset`, `removeAsset`
- [x] Position helpers: `--at center|top-center|...`
- [x] Snapshot-style undo via list of past Documents (optional, in-memory)

### Errors
- [x] Typed `EditorError` (asset not found, layer not found, invalid hex, etc.)
- [x] Friendly `localizedDescription` for CLI/MCP

## macOS app (`AIImageEditor`)

- [x] `DocumentGroup` with custom file type `.aiproj`
- [x] `EditorView` 3-pane layout: layer list | canvas | inspector
- [x] Canvas: zoom + fit-to-window + checkerboard background for transparency
- [x] Canvas: draw layers using `Renderer`
- [x] Canvas: click-to-select, drag-to-move selected layer
- [x] Toolbar: add image, add text, add rect, add bezel, render PNG
- [x] Inspector: edit frame, rotation, opacity, color, text properties, font picker
- [x] Layer list: reorder via drag, show/hide eye, delete, rename
- [x] Export dialog: choose preset / custom size, PNG / 1× 2× 3×
- [x] Light / dark mode tested

## CLI (`aiimageeditor-cli`)

- [x] Subcommand dispatcher
- [x] `new` (with `--preset` / `--width --height`)
- [x] `list` (layers, with z-order)
- [x] `add-image`, `add-text`, `add-rect`, `add-ellipse`, `add-bezel`
- [x] `move`, `resize`, `set-frame`, `rotate`
- [x] `set-text`, `set-font`, `set-color`, `set-alignment`
- [x] `opacity`, `visible`, `z`
- [x] `front`, `back`, `forward`, `backward`
- [x] `remove`, `duplicate`, `rename`
- [x] `bg` (set background color)
- [x] `assets add`, `assets list`, `assets remove`
- [x] `presets`, `bezels`, `fonts`
- [x] `render` (PNG output)
- [x] `inspect` (pretty-print JSON)
- [x] `--help` for every subcommand
- [x] Non-zero exit on failure with readable error

## MCP server (`aiimageeditor-mcp`)

- [x] stdio JSON-RPC 2.0 transport (newline-delimited)
- [x] `initialize` handshake
- [x] `tools/list` with full JSON Schema for each tool
- [x] `tools/call` dispatch to the shared command engine
- [x] One tool per command, plus `render` and `inspect`
- [x] `resources/list` exposes built-in presets + bezels as resources
- [x] Returns useful content (text + image) so the LLM can see the rendered PNG
- [x] Error responses include readable messages
- [x] Documented in `docs/MCP_GUIDE.md` with sample Claude Desktop config

## Tests
- [x] Document codec round-trip
- [x] CommandEngine: add/move/resize/zorder/remove
- [x] Renderer smoke test (renders to PNG > 0 bytes)
- [x] Color hex parsing

## Examples
- [x] `Examples/01-simple-hero.aiproj` (text over a colored background)
- [x] `Examples/02-device-bezel.aiproj` (single iPhone with screenshot)
- [x] `Examples/03-multi-screenshot.aiproj` (two phones + caption)
- [x] `Examples/build.sh` script that renders all examples via the CLI
