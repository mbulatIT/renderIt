# Publishing (signed Developer ID distribution)

How to ship AIImageEditor as a signed + notarized DMG that runs on any Mac
without Xcode, Tuist, or Gatekeeper warnings. This is "Direct Distribution"
(outside the Mac App Store) using a **Developer ID Application** certificate.

Bundle identifiers are `com.bulat.aiimageeditor[.core|.cli|.mcp]`; the
document UTI is `com.bulat.aiimageeditor.aiproj` (declared in
[Project.swift](../Project.swift) and mirrored in `AIImageEditorApp.swift`).

## One-time setup

Requires a paid Apple Developer Program membership.

### 1. Developer ID Application certificate

Xcode → **Settings → Accounts** → select your Apple ID → **Manage
Certificates…** → **+** → **Developer ID Application**.

Verify it landed in the keychain:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 2. Notarization credentials

Notarization uses an **app-specific password** (not your Apple ID password):

1. Create one at [account.apple.com](https://account.apple.com) →
   Sign-In and Security → App-Specific Passwords.
2. Find your 10-character Team ID at
   [developer.apple.com/account](https://developer.apple.com/account) → Membership.
3. Store a keychain profile so scripts never see the password:

```bash
xcrun notarytool store-credentials aiimageeditor \
    --apple-id <your-apple-id-email> \
    --team-id <TEAMID> \
    --password <app-specific-password>
```

## Releasing

```bash
NOTARY_PROFILE=aiimageeditor ./Scripts/release.sh 1.0.0
```

The script:

1. `tuist generate` + Release builds of the app, CLI, and MCP server.
2. Stages `AIImageEditor.app`, `aiimageeditor-cli`, `aiimageeditor-mcp` into `dist/stage/`.
3. Signs everything with hardened runtime + secure timestamp.
4. Builds a read-write DMG and scripts Finder to apply the install-window
   layout: background picture (`Packaging/dmg-background.tiff` — itself
   rendered from `Packaging/dmg-background.aiproj` by `aiimageeditor-cli`),
   icon positions, window size. Requires a GUI session; on first run macOS may
   ask to allow your terminal to control Finder (Automation permission).
5. Compresses to the final DMG, signs it, submits to Apple notarization
   (`notarytool --wait`), staples the ticket, and runs a Gatekeeper self-check
   (`spctl`).

Output: `dist/AIImageEditor-<version>.dmg`. If the keychain holds more than one
Developer ID identity, pass the exact one:
`SIGN_ID="Developer ID Application: Name (TEAMID)"`.

## Recipient install

1. Open the DMG, drag `AIImageEditor.app` onto the bundled `Applications`
   shortcut.
2. Double-click `Install Command Line Tools.command` — it copies
   `aiimageeditor-cli` / `aiimageeditor-mcp` into `/usr/local/bin` (asks for
   the admin password once). If Gatekeeper balks at the script, right-click →
   Open. Manual alternative (the binaries sit in a hidden `.bin` folder to keep
   the Finder window clean):
   ```bash
   sudo cp /Volumes/AIImageEditor/.bin/aiimageeditor-{cli,mcp} /usr/local/bin/
   ```
3. Register the MCP server with an AI agent as usual — see
   [MCP_GUIDE.md](MCP_GUIDE.md) / [ONBOARDING.md](../ONBOARDING.md). No Xcode or
   Tuist needed on the recipient's machine.

## Troubleshooting

- **`notarytool submit` returns `Invalid`** — run
  `xcrun notarytool log <submission-id> --keychain-profile aiimageeditor` and
  fix the listed issues (usually a binary missed by signing or a missing
  `--options runtime`).
- **`errSecInternalComponent` while signing** — the keychain is locked:
  `security unlock-keychain login.keychain-db`.
- **Standalone CLI binaries and stapling** — bare Mach-O executables cannot
  carry a stapled ticket; they are still notarized and Gatekeeper verifies them
  online. Only the DMG (and `.app` bundles) get stapled.
