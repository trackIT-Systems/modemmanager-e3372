# Changelog

## [Unreleased]

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
