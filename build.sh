#!/bin/zsh
set -eu
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$ROOT/dist}"
BUILD="$ROOT/.build"
APP="$DEST/合盖不眠.app"
mkdir -p "$BUILD/ModuleCache" "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchServices" "$APP/Contents/Resources"
COMMON=("$ROOT/Sources/Core.swift" "$ROOT/Sources/System.swift" "$ROOT/Sources/IPC.swift")
for ARCH in arm64 x86_64; do
  SWIFT=(/usr/bin/swiftc -O -target "${ARCH}-apple-macosx13.0" -module-cache-path "$BUILD/ModuleCache")
  "${SWIFT[@]}" "${COMMON[@]}" "$ROOT/Sources/ServiceCore.swift" "$ROOT/Sources/Journal.swift" "$ROOT/Service/main.swift" -o "$BUILD/daemon-$ARCH"
  "${SWIFT[@]}" "${COMMON[@]}" "$ROOT/App/Controller.swift" "$ROOT/App/Interface.swift" "$ROOT/App/main.swift" -o "$BUILD/app-$ARCH"
done
/usr/bin/lipo -create "$BUILD/daemon-arm64" "$BUILD/daemon-x86_64" -output "$APP/Contents/Library/LaunchServices/LidAwakeDaemon"
/usr/bin/lipo -create "$BUILD/app-arm64" "$BUILD/app-x86_64" -output "$APP/Contents/MacOS/LidAwake"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Installer/install-service.sh" "$ROOT/Installer/uninstall-service.sh" "$ROOT/Installer/local.lidawake.helper.plist" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
/usr/bin/swiftc -O -module-cache-path "$BUILD/ModuleCache" "$ROOT/Icon.swift" -o "$BUILD/icon-render"
"$BUILD/icon-render" "$BUILD/icon.png"
mkdir -p "$BUILD/AppIcon.iconset"
for SIZE in 16 32 128 256 512; do
  /usr/bin/sips -z "$SIZE" "$SIZE" "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  /usr/bin/sips -z "$DOUBLE" "$DOUBLE" "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - --options runtime --timestamp=none --identifier local.lidawake.helper "$APP/Contents/Library/LaunchServices/LidAwakeDaemon"
/usr/bin/codesign --force --sign - --options runtime --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
