#!/bin/zsh
# Publishes a new ZSnip release:
#   ./release.sh 0.2.0 "What changed in this version"
#
# Bumps the version, builds and signs with Developer ID, notarizes with Apple,
# signs the update for Sparkle, then tags, pushes and creates the GitHub release
# (with the zip and appcast.xml that installed copies check for updates).
#
# One-time setup on the release machine:
#   - "Developer ID Application" certificate in Keychain
#   - xcrun notarytool store-credentials zsnip-notary --apple-id … --team-id …
#   - Sparkle private key in Keychain (scripts/sparkle-tools.sh, then generate_keys)
#   - gh auth login
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
NOTES="${2:-}"
NOTARY_PROFILE="${ZSNIP_NOTARY_PROFILE:-zsnip-notary}"

die() { echo "error: $*" >&2; exit 1; }

[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "usage: ./release.sh <major.minor.patch> [\"release notes\"]"
git diff --quiet && git diff --cached --quiet || die "commit or stash your changes first"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)" || die "no GitHub repo found (gh repo view failed)"
gh release view "v$VERSION" >/dev/null 2>&1 && die "release v$VERSION already exists"

echo "==> Releasing ZSnip $VERSION to $REPO"

# 1. Version bump
PLIST=Resources/Info.plist
CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [[ "$CURRENT" != "$VERSION" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$PLIST"
    git commit -q -m "Release $VERSION" "$PLIST"
fi

# 2. Build + sign
./build.sh
APP=build/ZSnip.app
SIGNING_INFO="$(codesign -dv "$APP" 2>&1)"
[[ "$SIGNING_INFO" == *"Authority=Developer ID Application"* ]] || die "app isn't signed with a Developer ID certificate"

# 3. Notarize + staple
ZIP="build/ZSnip-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> Notarizing (usually a few minutes)…"
RESULT="$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
STATUS="$(echo "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
if [[ "$STATUS" != "Accepted" ]]; then
    ID="$(echo "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
    xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" || true
    die "notarization status: $STATUS"
fi
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip so the download includes the staple
spctl --assess --type exec "$APP" || die "Gatekeeper rejected the notarized app"

# 4. Sparkle signature + appcast
SPARKLE_BIN="$(scripts/sparkle-tools.sh)"
SIGNATURE="$("$SPARKLE_BIN/sign_update" "$ZIP")"   # sparkle:edSignature="…" length="…"
DESCRIPTION=""
[[ -n "$NOTES" ]] && DESCRIPTION="<description><![CDATA[<p>${NOTES//$'\n'/<br>}</p>]]></description>"
cat > build/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ZSnip</title>
    <item>
      <title>ZSnip $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      $DESCRIPTION
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/ZSnip-$VERSION.zip" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF

# 5. Tag, push, publish
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" "$ZIP" build/appcast.xml \
    --title "ZSnip $VERSION" \
    --notes "${NOTES:-ZSnip $VERSION}"

echo "==> Done: https://github.com/$REPO/releases/tag/v$VERSION"
