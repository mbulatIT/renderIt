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
- `--frame "x,y,w,h"` **or** `--at <position>` `--size "w,h"` — both optional;
  if omitted, the layer's frame defaults to the **image's natural pixel
  dimensions** (uniformly downscaled so neither side exceeds the canvas).
- `--content-mode fit|fill|stretch` — defaults to `stretch` so any later
  resize of the frame deforms the image directly. Pass `--content-mode fit`
  for aspect-preserving centred display with whitespace, or `fill` to crop.
- `--z <int>` (default top)

The image's `contentMode` is still encoded as `fit` (the JSON default) when
omitted in stored documents — the new `stretch` default only applies to layers
freshly added by `add-image` / the GUI's import flow / canvas drag-drop.

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

### `add-gradient`
Adds a linear or radial gradient fill, optionally with rounded corners.
- `--frame "x,y,w,h"` **or** `--at <position>` `--size "w,h"`
- `--type linear|radial` (default `linear`)
- `--stops "<colorN>@<posN>,…"` — e.g. `"#FF6F61@0,#6B5BFF@1"`. `@pos` is
  optional; if omitted, positions are spread evenly. Default
  `"#000000@0,#FFFFFF@1"`.
- `--start "x,y"`, `--end "x,y"` — normalized `0…1` within the frame.
  Defaults `0,0` → `0,1` (top to bottom).
- `--corner-radius <num>` (default `0`)

MCP equivalent: `add_gradient` (`stops` is a JSON array of `{ "color", "at" }`).

### `add-blur`
Adds a Gaussian blur ("frosted glass") over whatever sits underneath the layer.
- `--frame "x,y,w,h"` **or** `--at <position>` `--size "w,h"`
- `--radius <num>` (default `24`, ignored when `--stops` is supplied)
- `--corner-radius <num>` (default `0`)
- `--tint "#RRGGBBAA"` (optional overlay tint)

#### Variable-radius blur (keypoints)

To make the blur radius vary across the layer's frame — a "progressive" or
"tilt-shift"-style blur — supply two or more stops with their own radii:

- `--stops "<radiusN>@<posN>,…"` — e.g. `"0@0,80@1"`. `@pos` is optional; if
  omitted, positions are spread evenly along `0…1`. Each stop's radius is in
  canvas pixels.
- `--type linear|radial` (default `linear`) — gradient direction.
- `--start "x,y"`, `--end "x,y"` — gradient direction endpoints normalized to
  the layer's frame. Defaults `0,0` → `0,1` (vertical).

Rendered via `CIMaskedVariableBlur` with a grayscale mask whose brightness
encodes each pixel's blur radius normalized to the largest stop. `--radius` is
unused when `--stops` is present; rotation is still ignored.

Example — sharp at the top of the layer, fully blurred at the bottom:

```bash
aiimageeditor-cli add-blur --project p.aiproj \
    --frame "0,0,600,600" \
    --stops "0@0,80@1" --start "0,0" --end "0,1" --id grad
```

### `add-line`
Straight line with optional arrowheads on either end.
- `--frame "x,y,w,h"` (defines the bounding box)
- `--color "#RRGGBB"` (default white)
- `--width <num>` (default `6`)
- `--start "x,y"`, `--end "x,y"` — normalized `0…1` within the frame.
  Defaults `0,0.5` → `1,0.5` (horizontal centered).
- `--arrow none|start|end|both` (default `none`)
- `--arrow-size <num>` — arrowhead length in units of stroke width (default `4`).

### `add-polygon`
Regular N-gon inscribed in the frame.
- `--sides <int>` (≥ 3)
- `--frame "x,y,w,h"` **or** `--at <position>` `--size "w,h"`
- `--fill "#RRGGBB"`
- `--stroke "color,width"` (optional)

### `add-star`
N-pointed star inscribed in the frame.
- `--points <int>` (≥ 3, default `5`)
- `--inner-radius <num>` (`0…1`, default `0.4`; lower = pointier)
- `--frame "x,y,w,h"` **or** `--at <position>` `--size "w,h"`
- `--fill "#RRGGBB"`
- `--stroke "color,width"` (optional)

## Shadows

`shadow` is a layer-level field on every layer (except `blur` and `group`).
- Inline on creation: every `add-*` command accepts `--shadow "color,dx,dy,blur"`.
- After the fact: `set-shadow --id <layerId> (--shadow "color,dx,dy,blur" | --clear)`.

`color` accepts `#RRGGBB` or `#RRGGBBAA`. `dx`/`dy` are pixel offsets (positive
`dy` = shadow falls below the layer). `blur` is the Gaussian blur radius in px.

## Corner radius

`cornerRadius` is a layer-level field that works on every layer kind where it
makes sense: `rect`, `gradient`, `blur`, `image`, `text`, `line`, `polygon`,
`star`, and `group`. Ignored on `ellipse` (already curved) and `deviceBezel`
(defines its own shape).

- **Inline on creation** — every `add-*` command accepts `--corner-radius N`
  (canvas-pixel radius, `0` means "no rounding").
  `add-rect` keeps `--radius N` as a legacy alias for the same field.
- **After the fact** —
  ```
  set-corner-radius --project <p> [--page <id>] --id <layerId> --value N
  ```
  Pass `--value 0` to clear. `--corner-radius N` is also accepted as an alias
  for `--value`.

When combined with `shadow`, the renderer routes the layer through a
transparency layer so the drop shadow wraps the rounded silhouette correctly
(no clipped shadow edges).

### Corner style

`cornerStyle` controls the **shape** of the rounded corners:

| Style | Visual | Notes |
|---|---|---|
| `continuous` *(default)* | iOS-style squircle | corners extend further into the edges (`reach ≈ 1.53 × r`) and are drawn with cubic Béziers for a softer transition. Matches modern Apple aesthetics. |
| `arc` | quarter-circle | what `CGPath(roundedRect:)` produces — the classic pre-iOS-7 rounding. Tight quarter-circles meeting straight edges with abrupt curvature change. |
| `cut` | 45° chamfer | replaces the rounded arc with a straight diagonal, yielding octagonal corners. |

Ignored when `cornerRadius == 0`. Existing documents that don't carry an explicit
`cornerStyle` adopt the new default on next load — see the note in [FILE_FORMAT.md](FILE_FORMAT.md).

Set it via:
```
set-corner-style --project <p> [--page <id>] --id <layerId> --style arc|continuous|cut
```

MCP: `set_corner_style` with the same `style` arg. The CLI errors with
`--style expects arc | continuous | cut` if the value isn't recognised.

### Which corners round

By default `cornerRadius` rounds all four corners. Restrict it to a subset so only
some corners are rounded (e.g. round just the top two for a card/sheet look); the
rest stay square. Works with every `cornerStyle`.

```
set-corners --project <p> [--page <id>] --id <layerId> --corners <spec>
```

`<spec>` is one of:
- `all` — round all four corners (the default).
- `none` — square corners (radius has no visible effect).
- a comma/space list of corner names: `topLeft`/`tl`, `topRight`/`tr`,
  `bottomLeft`/`bl`, `bottomRight`/`br` — e.g. `--corners "tl,tr"`.
- an edge shortcut: `top`, `bottom`, `left`, `right` — e.g. `--corners top`
  rounds the top-left and top-right corners.

MCP: `set_corners` takes `corners` as a JSON array of corner names
(`["topLeft","topRight"]`); an empty array squares every corner.
In the file format this is the `roundedCorners` field (see [FILE_FORMAT.md](FILE_FORMAT.md)).

#### Example — three rects with each style, side by side

```bash
aiimageeditor-cli new --output styles.aiproj --width 900 --height 400 \
    --background "#202028"

aiimageeditor-cli add-rect --project styles.aiproj --id arc \
    --frame "40,40,240,240" --fill "#FFD60A" --corner-radius 60

aiimageeditor-cli add-rect --project styles.aiproj --id continuous \
    --frame "320,40,240,240" --fill "#34C759" --corner-radius 60
aiimageeditor-cli set-corner-style --project styles.aiproj \
    --id continuous --style continuous

aiimageeditor-cli add-rect --project styles.aiproj --id cut \
    --frame "600,40,240,240" --fill "#FF453A" --corner-radius 60
aiimageeditor-cli set-corner-style --project styles.aiproj \
    --id cut --style cut

aiimageeditor-cli render --project styles.aiproj --output styles.png
```

Yields three same-sized rounded squares — yellow with standard quarter-circle
corners, green visibly softened by the squircle reach, red with octagonal
chamfers.

## Layer background

`background` is a layer-level fill drawn behind the layer's primary content,
respecting `cornerRadius` and `cornerStyle`. Either a solid color or a
gradient. Useful for things like translucent cards under text, or coloured
panels under grouped compositions.

- `set-layer-bg --id <id> --color "#RRGGBBAA"` — solid colour fill.
- `set-layer-bg --id <id> [--type linear|radial] [--stops "#hex@pos,…"]
  [--start "x,y"] [--end "x,y"]` — gradient fill (same flag set as
  `add-gradient`).
- `set-layer-bg --id <id> --clear` — remove the background.

MCP: `set_layer_background` accepts `color`, the gradient fields, or
`clear: true`.

## Gradient fill

`gradient` is a layer-level field that turns any layer into a gradient-filled
version of itself. The renderer paints the gradient masked by the layer's
silhouette — gradient text, gradient shapes, gradient-tinted images, etc. No
effect on `blur`/`deviceBezel`/`.gradient` kind layers.

- `set-gradient --id <layerId> [--type linear|radial] [--stops "#hex@pos,…"]
  [--start "x,y"] [--end "x,y"]` — flags match `add-gradient`.
- `set-gradient --id <layerId> --clear` — removes the gradient fill.

MCP: `set_gradient` accepts the same fields (plus `clear: true`).

## Groups

Wrap existing layers into a single `group` and treat them as one — move,
duplicate, or apply effects to the composite. The group's frame is the union
of its children's frames.

- `group --ids "a,b,c" [--id <gid>] [--name "..."]` — bundles the named layers
  into a new group.
- `ungroup --id <gid>` — promotes the group's children back to the page's
  layer list, removes the group.
- `set-group-clip --id <gid> [--value true|false]` (alias `crop-to-bounds`) —
  crop the group's children to its bounds. Value defaults to `true`. Trims
  rotated children, `fill`-mode images, overflowing text, shadows, and strokes
  that spill past the box. Combine with `set-corner-radius` for a rounded crop.

MCP: `group` (takes `ids: [string]`), `ungroup`, and `set_group_clip`
(takes `value: boolean`).

In the macOS GUI the layer-list menu offers "Wrap in Group" (singleton wrap
of the selected layer) and "Ungroup" (only enabled for group layers). For
multi-layer grouping, use the CLI or MCP.

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
