#!/bin/sh
set -eu
[ "$(/usr/bin/id -u)" -eq 0 ] || { echo '需要 macOS 管理员授权。' >&2; exit 1; }
BASE='/Library/Application Support/LidAwake'
# Gracefully stop the daemon. It restores the original setting before exiting.
/bin/launchctl bootout system/local.lidawake.helper 2>/dev/null || true
COUNT=0
while /usr/bin/pgrep -f '^/Library/PrivilegedHelperTools/local.lidawake.helper$' >/dev/null 2>&1 && [ "$COUNT" -lt 40 ]; do
    /bin/sleep 0.25
    COUNT=$((COUNT + 1))
done
# A saved journal means restoration has not completed. Preserve recovery resources.
if [ -f "$BASE/session.json" ]; then
    /bin/launchctl bootstrap system /Library/LaunchDaemons/local.lidawake.helper.plist 2>/dev/null || true
    echo '原设置尚未恢复，服务已保留。请关闭开关后再次卸载。' >&2
    exit 1
fi
/bin/rm -f /Library/LaunchDaemons/local.lidawake.helper.plist /Library/PrivilegedHelperTools/local.lidawake.helper
/bin/rm -f /var/run/local.lidawake.helper.sock /var/run/local.lidawake.lock /var/log/local.lidawake.helper.log
/bin/rm -f "$BASE/client.requirement"
/bin/rmdir "$BASE" 2>/dev/null || true
/usr/sbin/pkgutil --forget local.lidawake.installer >/dev/null 2>&1 || true
