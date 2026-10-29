# Lid Awake

A minimal, native macOS app with one button to keep work running while the lid is closed.

[中文](README.md) · [Downloads](https://github.com/MoFanMon/lid-awake/releases) · [Architecture](docs/ARCHITECTURE.md)

<img src="docs/images/app.png" width="330" alt="Lid Awake's single power button">

## Preview status

This is the **2.0 open-source preview**. Automated logic tests and local builds have been checked. Administrator installation, reboot recovery, Intel hardware and physical lid closure still need testing on real machines.

Downloads are ad-hoc signed and **not Developer ID signed or notarized by Apple**. macOS may block them. Review the source or build it yourself, and only run software whose origin you trust. See [Apple's guidance](https://support.apple.com/102445).

## Use

Requires macOS 13 or later. Universal builds include Apple silicon and Intel.

1. Quit older versions and install the `.pkg` from [Releases](https://github.com/MoFanMon/lid-awake/releases).
2. Authorize the system helper once during installation.
3. Open **合盖不眠** from Applications and click its power button.
4. Click again, close the window or quit to restore the previous sleep setting.

You can also drag the app from the DMG to Applications. Its first launch installs the same helper with administrator authorization. Normal use does not store or repeatedly request an administrator password. Updates, reinstalls, removal or system permission revocation may require authorization again.

The built-in display still turns off when the lid closes. While active, the app prevents system sleep, including manual and idle sleep. Keep the Mac ventilated and monitor battery charge.

## Build

Requires Apple Command Line Tools or Xcode. No third-party dependencies.

```sh
git clone https://github.com/MoFanMon/lid-awake.git
cd lid-awake
./test.sh
./build.sh
./package.sh
```

Artifacts are written to `dist/`. Building and testing do not install the helper or change system sleep settings. CI skips the read-only comparison against the host's saved power preferences; local tests include it by default.

## Privileged helper

The GUI runs as the normal user. A root `launchd` helper accepts only fixed enable, disable and status requests over a local Unix socket. It checks the peer's kernel audit token, pinned code signature hashes and console user. The original setting is durably recorded before mutation and restored when the app exits or the helper restarts.

Only `SleepDisabled` is changed. Existing values set by other software are preserved. The implementation uses macOS's `pmset` command and verifies the effective state through IOKit.

## Remove

Turn the switch off, choose **卸载系统辅助服务…** from the app menu, then move the app to Trash. Removing the helper requires administrator authorization.

To manually allow system sleep again:

```sh
sudo pmset -a disablesleep 0
```

This explicitly enables sleep rather than preserving a pre-existing disabled setting.

## Contribute

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Copyright © 2026 MoFanMon.
