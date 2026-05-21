# Per-feature checklists

Implementation breakdowns. The headline list lives in [TODO.md](TODO.md);
these are the *details* for each feature so nothing is silently dropped.

## Compose multiple images
- [x] image layer references an asset, not a path → multi-instance is cheap
- [x] each layer has its own frame, opacity, rotation, blend mode
- [x] `contentMode` of fit / fill / stretch
- [x] add an asset and an image layer in a single CLI call (`--asset-path`)

## Text
- [x] arbitrary string, multiline
- [x] font family + size + weight + italic
- [x] color
- [x] alignment (left / center / right / justified)
- [x] line spacing, kerning
- [x] optional drop shadow
- [x] `fonts` command lists every family on the system
- [x] gracefully falls back to system font if family is unknown

## Z-axis reordering
- [x] explicit `zIndex` numeric value
- [x] `front` / `back` / `forward` / `backward` shortcuts
- [x] GUI: drag-to-reorder in the layer list
- [x] documented in COMMAND_REFERENCE

## Device bezels
- [x] catalog of 7 devices (iPhone Pro / Pro Max / SE, iPad Pro 13 / 11, MacBook 14 / 16)
- [x] each computes screenRect → screenshot auto-fits regardless of caller's frame
- [x] copyright-safe (geometric, not vendor PNGs)
- [x] CLI command imports a screenshot AND adds the bezel in one shot

## Positioning
- [x] explicit `--frame "x,y,w,h"`
- [x] explicit `--to "x,y"`
- [x] anchor tokens: `top-left`, `top-center`, `top-right`, `center-left`,
      `center`, `center-right`, `bottom-left`, `bottom-center`, `bottom-right`
- [x] `--size` plus `--at` combo for the common "pick the size, place it
      somewhere sensible" case

## Multi-frontend
- [x] AIImageEditorCore is target-agnostic (no AppKit-only types in public API)
- [x] GUI uses Renderer for the canvas preview
- [x] CLI parses argv → builds Command → calls CommandEngine
- [x] MCP parses JSON-RPC → builds Command → calls CommandEngine

## Examples
- [x] simple hero (background + title + subtitle)
- [x] single device bezel
- [x] multiple devices

## Documentation
- [x] CLAUDE.md as entry point with links to every doc
- [x] FILE_FORMAT.md describes every field
- [x] COMMAND_REFERENCE.md describes every command
- [x] CLI_GUIDE / MCP_GUIDE for the two LLM surfaces
