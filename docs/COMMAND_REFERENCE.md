# Command reference

Single source of truth for every mutation the engine supports. The CLI maps each
command to a subcommand of `aiimageeditor-cli`. The MCP server maps each command
to a tool with the same name. The GUI calls these through `CommandEngine.apply`.

Every command takes a project file path (`--project file.aiproj` for the CLI,
`project` arg for MCP). Mutations are written back to disk atomically.

## Canvas

### `set-canvas`
Change canvas size.
- `--width <int>` (required)
- `--height <int>` (required)

### `bg` / `set-background`
- `--color "#RRGGBB"` or `--color transparent`

## Adding layers

All `add-*` commands return the new layer id on stdout (CLI) or in the tool
result (MCP). Pass `--id <str>` to choose your own id, otherwise one is generated.

### `add-image`
- `--asset <id>` (must exist) **or** `--asset-path <path>` (auto-imports)
- `--frame "x,y,w,h"` (required) **or** `--at <position>` `--size "w,h"`
- `--content-mode fit|fill|stretch` (default `fit`)
- `--z <int>` (default top)

### `add-text`
- `--text "..."` (required)
- `--frame "x,y,w,h"` **or** `--at <position>` `--size "w,h"`
- `--font <name>` (default `SF Pro Display`)
- `--font-size <int>` (default `72`)
- `--font-weight <weight>` (default `regular`)
- `--italic` (flag)
- `--color "#RRGGBB"` (default `#FFFFFF`)
- `--align left|center|right|justified` (default `center`)
- `--line-spacing <num>` (default `0`)
- `--shadow "color,dx,dy,blur"` (optional)

### `add-rect`
- `--frame "x,y,w,h"`
- `--fill "#RRGGBBAA"` (default opaque white)
- `--stroke "color,width"` (optional)
- `--radius <num>` (default `0`)

### `add-ellipse`
Same as `add-rect` but no radius.

### `add-bezel`
Wraps a screenshot in a device frame.
- `--device <id>` (see `bezels` command)
- `--screenshot-asset <id>` or `--screenshot-path <path>` (optional but typical)
- `--at <position>` (default `center`)
- `--height <int>` (optional — width is derived from device aspect)
- `--frame "x,y,w,h"` (alternative explicit positioning)
- `--chrome-color "#RRGGBB"` (optional)

## Editing layers

All take `--id <layerId>` selecting the layer.

| Command | Args |
|---------|------|
| `move` | `--dx <num>` `--dy <num>` **or** `--to "x,y"` **or** `--at <position>` |
| `resize` | `--width <num>` `--height <num>` (one or both) |
| `set-frame` | `--frame "x,y,w,h"` |
| `rotate` | `--degrees <num>` (absolute) |
| `opacity` | `--value 0..1` |
| `visible` | `--value true|false` |
| `blend` | `--mode normal|multiply|screen|overlay|softLight|hardLight` |
| `rename` | `--name "new name"` |
| `duplicate` | (returns new id) |
| `remove` | (no extra args) |

### Text-only

| Command | Args |
|---------|------|
| `set-text` | `--text "..."` |
| `set-font` | `--font <name>` `--font-size <int>` `--font-weight <w>` `--italic <bool>` |
| `set-color` | `--color "#RRGGBB"` |
| `set-alignment` | `--align left\|center\|right\|justified` |

## Z-order

| Command | Args |
|---------|------|
| `z` / `set-z` | `--id <id>` `--value <int>` |
| `front` / `bring-to-front` | `--id <id>` |
| `back` / `send-to-back` | `--id <id>` |
| `forward` / `move-forward` | `--id <id>` |
| `backward` / `move-backward` | `--id <id>` |

## Assets

| Command | Args |
|---------|------|
| `assets add` | `--path <file>` `--id <id?>` |
| `assets remove` | `--id <id>` |
| `assets list` | none |

## Rendering / inspection

| Command | Args |
|---------|------|
| `render` | `--output <file.png>` `--scale 1\|2\|3` (default `1`) |
| `inspect` | (pretty-prints the project JSON) |
| `list` | (lists layers in z-order with id, type, frame) |
| `new` | `--output <file.aiproj>` `--preset <id>` **or** `--width --height` `--background "..."` |
| `presets` | (lists available canvas presets) |
| `bezels` | (lists available device bezels) |
| `fonts` | (lists installed font families) |

## Position tokens

Used by `--at`:

```
top-left   top-center   top-right
center-left  center  center-right
bottom-left bottom-center bottom-right
```

The token positions the **center** of the layer at the corresponding canvas
anchor — except `top-*` (top edge), `bottom-*` (bottom edge), `*-left`/`*-right`
(left/right edge respectively), each with a small built-in margin (≈ 4% of the
relevant canvas dimension).

## Examples

See [EXAMPLES.md](EXAMPLES.md) for full multi-command flows.
