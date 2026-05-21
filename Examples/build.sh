#!/usr/bin/env bash
# Render every example .aiproj via the CLI. Run after building aiimageeditor-cli.
set -euo pipefail

SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"
cd "${SCRIPT_DIR}/.."

CLI="${AIIMAGE_CLI:-Derived/Build/Products/Release/aiimageeditor-cli}"
if [[ ! -x "${CLI}" ]]; then
    CLI="${AIIMAGE_CLI:-Derived/Build/Products/Debug/aiimageeditor-cli}"
fi
if [[ ! -x "${CLI}" ]]; then
    echo "build aiimageeditor-cli first (xcodebuild -scheme aiimageeditor-cli)"
    exit 1
fi

mkdir -p Examples/out

# A small placeholder screenshot — solid gradient PNG generated on the fly.
if [[ ! -f Examples/screenshots/placeholder.png ]]; then
    mkdir -p Examples/screenshots
    "${CLI}" new --output /tmp/placeholder.aiproj --width 1170 --height 2370 --background "#2A4D8F"
    "${CLI}" add-text --project /tmp/placeholder.aiproj --text "Screenshot" \
        --font-size 200 --color "#FFFFFF" --at center --size "1100,300"
    "${CLI}" render --project /tmp/placeholder.aiproj --output Examples/screenshots/placeholder.png
fi

for f in Examples/01-simple-hero.aiproj Examples/02-device-bezel.aiproj Examples/03-multi-screenshot.aiproj; do
    name="$(basename "$f" .aiproj)"
    out="Examples/out/${name}.png"
    echo "rendering ${out}"
    "${CLI}" render --project "$f" --output "$out"
done

echo "done. PNGs in Examples/out/"
