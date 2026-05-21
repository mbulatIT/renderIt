# Device bezels

Two kinds of bezels are registered with the engine:

1. **Image-backed** — high-resolution PNG chrome bundled in `AIImageEditorCore/Resources/Bezels/`,
   with the screen rectangle auto-detected at first use by scanning for the dark display area.
   These devices may have multiple **color variants** selected via the `color` field on a
   `deviceBezel` layer.
2. **Programmatic** — pure Core Graphics paths (rounded chrome, decorations). No PNGs needed,
   resolution-independent, copyright-clean. Used for legacy / generic devices.

## Catalog

| Device id | Family | Title | Source | Colors |
|-----------|--------|-------|--------|--------|
| `iphone16` | iphone | iPhone 16 | image | _default_ |
| `iphone16Plus` | iphone | iPhone 16 Plus | image | _default_ |
| `iphone16Pro` | iphone | iPhone 16 Pro | image | _default_ |
| `iphone16ProMax` | iphone | iPhone 16 Pro Max | image | _default_ |
| `iphone17` | iphone | iPhone 17 | image | White, Sage, Lavender, Mist blue, Black |
| `iphone17Pro` | iphone | iPhone 17 Pro | image | Silver, Deep blue, Cosmic orange |
| `iphone17ProMax` | iphone | iPhone 17 Pro Max | image | Silver, Deep blue, Cosmic orange |
| `iphoneAir` | iphone | iPhone Air | image | Cloud white, Light gold, Sky blue, Space black |
| `ipadProM411` | ipad | iPad Pro M4 11 | image | Silver, Space grey |
| `ipadProM413` | ipad | iPad Pro M4 13 | image | Silver, Space grey |
| `ipadmini` | ipad | iPad mini | image | _default_ |
| `iphoneSE` | iphoneLegacy | iPhone SE (legacy) | programmatic | — |
| `macbookPro14` | mac | MacBook Pro 14" | programmatic | — |
| `macbookPro16` | mac | MacBook Pro 16" | programmatic | — |

List from the CLI:

```bash
aiimageeditor-cli bezels
```

## Color selector

Choose a color via the `color` field on a `deviceBezel` layer (it's a layer property, not a
separate device id). Pass the color label exactly as listed above.

CLI:
```bash
aiimageeditor-cli add-bezel --project x.aiproj \
    --device iphone17Pro --color "Deep blue" \
    --at center --height 2100
```

```bash
# Change the color later
aiimageeditor-cli set-bezel-color --project x.aiproj --id phone --color "Cosmic orange"
```

MCP:
```json
{ "name": "add_bezel",
  "arguments": { "project": "x.aiproj", "device": "iphone17Pro",
                 "color": "Deep blue", "at": "center", "height": 2100 } }
```

GUI: when a device-bezel layer is selected the Inspector shows a Color picker populated with
the available variants.

## Screen rect detection

For image-backed bezels we compute the inner screen rectangle by scanning the loaded PNG for
the dark display area (`BezelImageStore.detectScreenInsetFractions`). The result is cached
per device id. Screenshots laid into the bezel are clipped to a rounded version of that rect
and `.fill`-scaled, so they always look correct regardless of the layer's outer frame.

## Asset licensing

The bundled bezel PNGs were extracted from SVG files the user provided
(`~/Downloads/iPhone bezels`, `~/Downloads/iPad bezels`). Designers commonly source bezel
mockups from Apple Design Resources, Figma Community files, paid asset packs and similar
libraries — terms vary widely. **Before publishing screenshots that use these specific
PNGs in the App Store** (or anywhere public) verify the license of your source pack and
Apple's [Marketing Resources](https://developer.apple.com/design/human-interface-guidelines/right-to-use)
guidance for product imagery. The loader code in `BezelImageStore` is generic — you can
drop in any other set of PNGs named `<deviceId>--<colorId>.png` and update
`manifest.json` to switch device renderings without touching Swift.

## Adding more devices

To add a new image-backed device:

1. Drop one PNG per color into `AIImageEditorCore/Resources/Bezels/`,
   named `<deviceId>--<colorId>.png` (e.g. `pixel9Pro--obsidian.png`).
2. Edit `AIImageEditorCore/Resources/Bezels/manifest.json` to add a new entry:
   ```json
   {
     "deviceId": "pixel9Pro",
     "title": "Pixel 9 Pro",
     "family": "iphone",
     "aspect": 0.46,
     "viewBoxW": 460, "viewBoxH": 1000,
     "colors": {
       "Obsidian": "pixel9Pro--obsidian.png",
       "Porcelain": "pixel9Pro--porcelain.png"
     }
   }
   ```
3. `tuist generate` and rebuild. No Swift changes required.
