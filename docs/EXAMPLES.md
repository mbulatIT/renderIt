# Examples

Three runnable example projects live under `Examples/`. Each is a `.aiproj`
JSON plus the screenshots it references. The shell script `Examples/build.sh`
renders all three using the CLI.

## 1. Simple hero (`Examples/01-simple-hero.aiproj`)

A coloured background with a centered title.

```bash
aiimageeditor-cli render --project Examples/01-simple-hero.aiproj --output Examples/out/01.png
```

## 2. Single device bezel (`Examples/02-device-bezel.aiproj`)

iPhone 15 Pro chrome with a placeholder screenshot inside, headline on top.

## 3. Multi-screenshot (`Examples/03-multi-screenshot.aiproj`)

Two iPhones side by side at a slight rotation, with a tagline below.

## Build everything

```bash
./Examples/build.sh
ls Examples/out
```
