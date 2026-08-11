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
# Xcode normalises dashes to underscores in product names on disk.
cp "$BUILD/aiimageeditor_cli" "$STAGE/aiimageeditor-cli"
cp "$BUILD/aiimageeditor_mcp" "$STAGE/aiimageeditor-mcp"

echo "==> Signing (hardened runtime + secure timestamp)"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$STAGE/aiimageeditor-cli"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$STAGE/aiimageeditor-mcp"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$STAGE/AIImageEditor.app"
codesign --verify --strict --verbose=2 "$STAGE/AIImageEditor.app"

echo "==> Packaging DMG"
hdiutil create -volname "AIImageEditor" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
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
