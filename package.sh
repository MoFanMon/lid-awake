#!/bin/zsh
set -eu
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$ROOT/dist}"
BUILD="$ROOT/.build/packaging"
RELEASE="$ROOT/.build/release"
mkdir -p "$DEST" "$BUILD/Payload/Applications" "$BUILD/Packages" "$BUILD/DiskImage"
"$ROOT/build.sh" "$RELEASE"
/usr/bin/ditto "$RELEASE/合盖不眠.app" "$BUILD/Payload/Applications/合盖不眠.app"
/usr/bin/pkgbuild --analyze --root "$BUILD/Payload" "$BUILD/Components.plist"
/usr/bin/python3 - "$BUILD/Components.plist" <<'PY'
import sys, plistlib
p = sys.argv[1]
with open(p, 'rb') as f: components = plistlib.load(f)
for c in components:
    c['BundleIsRelocatable'] = False
    c['BundleHasStrictIdentifier'] = True
    c['BundleIsVersionChecked'] = True
    c['BundleOverwriteAction'] = 'upgrade'
with open(p, 'wb') as f: plistlib.dump(components, f)
PY
/usr/bin/pkgbuild --root "$BUILD/Payload" --component-plist "$BUILD/Components.plist" --install-location / --identifier local.lidawake.installer --version 2.0 --ownership recommended --scripts "$ROOT/Installer/Scripts" "$BUILD/Packages/LidAwake-component.pkg"
/usr/bin/productbuild --distribution "$ROOT/Installer/Distribution.xml" --resources "$ROOT/Installer/Resources" --package-path "$BUILD/Packages" "$DEST/合盖不眠-2.0.pkg"
/usr/bin/ditto "$RELEASE/合盖不眠.app" "$BUILD/DiskImage/合盖不眠.app"
cp "$DEST/合盖不眠-2.0.pkg" "$BUILD/DiskImage/合盖不眠-2.0.pkg"
cp "$ROOT/使用说明.txt" "$BUILD/DiskImage/使用说明.txt"
if [ ! -L "$BUILD/DiskImage/Applications" ]; then /bin/ln -s /Applications "$BUILD/DiskImage/Applications"; fi
/usr/bin/hdiutil create -volname '合盖不眠 2.0' -srcfolder "$BUILD/DiskImage" -format UDZO -ov "$DEST/合盖不眠-2.0.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$RELEASE/合盖不眠.app" "$DEST/合盖不眠-2.0-应用.zip"
/usr/bin/codesign --verify --deep --strict "$RELEASE/合盖不眠.app"
/usr/bin/hdiutil verify "$DEST/合盖不眠-2.0.dmg"
printf 'Packaged %s\n' "$DEST"
