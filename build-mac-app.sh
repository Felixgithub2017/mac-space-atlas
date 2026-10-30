#!/bin/zsh
set -e

ROOT="${0:A:h}"
APP="$ROOT/空间地图.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/NativeApp/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/NativeApp/SpaceAtlas.icns" "$APP/Contents/Resources/SpaceAtlas.icns"

swiftc -O \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
  -framework SwiftUI -framework AppKit \
  "$ROOT/NativeApp/DiskModel.swift" \
  "$ROOT/NativeApp/ContentView.swift" \
  "$ROOT/NativeApp/SpaceAtlasApp.swift" \
  -o "$APP/Contents/MacOS/SpaceAtlas"

echo "已生成：$APP"
