# CLAUDE.md — operating guide for the next AI‑coder session

> This file orients an AI coding agent picking up this project. Read it fully before acting.
> Then read [plan.md](plan.md). Reference docs live in [docs/](docs/).

## What this project is

A **macOS port** of the Windows tool [IPA_Downloader](https://github.com/kda2495/IPA_Downloader):
download App Store apps with an Apple ID and **install them onto a connected iPhone/iPad over USB**.
It is a thin wrapper around two binaries — `ipatool` (download) and `ideviceinstaller` (install).
The end goal is **install‑to‑device**, not just downloading.

## Current state snapshot (2026‑06‑15)

**Done**
- Reverse‑engineered the original: PowerShell menu + two bundled binaries.
  - `ipatool.exe` = **[Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool)** (C++ "ipatool‑cpp")
  - `ideviceinstaller.exe` = **libimobiledevice**
  - Install is literally `ideviceinstaller install <file>.ipa` (`IPA_Downloader.ps1:981`)
- Toolchain installed & verified (Apple Silicon, `/opt/homebrew`, Darwin 25.5 / macOS Tahoe).
- **ipatool‑cpp built** → `bin/ipatool` (4.8 MB arm64; static OpenSSL, `-Dexplicit_bzero=bzero`).
  `bin/ideviceinstaller` symlinks Homebrew's 1.2.0. Smoke tests pass.
- **Full Python TUI implemented** in `ipa_install/` (stdlib only): `config.py i18n.py ipatool.py
  device.py library.py tui.py __main__.py`. All 15 menu items + sub‑flows ported faithfully.
  JSON shapes pinned from `ipatool-cpp/main.cpp` (see [docs/ipatool-cpp-reference.md](docs/ipatool-cpp-reference.md)).
- **Verified offline** with `tests/run_checks.py` (53 checks vs a fake backend, all green) and
  `python3 -m py_compile`. `python3 -m ipa_install` launches and gates on login.
- **SwiftUI GUI at full 15‑item parity** in `gui/` (SwiftPM, no Xcode): `Localization.swift` (RU/EN,
  mirrors `i18n.py`), `Backend.swift` (mirrors `ipatool.py`/`device.py`/`library.py`), `AppState.swift`,
  `Views.swift` (Account/Store/Lists/Device tabs + top bar: language/clear‑data/GitHub), `SelfTest.swift`.
  `swift build` clean; `--selftest` 18 checks green; `build_app.sh` → `IpaInstall.app`.
- **Ownership scan (macOS extra)**: `ipa_install/scan.py`, two-phase + account-frugal — (1) free
  iTunes Lookup API filters the catalog to apps **removed from the store**; (2) probe ownership only on
  those (`download` minus `--purchase`: not-owned fails fast, owned starts transferring → aborted). Result
  `{removedOwned, removedNotOwned}` → `Lists/Owned_scan.json`. Surfaced as TUI menu **16** and the GUI
  Lists tab **Scan my apps** (sources "Мои — удалены из App Store" / "Удалены — не куплены").
- Reference repos: `/Users/dmitriy/code/archive/IPA_Downloader` (orig `446a038`), `/Users/dmitriy/code/archive/ipatool-cpp` (`74f4247`).

**Not done yet**
- **Phase 1: real‑hardware install is NOT yet validated.** Needs a physical iPhone/iPad + an
  interactive Apple ID login (2FA) — neither can be automated. This is the one remaining unknown.

## How to continue

1. **Phase 1 validation only.** Run `python3 -m ipa_install`, log in with a disposable Apple ID,
   download a free app (menu 2), then install to a connected device (menu 11). Decisive question +
   checklist: [docs/risks-and-validation.md](docs/risks-and-validation.md) — record results there.
2. The SwiftUI GUI (Phase 4) is **done and at full 15‑item parity** — `cd gui && ./build_app.sh`,
   then `open IpaInstall.app` (or `.build/release/IpaInstallGUI --selftest` for headless checks). Once
   Phase 1 is validated on hardware, the project is functionally complete.

Architecture & module contracts: [docs/architecture.md](docs/architecture.md) and
[docs/impl-spec.md](docs/impl-spec.md). Keep [plan.md](plan.md) checkboxes current.

## Conventions

- **Language:** Python 3, **stdlib only** (no pip). Entry point `python3 -m ipa_install`.
- **Backends are subprocesses.** Always call `ipatool` with `--format json` and parse JSON — never
  scrape human text. Confirm exact JSON keys at runtime with `--debug` / by inspecting output.
- **Paths (mirror the original):**
  - `~/.ipatool/` — ipatool session (`account`, `cookies`). Managed by ipatool itself.
  - `Apps/` (project‑relative) — downloaded `.ipa` files.
  - `Lists/` — saved app‑ID lists as JSON (`Purchased_IDs.json`, `Downloaded_IDs.json`).
- **Binaries:** prefer a project‑local `bin/` (`bin/ipatool`, `bin/ideviceinstaller` symlink or copy),
  fall back to `PATH`. Resolve once in `config.py`.
- **Localization:** RU + EN, default RU (the original defaults to `RU`). Labels are in
  [docs/original-tool-analysis.md](docs/original-tool-analysis.md).

## Guardrails (important)

- **Apple ID safety:** Apple may flag/lock accounts used with these tools. Use a **disposable/test
  Apple ID** for development. **Never** hardcode, log, or commit Apple ID credentials, the
  `--keychain-passphrase`, `~/.ipatool/*`, cookies, or any `.ipa`/`iTunesMetadata.plist`.
- **Do not commit secrets or large/binary artifacts.** Add `.gitignore` for `bin/`, `Apps/`,
  `Lists/`, `~/.ipatool` is outside the tree anyway. `.ipa` files and account data must never be committed.
- **Legal:** only operate on apps the signed‑in account is licensed for. This is not a piracy tool.
- **Don't re‑sign or strip DRM.** ipatool already produces an install‑ready, account‑licensed IPA.
- **Verify before asserting.** Treat JSON shapes / iOS install behavior as "confirm at runtime"
  until you've actually run it. Mark assumptions clearly.

## Command cheat sheet

```sh
# Download engine (ipatool-cpp) — always add --format json for machine parsing
ipatool --format json auth login -e EMAIL -p PASSWORD   # 2FA prompted if no --auth-code
ipatool --format json auth info
ipatool auth revoke
ipatool --format json search "TERM" -l 20
ipatool --format json purchase -i APP_ID
ipatool --format json download -i APP_ID --purchase -o Apps/
ipatool --format json list-versions -i APP_ID
ipatool --format json get-version-metadata -i APP_ID --external-version-id VID

# Device side (libimobiledevice)
idevice_id -l                 # list connected device UDIDs
ideviceinfo                   # device details (needs pairing/trust)
idevicepair pair              # pair (unlock device, tap "Trust")
ideviceinstaller list         # apps on device
ideviceinstaller install Apps/<file>.ipa
```

## Where things live

| Path | What |
|---|---|
| `/Users/dmitriy/code/ipa_install_claude/` | this project |
| `/Users/dmitriy/code/archive/IPA_Downloader/` | the Windows original (reference) |
| `/Users/dmitriy/code/archive/ipatool-cpp/` | download‑engine source (build from here) |
| `~/.ipatool/` | ipatool session/credentials (do not commit) |

If a referenced repo is missing in a fresh environment, re‑clone:
`git clone https://github.com/kda2495/IPA_Downloader` and
`git clone https://github.com/Sorvigolova/ipatool` (pin to the commits above for reproducibility).
