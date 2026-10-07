#!/bin/sh
# Verify that every symbol the built plugin imports is provided by the installed
# ModemManager daemon or libmm-glib. Catches a plugin that would fail to load
# on the target system.
#
# Needs the Debian modemmanager package (MM_DEBIAN_VERSION) installed.
# usage: ./check-symbols.sh
set -eu

TOP=$(cd "$(dirname "$0")" && pwd)
. "$TOP/versions.env"

MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
PLUGINDIR=$TOP/build/stage/usr/lib/$MULTIARCH/ModemManager
DAEMON=/usr/sbin/ModemManager
LIBMM=$(ldd "$DAEMON" | awk '/libmm-glib\.so/ { print $3 }')

if [ ! -e "$PLUGINDIR/libmm-plugin-huawei.so" ]; then
    echo "error: $PLUGINDIR/libmm-plugin-huawei.so not found, run ./build.sh first" >&2
    exit 1
fi

installed=$(dpkg-query -W -f='${Version}' modemmanager)
if [ "$installed" != "$MM_DEBIAN_VERSION" ]; then
    echo "error: modemmanager $installed installed, expected $MM_DEBIAN_VERSION" >&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT

defined() {
    nm -D --defined-only "$@" | awk 'NF == 3 { sub(/@.*/, "", $3); print $3 }'
}

defined "$DAEMON" "$LIBMM" | sort -u > "$tmp/provided"
nm -D --undefined-only "$PLUGINDIR"/*.so | awk '{ sub(/@.*/, "", $2); print $2 }' |
    grep -E '^_?mm_' | sort -u > "$tmp/needed"

missing=$(comm -23 "$tmp/needed" "$tmp/provided")
if [ -n "$missing" ]; then
    echo "error: symbols not provided by modemmanager $installed:" >&2
    echo "$missing" >&2
    exit 1
fi
echo "ok: all $(wc -l < "$tmp/needed") ModemManager symbols resolve against modemmanager $installed"

# ModemManager rejects plugins without these exports
fail=0
for so in "$PLUGINDIR"/libmm-plugin-*.so; do
    defined "$so" > "$tmp/exports"
    for sym in mm_plugin_major_version mm_plugin_minor_version mm_plugin_create; do
        if ! grep -qx "$sym" "$tmp/exports"; then
            echo "error: $(basename "$so") does not export $sym" >&2
            fail=1
        fi
    done
done
[ "$fail" -eq 0 ] || exit 1
echo "ok: plugin version and creator exports present"
