# Project Plan — ipa_install (macOS port of IPA_Downloader)

**Last updated:** 2026‑06‑15
**Current phase:** Phase 0 (toolchain) ✅ · Phase 2 (TUI) ✅ · Phase 3 (parity) ✅ · Phase 4 (SwiftUI GUI) ✅ ·
**only remaining → Phase 1 (real‑device install validation, needs hardware + interactive login)**
**Owner decisions captured:** TUI first then GUI · download engine = ipatool‑cpp · TUI in Python 3 · GUI in SwiftUI (SwiftPM, no Xcode)

---

## 1. Goal

Re‑create the **full** functionality of the Windows tool
[IPA_Downloader](https://github.com/kda2495/IPA_Downloader) on **macOS**, with the end goal being
**installation of downloaded App Store apps onto a connected iOS device** (not merely downloading
the `.ipa`).

A user should be able to:
1. Log in with an Apple ID.
2. Search / pick apps (or paste app IDs, or use a saved list).
3. Download the `.ipa` (latest or a chosen older version).
4. **Install it onto a connected iPhone/iPad over USB.**

### Non‑goals
- No piracy: only apps the signed‑in Apple ID is licensed for (same constraint as the original).
- No jailbreak, no re‑signing with developer certs, no IPA patching beyond what ipatool already does.
- GUI is **deferred** (Phase 4). First deliverable is a terminal UI.

---

## 2. Key decisions (with rationale)

| # | Decision | Rationale |
|---|---|---|
| D1 | **Phased: working TUI first, SwiftUI GUI later** | Validates the risky device‑install path fastest; mirrors the original's UX; minimal code to a usable tool. (User choice.) |
| D2 | **Download engine = [Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool) (ipatool‑cpp), built from source** | It is the *exact* engine the original bundles, proven to work end‑to‑end with `ideviceinstaller`. Has `get-version-metadata` (version preview for downgrades) which majd's Go `ipatool` lacks. Fallback: `brew install ipatool` (Go) if the C++ build ever breaks — accepting the loss of `get-version-metadata`. |
| D3 | **Device install = `ideviceinstaller` (libimobiledevice), from Homebrew** | Same tool the original bundles; native on macOS; talks to the built‑in `usbmuxd`. No iTunes driver needed. |
| D4 | **TUI in Python 3, stdlib only** | macOS has `python3` (3.14 via Homebrew here). Clean JSON parsing of `ipatool --format json`, easy menu/range parsing, logic reusable by a later GUI. Zero pip deps. |
| D5 | **Parse `ipatool --format json`, never scrape text** | ipatool‑cpp supports `--format json` globally → robust, locale‑independent parsing. |

---

## 3. Architecture (summary)

```
ipa_install (Python TUI)
   ├─► ipatool  (ipatool-cpp)        auth · search · purchase · download · list-versions · get-version-metadata
   │      └─► Apple App Store API     → writes a fully-formed .ipa (iTunesMetadata + Sinf license) to Apps/
   └─► ideviceinstaller (libimobiledevice)   install <ipa>
          └─► usbmuxd (built into macOS) → iPhone/iPad installation_proxy
```

Full detail: **[docs/architecture.md](docs/architecture.md)**.

---

## 4. Roadmap

Legend: `[x]` done · `[~]` in progress · `[ ]` todo

### Phase 0 — Toolchain & backends  ✅ done
- [x] Identify original tool, its two bundled binaries, and the exact install command (`ideviceinstaller install`)
- [x] Install Homebrew deps: `ideviceinstaller` 1.2.0, `cmake` 4.3.3, `nlohmann-json` 3.12.0, `minizip` 1.3.2_1, `openssl@3`
- [x] Confirm `python3` (3.14.4) and `git` present
- [x] Clone `Sorvigolova/ipatool` → `/Users/dmitriy/code/ipatool-cpp` (commit `74f4247`)
- [x] **Build ipatool‑cpp → `bin/ipatool`** (4.8 MB arm64 binary; static OpenSSL, `-Dexplicit_bzero=bzero`)
- [x] Smoke test: `ipatool --help` OK · `ideviceinstaller --version` → 1.2.0 · `auth info` → "Not logged in" (expected)

### Phase 1 — Backend validation  ⛳ **critical de‑risk, do this before writing the TUI**
- [ ] `ipatool auth login` with a **disposable/test** Apple ID (see guardrails in CLAUDE.md)
- [ ] `ipatool search`, then `ipatool download --purchase` a small **free** app → obtain a `.ipa`
- [ ] Pair an iPhone over USB: `idevicepair pair` (unlock + "Trust" on device; Developer Mode if iOS 16+)
- [ ] **`ideviceinstaller install <app>.ipa` → confirm the app installs AND launches**
- [ ] Record the exact behavior/errors in [docs/risks-and-validation.md](docs/risks-and-validation.md)

> If Phase 1 passes, the project is fundamentally sound and the rest is UX.
> If `ideviceinstaller install` rejects FairPlay App Store IPAs on current iOS, escalate — see the
> risk doc for fallbacks before building more.

### Phase 2 — Python TUI (MVP)  ✅ done
- [x] Package skeleton `ipa_install/` (layout in architecture.md); entry `python3 -m ipa_install`
- [x] `config.py` — paths (`~/.ipatool`, `Apps/`, `Lists/`), language (RU/EN), locate binaries (`bin/` or PATH)
- [x] `ipatool.py` — typed wrapper over ipatool‑cpp using `--format json` (shapes pinned from `main.cpp`)
- [x] `device.py` — wrapper over `idevice_id`/`idevicepair`/`ideviceinstaller` (list devices, pair, install)
- [x] `i18n.py` — RU/EN strings (80 keys each, full parity; ported from the original + macOS additions)
- [x] `tui.py` — menu loop + number/range selection parser (`"1-3,5"`)
- [x] Wire up the **download → install** happy path end‑to‑end
- [x] `library.py` — finalize downloads in `Apps/`, read `MinimumOSVersion` via `plistlib`, persist ID lists as JSON

### Phase 3 — Parity polish (match the original's 15‑item menu)  ✅ done
- [x] Version‑selection flow (`list-versions` + `get-version-metadata` table)
- [x] App‑name lookup from the `Apps_ID_List.txt` map (bundled at `assets/Apps_ID_List.txt`, offline)
- [x] Saved lists: `Lists/Purchased_IDs.json`, `Lists/Downloaded_IDs.json` (original‑compatible `{name,appid}`)
- [x] iOS min‑version check for apps in `Apps/`
- [x] Clear‑data menu, language switch, full RU/EN
- [x] Robust errors (no device / not paired / network / not licensed)
- [x] Offline verification harness `tests/run_checks.py` (53 checks, fake backend) — all green

### Phase 4 — SwiftUI GUI  ✅ done — **full 15‑item parity** (build verified; on‑device install still Phase 1)
- [x] Native `.app` shelling out to the same `bin/` binaries (Swift backend mirrors `ipatool.py`/`device.py`/`library.py`; `Localization.swift` mirrors `i18n.py`)
- [x] Four tabs + top bar covering **all 15 original menu items**:
  - **Account** — login/2FA/logout (13)
  - **Store** — search (multi‑select) → purchase (1)/download‑latest (2)/download‑version (3); by‑ID → download (5)/purchase (4)/version (6)
  - **Lists** — browse offline catalog / saved Purchased+Downloaded / not‑in‑list → purchase (7)/download‑latest (8)/download‑version (9)
  - **Device** — picker + **Pair**, `Apps/` library + min‑iOS (10), multi‑select install (11)
  - **Top bar** — RU/EN language switch (15, persisted to `Lang_Config.txt`), clear‑data menu (12), GitHub link (14)
- [x] **RU/EN localization** (default RU) live‑switching; string table ported from `i18n.py` + GUI keys
- [x] Multi‑select (range‑equivalent) on results, version sheet, lists, and install; sequential batch runner
- [x] Builds **without Xcode** via SwiftPM (`gui/build_app.sh` → `IpaInstall.app`, ad‑hoc signed); `--selftest` headless backend checks pass (16 checks)
- [x] GUI‑specific handling documented: argv login (no TTY for hidden prompts) + `--format json` download capture
- [ ] Packaging / notarization for distribution outside this machine (Developer ID) — deferred, not needed for local use

### Phase 5 — macOS-only extra: **Ownership scan**  ✅ done
The bundled catalog is just IDs; it doesn't know which apps *your* Apple ID owns. The scan closes that
gap, and only for what matters: apps **removed from the store** that you can still recover.
- [x] `ipa_install/scan.py` — **two-phase, account-frugal**:
  1. **Filter (free, no account risk):** the public **iTunes Lookup API** tells which catalog apps are
     **removed** from the store (~270 of 462 for RU). In-store apps are skipped — you can install those normally.
  2. **Probe ownership ONLY on the removed subset:** `download` **without** `--purchase` (not owned → fast
     fail; owned → transfer starts, aborted early in a temp dir, `Apps/` untouched). ~42% fewer requests
     against the Apple ID than probing the whole catalog.
  Result → `Lists/Owned_scan.json` (`{removedOwned, removedNotOwned}`, shared by GUI + TUI).
- [x] **TUI**: menu item **16** "Найти мои приложения (скан владения)" with a personal-account warning + progress.
- [x] **GUI**: Lists tab gets a **Scan my apps** button (warning alert → filter → probe progress/cancel) and two
  new sources — **"Мои — удалены из App Store"** (recoverable) / **"Удалены из стора — не куплены"**; result persists.
- [x] `tools/scan_owned.py` — thin CLI over `ipa_install.scan` (`--limit`/`--ids` for spot checks).
- ⚠️ Guardrail: a probe is a real (aborted) download request; the removed subset is still hundreds of
  requests — gate behind explicit consent, keep the delay, prefer a disposable Apple ID.

---

## 5. Milestones / Definition of Done

- **M1 (proof):** one free app downloaded via ipatool‑cpp and installed onto a real iPhone via ideviceinstaller, from the command line. *(Phase 1)*
- **M2 (MVP):** `python3 -m ipa_install` → log in, search, download, install — all from the menu. *(Phase 2)*
- **M3 (parity):** all 15 original menu functions work on macOS. *(Phase 3)*
- **M4 (GUI):** SwiftUI app delivering the same flows. *(Phase 4)*

---

## 6. Immediate next steps (for the next session)

Engine + TUI + parity are done and verified offline. The **only** remaining work is the
real‑hardware experiment that can't be automated:

1. `python3 -m ipa_install` → log in with a **disposable/test** Apple ID (ipatool prompts password + 2FA).
2. Menu **2** (or **5**): search/enter‑ID → download a small **free** app → confirms a `.ipa` lands in `Apps/`.
3. Connect an iPhone over USB, unlock, tap **Trust** (enable Developer Mode on iOS 16+).
4. Menu **11** → install the app → **does `ideviceinstaller install` accept the FairPlay IPA and does the app launch?**
5. Record the outcome in [docs/risks-and-validation.md](docs/risks-and-validation.md).

## 7. Open questions
Tracked in **[docs/risks-and-validation.md](docs/risks-and-validation.md)**. The decisive one:
*does `ideviceinstaller install` accept a FairPlay‑DRM App Store IPA on current iOS, for a device
signed into the same Apple ID?*
