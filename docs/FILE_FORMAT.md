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
| `type` | string | required | One of `image`, `text`, `rect`, `ellipse`, `deviceBezel`, `group`. |
| `frame` | `[x, y, w, h]` | required | Top-left origin, pixels. |
| `zIndex` | number | `0` | Higher = drawn on top. Ties broken by array order. |
| `rotation` | number | `0` | Degrees, clockwise, around frame center. |
| `opacity` | number | `1.0` | `0..1`. |
| `visible` | bool | `true` | Hidden layers are skipped entirely. |
| `blendMode` | string | `"normal"` | `normal`, `multiply`, `screen`, `overlay`, `softLight`, `hardLight`. |
| `name` | string | `id` | Display name in the GUI layer list. |

## Type-specific payloads

### `image`
```json
{ "type": "image", "assetId": "homeScreen", "contentMode": "fit" }
```
- `assetId`: must exist in `assets`.
- `contentMode`: `fit` (default), `fill`, `stretch`.

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
- `shadow` is optional.

### `rect`
```json
{
  "type": "rect",
  "fill": "#FFFFFF",
  "stroke": { "color": "#000000", "width": 2 },
  "cornerRadius": 24
}
```
`stroke` is optional. `cornerRadius` may be `0`.

### `ellipse`
Same payload as `rect` minus `cornerRadius`.

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
{ "type": "group", "children": [ ...layer objects... ] }
```
Children inherit nothing; `frame` is used as a clipping/positioning hint for
the GUI but does not affect children's coordinates.

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
