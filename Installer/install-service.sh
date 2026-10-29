#!/bin/sh
set -eu
[ "$(/usr/bin/id -u)" -eq 0 ] || { echo '需要 macOS 管理员授权。' >&2; exit 1; }
SOURCE=${1:?缺少应用路径}
TARGET='/Applications/合盖不眠.app'
BASE='/Library/Application Support/LidAwake'
HELPER='/Library/PrivilegedHelperTools/local.lidawake.helper'
PLIST='/Library/LaunchDaemons/local.lidawake.helper.plist'
/usr/bin/codesign --verify --deep --strict "$SOURCE"
for DIR in '/Library/PrivilegedHelperTools' '/Library/LaunchDaemons' "$BASE"; do
    [ ! -L "$DIR" ] || { echo '安装目录不能是符号链接。' >&2; exit 1; }
    if [ -e "$DIR" ]; then
        [ -d "$DIR" ] && [ "$(/usr/bin/stat -f %u "$DIR")" -eq 0 ] || { echo '安装目录权限无效。' >&2; exit 1; }
    else
        /bin/mkdir -p "$DIR"
        /usr/sbin/chown root:wheel "$DIR"
    fi
done
/bin/chmod 700 "$BASE"
[ ! -L "$TARGET" ] || { echo '目标应用不能是符号链接。' >&2; exit 1; }
if [ "$SOURCE" != "$TARGET" ]; then
    /usr/bin/ditto "$SOURCE" "$TARGET"
fi
/usr/sbin/chown -R root:wheel "$TARGET"
/bin/chmod -R go-w "$TARGET"
/usr/bin/codesign --verify --deep --strict "$TARGET"
/bin/launchctl bootout system/local.lidawake.helper 2>/dev/null || true
/usr/bin/install -o root -g wheel -m 755 "$TARGET/Contents/Library/LaunchServices/LidAwakeDaemon" "$HELPER"
/usr/bin/install -o root -g wheel -m 644 "$TARGET/Contents/Resources/local.lidawake.helper.plist" "$PLIST"
REQUIREMENT='identifier "local.lidawake.mac" and ('
SEPARATOR=''
for ARCH in $(/usr/bin/lipo -archs "$TARGET/Contents/MacOS/LidAwake"); do
    HASH=$(/usr/bin/codesign -d --arch "$ARCH" --verbose=4 "$TARGET/Contents/MacOS/LidAwake" 2>&1 | /usr/bin/awk -F= '/^CDHash=/{print $2}')
    case "$HASH" in ''|*[!0-9a-fA-F]*) echo '无法确认应用签名。' >&2; exit 1;; esac
    [ ${#HASH} -eq 40 ] || { echo '应用签名长度无效。' >&2; exit 1; }
    REQUIREMENT="$REQUIREMENT${SEPARATOR}cdhash H\"$HASH\""
    SEPARATOR=' or '
done
[ -n "$SEPARATOR" ] || exit 1
REQUIREMENT="$REQUIREMENT)"
TEMP=$(/usr/bin/mktemp "$BASE/requirement.XXXXXX")
trap '/bin/rm -f "$TEMP"' EXIT HUP INT TERM
printf '%s\n' "$REQUIREMENT" > "$TEMP"
/usr/sbin/chown root:wheel "$TEMP"
/bin/chmod 600 "$TEMP"
/bin/mv -f "$TEMP" "$BASE/client.requirement"
/bin/launchctl enable system/local.lidawake.helper
/bin/launchctl bootstrap system "$PLIST"
COUNT=0
while [ "$COUNT" -lt 40 ]; do
    if [ -S /var/run/local.lidawake.helper.sock ]; then exit 0; fi
    /bin/sleep 0.25
    COUNT=$((COUNT + 1))
done
echo '辅助服务尚未启动，请重新安装或查看 /var/log/local.lidawake.helper.log。' >&2
exit 1
