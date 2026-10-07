#!/bin/sh
# Build ModemManager's Huawei plugin with E3372 support against a pinned
# ModemManager release and package it as a .deb for Debian / Raspberry Pi OS
# trixie.
#
# Runs on trixie with the build dependencies from the README installed.
# usage: ./build.sh [version]
#   version defaults to the git tag on HEAD, or <MM_TAG>-0~git<date>.<count>.<sha>
#   for untagged builds (sorts before the first release for that MM version;
#   the commit count keeps builds from the same day in order).
set -eu

TOP=$(cd "$(dirname "$0")" && pwd)
. "$TOP/versions.env"

NAME=modemmanager-e3372
MAINTAINER="Jonas Höchst <hoechst@trackit.systems>"
HOMEPAGE=https://github.com/trackIT-Systems/modemmanager-e3372

SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$TOP" log -1 --format=%ct 2>/dev/null || date +%s)}
export SOURCE_DATE_EPOCH

if [ $# -ge 1 ]; then
    VERSION=$1
elif tag=$(git -C "$TOP" describe --tags --exact-match 2>/dev/null); then
    VERSION=$tag
else
    VERSION="$MM_TAG-0~git$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%d).$(git -C "$TOP" rev-list --count HEAD).$(git -C "$TOP" rev-parse --short HEAD)"
fi
dpkg --validate-version "$VERSION"

ARCH=$(dpkg --print-architecture)
MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH)

WORK=$TOP/build
SRC=$WORK/src
BUILD=$WORK/meson
STAGE=$WORK/stage
DIST=$TOP/dist

if [ -e "$WORK" ]; then
    echo "error: $WORK exists, remove it for a clean build" >&2
    exit 1
fi
mkdir -p "$WORK" "$DIST"

# Fetch the pinned ModemManager release and apply the plugin patches
git clone --quiet --depth 1 --branch "$MM_TAG" "$MM_REPO" "$SRC"
if [ "$(git -C "$SRC" rev-parse HEAD)" != "$MM_COMMIT" ]; then
    echo "error: tag $MM_TAG does not point to $MM_COMMIT" >&2
    exit 1
fi
git -C "$SRC" -c user.name=build -c user.email=build@localhost \
    am --quiet "$TOP"/patches/*.patch

# Configure like Debian's package, but build only the Huawei plugin
meson setup "$BUILD" "$SRC" \
    --buildtype=plain \
    -Dpolkit=permissive \
    -Dmbim=true -Dqmi=true -Dqrtr=true \
    -Dintrospection=false -Dvapi=false -Dman=false \
    -Dbash_completion=false -Dtests=false -Dexamples=false \
    -Dauto_features=disabled \
    -Dplugin_huawei=enabled

# The plugin target alone doesn't wait for all generated headers it includes
ninja -C "$BUILD" \
    src/mm-helper-enums-types.h src/mm-port-enums-types.h \
    src/mm-daemon-enums-types.h src/plugins/mm-huawei-enums-types.h
ninja -C "$BUILD" src/plugins/libmm-plugin-huawei.so

# Stage the files at their install locations
PLUGINDIR=$STAGE/usr/lib/$MULTIARCH/ModemManager
UDEVDIR=$STAGE/usr/lib/udev/rules.d
MODESWITCHDIR=$STAGE/etc/usb_modeswitch.d
DOCDIR=$STAGE/usr/share/doc/$NAME
install -d "$PLUGINDIR" "$UDEVDIR" "$MODESWITCHDIR" "$DOCDIR"

install -m 644 "$BUILD/src/plugins/libmm-plugin-huawei.so" "$PLUGINDIR/"
# drop the build-tree RUNPATH and debug info, like `meson install` + dh_strip
patchelf --remove-rpath "$PLUGINDIR/libmm-plugin-huawei.so"
strip --strip-unneeded --remove-section=.comment --remove-section=.note "$PLUGINDIR/libmm-plugin-huawei.so"

install -m 644 "$SRC/src/plugins/huawei/77-mm-huawei-net-port-types.rules" "$UDEVDIR/"
install -m 644 "$TOP"/udev/*.rules "$UDEVDIR/"
install -m 644 "$TOP"/usb_modeswitch/* "$MODESWITCHDIR/"

# Documentation, as required by Debian policy
install -m 644 "$TOP/README.md" "$TOP/docs/E3372-325.md" "$DOCDIR/"
cat > "$DOCDIR/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ModemManager
Upstream-Contact: https://gitlab.freedesktop.org/mobile-broadband/ModemManager
Source: $HOMEPAGE

Files: *
Copyright: ModemManager contributors
           2026 trackIT Systems
License: GPL-2+
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 .
 On Debian systems, the complete text of the GNU General Public License
 version 2 can be found in /usr/share/common-licenses/GPL-2.
EOF
cat > "$WORK/changelog.Debian" <<EOF
$NAME ($VERSION) trixie; urgency=medium

  * Built from $(git -C "$TOP" rev-parse --short HEAD 2>/dev/null || echo unknown) against ModemManager $MM_TAG ($MM_COMMIT),
    for Debian modemmanager $MM_DEBIAN_VERSION.
  * See $HOMEPAGE/blob/main/CHANGELOG.md

 -- $MAINTAINER  $(date -u -R -d "@$SOURCE_DATE_EPOCH")
EOF
gzip -9n < "$WORK/changelog.Debian" > "$DOCDIR/changelog.Debian.gz"
chmod 644 "$DOCDIR"/*

# Runtime library dependencies
mkdir -p "$WORK/shlibs/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$NAME" "$NAME" > "$WORK/shlibs/debian/control"
SHLIBS=$(cd "$WORK/shlibs" && dpkg-shlibdeps -O "$PLUGINDIR"/*.so |
    sed -n 's/^shlibs:Depends=//p')
if [ -z "$SHLIBS" ]; then
    echo "error: dpkg-shlibdeps found no library dependencies" >&2
    exit 1
fi
# libmm-glib0 gets an exact dependency below instead of the generated one
SHLIBS=$(echo "$SHLIBS" | tr ',' '\n' | sed 's/^ *//' | grep -v '^libmm-glib0 ' | paste -sd, - | sed 's/,/, /g')

# The plugin uses daemon-internal symbols: only the exact ModemManager build fits
DEPENDS="$SHLIBS, modemmanager (= $MM_DEBIAN_VERSION), libmm-glib0 (= $MM_DEBIAN_VERSION), usb-modeswitch"

install -d "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)
Depends: $DEPENDS
Section: net
Priority: optional
Homepage: $HOMEPAGE
Description: ModemManager support for the ZOWEE (Brovi) E3372-325 LTE stick
 Runs the E3372-325 (3566:2001) in modem mode with ModemManager and
 NetworkManager instead of HiLink mode: switches it with usb_modeswitch, binds
 the option driver to its AT ports and replaces ModemManager's Huawei plugin
 with one that supports the stick (PPP data connection, signal values).
 .
 The Huawei plugin and its udev rules are built from ModemManager $MM_TAG with
 patches for the stick and replace Debian's files via dpkg-divert. Built
 against Debian's modemmanager $MM_DEBIAN_VERSION.
EOF

# The usb_modeswitch configuration lives in /etc, so it's a conffile
(cd "$STAGE" && find etc -type f -printf '/%p\n' | sort) > "$STAGE/DEBIAN/conffiles"

# Debian's Huawei plugin and udev rules are diverted and replaced by ours.
# ModemManager only loads files ending in .so and udev only reads *.rules, so
# the diverted copies stay inactive.
DIVERTED="/usr/lib/$MULTIARCH/ModemManager/libmm-plugin-huawei.so /usr/lib/udev/rules.d/77-mm-huawei-net-port-types.rules"

cat > "$STAGE/DEBIAN/preinst" <<EOF
#!/bin/sh
set -e

if [ "\$1" = install ] || [ "\$1" = upgrade ]; then
    for f in $DIVERTED; do
        dpkg-divert --package $NAME --add --rename --divert "\$f.distrib" "\$f"
    done
fi

exit 0
EOF

cat > "$STAGE/DEBIAN/postrm" <<EOF
#!/bin/sh
set -e

if [ "\$1" = remove ] || [ "\$1" = abort-install ] || [ "\$1" = disappear ]; then
    for f in $DIVERTED; do
        dpkg-divert --package $NAME --remove --rename --divert "\$f.distrib" "\$f"
    done
fi

# Reload udev rules and restart ModemManager on a running system. In image
# builds (chroot, no systemd running) there is nothing to do.
if [ -d /run/systemd/system ]; then
    udevadm control --reload || true
    deb-systemd-invoke try-restart ModemManager.service >/dev/null || true
fi

exit 0
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

# Reload udev rules and restart ModemManager on a running system. In image
# builds (chroot, no systemd running) there is nothing to do.
if [ -d /run/systemd/system ]; then
    udevadm control --reload || true
    deb-systemd-invoke try-restart ModemManager.service >/dev/null || true
fi

exit 0
EOF
chmod 755 "$STAGE/DEBIAN/preinst" "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

(cd "$STAGE" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | sort -z | xargs -0 md5sum) \
    > "$STAGE/DEBIAN/md5sums"

DEB=$DIST/${NAME}_${VERSION}_${ARCH}.deb
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DEB"
dpkg-deb --info "$DEB"
dpkg-deb --contents "$DEB"
