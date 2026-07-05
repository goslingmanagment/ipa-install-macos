# ipa_install (macOS)

A macOS port of **[IPA_Downloader (IPATool)](https://github.com/kda2495/IPA_Downloader)** — a tool that
downloads previously‑purchased iOS apps from the App Store and **installs them onto a connected
iPhone/iPad over USB**.

The Windows original is a PowerShell menu wrapping two binaries. This project re‑implements that
wrapper natively for macOS, where both binaries are first‑class citizens and the iTunes driver is
unnecessary (macOS has `usbmuxd` built in).

> **Status (2026‑06‑14): MVP implemented.** The download engine is built (`bin/ipatool`), the full
> Python TUI is written (`python3 -m ipa_install`, all 15 menu items), and every non‑device path is
> verified offline against a stubbed backend (`tests/run_checks.py`, 48 checks). The one remaining
> step is **Phase 1 device‑install validation on real hardware** (needs a physical iPhone + an
> interactive Apple ID login — see the checklist in [docs/risks-and-validation.md](docs/risks-and-validation.md)).

---

## The 60‑second mental model

```
ipa_install (Python 3 TUI)  ── calls ──►  ipatool   (download .ipa, signed for your Apple ID)
        │                                  ipatool-cpp = github.com/Sorvigolova/ipatool
        └────────────────── calls ──────►  ideviceinstaller  (push .ipa → device)
                                           libimobiledevice → usbmuxd (built into macOS) → iPhone
```

The whole thing is a convenience wrapper. The hard parts (App Store protocol, FairPlay license
injection, on‑device install) already exist as native macOS tools. We are gluing + replicating the
menu UX.

---

## Documentation map (read in this order)

| Doc | What it covers |
|---|---|
| **[plan.md](plan.md)** | Goal, decisions, phased roadmap with checkboxes, current state, next steps. **Start here.** |
| **[CLAUDE.md](CLAUDE.md)** | Operating guide for the next AI‑coder session: current snapshot, how to continue, guardrails. |
| [docs/architecture.md](docs/architecture.md) | System design: components, the 3 pipelines (auth / download / install), on‑disk state, proposed Python layout. |
| [docs/original-tool-analysis.md](docs/original-tool-analysis.md) | Reverse‑engineering of the Windows original — full menu table + backend command mapping + conventions to stay faithful. |
| [docs/ipatool-cpp-reference.md](docs/ipatool-cpp-reference.md) | CLI surface of the download engine (commands, flags, JSON output, session files, build). |
| [docs/toolchain-macos.md](docs/toolchain-macos.md) | Verified environment + exact build/bootstrap commands. |
| [docs/risks-and-validation.md](docs/risks-and-validation.md) | Risks, open questions, and the device‑install validation checklist (the one true unknown). |

## Quick start

```sh
# 0. (one-time) build the engine + link the installer into bin/  — see docs/toolchain-macos.md
#    bin/ipatool and bin/ideviceinstaller must exist (already done in this checkout).

# 1. launch the menu (Python 3, stdlib only — no pip install needed)
python3 -m ipa_install
```

On first run it asks for your Apple ID email, then hands off to `ipatool` for the (hidden) password
and 2FA prompt. After login you get the 15‑item menu: search/enter‑ID/saved‑list × purchase /
download‑latest / download‑with‑version, plus check‑min‑iOS, **install‑to‑device**, clear‑data,
log‑out, and a RU/EN language toggle (default RU).

**Use a disposable/test Apple ID** for development — Apple may flag accounts used with these tools.

### Install to a device (menu item 11)
1. Connect the iPhone/iPad over USB; unlock it and tap **Trust**.
2. On iOS 16+, enable **Settings → Privacy & Security → Developer Mode** if prompted.
3. Pick the downloaded app(s) from `Apps/`; the tool runs `ideviceinstaller install`.

### Verify offline (no Apple ID, no device)
```sh
python3 tests/run_checks.py     # drives the wrappers + TUI against a fake backend
python3 -m py_compile ipa_install/*.py
```

> **Phase 1 (real‑hardware install) is the one path not yet validated** — it needs a physical device
> and interactive login, which can't be automated. Checklist:
> [docs/risks-and-validation.md](docs/risks-and-validation.md).
