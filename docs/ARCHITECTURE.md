# Architecture

## Targets

```
                ┌──────────────────────────────────┐
                │       AIImageEditorCore          │
                │   (.staticFramework, macOS)      │
                │  - Document model                │
                │  - JSON codec                    │
                │  - Renderer (CoreGraphics)       │
                │  - Device bezels                 │
                │  - Command engine                │
                │  - Errors                        │
                └──────────────┬───────────────────┘
                               │
        ┌──────────────────────┼─────────────────────────┐
        ▼                      ▼                         ▼
 ┌──────────────┐    ┌────────────────────┐   ┌────────────────────┐
 │ AIImageEditor│    │ aiimageeditor-cli  │   │ aiimageeditor-mcp  │
 │ (.app)       │    │ (.commandLineTool) │   │ (.commandLineTool) │
 │ SwiftUI GUI  │    │ subcommand parser  │   │ JSON-RPC over stdio│
 └──────────────┘    └────────────────────┘   └────────────────────┘
```

All three frontends call the same `CommandEngine` and use the same `DocumentCodec`,
so they are guaranteed to produce identical results from identical inputs.

## Data flow

```
JSON (.aiproj) ──decode──► Document ──Command ──► Document' ──encode──► JSON
                                │
                                └──Renderer──► NSImage / PNG Data
```

## Why this shape

- **Single source of truth.** The document JSON is the contract between humans,
  LLMs and the GUI. Every mutation is expressible as a typed `Command`.
- **No external deps.** Foundation + AppKit + CoreGraphics + UniformTypeIdentifiers
  only — keeps the CLI/MCP binaries small and fast to build.
- **Reproducible.** Given the same JSON + the same asset bytes, the renderer
  produces a deterministic PNG.

## Coordinate system

The document uses a **top-left origin** (x right, y down) with pixel units.
This matches the way every image and every App Store screenshot is measured,
and matches how an LLM thinks about positions ("at y=200"). Internally the
renderer flips into Core Graphics' bottom-left coordinate space when drawing.

## Rendering pipeline

1. Sort layers by `zIndex` ascending (stable for ties via array order).
2. Allocate an `CGContext` of canvas size in DeviceRGB.
3. Fill canvas background (`Color` or transparent).
4. For each visible layer:
   a. Save graphics state.
   b. Translate to layer center, rotate, translate back.
   c. Apply opacity via layer alpha.
   d. Dispatch on `LayerKind` → typed drawer.
   e. Restore.
5. Wrap context as `NSImage` (for GUI) or encode PNG (for CLI/MCP).

## Layer drawers

| Kind | Drawer |
|------|--------|
| `image` | `NSImage(byReferencingFile:)` then `draw(in:)` |
| `text` | `NSAttributedString` with `NSFont`, `NSColor`, `NSParagraphStyle`, drawn into the layer frame; auto-shrink optional |
| `rect` | `CGPath` rounded rect, fill + optional stroke |
| `ellipse` | `CGContext.fillEllipse`, fill + optional stroke |
| `deviceBezel` | `BezelRenderer` draws the chrome, then draws the screenshot into `screenRect` |
| `group` | recursive render of child layers |

## Command engine

`Command` is a Swift enum carrying typed payloads. `CommandEngine.apply(_:to:)`
returns a mutated `Document` (value semantics → cheap copies, easy undo).
The same enum is the public API for CLI and MCP; the only difference is the
serialization (argv vs JSON).

## MCP transport

Newline-delimited JSON-RPC 2.0 on stdin / stdout. Each line is a complete JSON
message. The server keeps document state in-memory keyed by a session/handle id
that the client supplies — but the canonical pattern is **stateless**: every
tool call takes a project path on disk, the server loads → mutates → saves,
which is the most LLM-friendly model (the LLM can also read the file itself).

## Bezels (copyright-safe, programmatic)

We draw geometric device frames rather than ship vendor artwork — round-rect
chrome, side rails, Dynamic-Island shapes, camera bumps, MacBook stand silhouette.
Each device knows its outer aspect and inner `screenRect` so screenshots inset
perfectly. The catalog is in `DeviceBezel.swift`.
