#!/bin/zsh
# Builds build/Screenshotee.app. Set SIGN_ID to a Developer ID / Apple Development identity
# for a stable code identity (keeps privacy grants across rebuilds); defaults to ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Screenshotee.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/screenshotee"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP"
