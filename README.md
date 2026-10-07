# modemmanager-e3372

ModemManager support for E3372 LTE sticks in **modem mode**, packaged for
**Raspberry Pi OS**. Currently the **ZOWEE (Brovi) E3372-325**: instead of
running as a HiLink router with its own NAT at `192.168.8.1`, the stick is
switched to modem mode and handled by ModemManager and NetworkManager. The
host gets the carrier IP directly on `ppp0`, and ModemManager reports signal,
cell and operator information.

The package contains:

* a usb_modeswitch configuration that switches the stick to modem mode,
* a udev rule that binds the kernel's `option` driver to its AT ports,
* ModemManager's Huawei plugin with patches for the stick, and its udev rules.

## Target system

| | |
|---|---|
| OS | Raspberry Pi OS (64-bit) **trixie** (Debian 13) |
| Architecture | `arm64` only |
| ModemManager | `modemmanager 1.24.0-1+deb13u1` from Debian trixie (also what Raspberry Pi OS trixie installs) |

The plugin uses ModemManager-internal symbols, so each release works with
**exactly one** `modemmanager` version, see
[Compatibility and updates](#compatibility-and-updates).

## Supported devices

| USB ID | Device | Status |
|---|---|---|
| `3566:2001` | ZOWEE E3372-325, sold as Brovi or Huawei E3372-325 | Supported, data over PPP |
| `12d1:14db` | Huawei E3372h-320 | Planned (NCM via `^NDISDUP`) |
| `12d1:14dc` | Huawei E3372h-153 | Planned |

The E3372-325 shares the name with Huawei's E3372 sticks but is a different
design (Marvell chipset, Huawei-compatible firmware), see
[docs/E3372-325.md](docs/E3372-325.md).

## Installation

Download the `.deb` for your release from the
[releases page](https://github.com/trackIT-Systems/modemmanager-e3372/releases)
and install it with apt:

```sh
sudo apt install ./modemmanager-e3372_<version>_arm64.deb
```

The package reloads the udev rules and restarts ModemManager. Re-plug the stick
(or reboot) so it's switched to modem mode.

Check that ModemManager handles the stick:

```sh
mmcli -L                      # [ZOWEE TECHNOLOGY (HEYUAN) CO., LTD.] E3372-325
mmcli -m any | grep plugin    # plugin: huawei
```

Then create a NetworkManager connection with your SIM's APN. **IPv6 must be
disabled**, the stick ends PPP sessions that negotiate IPv6:

```sh
sudo nmcli connection add type gsm ifname '*' con-name cellular apn <your-apn> ipv6.method disabled
```

NetworkManager connects automatically and brings up `ppp0`. Signal values:

```sh
mmcli -m any --signal-setup=10
mmcli -m any --signal-get
```

> [!IMPORTANT]
> **The package replaces ModemManager's Huawei plugin.** It diverts Debian's
> `libmm-plugin-huawei.so` and `77-mm-huawei-net-port-types.rules`
> (`dpkg-divert`, the originals are kept as `*.distrib`) and installs patched
> builds of both. The patches only add support for the E3372-325 and keep the
> behavior for Huawei devices otherwise unchanged (see [Background](#background)).
> Removing the package restores Debian's files.

### In image builds

The package can be installed in a chroot, e.g. with
[pi-gen](https://github.com/RPi-Distro/pi-gen) or
[pimod](https://github.com/Nature40/pimod). Without a running systemd, the
package scripts only set up the diversions. Example for a pimod `Pifile`:

```sh
MM_E3372_VERSION=1.24.0-1
RUN sh -c "curl -fsSL -o /tmp/modemmanager-e3372.deb https://github.com/trackIT-Systems/modemmanager-e3372/releases/download/${MM_E3372_VERSION}/modemmanager-e3372_${MM_E3372_VERSION}_arm64.deb"
RUN apt-get install -y /tmp/modemmanager-e3372.deb
RUN rm /tmp/modemmanager-e3372.deb
```

`apt-get install` fails the build if the image's `modemmanager` isn't the
version the release was built for.

## Compatibility and updates

The package depends on the exact `modemmanager` and `libmm-glib0` version it
was built against, e.g. `modemmanager (= 1.24.0-1+deb13u1)`. apt refuses to
install it next to any other ModemManager version, and the plugin can't end up
loaded into a ModemManager it doesn't fit.

When Debian publishes a new `modemmanager` for trixie:

* `apt upgrade` holds the new `modemmanager` back.
* `apt full-upgrade` would remove this package to install it.

Wait for a release of this repository for the new version, or build one (see
[Maintenance](#maintenance)). Check the installed version with
`apt-cache policy modemmanager`.

## Hardware notes

* **Port layout** in modem mode: interface 1 AT and PPP (primary), interface 2
  Marvell diagnostics (ignored), interface 4 AT (secondary), interfaces 5/6 NCM
  (ignored, it never gets a link).
* **Modes:** the stick starts in storage (CD-ROM) mode after every power-on.
  The package's usb_modeswitch configuration (`/etc/usb_modeswitch.d/3566:2001`)
  switches it to modem mode each time; nothing is stored in the stick.
* **Throughput** (LTE, roaming, single samples): about 6 Mbit/s down, 1 Mbit/s
  up, 80–90 ms ping. PPP framing costs no measurable CPU on a Pi 5.
* **Back to HiLink:** `apt purge modemmanager-e3372` (a plain `remove` keeps
  the usb_modeswitch configuration, which would keep switching the stick to
  modem mode), re-plug, and switch the stick with
  `usb_modeswitch -v 3566 -p 2001 -J`.

Firmware details (USB modes, the attach context, supported AT commands, how to
test a change) are in [docs/E3372-325.md](docs/E3372-325.md).

## Background

Stock Raspberry Pi OS can't run the E3372-325 in modem mode:

* usb-modeswitch-data, the kernel's `option` driver and ModemManager don't know
  `3566:2001`.
* ModemManager's Huawei plugin only accepts Huawei's vendor ID, so the stick
  ends up with the generic plugin: no signal values (`+CESQ` isn't supported),
  and with no port hints it may pick the wrong AT port.
* After every boot, the stick's firmware defines its own LTE attach context
  (cid 7). ModemManager reuses it because the APN matches, but PPP on that
  context never gets through IPCP; NetworkManager retries and gives up. Any
  context the host defines works.

`patches/` applies to ModemManager `1.24.0` and only touches the Huawei plugin:

| Patch | Change |
|---|---|
| 0001 | Accept `3566:2001` in the Huawei plugin; udev rules for its port types, skip `^GETPORTMODE` (unsupported), ignore the NCM port |
| 0002 | New udev tag `ID_MM_HUAWEI_ATTACH_PROFILE_ID`: hide the firmware's attach context from the profile list, so ModemManager defines and dials its own; raise the minimum profile id to 1 (the stick rejects cid 0) |
| 0003 | Don't clear the extended signal values before querying `^HCSQ?`: the stick answers with a bare `OK` and only reports `^HCSQ` unsolicited |

0001 and 0002 only change behavior for devices tagged by the udev rules (the
E3372-325). 0003 changes when Huawei devices drop old `^HCSQ` values: on the
next `^HCSQ` message instead of before every query.

The patches are meant to go upstream to ModemManager. Once a ModemManager with
them is shipped by Debian, the plugin part of this package is obsolete; the
usb_modeswitch and `option` parts belong in usb-modeswitch-data and the kernel.

Debian's `1.24.0-1+deb13u1` only patches the Fibocom plugin, so upstream
`1.24.0` is ABI-identical to it.

## Status

Tested on a ZOWEE E3372-325 (firmware `3.0.2.61(H057SP5C983)`) on a Raspberry
Pi 5 with `modemmanager 1.24.0-1+deb13u1`, NetworkManager 1.52.1, kernel
6.18 (Raspberry Pi), SIM roaming on LTE:

* Cold start: the stick boots in storage mode, usb_modeswitch switches it,
  `option` binds the AT ports, the Huawei plugin takes the modem with the
  right ports, and NetworkManager connects on its own (`ppp0` up about 45 s
  after a firmware reboot with `AT^RESET`).
* With data checked after each step: 3 of 3 NetworkManager disconnect/reconnect
  cycles (about 2 s each), a ModemManager restart (data after about 30 s),
  `mmcli --disable`/`--enable`, and a re-attach that wiped the stick's
  contexts.
* Signal quality, access technology, operator and extended LTE signal values
  (RSSI, RSRP, RSRQ, SNR) are reported.

Known issues:

* The attach context's cid (7) is hard-coded in the udev rules; only tested with
  one carrier.
* Once, `mmcli --disable` timed out while connected; it didn't happen again.

## Maintenance

### Building

On Raspberry Pi OS or Debian trixie, arm64 (or in a `debian:trixie` container):

```sh
apt-get install --no-install-recommends \
  build-essential ca-certificates dpkg-dev git gettext \
  meson ninja-build pkg-config patchelf python3 xsltproc \
  libdbus-1-dev libglib2.0-dev libgudev-1.0-dev \
  libmbim-glib-dev libqmi-glib-dev libqrtr-glib-dev \
  libpolkit-gobject-1-dev libsystemd-dev systemd-dev modemmanager
./build.sh
./check-symbols.sh
```

`build.sh` fetches the ModemManager release pinned in `versions.env`, applies
`patches/`, builds only the Huawei plugin and packages
`dist/modemmanager-e3372_<version>_arm64.deb` with:

```
etc/usb_modeswitch.d/3566:2001
usr/lib/aarch64-linux-gnu/ModemManager/libmm-plugin-huawei.so   (diverts Debian's)
usr/lib/udev/rules.d/40-e3372-usb_modeswitch.rules
usr/lib/udev/rules.d/70-e3372-option.rules
usr/lib/udev/rules.d/77-mm-huawei-net-port-types.rules           (diverts Debian's)
usr/share/doc/modemmanager-e3372/{README.md,E3372-325.md,copyright,changelog.Debian.gz}
```

It refuses to run if `build/` exists; remove it for a fresh build.

`check-symbols.sh` verifies that every ModemManager symbol the plugin imports is
exported by the installed `modemmanager`/`libmm-glib0`, and that the module
exports what ModemManager's loader requires. CI runs it on every build,
test-installs the package on Debian trixie with the Raspberry Pi OS archive
(`archive.raspberrypi.com`) enabled, i.e. the package set of Raspberry Pi OS
trixie, and checks that installing and removing it sets up and removes the
diversions.

### When Debian updates ModemManager

1. Update `MM_TAG`, `MM_COMMIT` and `MM_DEBIAN_VERSION` in `versions.env`.
   Check `debian/patches` of the new Debian version for changes to the Huawei
   plugin or outside `src/plugins/`: the package replaces Debian's Huawei
   plugin, so a Debian fix there would otherwise be lost.
2. Rebase `patches/` if needed (`git am` onto the new tag, then
   `git format-patch -N --zero-commit --no-signature <tag>..HEAD`).
3. Build, test on hardware, and release (see below).

### Versioning

Releases are tagged `<ModemManager version>-<revision>`, like Debian package
revisions. The tag is also the package version:

```
1.24.0-1   first release for ModemManager 1.24.0
1.24.0-2   our own changes (fixes, new devices, ...) or a Debian-only update
           of ModemManager 1.24.0 (e.g. +deb13u2), still for 1.24.0
1.26.0-1   rebuilt for ModemManager 1.26.0, revision starts again at 1
```

The exact Debian ModemManager version is in `versions.env` and in the package's
`Depends`. Tags have no `v` prefix.
