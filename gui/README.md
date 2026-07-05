# IPA Install — SwiftUI GUI (Phase 4)

A native macOS app (SwiftUI) that delivers the same flows as the Python TUI through a window:
sign in, search/download App Store apps, and **install them onto a connected iPhone/iPad over USB**.
It is a thin front‑end over the *same* `bin/ipatool` and `bin/ideviceinstaller` binaries — all App
Store / device logic lives in those tools, mirrored in `Sources/IpaInstallGUI/Backend.swift`
(the Swift counterpart of `ipa_install/ipatool.py` · `device.py` · `library.py`) with
`Localization.swift` mirroring `ipa_install/i18n.py` (the RU/EN string tables).

> Built without Xcode — just the Swift toolchain from the Command Line Tools (`swiftc`, `swift build`).

## Build & run

```sh
cd gui
./build_app.sh            # → gui/IpaInstall.app  (swift build + bundle + ad-hoc sign)
open IpaInstall.app

# or, for development, run the SwiftPM binary directly:
swift build -c release
.build/release/IpaInstallGUI            # launches the GUI
.build/release/IpaInstallGUI --selftest # headless backend checks, no GUI/login needed
```

The app locates the project's `bin/`, `Apps/`, `Lists/`, and `assets/` by walking up from its own
location; if you move `IpaInstall.app` elsewhere, point it at the repo with
`IPA_INSTALL_ROOT=/path/to/ipa-install-macos`.

## Full parity with the original 15‑item menu

The GUI now covers every action of the original PowerShell tool, organized into a top bar + four tabs.
Numbers in parentheses map to the original menu items.

**Top bar** — a **RU / EN** language switch (15; persisted to `Lang_Config.txt`, shared with the TUI,
default RU), a **Data** menu to clear the downloaded list / purchased list / the `Apps/` folder (12),
and a **GitHub** button that opens the project page (14).

- **Account** (Аккаунт) — sign in with email + password (+ a 2‑factor field that appears when Apple
  asks); shows the signed‑in account; log out (13).
- **Store** (Магазин) — search the App Store, **multi‑select** results, then **Purchase** (1),
  **Download latest** (2), or **Download version…** (3); or act on one or more numeric app IDs:
  **Download by ID** (5), **Purchase by ID** (4), **Download version…** (6). The version sheet lists
  historical versions (display version + date) and supports selecting several at once.
- **Lists** (Списки) — browse the offline catalog, the saved Purchased/Downloaded lists, or the
  "not yet downloaded / purchased" subsets, multi‑select, then **Purchase** (7),
  **Download latest** (8), or **Download version…** (9). Also hosts **Scan my apps** (macOS extra),
  which finds the apps *this* Apple ID can **recover**. It is account‑frugal: first the free public
  iTunes API filters the catalog to apps **removed from the store** (in‑store apps are skipped — you can
  install those normally), then an aborted `download` probe runs **only** on the removed subset (gentle,
  with pauses, behind a personal‑account warning). Two result sources: **"Mine — removed from App Store"**
  (owned + removed → recoverable only via this tool) and **"Removed from store — not owned"**. Cached to
  `Lists/Owned_scan.json` (shared with the TUI's menu 16).
- **Device** (Устройство) — pick a connected device, **Pair** it (taps "Trust" on device), see the
  `Apps/` library with each IPA's minimum iOS (10), multi‑select and **Install to device** (11,
  runs `ideviceinstaller install`).

Downloads land in `Apps/` and are recorded to `Lists/Downloaded_IDs.json`; purchases to
`Lists/Purchased_IDs.json` (blank/`Unknown` names are not recorded, matching the original). All
strings are RU/EN and switch live.

## GUI vs. the terminal version (intentional differences)

A GUI has no controlling terminal, so two flows differ from `ipa_install` (the TUI):

- **Login** passes `-e/-p` (and `--auth-code` on the retry) to ipatool on the command line, because
  ipatool refuses its hidden‑password / 2FA prompts when stdin is not a TTY. The password is
  therefore briefly visible to other local processes via `ps`; the app never stores or logs it.
  *(The TUI avoids this by letting ipatool prompt on the terminal.)* Use a **disposable/test Apple ID**.
- **Download** runs with `--format json` and reads the saved path from the JSON `output` key — there
  is no live progress bar without a TTY (the UI shows a spinner instead).

## Notes

- Requires the same backends as the TUI: `bin/ipatool` (built) and `bin/ideviceinstaller`.
- `swift build` artifacts (`.build/`) and the assembled `IpaInstall.app` are git‑ignored.
- Real‑device install is the one path that still needs validation on hardware — see
  [../docs/risks-and-validation.md](../docs/risks-and-validation.md).
