# ZSnip

A small, free macOS menu-bar screenshot tool: hotkey → draw → select → Enter → clipboard.

## Install

Download the latest `ZSnip-x.y.z.zip` from [Releases](https://github.com/KnightUS99/ZSnip/releases/latest),
unzip it and drag **ZSnip** to Applications. It's signed and notarized, so it opens normally, and it
updates itself (menu-bar icon → Check for Updates…).

On first run a setup window walks you through granting **Screen Recording** (it opens the right
System Settings page and can relaunch ZSnip for you). Reopen it any time from the menu-bar icon →
Setup & Permissions….

Requires macOS 14 or later.

## Keys

Everything is also clickable in the toolbar at the top of the capture screen.

| Key | Action |
|---|---|
| Print Screen (F13) | Start a capture (change it from the menu-bar icon → Change Hotkey…) |
| **S** | Select mode: drag an area (the default mode) |
| **D** | Draw mode |
| R / C / F | Rectangle / Circle / Freehand (also switches to Draw mode). Hold ⇧ for square or circle |
| 1–5 | Colour: red, yellow, green, blue, white |
| [ / ] | Thinner / thicker line |
| **B** | Blur toggle (stays on until turned off): ↩ copies the whole screen, blurred everywhere except the selection (or the area around your drawings) |
| ⌘Z or ⌫ | Undo the last shape |
| ↩ | Copy the selection. With no selection it copies the area around your drawings (shown dashed), or the whole screen if you haven't drawn anything |
| ⇧↩ | Upload with the active destination, then copy the link |
| Esc | Cancel |

## Upload destinations

Any image host that takes a POST and returns a URL can be added without code. Put a JSON file in
`~/Library/Application Support/ZSnip/Uploaders/` (menu → Upload Destination → Open Uploaders Folder):

```json
{
  "name": "Imgur",
  "requestURL": "https://api.imgur.com/3/image",
  "body": "multipart",
  "fileFormName": "image",
  "headers": { "Authorization": "Client-ID YOUR_CLIENT_ID" },
  "formFields": { "type": "file" },
  "urlJSONPath": "data.link"
}
```

| Field | Meaning |
|---|---|
| `body` | `multipart` (default) or `binary` (raw PNG as the request body) |
| `method` | Default `POST` |
| `fileFormName` | Multipart field name for the image, default `file` |
| `urlJSONPath` | Dot path to the link in the JSON response (`files.0.url` indexes arrays). Leave it out if the response is the URL as plain text |
| `deletionURLJSONPath`, `thumbnailURLJSONPath` | Optional |

For hosts that need real logic (OAuth, signed requests, multi-step uploads), implement the
`ImageUploader` protocol in `Sources/ZSnip/Upload/` and add it to `builtIn` in `UploaderRegistry.swift`.

## Building from source

Needs Xcode or the Command Line Tools.

```sh
./build.sh --run        # build to build/ZSnip.app and launch
./build.sh --install    # copy to /Applications (recommended before enabling Launch at Login)
```

The app icon is drawn in code: edit `scripts/make-icon.swift` and run `swift scripts/make-icon.swift`
to regenerate `Resources/AppIcon.icns`. The menu-bar glyph lives in `Sources/ZSnip/App/MenuBarIcon.swift`.

Without a Developer ID or Apple Development certificate the app is ad-hoc signed, and macOS asks
for Screen Recording permission again after every rebuild.

## Releasing

```sh
./release.sh 0.2.0 "What changed"
```

Builds, signs, notarizes, signs the update for Sparkle, and publishes a GitHub release with the zip
and `appcast.xml` (the feed installed copies check). One-time setup is listed at the top of `release.sh`.

## License

MIT, see [LICENSE](LICENSE).
