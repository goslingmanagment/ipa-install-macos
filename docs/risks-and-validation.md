# Risks & validation

## The one decisive unknown

**Does `ideviceinstaller install` accept a FairPlay‑DRM App Store IPA on current iOS, for a device
signed into the same Apple ID?**

- Why it matters: the entire project's *raison d'être* is install‑to‑device. Downloading is already
  solved; installing is the part that can fail.
- Why it's *probably* fine: the Windows original does exactly this with the **same**
  `ideviceinstaller` binary and the same on‑device `installation_proxy`; the only Windows‑specific
  dependency (Apple's `usbmuxd` driver) is **built into macOS**. So the path is proven; macOS removes
  a dependency rather than adding one.
- Why we still must test: newer iOS releases have tightened install/trust behavior; FairPlay apps may
  need the device's Apple ID to match and the app license to be provisioned on the device.

**→ This is now the ONLY unvalidated path.** Everything upstream of it is built and verified offline
(see "What's already validated" below); this last step needs a physical device + interactive login.

## What's already validated (offline, 2026‑06‑14)

- `bin/ipatool` builds and runs; `--format json` output keys confirmed from `main.cpp` and pinned in
  `ipa_install/ipatool.py`.
- `ideviceinstaller 1.2.0` present; `idevice_id`/`idevicepair` resolve.
- Full TUI implemented and exercised by `tests/run_checks.py` against a **fake** ipatool/ideviceinstaller
  (48 checks, all green): search→download (dir‑diff finds the file), `purchase` leading‑line JSON scan,
  list‑versions + get‑version‑metadata table, friendly‑rename + `MinimumOSVersion` via `plistlib`,
  saved‑list round‑trip (original‑compatible `{name,appid}`), name lookup, clear‑data, language toggle,
  and the no‑device install warning. `python3 -m ipa_install` launches and gates on login as designed.
- Not yet exercised against the **real** App Store / a **real** device — that's Phase 1 below.

## Phase 1 validation checklist

Prereqs: this checkout (has `bin/ipatool` + `bin/ideviceinstaller`), an iPhone/iPad + USB cable, a
**disposable/test Apple ID**. You can do it all through the TUI, or run the raw commands below.

**Via the TUI (preferred):**
1. [ ] `python3 -m ipa_install` → enter test Apple ID email → ipatool prompts password + 2FA
2. [ ] Menu **2** → search a small **free** app (e.g. "vlc") → select it → confirms a `.ipa` in `Apps/`
3. [ ] Connect the iPhone; unlock; tap **Trust**; if iOS ≥ 16 enable **Developer Mode**
       (Settings → Privacy & Security → Developer Mode)
4. [ ] Menu **11** → it lists `Apps/` with min‑iOS + reports the connected device → pick the app
5. [ ] Installation runs `ideviceinstaller install` → success?
6. [ ] On the device: the app appears and **launches** (FairPlay license accepted)
7. [ ] Record exact output / any error codes below

**Raw‑command equivalent (for debugging):**
- [ ] `bin/ipatool --format json auth login -e <test-id>` (password + 2FA prompted on the terminal)
- [ ] `bin/ipatool --format json search "vlc" -l 5` → pick a free app id
- [ ] `bin/ipatool download -i <appid> --purchase -o Apps/` → a `.ipa` appears
- [ ] `idevice_id -l` → UDID; `idevicepair validate` → paired
- [ ] `bin/ideviceinstaller install Apps/<file>.ipa` → success? app launches?

> The device's Apple ID **should match** the one used to download (FairPlay license binding). Test
> that configuration first.

### Record results here
```
date:
iOS version / device:
ipatool build: ok / fail (notes)
download: ok / fail (notes)
ideviceinstaller install: ok / fail (exact message)
app launches: yes / no
```

## Other risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Apple account flagged/locked** for tool use | medium | Use a disposable/test Apple ID for dev; don't hammer auth; never share credentials. |
| **iOS trust / Developer Mode / pairing** friction | medium | `idevicepair pair`, unlock device, tap Trust; enable Developer Mode on iOS 16+; document steps in the TUI. |
| **ipatool‑cpp build fails** on this toolchain | low | The `-Dexplicit_bzero=bzero` + OpenSSL flags are the known macOS fixes; fallback to `brew install ipatool` (Go), losing `get-version-metadata`. |
| **Apple changes auth/StoreKit**, breaking ipatool‑cpp | ongoing | Pin a known‑good commit; watch upstream; this is the same maintenance the original carries (it's at v3.8.x for this reason). |
| **FairPlay install rejected on newest iOS** | low–medium | If step 7/8 fails: try `--HEAD` libimobiledevice; confirm device Apple ID matches; check whether the app must first be installed once via App Store on that device; escalate before building UI. |
| **libimobiledevice stable lags new iOS** | low | Switch to `brew install --HEAD libimobiledevice ideviceinstaller usbmuxd`. |
| **Legal / App Store ToS** | inherent | Only licensed apps; no DRM stripping; not a piracy tool (same posture as the original). |

## Security / privacy guardrails

- **Never** commit or log: Apple ID, password, `--keychain-passphrase`, `~/.ipatool/account`,
  `~/.ipatool/cookies`, any `.ipa`, or `iTunesMetadata.plist` (contains account info).
- Keep `Apps/`, `Lists/`, `bin/` out of git (see `.gitignore` in toolchain doc).
- The downloaded IPA embeds the account's Sinf/iTunesMetadata — treat `.ipa` files as personal data.

## Open questions for the next session

1. Exact `--format json` key names for `search` / `download` / `auth info` (confirm at runtime; pin in `ipatool.py`).
2. Does `ideviceinstaller install` need the app pre‑provisioned on the device for FairPlay apps, or
   does same‑Apple‑ID suffice? (Answer via Phase 1.)
3. iOS 17/18/26 specifics: is Developer Mode required for `ideviceinstaller`‑pushed App Store IPAs, or
   only for developer‑signed apps? (Test.)
4. Does the user want to bundle `assets/Apps_ID_List.txt` from the original for name lookup?
