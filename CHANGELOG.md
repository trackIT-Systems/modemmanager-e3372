# Changelog

## [Unreleased]

- Huawei E3372h-153 (HiLink firmware) tested and documented
  (`docs/E3372h-153.md`): the existing `12d1:1f01` configuration switches it
  to modem mode, data goes over NCM (`wwan0`) like on the E3372h-320.

## [1.24.0-2] - 2026-10-08

- Support the Huawei E3372h-320 in modem mode: a usb_modeswitch configuration
  for `12d1:1f01` sends the HuaweiAlt message instead of usb-modeswitch-data's
  HuaweiNew message, so the stick comes up as `12d1:155e` (AT ports and NCM)
  instead of in HiLink mode. The kernel and ModemManager's Huawei plugin
  already support it; data goes over NCM (`wwan0`). This applies to all Huawei
  sticks that start as `12d1:1f01`.
- Huawei plugin: before dialing with `^NDISDUP`, disconnect a connection
  that is still active in the modem (patch 0004). After ModemManager was
  killed while connected, the E3372h-320 previously failed every dial attempt
  until it was power cycled.
- Ship all documents in `docs/` with the package.

## [1.24.0-1] - 2026-10-07

First version, for Raspberry Pi OS trixie (arm64) with
`modemmanager 1.24.0-1+deb13u1`.

- Support the ZOWEE (Brovi) E3372-325 (`3566:2001`) in modem mode:
  usb_modeswitch configuration (HuaweiAlt message), udev rule that triggers it,
  and a udev rule that binds the kernel's `option` driver to the AT ports.
- ModemManager's Huawei plugin, built from ModemManager 1.24.0 with three
  patches: accept the E3372-325 with explicit port types (`^GETPORTMODE`
  skipped, NCM port ignored); never dial the firmware's LTE attach context
  (new udev tag `ID_MM_HUAWEI_ATTACH_PROFILE_ID`), on which PPP never gets
  through IPCP; keep `^HCSQ` values reported unsolicited, so extended signal
  values work on the E3372-325.
- Debian package that diverts Debian's Huawei plugin and udev rules, depends
  on the exact `modemmanager`/`libmm-glib0` version and reloads udev and
  ModemManager on install and removal.
- CI builds on Debian trixie with the Raspberry Pi OS archive, checks the
  plugin's symbols against Debian's ModemManager and test-installs and removes
  the package.
