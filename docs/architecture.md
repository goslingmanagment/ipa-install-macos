# Architecture

## Overview

`ipa_install` is a **Python 3 terminal UI** that orchestrates two command‑line backends. It holds no
App Store or device protocol logic of its own — that lives entirely in the two binaries. Our job is
auth flow, menu UX, file/library management, and gluing download → install.

```
┌─────────────────────────────────────────────────────────────┐
│  ipa_install  (Python 3 TUI, stdlib only)                     │  ← we build this
│  menu loop · input parsing · i18n (RU/EN) · Apps/Lists mgmt    │
└───────────────┬───────────────────────────┬───────────────────┘
                │ subprocess (--format json) │ subprocess
        ┌───────▼─────────────┐      ┌───────▼──────────────────┐
        │ ipatool (ipatool-cpp)│      │ ideviceinstaller         │
        │ auth/search/purchase │      │ (libimobiledevice)       │
        │ download/list-versions│     │ install / list / uninstall│
        └───────┬─────────────┘      └───────┬──────────────────┘
                │ HTTPS (libcurl)             │ usbmuxd (BUILT INTO macOS)
        ┌───────▼─────────────┐      ┌───────▼──────────────────┐
        │ Apple App Store API  │      │ iPhone/iPad over USB      │
        │ (StoreKit endpoints) │      │ installation_proxy / afc  │
        └─────────────────────┘      └──────────────────────────┘
```

Key macOS advantage over the Windows original: **`usbmuxd` is part of macOS**, so no
AppleMobileDeviceSupport / iTunes driver is required.

## Components

### 1. ipatool (ipatool‑cpp) — the download engine
- Source: github.com/Sorvigolova/ipatool (C++, libcurl + OpenSSL + nlohmann/json + minizip).
- Authenticates to the App Store, acquires a license (`purchase`), downloads the encrypted app, and
  **patches the IPA into iTunes format** so it is installable: injects `iTunesMetadata.plist`,
  `iTunesArtwork`, and the **Sinf DRM token** (the per‑Apple‑ID license) into `Payload/<App>.app/SC_Info/`.
- Credentials saved at `~/.ipatool/account` (encrypted, **machine‑bound** via a hardware ID) and a
  cookie jar at `~/.ipatool/cookies`.
- Full CLI surface: [ipatool-cpp-reference.md](ipatool-cpp-reference.md).

### 2. ideviceinstaller — the device installer
- From libimobiledevice (Homebrew). `ideviceinstaller install <ipa>` streams the IPA to the device's
  `installation_proxy` over `usbmuxd`. The device validates the FairPlay license; it must be signed
  into the **same Apple ID** that the IPA was downloaded for.

### 3. usbmuxd — USB multiplexer
- Built into macOS (the same service Finder/Xcode use). No install. Handles device discovery + the
  socket multiplexing libimobiledevice talks over.

## The three pipelines

### A. Authentication
```
ipatool --format json auth login -e EMAIL -p PASSWORD [--auth-code CODE]
```
- 2FA: if `--auth-code` is omitted and the account has 2FA, ipatool prompts interactively. The TUI
  should run this attached to the terminal so the user can type the code (or collect the code and
  pass `--auth-code`).
- Session persists in `~/.ipatool/`. Presence of `~/.ipatool/account` == "logged in" (this is exactly
  how the original gates its main loop). `auth info` shows who; `auth revoke` logs out.

### B. Download
```
ipatool --format json download -i APP_ID [--external-version-id VID] --purchase -o Apps/
```
- `--purchase` acquires the free license first if needed (paid apps must already be owned).
- Output filename: `{bundleID}_{appID}_{version}.ipa`. `-o` may be a dir or file.
- Resumable: leftover `*.ipa.tmp` on interruption; the original deletes stray `*.ipa.tmp` on startup —
  replicate that cleanup.
- Result: a ready‑to‑install `.ipa` in `Apps/`.

### C. Install to device
```
idevice_id -l                       # discover device(s)
idevicepair pair                    # ensure paired + trusted
ideviceinstaller install Apps/<file>.ipa
```
- This is the project's reason to exist and the **one path to validate on real hardware first**
  (see [risks-and-validation.md](risks-and-validation.md)).

## On‑disk state

| Path | Owner | Notes |
|---|---|---|
| `~/.ipatool/account` | ipatool | encrypted, machine‑bound credentials — **never commit** |
| `~/.ipatool/cookies` | ipatool | libcurl cookie jar |
| `Apps/` | us | downloaded `.ipa` files |
| `Lists/Purchased_IDs.json`, `Lists/Downloaded_IDs.json` | us | saved app‑ID lists |
| `bin/ipatool`, `bin/ideviceinstaller` | us | resolved binaries (or use PATH) |
| `assets/Apps_ID_List.txt` | us (optional) | app‑ID → name map copied from the original |

## Machine binding / hardware ID (important nuance)

ipatool‑cpp computes a hardware ID — on macOS `SHA256(IOPlatformSerialNumber + IOPlatformUUID)` via
IOKit (built in). This identifies **the Mac** as a "computer" to the Apple ID (analogous to iTunes
authorization). Implication: the download is tied to the Mac's identity and the account's machine
slots, independent of which iPhone you later install onto. Re‑using the same Mac avoids burning extra
authorization slots.

## Localization

RU + EN, default RU. The original stores the choice in a one‑line `Lang_Config.txt` (`RU`/`EN`).
Port the string tables from [original-tool-analysis.md](original-tool-analysis.md) into `i18n.py`.

## Output parsing strategy

Always pass `--format json` to ipatool and `json.loads` the output. Do **not** parse human text
(locale‑ and version‑fragile). Exact JSON keys are not assumed in these docs — confirm at runtime
(`--debug` prints raw server responses; inspect a real `search`/`download` JSON once and pin the
shapes in `ipatool.py`).

## Proposed Python layout (Phase 2)

```
ipa-install-macos/
├── ipa_install/
│   ├── __init__.py
│   ├── __main__.py        # python3 -m ipa_install  → tui.main()
│   ├── config.py          # paths, language, binary resolution
│   ├── ipatool.py         # wrapper: auth/search/purchase/download/list_versions/get_version_metadata
│   ├── device.py          # wrapper: list_devices/pair_status/install
│   ├── library.py         # Apps/ + Lists/ mgmt, read MinimumOSVersion, name lookup
│   ├── i18n.py            # RU/EN string tables
│   └── tui.py             # menu loop + selection parsing
├── bin/                   # ipatool, ideviceinstaller (gitignored)
├── assets/Apps_ID_List.txt
├── Apps/                  # downloads (gitignored)
└── Lists/                 # saved lists (gitignored)
```

`ipatool.py` and `device.py` are the stable contract a future SwiftUI GUI (Phase 4) can reuse or mirror.
