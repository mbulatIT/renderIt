# `.aiproj` file format

A project file is a single UTF-8 JSON document. Designed to be hand-editable and
LLM-friendly: small key set, top-level arrays, no binary blobs, stable ids.

## Top level

```json
{
  "version": 1,
  "canvas": { "width": 1290, "height": 2796, "background": "#1A1A2E", "dpi": 72 },
  "assets": {
    "homeScreen": { "path": "screenshots/home.png" }
  },
  "layers": [ ... ]
}
```

| Field | Type | Notes |
|-------|------|-------|
| `version` | int | Current version is `1`. |
| `canvas.width`, `canvas.height` | int | Pixels. |
| `canvas.background` | string | `#RRGGBB` or `#RRGGBBAA`, or `"transparent"`. |
| `canvas.dpi` | int | Informational only; renderer treats canvas as pixels. |
| `assets` | object | Map of asset id → asset definition (see below). |
| `layers` | array | Ordered by author; renderer sorts by `zIndex`. |

## Asset definition

```json
{ "path": "screenshots/home.png" }
```

`path` is resolved relative to the directory of the `.aiproj` file.
(Asset id is the object key.)

## Common layer fields

Every layer has these fields:

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | string | required | Stable; LLMs reference layers by id. |
| `type` | string | required | One of `image`, `text`, `rect`, `ellipse`, `deviceBezel`, `group`, `gradient`, `blur`, `line`, `polygon`, `star`. |
| `frame` | `[x, y, w, h]` | required | Top-left origin, pixels. |
| `zIndex` | number | `0` | Higher = drawn on top. Ties broken by array order. |
| `rotation` | number | `0` | Degrees, clockwise, around frame center. |
| `opacity` | number | `1.0` | `0..1`. |
| `visible` | bool | `true` | Hidden layers are skipped entirely. |
| `blendMode` | string | `"normal"` | `normal`, `multiply`, `screen`, `overlay`, `softLight`, `hardLight`. |
| `shadow` | object | — | Optional drop shadow. `{ "color": "#RRGGBBAA", "offset": [dx, dy], "blur": N }`. Applies to every layer kind except `blur` and `group`. |
| `cornerRadius` | number | `0` | Rounded-corner radius in canvas pixels. For `rect`/`gradient`/`blur` it's baked into the layer's own path; for `image`/`text`/`line`/`polygon`/`star`/`group` the renderer clips the drawing to a rounded-rect mask. No effect on `ellipse` or `deviceBezel`. Combines correctly with `shadow` — the drop shadow wraps the rounded silhouette. |
| `cornerStyle` | string | `"continuous"` | Shape of the rounded corners: `continuous` (default — iOS-style squircle with extended reach + cubic Béziers), `arc` (true quarter-circles), or `cut` (45° chamfer producing octagonal corners). Ignored when `cornerRadius` is `0`. Documents written before the default change still re-encode without an explicit `cornerStyle`, so on load they pick up `continuous` automatically. Use `--style arc` (CLI) or `cornerStyle: "arc"` (JSON) to keep classic quarter-circles. |
| `roundedCorners` | array of strings | all four | Which corners the `cornerRadius` rounds — any of `"topLeft"`, `"topRight"`, `"bottomLeft"`, `"bottomRight"`. Corners not listed stay square. Omitted from JSON when all four are rounded (the default, matching the previous always-uniform behaviour); an explicit empty array `[]` leaves every corner square. Ignored when `cornerRadius` is `0`. |
| `gradient` | object | — | Optional layer-level gradient fill, nested under the `gradient` key. Same shape as a standalone `gradient` layer's payload (`type`, `stops`, `start`, `end`). The renderer paints this gradient masked by the layer's silhouette, so text becomes gradient text, shapes become gradient shapes, images become gradient-tinted. No effect on `blur`/`deviceBezel`/`.gradient` kind layers. |
| `background` | object | — | Optional fill drawn behind the layer's primary content, respecting `cornerRadius` and `cornerStyle`. Either `{ "color": "#RRGGBBAA" }` for a solid fill or `{ "gradient": { "type": …, "stops": [...], "start": [...], "end": [...] } }` for a gradient. No effect on `blur` or `deviceBezel`. |
| `name` | string | `id` | Display name in the GUI layer list. |

## Type-specific payloads

### `image`
```json
{ "type": "image", "assetId": "homeScreen", "contentMode": "stretch" }
```
- `assetId`: must exist in `assets`.
- `contentMode`: `fit`, `fill`, or `stretch`. The JSON default (when the field
  is omitted) is `fit`. New layers added via the CLI's `add-image`, the GUI's
  import dialog, or canvas drag-drop are created with `stretch` so resizing
  the frame deforms the image directly — they emit `"contentMode": "stretch"`
  explicitly. Older documents that don't carry the field continue to use
  `fit`, preserving their look.

### `text`
```json
{
  "type": "text",
  "text": "Edit photos with AI",
  "font": "SF Pro Display",
  "fontSize": 110,
  "fontWeight": "bold",
  "italic": false,
  "color": "#FFFFFF",
  "alignment": "center",
  "lineSpacing": 4,
  "kerning": 0,
  "shadow": { "color": "#00000080", "offset": [0, 4], "blur": 12 }
}
```
- `font`: PostScript or family name. Falls back to system font if missing.
- `fontWeight`: `ultraLight | thin | light | regular | medium | semibold | bold | heavy | black`.
- `alignment`: `left | center | right | justified`.
- `shadow` is the common layer-level field (see the Common layer fields table above).
  Kept as a sibling key here for backward-compat with older documents.

### `rect`
```json
{
  "type": "rect",
  "fill": "#FFFFFF",
  "stroke": { "color": "#000000", "width": 2 },
  "cornerRadius": 24
}
```
`stroke` is optional. `cornerRadius` and `cornerStyle` are the common layer-level fields
(sibling keys, not nested in the payload). `cornerStyle` is omitted in JSON when it's
the default `"continuous"`; pass `"cornerStyle": "arc"` or `"cornerStyle": "cut"` to
override. May be `0` for `cornerRadius`.

### `ellipse`
Same payload as `rect`. `cornerRadius` / `cornerStyle` are decoded but ignored — the shape
is already curved.

### `deviceBezel`
```json
{
  "type": "deviceBezel",
  "device": "iphone15Pro",
  "screenshotAssetId": "homeScreen",
  "chromeColor": "#0F0F10"
}
```
- `device`: one of the keys in [`DEVICE_BEZELS.md`](DEVICE_BEZELS.md).
- `screenshotAssetId`: optional. If supplied, the asset is drawn into the
  device's screen rectangle (auto-fitted to the bezel's aspect).
- `chromeColor`: optional override for the bezel chrome color.

The layer's `frame` defines the **outer** device bounds. The renderer derives
the screen rect from the bezel definition (insets + corner radius), so the
screenshot always fits perfectly regardless of the user-supplied frame.

### `group`
```json
{ "type": "group", "children": [ ...layer objects... ], "clipsToBounds": true }
```
Children inherit nothing; `frame` is used as a clipping/positioning hint for
the GUI but does not affect children's coordinates. The group's frame is
typically the union of its children's frames (set automatically by the `group`
command). Children are drawn in array order at the group's z-position.

- `clipsToBounds` (boolean, default `false`): when true, the group crops its
  children's drawing to its frame, respecting the layer-level `cornerRadius` /
  `cornerStyle`. This trims anything that paints past the box — rotated children,
  `fill`-mode images, overflowing text, drop shadows, and strokes. Combine with
  `cornerRadius` for a rounded crop. Omitted from the JSON when `false`.

### `gradient`
```json
{
  "type": "gradient",
  "gradientType": "linear",
  "stops": [
    { "color": "#FF6F61", "at": 0 },
    { "color": "#6B5BFF", "at": 1 }
  ],
  "start": [0, 0],
  "end":   [1, 1],
  "cornerRadius": 0
}
```
- `gradientType`: `linear` (default) or `radial`. For `radial`, `start` is the
  center and the radius is `|end - start|` (in normalized units, then scaled to
  the frame).
- `stops`: array of `{ color, at }`. `at` is normalized `0…1`. Need at least one
  stop (default = black→white).
- `start`, `end`: 2-element arrays of `[x, y]` normalized to the layer's frame.
  Defaults `[0,0]` → `[0,1]` (top to bottom).
- `cornerRadius` lives at the layer level (see Common layer fields).

### `blur`
```json
{
  "type": "blur",
  "radius": 24,
  "tint": "#FFFFFF20"
}
```
- `radius`: Gaussian blur radius in canvas pixels (used when `stops` is absent).
- `tint`: optional `#RRGGBBAA` overlay drawn on top of the blurred sample.
- `cornerRadius` / `cornerStyle` live at the layer level (see Common layer fields).

#### Variable-radius blur (keypoints)

A blur layer can have its radius vary across the frame by supplying `stops` plus
a gradient direction. Internally implemented via `CIMaskedVariableBlur` with a
grayscale mask whose brightness encodes `radius / maxRadius`.

```json
{
  "type": "blur",
  "stops": [
    { "radius": 0,  "at": 0 },
    { "radius": 80, "at": 1 }
  ],
  "gradientType": "linear",
  "start": [0, 0],
  "end":   [0, 1]
}
```
- `stops`: array of `{ radius, at }`. `radius` is in canvas pixels at the stop's
  normalized position `at` (`0…1`). Need at least two stops for the gradient
  blur to activate; otherwise the layer falls back to a uniform `radius` blur.
- `gradientType`: `linear` (default) or `radial`. For `radial`, `start` is the
  center and the gradient extends to `end` (radius derived from the distance).
- `start`, `end`: 2-element arrays of `[x, y]` normalized to the layer's frame.
  Defaults `[0,0]` → `[0,1]` (top to bottom). The `at=0` stop maps to the
  visual `start` of the gradient.

Blur samples whatever has been drawn underneath this layer within its frame and
draws it back inside the (optionally rounded) frame — like CSS `backdrop-filter`.
Rotation on blur layers is ignored; the sample rect is always axis-aligned.

### `line`
```json
{
  "type": "line",
  "color": "#FFFFFF",
  "width": 6,
  "start": [0, 0.5],
  "end":   [1, 0.5],
  "startArrow": false,
  "endArrow":   false,
  "arrowSize": 4
}
```
- `start`, `end`: normalized `0…1` within the layer's frame.
- `width`: stroke width in canvas pixels.
- `startArrow` / `endArrow`: filled triangular arrowheads.
- `arrowSize`: arrowhead length as a multiple of `width`.

### `polygon`
```json
{ "type": "polygon", "sides": 6, "fill": "#FFFFFF", "stroke": { "color": "#000", "width": 2 } }
```
Regular N-gon (sides ≥ 3) inscribed in the frame. First vertex points up; use
`rotation` to spin.

### `star`
```json
{ "type": "star", "points": 5, "innerRadius": 0.4, "fill": "#FFD60A" }
```
- `points`: number of star points (≥ 3).
- `innerRadius`: inner-radius fraction `0…1`. Lower = pointier.

## Colors

Strings of the form `#RRGGBB` or `#RRGGBBAA`. Case insensitive. The special
value `"transparent"` is accepted for `canvas.background`.

## Coordinate system

Top-left origin, x right, y down. All values are in pixels.

## Validation rules

- Every `assetId` / `screenshotAssetId` must exist in `assets`.
- Layer ids must be unique.
- `frame[2]` (w) and `frame[3]` (h) must be ≥ 0.
- Unknown layer fields are preserved on round-trip but ignored by the renderer.
