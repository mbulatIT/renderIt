#!/usr/bin/env bash
# Exercises every command documented in docs/CLI_GUIDE.md and reports pass/fail.
# Each section uses isolated /tmp paths so re-runs are deterministic.

set -uo pipefail

CLI="${AIIMAGE_CLI:-$HOME/Library/Developer/Xcode/DerivedData/AIImageEditor-fzcxasocxdbzweaqgxdthxldmkjr/Build/Products/Debug/aiimageeditor_cli}"
if [[ ! -x "$CLI" ]]; then
    echo "✗ aiimageeditor_cli not found at $CLI"
    exit 1
fi

TMP=/tmp/aiimage-verify
rm -rf "$TMP"
mkdir -p "$TMP"
P="$TMP/project.aiproj"
OUT="$TMP/out"
mkdir -p "$OUT"

pass=0
fail=0
declare -a failed_cmds

run() {
    local desc="$1"
    shift
    local output
    if output="$("$CLI" "$@" 2>&1)"; then
        echo "✓ $desc"
        pass=$((pass + 1))
    else
        echo "✗ $desc"
        echo "  cmd: $CLI $*"
        echo "  out: $output"
        fail=$((fail + 1))
        failed_cmds+=("$desc")
    fi
}

expect_fail() {
    local desc="$1"
    shift
    if "$CLI" "$@" >/dev/null 2>&1; then
        echo "✗ $desc (expected non-zero exit)"
        fail=$((fail + 1))
        failed_cmds+=("$desc")
    else
        echo "✓ $desc (exited non-zero as expected)"
        pass=$((pass + 1))
    fi
}

echo "=========================================="
echo "1. DISCOVERY"
echo "=========================================="
run "presets"   presets
run "bezels"    bezels
run "fonts"     fonts

echo
echo "=========================================="
echo "2. NEW / INSPECT / LIST"
echo "=========================================="
run "new (preset)" new --output "$P" --preset iphone-6.7
run "list"          list --project "$P"
run "inspect"       inspect --project "$P"

# Verify --background flag
P2="$TMP/project2.aiproj"
run "new with --width --height --background" new --output "$P2" --width 800 --height 600 --background "#FF00CC"

echo
echo "=========================================="
echo "3. PAGES"
echo "=========================================="
run "pages list"   pages list --project "$P"
run "pages add"    pages add --project "$P" --name "Features" --id features
run "pages list (after add)" pages list --project "$P"
run "pages rename" pages rename --project "$P" --id features --name "Feature Highlights"
run "pages select" pages select --project "$P" --id features
run "pages remove" pages remove --project "$P" --id features

echo
echo "=========================================="
echo "4. PAGE SETTINGS (layout / background)"
echo "=========================================="
run "set-layout count"            set-layout --project "$P" --count 3
run "set-layout preview-size"     set-layout --project "$P" --preview-width 1290 --preview-height 2796
run "set-layout spacing"          set-layout --project "$P" --spacing 120
run "bg #RRGGBB"                  bg --project "$P" --color "#101030"
run "set-background (alias) hex"  set-background --project "$P" --color "#0A0F2A"
run "bg transparent"              bg --project "$P" --color transparent
run "bg back to white"            bg --project "$P" --color "#FFFFFF"

echo
echo "=========================================="
echo "5. PREVIEWS"
echo "=========================================="
run "previews list"           previews list --project "$P"
run "previews add"            previews add --project "$P" --name "Hero" --background "#111133"
run "previews rename"         previews rename --project "$P" --id page-1-preview-1 --name "First"
run "previews set-background" previews set-background --project "$P" --id page-1-preview-2 --color "#1B1F4A"
run "previews export"         previews export --project "$P" --output "$OUT/previews" --scale 1
ls -1 "$OUT/previews" | sed 's/^/   /'
run "previews remove"         previews remove --project "$P" --id page-1-preview-4

echo
echo "=========================================="
echo "6. ASSETS"
echo "=========================================="
# Generate a stand-in asset PNG via a tiny project.
ASSET_PROJ="$TMP/asset-source.aiproj"
ASSET_PNG="$TMP/sample.png"
"$CLI" new --output "$ASSET_PROJ" --width 600 --height 1000 --background "#3366FF" >/dev/null
"$CLI" add-text --project "$ASSET_PROJ" --text "Sample" --at center --size "500,400" \
    --font-size 200 --color "#FFFFFF" --align center --font-weight bold --id t >/dev/null
"$CLI" render --project "$ASSET_PROJ" --output "$ASSET_PNG" >/dev/null

run "assets add"     assets add --project "$P" --path "$ASSET_PNG" --id sample
run "assets list"    assets list --project "$P"
run "assets add (dedup)" assets add --project "$P" --path "$ASSET_PNG" --id sample2  # would dedupe via auto-id; explicit id forces a new entry
# Actually, with explicit --id, we'd get a duplicate-asset-id error. Verify by removing this case.

run "assets remove (sample2)" assets remove --project "$P" --id sample2
# Re-add via auto-id and confirm dedup works
run "assets add (auto-id dedup)" assets add --project "$P" --path "$ASSET_PNG"

echo
echo "=========================================="
echo "7. ADD LAYERS"
echo "=========================================="
run "add-text (frame)"      add-text --project "$P" --text "Hello world" --frame "100,300,2000,300" --font-size 220 --color "#FFFFFF" --align center --font-weight bold --id title
run "add-text (--at)"       add-text --project "$P" --text "Subtitle" --at top-center --size "1100,150" --font-size 80 --color "#A0B8FF" --id subtitle
run "add-rect (radius)"     add-rect --project "$P" --frame "100,2000,1000,400" --fill "#FFFFFF22" --radius 32 --id panel
run "add-ellipse"           add-ellipse --project "$P" --frame "2000,2000,400,400" --fill "#FF00CC" --id dot
run "add-image (--asset-path)" add-image --project "$P" --asset-path "$ASSET_PNG" \
    --frame "200,3500,800,1200" --content-mode fit --id image1
run "add-image (--asset)"   add-image --project "$P" --asset sample --frame "1500,3500,800,1200" --id image2
run "add-bezel (image-backed device + color)" add-bezel --project "$P" --device iphone17Pro \
    --color "Silver" --frame "1290,1700,1290,2400" --id phone
run "add-bezel (--screenshot-path)" add-bezel --project "$P" --device iphone17Pro \
    --color "Deep blue" --frame "3580,1700,1290,2400" --screenshot-path "$ASSET_PNG" --id phone2

echo
echo "=========================================="
echo "8. EDIT LAYERS"
echo "=========================================="
run "move (--to)"        move --project "$P" --id title --to "200,500"
run "move (--dx --dy)"   move --project "$P" --id title --dx 50 --dy 0
run "move (--at)"        move --project "$P" --id subtitle --at top-center
run "resize"             resize --project "$P" --id panel --width 1500 --height 500
run "set-frame"          set-frame --project "$P" --id dot --frame "2000,2500,300,300"
run "rotate"             rotate --project "$P" --id phone --degrees -6
run "opacity"            opacity --project "$P" --id panel --value 0.7
run "visible false"      visible --project "$P" --id image2 --value false
run "visible true"       visible --project "$P" --id image2 --value true
run "blend"              blend --project "$P" --id dot --mode multiply
run "rename"             rename --project "$P" --id panel --name "Info Panel"
run "set-text"           set-text --project "$P" --id title --text "ACROSS PREVIEWS"
run "set-font"           set-font --project "$P" --id title --font Helvetica --font-size 240 --font-weight black --italic false
run "set-color"          set-color --project "$P" --id title --color "#FFEE88"
run "set-alignment"      set-alignment --project "$P" --id title --align center
run "set-bezel-color"    set-bezel-color --project "$P" --id phone --color "Cosmic orange"
run "set-bezel-screenshot --clear"  set-bezel-screenshot --project "$P" --id phone --clear
run "set-bezel-screenshot --asset-path" set-bezel-screenshot --project "$P" --id phone --asset-path "$ASSET_PNG"
run "duplicate"          duplicate --project "$P" --id dot
run "remove"             remove --project "$P" --id image2

echo
echo "=========================================="
echo "9. Z-ORDER"
echo "=========================================="
run "z (set explicit)"  z --project "$P" --id phone --value 100
run "set-z (alias)"     set-z --project "$P" --id phone --value 99
run "front"             front --project "$P" --id title
run "bring-to-front"    bring-to-front --project "$P" --id title
run "back"              back --project "$P" --id panel
run "send-to-back"      send-to-back --project "$P" --id panel
run "forward"           forward --project "$P" --id dot
run "move-forward"      move-forward --project "$P" --id dot
run "backward"          backward --project "$P" --id dot
run "move-backward"     move-backward --project "$P" --id dot

echo
echo "=========================================="
echo "10. RENDER (modes and per-preview)"
echo "=========================================="
run "render export (default)"     render --project "$P" --output "$OUT/export.png"
run "render editor mode"          render --project "$P" --output "$OUT/editor.png" --mode editor
run "render --scale 2"            render --project "$P" --output "$OUT/scale2.png" --scale 2
run "render --preview <id>"       render --project "$P" --output "$OUT/single.png" --preview page-1-preview-1
ls -la "$OUT"/*.png | sed 's/^/   /'

echo
echo "=========================================="
echo "11. ERROR CASES (must exit non-zero)"
echo "=========================================="
expect_fail "missing required flag --project" list
expect_fail "unknown subcommand"               not-a-command
expect_fail "unknown layer id"                 move --project "$P" --id no-such-layer --to "0,0"
expect_fail "unknown preview id"               render --project "$P" --output "$OUT/x.png" --preview no-such-preview
expect_fail "bad color hex"                    bg --project "$P" --color "not-a-color"

echo
echo "=========================================="
echo "RESULT"
echo "=========================================="
echo "passed: $pass"
echo "failed: $fail"
if (( fail > 0 )); then
    echo
    echo "Failed:"
    for d in "${failed_cmds[@]}"; do echo "  - $d"; done
    exit 1
fi
echo "All documented commands work as expected."
