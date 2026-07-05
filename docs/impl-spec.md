# Implementation spec — `ipa_install` Python package (FROZEN CONTRACT)

This is the **frozen interface contract** every module is built against. Signatures and data
shapes here are authoritative — do not deviate. Confirmed against `ipatool-cpp/main.cpp` (JSON
shapes) and `IPA_Downloader.ps1` (behaviors). Package lives at
`/Users/dmitriy/code/ipa-install-macos/ipa_install/`.

## Global rules
- **Python 3, stdlib only.** No third-party imports anywhere. Allowed: `subprocess, json, os, sys,
  shutil, pathlib, plistlib, zipfile, re, dataclasses, typing, webbrowser, glob`.
- **Never print, log, or store secrets:** Apple ID password, `--auth-code`, `--keychain-passphrase`,
  cookies, or the contents of `~/.ipatool/*`. Do not put password/auth-code into exception messages.
- All binaries are invoked by **absolute path** resolved in `config.py`.
- Subprocess: pass args as a **list** (never `shell=True`). Use `text=True, encoding="utf-8"`.

## Exact ipatool CLI + JSON contracts (verified from main.cpp)
Invocation form: `ipatool --format json <cmd> [flags]`. The custom arg parser treats `--flag` with
no following non-dash token as the literal value `"true"`; a value that itself starts with `-` is
NOT consumed. So: put boolean flags (`--purchase`) **last or immediately before another `-flag`**,
and never pass values that begin with `-`.

| command | invocation | stdout JSON (one line) |
|---|---|---|
| auth login | `auth login -e EMAIL [-p PW] [--auth-code CODE]` | `{"name","email","success":true}` (we run it **attached/interactive**, not via JSON capture) |
| auth info | `auth info` | `{"name","email","success":true}` |
| auth revoke | `auth revoke` | `{"success":true}` (prints `Not logged in.` to stderr + exit 1 if none) |
| search | `search "<term>" -l <limit>` | `{"count":N,"apps":[{"id","bundleID","name","version","price"}]}` |
| purchase | `purchase -i <APPID>` | stdout = `Purchasing: <name> (<bundle>)\n` **then** `{"success":true}` |
| download | `download -i <APPID> -o <DIR> [--external-version-id <VID>] [--purchase]` | `{"output","purchased":bool,"success":true}` |
| list-versions | `list-versions -i <APPID>` | `{"externalVersionIdentifiers":[...],"bundleID","success":true}` (bundleID empty when `-i` used) |
| get-version-metadata | `get-version-metadata -i <APPID> --external-version-id <VID>` | `{"externalVersionID","displayVersion","releaseDate","success":true}` |

Notes:
- Errors → message on **stderr**, non-zero exit. Success → exit 0.
- `search` `id` may serialize as a JSON number — **coerce to str**. `externalVersionIdentifiers`
  entries likewise — coerce to str.
- `purchase` emits a non-JSON `Purchasing:` line before the JSON: the JSON parser must **scan stdout
  lines for the object**, not assume the whole stream is JSON.
- `download` draws a progress bar to stderr **only when stdout is a TTY**; if stdout is a pipe the bar
  is suppressed. Strategy below avoids needing to capture download stdout at all.

---

## `config.py`
Module-level (computed at import):
```
PROJECT_ROOT: Path      # = Path(__file__).resolve().parent.parent
BIN_DIR        = PROJECT_ROOT / "bin"
APPS_DIR       = PROJECT_ROOT / "Apps"
LISTS_DIR      = PROJECT_ROOT / "Lists"
ASSETS_DIR     = PROJECT_ROOT / "assets"
IPATOOL_HOME   = Path.home() / ".ipatool"
ACCOUNT_FILE   = IPATOOL_HOME / "account"
COOKIES_FILE   = IPATOOL_HOME / "cookies"
LANG_CONFIG_FILE = PROJECT_ROOT / "Lang_Config.txt"
PURCHASED_LIST = LISTS_DIR / "Purchased_IDs.json"
DOWNLOADED_LIST= LISTS_DIR / "Downloaded_IDs.json"
APPS_ID_LIST_TXT = ASSETS_DIR / "Apps_ID_List.txt"
GITHUB_URL     = "https://github.com/kda2495/IPA_Downloader"

IPATOOL          = resolve_binary("ipatool")
IDEVICEINSTALLER = resolve_binary("ideviceinstaller")
IDEVICE_ID       = resolve_binary("idevice_id")
IDEVICEPAIR      = resolve_binary("idevicepair")
```
Functions:
- `resolve_binary(name:str)->str` — return `str(BIN_DIR/name)` if it exists and is executable
  (follow symlinks via `os.access(..., os.X_OK)`), else `shutil.which(name)` if found, else `name`.
- `ensure_dirs()->None` — `mkdir(parents=True, exist_ok=True)` for APPS_DIR, LISTS_DIR, IPATOOL_HOME.
- `cleanup_tmp()->None` — delete `*.ipa.tmp` in PROJECT_ROOT and APPS_DIR (ignore errors).
- `is_logged_in()->bool` — `ACCOUNT_FILE.exists()`.
- `missing_binaries()->list[str]` — of {ipatool, ideviceinstaller}, the ones not resolvable
  (resolved path not executable AND not on PATH). Used for the startup check.
- `load_language()->str` — read LANG_CONFIG_FILE, `.strip().upper()`, return if in {"RU","EN"};
  else default "RU"; if file missing, create it containing "RU". Never raise.
- `save_language(lang:str)->None` — write `lang` (must be "RU"/"EN") to LANG_CONFIG_FILE.

## `i18n.py`
- `STRINGS: dict` with top-level keys `"RU"` and `"EN"`; each maps every key below to its string.
- `t(key:str, lang:str, *args)->str` — return `STRINGS[lang].get(key)`, falling back to
  `STRINGS["EN"].get(key, key)`; if `args`, return `value.format(*args)`.
- Templated values use `{0}`, `{1}` (AddedToDownloadedList/AddedToPurchasedList/AlreadyInList take
  `name, appid`).
- Keys (RU/EN both): the 15 menu items `Menu1..Menu15`, `MenuTitle`, `AuthSuccess`, `AuthFail`,
  `LoggedOut`, `AskSearch`, `AskIdSearch`, `AskIdDownload`, `AskIdPurchase`, `AskAppNum`,
  `AskVerCount`, `AskVerNum`, `CancelStep`, `HeaderAppName`, `HeaderAppID`, `HeaderVerID`,
  `HeaderVersion`, `HeaderFileName`, `HeaderMinIOS`, `SelectedApp`, `SelectedVer`, `FileSaved`,
  `FileName`, `MinIOS`, `AddedToDownloadedList`, `AddedToPurchasedList`, `AlreadyInList`,
  `InstallApp`, `ClearMenuTitle`, `ClearMenu1`, `ClearMenu2`, `ClearMenu3`, `DownloadedListCleared`,
  `PurchasedListCleared`, `AppsCleared`, `ListMenuTitle`, `DownloadedListMenu1..3`,
  `PurchasedListMenu1..3`, `ErrorInvalidInput`, `ErrorNoAppsFound`, `ErrorNoApps`,
  `ErrorHistoryEmpty`, `ErrorPurchasedEmpty`, `ErrorListLoadError`, `ErrorMissingFiles`,
  `PressEnter`, `LangChanged`. Plus macOS additions: `AskEmail`, `AskPassword`, `Auth2FAHint`,
  `Downloading`, `DownloadFailed`, `PurchaseFailed`, `PurchaseDone`, `NoDevice`, `DeviceFound`,
  `InstallSuccess`, `InstallFailed`, `PairHint`, `Searching`, `Back`, `MenuPrompt`.
  (Exact RU/EN text is supplied to the i18n implementer.)

## `ipatool.py`
```
class IpatoolError(Exception): pass

@dataclass
class App:        id:str; bundle_id:str; name:str; version:str; price:str
@dataclass
class DownloadResult: output:str; purchased:bool
@dataclass
class VersionMeta: external_version_id:str; display_version:str; release_date:str
```
Helpers:
- `_run_json(cmd_args:list[str])->dict` — run `[IPATOOL,"--format","json",*cmd_args]` with
  `capture_output=True, text=True`. If returncode != 0 → `raise IpatoolError(stderr.strip() or
  stdout.strip() or "ipatool failed")`. Else parse stdout: try `json.loads(stdout)`; on failure scan
  lines bottom-up for the first whose `.strip()` starts with `{` and `json.loads` succeeds; return it.
  If none parse → `IpatoolError`.
Public:
- `auth_login(email:str, password:str|None=None, auth_code:str|None=None)->None` — run
  `[IPATOOL,"auth","login","-e",email] (+ ["-p",password]) (+ ["--auth-code",auth_code])` with
  **streams inherited** (no capture) so ipatool can do hidden-password / 2FA prompts on the terminal.
  Return None if returncode==0 else `raise IpatoolError("login failed")`. **Do not** echo or store
  password/auth_code.
- `auth_info()->dict` — `_run_json(["auth","info"])`.
- `auth_revoke()->None` — run `[IPATOOL,"auth","revoke"]` (capture); ignore failure when already
  logged out (returncode!=0 with "Not logged in" is acceptable → return None).
- `search(term:str, limit:int=20)->list[App]` — `_run_json(["search",term,"-l",str(limit)])`; map
  each app dict → `App(id=str(a["id"]), bundle_id=a.get("bundleID",""), name=a.get("name",""),
  version=a.get("version",""), price=str(a.get("price","")))`.
- `purchase(app_id:str)->None` — `_run_json(["purchase","-i",str(app_id)])`; success if dict
  `success` truthy, else IpatoolError.
- `download(app_id:str, output_dir:str|Path, external_version_id:str|None=None,
  purchase:bool=True)->DownloadResult` — **does NOT use `_run_json`.** Build
  `[IPATOOL,"download","-i",str(app_id),"-o",str(output_dir)] (+ ["--external-version-id",vid]) (+
  ["--purchase"] if purchase)` (note `--purchase` placed last). Snapshot `{p:p.stat().st_mtime}` of
  `*.ipa` in `output_dir` before. Run **attached (inherit stdout/stderr/stdin)** so the native
  progress bar shows. If returncode != 0 → `IpatoolError`. After: find the `.ipa` in `output_dir`
  that is new or whose mtime increased; pick the newest such; that path is `output`. Return
  `DownloadResult(output=that_path, purchased=purchase)`. If none found → IpatoolError.
- `list_versions(app_id:str)->list[str]` — `_run_json(["list-versions","-i",str(app_id)])` →
  `[str(v) for v in dict.get("externalVersionIdentifiers",[])]`.
- `get_version_metadata(app_id:str, external_version_id:str)->VersionMeta` —
  `_run_json(["get-version-metadata","-i",str(app_id),"--external-version-id",str(external_version_id)])`
  → `VersionMeta(external_version_id=str(...), display_version=d.get("displayVersion",""),
  release_date=d.get("releaseDate",""))`.

## `device.py`
```
class DeviceError(Exception): pass
```
- `list_devices()->list[str]` — run `[IDEVICE_ID,"-l"]` capture; return non-empty stripped lines.
  If binary unresolved / OSError → `raise DeviceError`. Non-zero exit with empty output → `[]`.
- `pair_validate(udid:str|None=None)->bool` — run `[IDEVICEPAIR] (+ ["-u",udid]) + ["validate"]`;
  return returncode==0. Never raise for the normal "not paired" case.
- `pair(udid:str|None=None)->tuple[bool,str]` — run `[IDEVICEPAIR] (+["-u",udid]) + ["pair"]`
  capture; return `(returncode==0, (stdout+stderr).strip())`.
- `install(ipa_path:str|Path, udid:str|None=None)->tuple[bool,str]` — run
  `[IDEVICEINSTALLER] (+ ["-u",udid]) + ["install", str(ipa_path)]` with stdout/stderr **inherited**
  so the user sees native progress; return `(returncode==0, "")`. (macOS: install the file directly;
  the original's copy-to-temp step is a Windows workaround and is intentionally dropped — document
  this.) If binary unresolved/OSError → `raise DeviceError`.

## `library.py`
```
class LibraryError(Exception): pass

@dataclass
class IpaInfo: path:Path; name:str; version:str; min_ios:str; bundle_id:str
```
- `read_ipa_metadata(ipa_path:str|Path)->IpaInfo` — open as `zipfile.ZipFile`; find first member
  matching `Payload/*.app/Info.plist` (use a regex on namelist:
  `^Payload/[^/]+\.app/Info\.plist$`); `plistlib.loads(zf.read(member))`. name =
  `plist.get("CFBundleName") or plist.get("CFBundleDisplayName") or ""`; version =
  `plist.get("CFBundleShortVersionString","")`; min_ios = `plist.get("MinimumOSVersion","")`;
  bundle_id = `plist.get("CFBundleIdentifier","")`. On any error → `raise LibraryError`.
- `list_apps()->list[IpaInfo]` — every `*.ipa` in `config.APPS_DIR`; for each, try
  `read_ipa_metadata`; on failure include an IpaInfo with name=filename stem and empty fields (so the
  file still lists). Sort by `name.lower()` then filename. (Menu 10/11 share this.)
- `sanitize_filename(s:str)->str` — remove chars `\ / : * ? " < > |`; strip; collapse internal
  whitespace runs to single `_`.
- `friendly_ipa_name(info:IpaInfo)->str` — `f"{sanitize_filename(info.name)}_{info.version}_iOS_
  {info.min_ios}+.ipa"` then replace any remaining whitespace with `_`. If name empty, caller passes
  a fallback before calling (see finalize_download).
- `finalize_download(output_path:str|Path, fallback_name:str|None=None, app_id:str|None=None)
  ->IpaInfo` — read metadata from `output_path`; if name empty use `fallback_name`, then
  `github_name(app_id)` (the offline list is keyed by the **numeric app id**, matching the original's
  `Get-GitHub-AppName -AppId`); compute friendly filename; if different from current, rename within
  `APPS_DIR` (handle collision by leaving the ipatool name if target exists); return the IpaInfo with
  `path` updated to the final location.
- Lists (JSON compatible with the original — array of `{"name":str,"appid":str}`):
  - `load_list(kind:str)->list[dict]` — kind in {"Purchased","Downloaded"} → read PURCHASED_LIST /
    DOWNLOADED_LIST; return `[]` if missing/invalid.
  - `save_to_list(app_id:str, name:str, kind:str)->str` — load, dedupe by `appid` (string compare);
    if present → return `"already"`; else append `{"name":name,"appid":str(app_id)}`, sort by
    `name.lower()`, write UTF-8 (`ensure_ascii=False, indent=2`), return `"added"`.
  - `clear_list(kind:str)->None` — delete the list file (ignore if absent).
  - `clear_apps()->bool` — delete every `*.ipa` in APPS_DIR; return True iff ≥1 deleted.
- Name lookup (the bundled `assets/Apps_ID_List.txt` is our "GitHub full list"; offline, no network):
  - `github_list()->list[dict]` — parse each line with `^(.+?):\s*(\d+)` → `{"Name":g1.strip(),
    "Id":g2.strip()}`; cache module-level; return `[]` if file missing.
  - `github_name(app_id:str)->str|None` — return the Name whose Id == str(app_id), else None.

## Input grammar — `parse_number_selection` (lives in `tui.py`; replicate PS1 exactly)
`parse_number_selection(selection:str, max_count:int)->list[int]|None`:
- split on `,`; trim each part.
- part matches `^\d+-\d+$` → inclusive range (if start>end, swap).
- part matches `^\d+$` → single.
- anything else → return None (invalid).
- dedupe, keep only `1..max_count`, preserve ascending order; if empty → None.

## `tui.py` (integrator) — flows
`main()->int`. Startup: `config.ensure_dirs()`, `config.cleanup_tmp()`, check
`config.missing_binaries()` (if any → print ErrorMissingFiles + names, return 1), `lang =
config.load_language()`. Auth gate (port of `Connect-AppleID`): while not `config.is_logged_in()`:
prompt email, call `ipatool.auth_login(email)` (let ipatool prompt password+2FA on the terminal);
on failure print AuthFail and loop. Once logged in: print AuthSuccess + `auth_info()` name/email.
Main loop while `is_logged_in()`: render the 15-item menu, read choice, dispatch. Implement all 15
exactly per `docs/original-tool-analysis.md` + the behavior report. Sub-flows: `search_apps_menu`,
`get_multiple_app_ids`, `get_apps_from_list(mode)`, `download_with_version(app_id, app_name)`,
`ios_min_version_table()`. Cancel sentinel `0` returns to menu. Use i18n `t()` for all text.
Item 14 → `webbrowser.open(config.GITHUB_URL)`. Item 15 → toggle + `config.save_language`.
Item 13 → `ipatool.auth_revoke()` then re-enter auth gate.

## `__main__.py`
```
import sys
from .tui import main
sys.exit(main())
```
