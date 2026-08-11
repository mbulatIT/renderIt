# AIImageEditor

> A macOS App Store screenshot editor that you can drive from a native GUI, a CLI, **or any MCP-aware AI assistant** — all backed by the same deterministic Swift engine.

AIImageEditor composes multiple images, adds rich text, wraps screenshots in device bezels, supports Z-ordering, positioning, rotation, and exports to PNG at App Store specs. It is purpose-built to be driven by humans **and** large language models.

[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](#license)

---

## Why

Designing App Store screenshots manually in Figma or Sketch is tedious and error-prone — sizes, bezels, retina densities, multiple locales. AIImageEditor flips the script:

- **One source of truth** — a JSON `.aiproj` file that any tool (GUI, shell, LLM) reads and writes.
- **Pixel-deterministic** — same JSON + same assets → identical PNG, every time.
- **Native-feeling GUI** for the parts humans are best at (layout, typography, picking colours).
- **CLI + MCP** for everything that wants to be scripted or generated.

---

## The three surfaces

```
                    ┌──────────────────────────────────┐
                    │       AIImageEditorCore          │
                    │   (Swift, no external deps)      │
                    │   Document · Renderer · Commands │
                    └──────────────┬───────────────────┘
                                   │
            ┌──────────────────────┼─────────────────────────┐
            ▼                      ▼                         ▼
     ┌──────────────┐    ┌────────────────────┐   ┌────────────────────┐
     │ AIImageEditor│    │ aiimageeditor-cli  │   │ aiimageeditor-mcp  │
     │ SwiftUI .app │    │ command-line tool  │   │ JSON-RPC over stdio│
     └──────────────┘    └────────────────────┘   └────────────────────┘
            ▲                      ▲                         ▲
            │                      │                         │
         humans              shell scripts          Claude / Codex /
                              & make targets       Gemini / Cursor / …
```

All three surfaces call the same `CommandEngine` and use the same `DocumentCodec`. There is no behaviour that exists in one and not the others.

---

## Features

- **Multi-page projects** with multiple export viewports ("previews") per page — one PNG per preview at export time.
- **Device bezels** — copyright-safe geometric frames for iPhone 17 Pro / Pro Max / SE, iPad Pro 13"/11", MacBook 14"/16", with auto-fitting screenshots and selectable chrome colours.
- **Text** — arbitrary multiline strings, full font catalogue, size / weight / italic / colour / alignment / line-spacing / kerning / drop shadow, graceful fallback when a family is missing.
- **Shapes** — rectangles and ellipses with fill, stroke, corner radius.
- **Images** — assets imported once, referenced anywhere, with `fit` / `fill` / `stretch` content modes.
- **Transforms** — frame, rotation, opacity, blend mode, explicit z-index plus `front` / `back` / `forward` / `backward` shortcuts.
- **App Store presets** — iPhone 6.7" / 6.5", iPad Pro 13" / 12.9", Mac, Watch Ultra, plus generic 9:16 / 16:9 / 1024².
- **Keyboard shortcuts** — arrow-nudge (±1 px, Shift = ±10 px), Tab / Shift+Tab to cycle layers, Esc to deselect, Cmd+= / Cmd+- / Cmd+0 / Cmd+1 zoom, Cmd+Shift+] / Cmd+Shift+[ to-front / to-back, Cmd+Option+] / Cmd+Option+[ forward / backward, plus the usual Cmd+Z/C/V/X/D/Delete.
- **Stateless MCP server** — every tool call reads, mutates, writes the JSON to disk so external editors and the LLM stay in sync.

Full per-feature breakdown: [docs/FEATURES.md](docs/FEATURES.md).

---

## Build

Requires macOS 14+, Xcode 15+, and [Tuist](https://tuist.io) (`brew install tuist`).

```bash
# 1. Generate the Xcode project from Project.swift
tuist generate

# 2. Build the GUI app
xcodebuild -workspace AIImageEditor.xcworkspace \
           -scheme AIImageEditor -configuration Debug \
           -derivedDataPath Derived build

# 3. Build the CLI and MCP server
xcodebuild -workspace AIImageEditor.xcworkspace \
           -scheme aiimageeditor-cli -configuration Release \
           -derivedDataPath Derived build
xcodebuild -workspace AIImageEditor.xcworkspace \
           -scheme aiimageeditor-mcp -configuration Release \
           -derivedDataPath Derived build
```

Binaries land in `Derived/Build/Products/Release/` (the `-derivedDataPath Derived`
flag keeps them project-local — omit it and Xcode uses `~/Library/Developer/Xcode/DerivedData/`
instead; Xcode also normalises dashes to underscores on disk — the file is
`aiimageeditor_cli`, not `aiimageeditor-cli`).

### Install on `$PATH`

```bash
sudo cp Derived/Build/Products/Release/aiimageeditor_cli /usr/local/bin/aiimageeditor-cli
sudo cp Derived/Build/Products/Release/aiimageeditor_mcp /usr/local/bin/aiimageeditor-mcp
```

---

## Quick start — CLI

```bash
# 1. Create an iPhone 6.7" project
aiimageeditor-cli new --preset iphone-6.7 --output hero.aiproj

# 2. Wrap a screenshot in an iPhone 17 Pro bezel
aiimageeditor-cli add-bezel --project hero.aiproj \
    --device iphone17Pro --asset-path screens/home.png --at center

# 3. Add a title
aiimageeditor-cli add-text --project hero.aiproj \
    --text "Edit photos with AI" \
    --font-size 110 --font-weight bold --color "#FFFFFF" --at top-center

# 4. Render PNG
aiimageeditor-cli render --project hero.aiproj --output hero.png
```

Full CLI reference: [docs/CLI_GUIDE.md](docs/CLI_GUIDE.md) · [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md).

---

## Setup guide — AI coding tools (CLI)

Each AI assistant below speaks MCP. Register `aiimageeditor-mcp` once and the assistant can build screenshots end-to-end from a natural-language prompt: pick a preset, drop a bezel, add headlines, render PNG, iterate.

> Replace `/usr/local/bin/aiimageeditor-mcp` below with the actual path on your machine if you installed elsewhere. All examples assume the binary is executable.

### Claude Code (`claude` CLI)

```bash
claude mcp add aiimageeditor /usr/local/bin/aiimageeditor-mcp
```

Or edit `~/.claude/settings.json`:

```jsonc
{
  "mcpServers": {
    "aiimageeditor": {
      "command": "/usr/local/bin/aiimageeditor-mcp"
    }
  }
}
```

Verify:

```bash
claude mcp list                 # should show "aiimageeditor"
```

Then in any Claude Code session:

> *"Create a 3-preview iPhone 6.7" project at `~/screens/release.aiproj`, drop an iPhone 17 Pro bezel into each preview using the PNGs in `~/screens/captures/`, headline each with the phrases I'll give you, and render."*

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```jsonc
{
  "mcpServers": {
    "aiimageeditor": {
      "command": "/usr/local/bin/aiimageeditor-mcp",
      "args": []
    }
  }
}
```

Restart Claude Desktop. Tools appear under the 🔌 menu with the `aiimageeditor.` prefix. The `render` tool returns the PNG inline so Claude can *see* what it just produced and self-correct.

### Codex CLI (OpenAI)

Edit `~/.codex/config.toml`:

```toml
[mcp_servers.aiimageeditor]
command = "/usr/local/bin/aiimageeditor-mcp"
args = []
```

Reload Codex and the `aiimageeditor.*` tools are available in any session.

### Gemini CLI (Google)

Edit `~/.gemini/settings.json`:

```jsonc
{
  "mcpServers": {
    "aiimageeditor": {
      "command": "/usr/local/bin/aiimageeditor-mcp"
    }
  }
}
```

Verify with `gemini mcp list`.

### Cursor

Add to either `~/.cursor/mcp.json` (global) or `.cursor/mcp.json` in the workspace:

```jsonc
{
  "mcpServers": {
    "aiimageeditor": {
      "command": "/usr/local/bin/aiimageeditor-mcp"
    }
  }
}
```

Then restart Cursor and confirm the server in **Settings → MCP**.

### Continue.dev

Add to `~/.continue/config.yaml`:

```yaml
mcpServers:
  - name: aiimageeditor
    command: /usr/local/bin/aiimageeditor-mcp
```

Reload Continue from the command palette.

### Cline (VS Code)

Open the Cline panel → **MCP Servers** → **Edit Settings**, then:

```jsonc
{
  "mcpServers": {
    "aiimageeditor": {
      "command": "/usr/local/bin/aiimageeditor-mcp",
      "transportType": "stdio"
    }
  }
}
```

### Aider, plain shells, or any non-MCP assistant

Aider doesn't speak MCP yet — and you don't need it to. Because `aiimageeditor-cli` is deterministic and well-documented, any assistant with shell access can drive it. Hand it [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md) as context and ask:

> *"Use `aiimageeditor-cli` to build me a 3-screenshot App Store gallery from the PNGs in `~/captures/`. Project file at `./hero.aiproj`. Render to `./out/`."*

The same approach works for `ollama`, `llm`, GitHub Copilot Chat, and the OpenAI/Anthropic playground when you're pasting commands by hand.

### Verifying any of the above

Once the server is registered, ask the assistant to list its tools — you should see ~30 named `new`, `add-text`, `add-bezel`, `previews`, `render`, etc. Or run the stdio handshake yourself:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"smoke","version":"0"}}}' \
  | aiimageeditor-mcp
```

Full MCP protocol details: [docs/MCP_GUIDE.md](docs/MCP_GUIDE.md).

---

## The `.aiproj` file format

A project is a single JSON file. Assets live as paths (relative to the project file or absolute), so the JSON itself stays small and version-controllable.

```jsonc
{
  "version": 2,
  "assets": {
    "home": { "path": "captures/home.png" }
  },
  "pages": [{
    "id": "page-1",
    "name": "Page 1",
    "canvas": { "width": 1290, "height": 2796, "background": "#FFFFFF" },
    "layout": { "previewWidth": 1290, "previewHeight": 2796, "spacing": 80 },
    "previews": [
      { "id": "page-1-preview-1", "name": "Preview 1",
        "frame": { "x": 0, "y": 0, "w": 1290, "h": 2796 },
        "background": "#0A0F2A" }
    ],
    "layers": [
      { "id": "title", "kind": "text",
        "frame": { "x": 100, "y": 200, "w": 1090, "h": 240 },
        "zIndex": 1, "opacity": 1, "rotation": 0, "visible": true,
        "payload": { "text": { "text": "Hello", "fontSize": 110,
                               "fontWeight": "bold", "color": "#FFFFFF",
                               "alignment": "center" } } }
    ]
  }],
  "activePageId": "page-1"
}
```

Full schema with every field: [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md).

---

## Project layout

```
AIImageEditor/
├── README.md                       # this file
├── CLAUDE.md                       # entry point for AI assistants
├── Project.swift                   # Tuist manifest
├── docs/                           # design + reference docs
├── AIImageEditorCore/Sources/      # shared engine (model + renderer + commands)
├── AIImageEditor/Sources/          # SwiftUI macOS app
├── CLI/Sources/                    # aiimageeditor-cli executable
├── MCP/Sources/                    # aiimageeditor-mcp executable (stdio JSON-RPC)
└── Examples/                       # sample .aiproj projects + screenshots
```

Deeper dive: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Documentation map

| File | What's in it |
|------|---|
| [docs/TODO.md](docs/TODO.md) | Authoritative status — done / in progress / open. |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Target graph, data flow, design decisions. |
| [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) | `.aiproj` JSON schema, every layer type, every field. |
| [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md) | Every command (CLI + MCP), arguments, examples. |
| [docs/CLI_GUIDE.md](docs/CLI_GUIDE.md) | End-to-end scripted workflow. |
| [docs/MCP_GUIDE.md](docs/MCP_GUIDE.md) | Protocol details and host registration. |
| [docs/PUBLISHING.md](docs/PUBLISHING.md) | Signed + notarized Developer ID distribution (DMG). |
| [docs/DEVICE_BEZELS.md](docs/DEVICE_BEZELS.md) | Built-in device frames, aspect ratios, screen insets. |
| [docs/PRESETS.md](docs/PRESETS.md) | App Store screenshot sizes, ready-made canvas presets. |
| [docs/FEATURES.md](docs/FEATURES.md) | Per-feature breakdowns and acceptance criteria. |
| [docs/EXAMPLES.md](docs/EXAMPLES.md) | Ready-to-run example projects and command sequences. |

---

## Contributing

PRs welcome. The codebase is small and the engine has no external Swift dependencies — Foundation + AppKit + CoreGraphics + UniformTypeIdentifiers only — so it builds quickly and is easy to reason about.

Run the bundled examples as a smoke test before submitting:

```bash
./Examples/build.sh
ls Examples/out
```

---

## License

MIT.
