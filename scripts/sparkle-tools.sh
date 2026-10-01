#!/bin/zsh
# Downloads Sparkle's command-line tools (generate_keys, sign_update) matching the
# Sparkle version in Package.swift, and prints the directory they're in.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -oE 'Sparkle", exact: "[0-9.]+' Package.swift | grep -oE '[0-9.]+$')
DIR=".build/sparkle-tools/$VERSION"
if [[ ! -x "$DIR/bin/sign_update" ]]; then
    mkdir -p "$DIR"
    curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" | tar -xJ -C "$DIR"
fi
echo "$PWD/$DIR/bin"
