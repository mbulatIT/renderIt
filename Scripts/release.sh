#!/usr/bin/env bash
set -euo pipefail

# Build + sign + notarize + package AIImageEditor for Developer ID distribution.
#
# One-time setup (see docs/PUBLISHING.md):
#   1. "Developer ID Application" certificate in the login keychain.
#   2. xcrun notarytool store-credentials <profile> \
#          --apple-id <apple-id-email> --team-id <TEAMID> --password <app-specific password>
#
# Usage:
#   NOTARY_PROFILE=aiimageeditor ./Scripts/release.sh [version]
#
# Env:
#   NOTARY_PROFILE  (required) notarytool keychain profile name
#   SIGN_ID         (optional) codesign identity, default "Developer ID Application"
#                   (substring match; set the full name if the keychain has several)

VERSION="${1:-0.1.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE — notarytool keychain profile name}"
SIGN_ID="${SIGN_ID:-Developer ID Application}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/Derived/Build/Products/Release"
DIST="$ROOT/dist"
STAGE="$DIST/stage"
DMG="$DIST/AIImageEditor-$VERSION.dmg"

cd "$ROOT"
rm -rf "$DIST"
mkdir -p "$STAGE"

echo "==> tuist generate"
tuist generate --no-open

echo "==> Building Release (app + cli + mcp)"
for scheme in AIImageEditor aiimageeditor-cli aiimageeditor-mcp; do
    xcodebuild -workspace AIImageEditor.xcworkspace -scheme "$scheme" \
               -configuration Release -derivedDataPath "$ROOT/Derived" \
               build -quiet
done

echo "==> Staging"
cp -R "$BUILD/AIImageEditor.app" "$STAGE/"
# CLI binaries live in a hidden folder so the Finder window stays clean;
# the installer script below copies them out. Xcode normalises dashes to
# underscores in product names on disk.
mkdir -p "$STAGE/.bin"
cp "$BUILD/aiimageeditor_cli" "$STAGE/.bin/aiimageeditor-cli"
cp "$BUILD/aiimageeditor_mcp" "$STAGE/.bin/aiimageeditor-mcp"

# Drag-and-drop convenience: /Applications shortcut right next to the app.
ln -s /Applications "$STAGE/Applications"

# Finder background with the install instructions (regenerate with
# Packaging/dmg-background.aiproj + aiimageeditor-cli render — the DMG
# background is itself an .aiproj project).
mkdir -p "$STAGE/.background"
cp "$ROOT/Packaging/dmg-background.tiff" "$STAGE/.background/background.tiff"

# Double-clickable installer for the CLI tools — Finder can't drag into
# /usr/local/bin (it doesn't even exist on a fresh macOS install).
cat > "$STAGE/Install Command Line Tools.command" <<'CMD'
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
DEST=/usr/local/bin
echo "Installing aiimageeditor-cli and aiimageeditor-mcp into $DEST"
echo "(administrator password may be requested)"
sudo mkdir -p "$DEST"
sudo install -m 755 "$DIR/.bin/aiimageeditor-cli" "$DIR/.bin/aiimageeditor-mcp" "$DEST/"
echo
echo "Done. To let an AI agent drive the editor, register the MCP server:"
echo "  claude mcp add aiimageeditor $DEST/aiimageeditor-mcp"
echo "(see ONBOARDING.md for Claude Desktop / Cursor / other agents)"
echo
read -r -p "Press Enter to close..."
CMD
chmod +x "$STAGE/Install Command Line Tools.command"

echo "==> Signing (hardened runtime + secure timestamp)"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$STAGE/.bin/aiimageeditor-cli"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$STAGE/.bin/aiimageeditor-mcp"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$STAGE/AIImageEditor.app"
# Shell scripts carry their signature in extended attributes (no hardened runtime).
codesign --force --timestamp --sign "$SIGN_ID" "$STAGE/Install Command Line Tools.command"
codesign --verify --strict --verbose=2 "$STAGE/AIImageEditor.app"

echo "==> Packaging DMG (read-write pass for Finder layout)"
# Detach any stale mounts so Finder scripting targets the right volume.
for vol in "/Volumes/AIImageEditor" "/Volumes/AIImageEditor 1"; do
    if [ -d "$vol" ]; then hdiutil detach "$vol" -quiet || true; fi
done
RW="$DIST/AIImageEditor-rw.dmg"
hdiutil create -volname "AIImageEditor" -srcfolder "$STAGE" -ov -format UDRW "$RW" -quiet
hdiutil attach "$RW" -noautoopen -quiet

echo "==> Applying Finder layout (background picture + icon positions)"
osascript <<'OSA'
tell application "Finder"
    tell disk "AIImageEditor"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- 660x420 content + ~28pt title bar
        set the bounds of container window to {400, 120, 1060, 568}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 104
        set text size of opts to 12
        set background picture of opts to file ".background:background.tiff"
        set position of item "AIImageEditor.app" of container window to {165, 150}
        set position of item "Applications" of container window to {495, 150}
        set position of item "Install Command Line Tools.command" of container window to {330, 320}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA
sync
hdiutil detach "/Volumes/AIImageEditor" -quiet

echo "==> Compressing to final DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" -ov -quiet
rm -f "$RW"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

echo "==> Notarizing (this waits for Apple; usually 1-5 min)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling ticket to DMG"
xcrun stapler staple "$DMG"

echo "==> Gatekeeper self-check"
spctl -a -vv -t install "$DMG" || true

echo
echo "Done: $DMG"
echo "Distribute the DMG. The app inside is covered by the same notarization"
echo "ticket; the bare cli/mcp binaries are notarized too (verified online by"
echo "Gatekeeper — standalone Mach-O files cannot carry a stapled ticket)."
