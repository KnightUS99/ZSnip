#!/bin/zsh
# Builds ZSnip.app into ./build. Pass --install to also copy it to /Applications,
# or --run to launch it after building.
#
# Signs with, in order of preference: $ZSNIP_SIGN_IDENTITY, a "Developer ID Application"
# certificate, an "Apple Development" certificate, or ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/ZSnip.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/ZSnip" "$APP/Contents/MacOS/ZSnip"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/ZSnip"

PLIST="$APP/Contents/Info.plist"
# Update feed: the appcast.xml attached to the latest GitHub release of the "origin" repo.
REPO="$(git remote get-url origin 2>/dev/null | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//' || true)"
if [[ -n "$REPO" ]]; then
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://github.com/$REPO/releases/latest/download/appcast.xml" "$PLIST"
else
    echo "note: no GitHub 'origin' remote, so this build has no auto-updates"
fi
if [[ -n "${ZSNIP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $ZSNIP_VERSION" -c "Set :CFBundleVersion $ZSNIP_VERSION" "$PLIST"
fi

find_identity() { security find-identity -v -p codesigning | grep -m1 "$1" | sed -E 's/.*"(.*)"/\1/' || true; }
IDENTITY="${ZSNIP_SIGN_IDENTITY:-$(find_identity 'Developer ID Application')}"
[[ -z "$IDENTITY" ]] && IDENTITY="$(find_identity 'Apple Development')"

if [[ -n "$IDENTITY" ]]; then
    FLAGS=(--force --options runtime --sign "$IDENTITY")
    [[ "$IDENTITY" == "Developer ID Application"* ]] && FLAGS+=(--timestamp)
    # Sign Sparkle's helpers inside-out, then the framework, then the app (per Sparkle's docs).
    SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
    codesign "${FLAGS[@]}" "$SPARKLE/XPCServices/Installer.xpc"
    codesign "${FLAGS[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
    codesign "${FLAGS[@]}" "$SPARKLE/Autoupdate"
    codesign "${FLAGS[@]}" "$SPARKLE/Updater.app"
    codesign "${FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
    codesign "${FLAGS[@]}" "$APP"
    echo "Signed with: $IDENTITY"
else
    echo "warning: no signing identity found; ad-hoc signing (Screen Recording permission resets on every rebuild)"
    codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"

for arg in "$@"; do
    case "$arg" in
        --install)
            pkill -x ZSnip || true
            rm -rf /Applications/ZSnip.app
            ditto "$APP" /Applications/ZSnip.app
            echo "Installed to /Applications/ZSnip.app"
            APP="/Applications/ZSnip.app"
            ;;
        --run)
            pkill -x ZSnip || true
            open "$APP"
            ;;
    esac
done
