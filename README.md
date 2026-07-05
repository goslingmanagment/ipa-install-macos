# IPA Install for macOS

[Русская версия](README_RU.md)

A native macOS app that **downloads your purchased App Store apps as .ipa files** and
**installs them onto an iPhone/iPad over USB**. A port of the Windows tool
[IPA_Downloader](https://github.com/kda2495/IPA_Downloader) — no iTunes, no VMs:
macOS ships `usbmuxd` out of the box.

Why: grab an older version of an app, install an app that was pulled from the App Store
(but that your Apple ID owns), or keep a local .ipa archive of your purchases.

## Features

- **Search & download** App Store apps under your Apple ID (2FA login supported)
- **Older versions**: list an app's version history and download any of them
- **Install to device** over USB in one click (`ideviceinstaller`)
- **Batch operations**: by ID list, saved lists, ranges (`1,3-5`)
- **Ownership scan** (unique to this port): finds your purchased apps that have been
  removed from the App Store and shows which are still downloadable
- **Two interfaces**: the `IpaInstall.app` GUI and a 15-item terminal menu
- **Russian and English** UI, switchable live
- Bundled offline catalog of 450+ popular apps

## Install

### Option 1: prebuilt app (recommended)

1. Download `IpaInstall.app.zip` from [Releases](../../releases) and unzip.
2. Clear quarantine (the app is ad-hoc signed, not notarized):
   ```sh
   xattr -cr ~/Downloads/IpaInstall.app
   ```
3. For device installs, install libimobiledevice:
   ```sh
   brew install ideviceinstaller
   ```
4. Launch. The download engine is bundled inside the app; data lives in
   `~/Library/Application Support/IpaInstall`, downloaded .ipa files in `~/Downloads/IPA`.

Requirements: macOS 13+, Apple Silicon (build from source for Intel).

### Option 2: from source

```sh
git clone https://github.com/goslingmanagment/ipa-install-macos
cd ipa-install-macos

# download engine (one command, see docs/toolchain-macos.md):
#   build ipatool from github.com/Sorvigolova/ipatool → bin/ipatool
brew install ideviceinstaller && ln -sf "$(command -v ideviceinstaller)" bin/ideviceinstaller

# terminal version (Python 3, stdlib only):
python3 -m ipa_install

# or the GUI:
cd gui && ./build_app.sh && open IpaInstall.app
```

## Installing onto an iPhone/iPad

1. Connect the device over USB, unlock it, tap **Trust**.
2. On iOS 16+, enable **Settings → Privacy & Security → Developer Mode** if prompted.
3. GUI: **Device** tab → pick the .ipa → Install. Terminal: menu item **11**.

The device must be signed into the same Apple ID that purchased the app —
the .ipa carries your account's FairPlay license.

## Security & privacy

- Your Apple ID password and 2FA code are **never stored or logged** by this app: in the
  terminal, `ipatool` itself prompts for them (hidden input); in the GUI they are fed to
  the engine through a pseudo-terminal — never via command-line arguments.
- The session lives in `~/.ipatool/` (encrypted by ipatool, machine-bound).
- Consider using a secondary Apple ID: Apple may flag accounts that use
  third-party App Store clients.

## Legality

This tool only works with **apps licensed to your Apple ID** — your own digital purchases.
It does not strip DRM, does not re-sign .ipa files, and gives no access to apps you don't
own. It is not a piracy tool.

## How it works

```
IpaInstall.app / python3 -m ipa_install
        ├── ipatool (C++, github.com/Sorvigolova/ipatool) — App Store protocol: login,
        │            search, purchase, .ipa download with your account's FairPlay license
        └── ideviceinstaller (libimobiledevice) → usbmuxd (built into macOS) → iPhone/iPad
```

For developers: docs map in [docs/](docs/), architecture in
[docs/architecture.md](docs/architecture.md), AI-session guide in [CLAUDE.md](CLAUDE.md).
Offline tests: `python3 tests/run_checks.py` (no network, Apple ID, or device needed);
GUI self-test: `gui/IpaInstall.app/Contents/MacOS/IpaInstall --selftest`.

## Credits

- [kda2495/IPA_Downloader](https://github.com/kda2495/IPA_Downloader) — the original
  Windows tool whose menu UX this port follows
- [Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool) — the download engine
  (pinned at commit `74f4247`)
- [libimobiledevice](https://libimobiledevice.org) — device communication

## License

[MIT](LICENSE)
