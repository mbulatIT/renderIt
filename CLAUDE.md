# AIImageEditor

A macOS App Store screenshot/image editor — composes multiple images, adds rich text,
wraps screenshots in device bezels, supports Z-ordering, positioning, rotation, and
exports to PNG at App Store specs.

Designed to be driven three ways:
1. **Native macOS GUI** (SwiftUI document-based editor).
2. **CLI** (`aiimageeditor-cli`) for batch / scripted use by humans and LLMs.
3. **MCP server** (`aiimageeditor-mcp`) so any MCP-aware LLM (Claude Desktop, Claude
   Code, etc.) can build screenshots from natural-language prompts.

All three surfaces share a single Swift core (`AIImageEditorCore`) and the same
JSON project format (`.aiproj`). LLMs read/write the JSON directly or use the typed
commands; the GUI is just another consumer of the same engine.

---

## Documentation map

Start with the TODO list, then read by topic. Each doc is small and self-contained.

| File | What's in it |
|------|---|
| [docs/TODO.md](docs/TODO.md) | Master todo list. Per-feature checklists. Authoritative status. |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System diagram, target graph, data flow, design decisions. |
| [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) | `.aiproj` JSON schema, every layer type, every field. |
| [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md) | Every command (CLI + MCP), arguments, examples. Single source of truth. |
| [docs/CLI_GUIDE.md](docs/CLI_GUIDE.md) | How to install/invoke the CLI, end-to-end scripted workflow. |
| [docs/MCP_GUIDE.md](docs/MCP_GUIDE.md) | How to register the MCP server in Claude Desktop / Claude Code. |
| [docs/PUBLISHING.md](docs/PUBLISHING.md) | Signed + notarized Developer ID distribution (DMG via `Scripts/release.sh`). |
| [docs/DEVICE_BEZELS.md](docs/DEVICE_BEZELS.md) | Built-in device frames (iPhone, iPad, Mac), aspect ratios, screen insets. |
| [docs/PRESETS.md](docs/PRESETS.md) | App Store screenshot sizes, ready-made canvas presets. |
| [docs/FEATURES.md](docs/FEATURES.md) | Per-feature breakdowns and acceptance criteria. |
| [docs/EXAMPLES.md](docs/EXAMPLES.md) | Ready-to-run example projects and command sequences. |

---

## TL;DR for LLMs

You almost certainly want one of these:

```bash
# Make a new App-Store-sized project
aiimageeditor-cli new --preset iphone-6.7 --output screenshot.aiproj

# Drop a screenshot inside an iPhone 15 Pro bezel
aiimageeditor-cli add-bezel screenshot.aiproj --device iphone15Pro --asset home.png --at center

# Add a title
aiimageeditor-cli add-text screenshot.aiproj --text "Edit photos with AI" \
    --font-size 110 --font-weight bold --color "#FFFFFF" --at "top-center"

# Render PNG
aiimageeditor-cli render screenshot.aiproj --output screenshot.png
```

For full command list see [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md).
For the MCP equivalent see [docs/MCP_GUIDE.md](docs/MCP_GUIDE.md).

---

## Build / run

```bash
# generate the Xcode project from the Tuist manifest
tuist generate

# build the app
xcodebuild -workspace AIImageEditor.xcworkspace -scheme AIImageEditor -configuration Debug build

# build CLI / MCP
xcodebuild -workspace AIImageEditor.xcworkspace -scheme aiimageeditor-cli -configuration Release build
xcodebuild -workspace AIImageEditor.xcworkspace -scheme aiimageeditor-mcp -configuration Release build
```

Binaries land in `Derived/Build/Products/Release/`.

---

## Project layout

```
AIImageEditor/
├── CLAUDE.md                        # this file
├── docs/                            # all design / reference docs
├── Project.swift                    # Tuist manifest
├── AIImageEditorCore/Sources/       # shared engine (model + renderer + commands)
├── AIImageEditor/Sources/           # SwiftUI macOS app
├── AIImageEditor/Resources/         # asset catalogs etc.
├── AIImageEditor/Tests/             # unit tests
├── CLI/Sources/                     # aiimageeditor-cli executable
├── MCP/Sources/                     # aiimageeditor-mcp executable (stdio JSON-RPC)
└── Examples/                        # sample .aiproj projects + screenshots
```
