# CLI guide

The `aiimageeditor-cli` is a single-binary command-line frontend over the same
`AIImageEditorCore` engine the GUI app uses. Anything you can do in the GUI you
can also do here — designed so LLMs and shell scripts can drive it deterministically.

This document is the **complete** reference for the binary as of v3.3. Every command,
every flag, with an end-to-end runnable example for each.

---

## 1. Install / locate

After building:

```bash
xcodebuild -workspace AIImageEditor.xcworkspace \
  -scheme aiimageeditor-cli -configuration Release build
```

The binary lands in:

```
Derived/Build/Products/Release/aiimageeditor_cli
```

(Xcode normalises the dash in `aiimageeditor-cli` to an underscore on disk.)

To use it as `aiimageeditor-cli` on `$PATH`:

```bash
cp Derived/Build/Products/Release/aiimageeditor_cli /usr/local/bin/aiimageeditor-cli
```

Through this guide, `$CLI` refers to whichever path you've installed it under.

---

## 2. Concepts (in one screen)

```
Document (.aiproj, JSON on disk)
├── assets              [id → file path]   shared across all pages
└── pages
    └── Page
        ├── canvas       derived from previews, NOT user-settable
        ├── layout       previewWidth / previewHeight / spacing
        ├── previews    [Preview]  ← export viewports — one PNG each
        │   └── Preview  { id, name, frame, background (always opaque) }
        └── layers      [Layer]   text / image / rect / ellipse / deviceBezel
```

Key invariants:

* The **page canvas auto-grows** from previews + margins (1 preview-width on the
  left and right, half a preview-height on top and bottom). You can't set it
  directly — change `previewWidth`/`Height`/`spacing` or `count` and the canvas
  reflows.
* **Previews are always opaque.** The data model forces `background.a = 1` on
  every preview, regardless of how you set it.
* **Each preview is one exported PNG.** A "page with 5 previews" exports 5 PNGs.
* **Layers** live in page-canvas coordinates and may straddle multiple previews.
  At export time each preview clips to its own rectangle, so only the part of
  the layer that falls inside the preview rect appears in that PNG.
* **Workspace background defaults to white.**
* **Asset IDs are shared at the document level**, not per-page. Drop one image
  once, reference it from any number of layers / pages.

---

## 3. Quickstart — make an App Store gallery

```bash
PROJECT=hero.aiproj

# 1. New iPhone 6.7" project
$CLI new --output $PROJECT --preset iphone-6.7

# 2. Three previews lined up horizontally
$CLI set-layout --project $PROJECT --count 3

# 3. Give each preview its own background
$CLI previews set-background --project $PROJECT --id page-1-preview-1 --color "#0A0F2A"
$CLI previews set-background --project $PROJECT --id page-1-preview-2 --color "#1A1F4A"
$CLI previews set-background --project $PROJECT --id page-1-preview-3 --color "#0A0F2A"

# 4. Drop a phone bezel into each preview (use one preview's centre as the anchor)
$CLI add-bezel --project $PROJECT --device iphone17Pro --color "Silver" \
    --frame "1290,1700,1290,2200" --id phone1
$CLI add-bezel --project $PROJECT --device iphone17Pro --color "Deep blue" \
    --frame "3580,1700,1290,2200" --id phone2
$CLI add-bezel --project $PROJECT --device iphone17Pro --color "Cosmic orange" \
    --frame "5870,1700,1290,2200" --id phone3

# 5. Headline above each preview
$CLI add-text --project $PROJECT --text "Fast" \
    --frame "1290,500,1290,250" --font-size 200 --color "#FFFFFF" \
    --font-weight bold --align center --id title1
# … and so on for "Beautiful", "Yours"

# 6. Export — one PNG per preview
$CLI previews export --project $PROJECT --output ./gallery_out --scale 1
ls ./gallery_out
# Preview 1.png  Preview 2.png  Preview 3.png
```

---

## 4. Reference — every command

Every command takes positional/named arguments in the form `--flag value` or
`--flag` (boolean). The order of flags doesn't matter. Required flags are
**bold**. The `--project` flag is required by every command that reads or
mutates a project file (everything except `presets / bezels / fonts / help`).

### 4.1 Discovery

#### `presets`
List the built-in canvas / preview presets (iPhone 6.7", iPad Pro 13", Mac, etc).

```bash
$CLI presets
# iphone-6.7           1290x2796  iPhone 6.7" (1290×2796)
# iphone-6.5           1284x2778  iPhone 6.5" (1284×2778)
# …
```

#### `bezels`
List every device bezel with its colour variants.

```bash
$CLI bezels
# iphone17Pro            iphone          iPhone 17 Pro   colors=[Silver, Deep blue, Cosmic orange]
# …
```

#### `fonts`
List every installed font family on the machine.

```bash
$CLI fonts | head
```

#### `list`  — **`--project`**
Pretty-print the page graph for a project — pages, previews, layers in z-order.

```bash
$CLI list --project myproj.aiproj
# document version=2  pages=1  active=page-1
# * page page-1  'Page 1'  3870x5592 bg=#FFFFFF  previews=1 spacing=80 preview=1290x2796
#     z=1.0  text       title  frame=[80,140,1130,260]
```

#### `inspect`  — **`--project`**
Pretty-print the project's JSON.

```bash
$CLI inspect --project myproj.aiproj | head -30
```

---

### 4.2 Project / pages

#### `new`  — **`--output`** + (**`--preset`** OR **`--width --height`**)
Create a new `.aiproj` file.

| Flag             | Type   | Notes |
|------------------|--------|-------|
| **`--output`**   | path   | Where to write the new file |
| `--preset <id>`  | string | Pick from `presets` |
| `--width <int>`  | int    | Explicit width (must pair with `--height`) |
| `--height <int>` | int    | Explicit height (must pair with `--width`) |
| `--background <hex>` | `#RRGGBB` / `#RRGGBBAA` / `transparent` | Workspace background; **default = white** |

```bash
$CLI new --output a.aiproj --preset iphone-6.7
$CLI new --output b.aiproj --width 1200 --height 800 --background "#101030"
```

#### `pages list`  — **`--project`**

```bash
$CLI pages list --project myproj.aiproj
# * page-1  'Page 1'  3870x5592
```

#### `pages add`  — **`--project`**

| Flag | Type | Notes |
|------|------|-------|
| `--id <id>` | string | Optional; auto-generated if omitted |
| `--name "..."` | string | Display name |
| `--preset <id>` OR (`--width --height`) | | Canvas defaults for new page; inherits active page's if omitted |

```bash
$CLI pages add --project myproj.aiproj --name "Features" --preset iphone-6.7
```

#### `pages remove / rename / select`  — **`--project --id`**

```bash
$CLI pages rename --project myproj.aiproj --id page-2 --name "Onboarding"
$CLI pages select --project myproj.aiproj --id page-2
$CLI pages remove --project myproj.aiproj --id page-2
```

The active page is the default target for any later command that omits `--page`.
A document always has at least one page; removing the last one auto-recreates a blank one.

---

### 4.3 Page settings

#### `set-layout`  — **`--project`**  [`--page <id>`]
Adjust the preview defaults; the canvas reflows automatically.

| Flag | Type | Notes |
|------|------|-------|
| `--count <int>` | int | Adds or removes previews to match |
| `--preview-width <num>` | double | Default width for each preview |
| `--preview-height <num>` | double | Default height for each preview |
| `--spacing <num>` | double | Gap between adjacent previews (px) |

```bash
$CLI set-layout --project myproj.aiproj --count 5 --spacing 120
$CLI set-layout --project myproj.aiproj --preview-width 1290 --preview-height 2796
```

#### `bg` / `set-background`  — **`--project --color`**  [`--page <id>`]
Workspace background (the area around the previews).

```bash
$CLI bg --project myproj.aiproj --color "#101830"
$CLI bg --project myproj.aiproj --color transparent
```

---

### 4.4 Previews (export viewports)

#### `previews list`  — **`--project`**  [`--page`]

```bash
$CLI previews list --project myproj.aiproj
# page-1-preview-1   'Preview 1'  frame=[1290,1398,1290,2796]  bg=#0A0F2A
```

#### `previews add`  — **`--project`**  [`--page`]

| Flag | Type | Notes |
|------|------|-------|
| `--id <id>` | string | Optional |
| `--name "..."` | string | Display name |
| `--background <hex>` | hex colour | Solid background (alpha forced to 1) |

```bash
$CLI previews add --project myproj.aiproj --name "Features" --background "#1B1F4A"
```

#### `previews remove`  — **`--project --id`**  [`--page`]

```bash
$CLI previews remove --project myproj.aiproj --id page-1-preview-3
```

#### `previews rename`  — **`--project --id --name`**

```bash
$CLI previews rename --project myproj.aiproj --id page-1-preview-1 --name "Hero"
```

#### `previews set-background`  — **`--project --id --color`**

```bash
$CLI previews set-background --project myproj.aiproj \
    --id page-1-preview-1 --color "#0A0F2A"
```

#### `previews export`  — **`--project --output <dir>`**  [`--page`] [`--scale 1|2|3`]
Write one PNG per preview to the given directory. Filenames are taken from each
preview's `name`.

```bash
$CLI previews export --project myproj.aiproj --output ./out --scale 2
# wrote ./out/Hero.png  (245 KB)
# wrote ./out/Preview 2.png  (231 KB)
```

---

### 4.5 Assets

Assets live at the document level. Layers reference them by `id`.

#### `assets add`  — **`--project --path`**  [`--id`]
Auto-generates an id from the file basename if `--id` is omitted, and **deduplicates**
— if a file at the same path is already registered, returns the existing id.

```bash
$CLI assets add --project myproj.aiproj --path ~/Pictures/home.png
# added asset home  /Users/.../home.png
```

#### `assets list`  — **`--project`**

```bash
$CLI assets list --project myproj.aiproj
# home   /Users/.../home.png
```

#### `assets remove`  — **`--project --id`**

```bash
$CLI assets remove --project myproj.aiproj --id home
```

---

### 4.6 Adding layers

All `add-*` commands take optional `--page <id>` and `--z <num>` (zIndex). Frame
can be expressed two ways:

* **Explicit:** `--frame "x,y,w,h"`
* **Anchored:** `--at <position>` plus optional `--size "w,h"` — position tokens
  are `top-left`, `top-center`, `top-right`, `center-left`, `center`,
  `center-right`, `bottom-left`, `bottom-center`, `bottom-right`.

#### `add-text`  — **`--project --text`**  [+ frame OR --at]

| Flag | Default |
|------|---------|
| `--font <name>` | `SF Pro Display` |
| `--font-size <num>` | 72 |
| `--font-weight <ultraLight\|thin\|light\|regular\|medium\|semibold\|bold\|heavy\|black>` | regular |
| `--italic` | false |
| `--color "#RRGGBB"` | `#FFFFFF` |
| `--align left\|center\|right\|justified` | center |
| `--line-spacing <num>` | 0 |
| `--kerning <num>` | 0 |
| `--shadow "color,dx,dy,blur"` | none |
| `--id <id>` | auto |

```bash
$CLI add-text --project myproj.aiproj \
    --text "Edit photos with AI" \
    --frame "80,140,1130,260" --font-size 110 --font-weight bold \
    --color "#FFFFFF" --id title
```

#### `add-image`  — **`--project`** + (`--asset <id>` OR `--asset-path <file>`) + frame
`--asset-path` auto-registers the file as an asset.

| Flag | Notes |
|------|-------|
| `--content-mode fit\|fill\|stretch` | default `fit` |

```bash
$CLI add-image --project myproj.aiproj \
    --asset-path ~/Pictures/logo.png \
    --at center --size "600,600" --content-mode fit --id logo
```

#### `add-rect` / `add-ellipse`  — **`--project`** + frame

| Flag | Notes |
|------|-------|
| `--fill "#RRGGBB[AA]"` | default opaque white |
| `--stroke "color,width"` | optional |
| `--radius <num>` | rect only — corner radius |

```bash
$CLI add-rect --project myproj.aiproj \
    --frame "60,60,800,300" --fill "#101030AA" --radius 24 --id panel
```

#### `add-bezel`  — **`--project --device`** + frame

| Flag | Notes |
|------|-------|
| `--device <id>` | from `bezels` |
| `--color "<Label>"` | for image-backed devices; see `bezels` for valid labels |
| `--screenshot-path <file>` | auto-imports + assigns the file as the bezel's screenshot |
| `--screenshot-asset <id>` | reuse an existing asset |
| `--chrome-color "#RRGGBB"` | programmatic (legacy) bezels only |
| `--frame "x,y,w,h"` | explicit position |
| `--at <position>` `--height <num>` | anchored — width derived from the device aspect |

```bash
$CLI add-bezel --project myproj.aiproj \
    --device iphone17Pro --color "Silver" \
    --screenshot-path ~/Screenshots/home.png \
    --at center --height 2400 --id phone
```

---

### 4.7 Editing layers

All editing commands take `--project` and `--id <layerId>`, plus optional `--page <id>`.

| Command | Extra flags |
|---------|-------------|
| `move` | `--to "x,y"` OR `--at <position>` OR `--dx N --dy N` |
| `resize` | `--width <num>` and/or `--height <num>` |
| `set-frame` | `--frame "x,y,w,h"` |
| `rotate` | `--degrees <num>` (absolute, around frame centre) |
| `opacity` | `--value 0..1` |
| `visible` | `--value true\|false` |
| `blend` | `--mode normal\|multiply\|screen\|overlay\|softLight\|hardLight\|darken\|lighten` |
| `rename` | `--name "..."` |
| `duplicate` | `[--new-id <id>]` |
| `remove` | (no extra args) |
| `set-text` | `--text "..."` |
| `set-font` | `--font` `--font-size` `--font-weight` `--italic` |
| `set-color` | `--color "#RRGGBB"` (text → font colour, shape → fill, bezel → chrome override) |
| `set-alignment` | `--align left\|center\|right\|justified` |
| `set-bezel-color` | `--color "<Label>"` (for image-backed bezels) |
| `set-bezel-screenshot` | `--asset-path <file>` OR `--asset <id>` OR `--clear` |

```bash
$CLI move           --project myproj.aiproj --id phone --to "500,1800"
$CLI rotate         --project myproj.aiproj --id phone --degrees -6
$CLI set-text       --project myproj.aiproj --id title --text "Hello world"
$CLI set-bezel-color --project myproj.aiproj --id phone --color "Deep blue"
$CLI set-bezel-screenshot --project myproj.aiproj --id phone --asset-path ~/shot.png
$CLI set-bezel-screenshot --project myproj.aiproj --id phone --clear
```

---

### 4.8 Z-order

| Command | Flags |
|---------|-------|
| `z` / `set-z` | `--value <num>` |
| `front` / `bring-to-front` | — |
| `back` / `send-to-back` | — |
| `forward` / `move-forward` | — |
| `backward` / `move-backward` | — |

```bash
$CLI front    --project myproj.aiproj --id title
$CLI z        --project myproj.aiproj --id panel --value 5
```

---

### 4.9 Rendering

#### `render`  — **`--project --output`**

| Flag | Notes |
|------|-------|
| **`--output <file.png>`** | Output path |
| `--scale 1\|2\|3` | Pixel scale; default 1 |
| `--page <id>` | Which page to render; default = active |
| `--preview <id>` | Render just that **one preview** clipped to its frame; canvas-sized otherwise |
| `--mode editor\|export` | `editor` includes the 50%-dim-outside-previews overlay; `export` is the clean version. Default `export`. Ignored when `--preview` is set. |

```bash
# Whole work area (export mode)
$CLI render --project myproj.aiproj --output workarea.png --scale 1

# Editor view (with dim)
$CLI render --project myproj.aiproj --output editor.png --mode editor

# Single preview as a clean PNG
$CLI render --project myproj.aiproj --output hero.png --preview page-1-preview-1
```

For batch-exporting *every* preview at once, prefer `previews export` — it
writes one PNG per preview with sensible filenames.

---

## 5. Position tokens

Anywhere `--at <token>` is accepted:

```
top-left   top-center   top-right
center-left center  center-right
bottom-left bottom-center bottom-right
```

Each token positions the layer relative to the canvas, with a built-in margin of
≈4% of the relevant axis. To override, use `--frame "x,y,w,h"` instead.

---

## 6. Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `64` | Usage error — bad/missing flag |
| `65` | Data error — engine could not satisfy the command (missing layer / asset / preset, etc.) |
| `74` | I/O error — could not read input or write output |

All non-zero exits print a human-readable error to stderr beginning with `error:`.

---

## 7. End-to-end demo script

See [`Examples/build.sh`](../Examples/build.sh) for a complete script that
renders every example project. Re-run it any time to verify your local build is
producing the expected images.

---

## 8. See also

- [docs/MCP_GUIDE.md](MCP_GUIDE.md) — same commands exposed as MCP tools.
- [docs/FILE_FORMAT.md](FILE_FORMAT.md) — the on-disk `.aiproj` schema.
- [docs/DEVICE_BEZELS.md](DEVICE_BEZELS.md) — bezel catalogue and naming.
- [docs/PRESETS.md](PRESETS.md) — canvas preset table.
