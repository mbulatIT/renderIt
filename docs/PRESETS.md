# Canvas presets

App Store screenshot sizes are surprisingly stable; these are the current
required / accepted sizes as of 2025.

| id | Width | Height | Use |
|----|-------|--------|-----|
| `iphone-6.7` | 1290 | 2796 | iPhone 14 Pro Max / 15 Pro Max / 15 Plus / 16 Pro Max |
| `iphone-6.5` | 1284 | 2778 | iPhone 11 Pro Max / XS Max / 14 Plus |
| `iphone-5.5` | 1242 | 2208 | older iPhone Plus, accepted by App Store as legacy |
| `ipad-13` | 2064 | 2752 | iPad Pro 13" (M4) |
| `ipad-12.9` | 2048 | 2732 | iPad Pro 12.9" |
| `mac` | 2880 | 1800 | Mac App Store (16:10) |
| `watch-ultra` | 410 | 502 | Apple Watch Ultra |
| `iphone-portrait` | 1080 | 1920 | generic 9:16 |
| `iphone-landscape` | 1920 | 1080 | generic 16:9 |
| `square-1k` | 1024 | 1024 | social / icon work |

List from the CLI:

```bash
aiimageeditor-cli presets
```

If you need a non-standard size, pass `--width` and `--height` to `new` instead
of `--preset`.
