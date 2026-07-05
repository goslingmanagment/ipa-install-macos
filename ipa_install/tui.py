"""Terminal UI — the 15-item menu loop that glues the backends together.

This is a faithful port of ``IPA_Downloader.ps1``'s menu: same numbering, same
flows, same on-disk conventions. All logic that touches the App Store or the
device lives in the backend wrappers (``ipatool``/``device``); this module only
does menu UX, input parsing, and orchestration.
"""

from __future__ import annotations

import re
import sys
import webbrowser

from . import config, device, ipatool, library, scan
from .i18n import t

# Current UI language; mutated by menu item 15. Loaded from Lang_Config.txt at start.
_state = {"lang": "RU"}

SEP_WIDTH = 60


# ── tiny presentation helpers ───────────────────────────────────────────────────
def tr(key: str, *args: object) -> str:
    return t(key, _state["lang"], *args)


def _color(text: str, code: str) -> str:
    if sys.stdout.isatty():
        return f"\x1b[{code}m{text}\x1b[0m"
    return text


def separator() -> None:
    print(_color("=" * SEP_WIDTH, "32"))


def error(text: str) -> None:
    separator()
    print(_color(text, "31"))


def read_input(prompt: str) -> str:
    """Print a prompt and read one line; '0' is the universal cancel sentinel."""
    try:
        return input(prompt + "\n> ").strip()
    except EOFError:
        return "0"


def _trunc(s: str, n: int) -> str:
    return s if len(s) <= n else s[: n - 1] + "…"


# ── input grammar (port of Parse-NumberSelection) ───────────────────────────────
def parse_number_selection(selection: str, max_count: int):
    """Parse "1-3,5" style selections into a sorted unique list of 1..max_count.

    Accepts single numbers and inclusive ranges (reverse ranges are swapped),
    comma-separated. Returns ``None`` on any malformed token or if nothing valid
    remains after filtering — mirroring the original exactly.
    """
    indices: list[int] = []
    for part in selection.split(","):
        part = part.strip()
        if re.fullmatch(r"\d+-\d+", part):
            a_s, b_s = part.split("-")
            a, b = int(a_s), int(b_s)
            indices.extend(range(a, b + 1) if a <= b else range(b, a + 1))
        elif re.fullmatch(r"\d+", part):
            indices.append(int(part))
        else:
            return None
    seen: set[int] = set()
    out: list[int] = []
    for v in indices:
        if 1 <= v <= max_count and v not in seen:
            seen.add(v)
            out.append(v)
    out.sort()
    return out or None


# ── authentication gate (port of Connect-AppleID) ───────────────────────────────
def connect_apple_id() -> None:
    """Loop until ipatool reports a saved account. ipatool itself collects the
    password (hidden) and any 2FA code on the terminal — we never handle them."""
    while not config.is_logged_in():
        separator()
        # Clear a possibly-stale cookie jar between attempts (as the original does).
        try:
            config.COOKIES_FILE.unlink()
        except OSError:
            pass
        try:
            email = input(tr("AskEmail") + " ").strip()
        except EOFError:
            print()
            return
        if not email:
            continue
        print(tr("Auth2FAHint"))
        try:
            ipatool.auth_login(email)
        except ipatool.IpatoolError:
            pass
        if not config.is_logged_in():
            error(tr("AuthFail"))
    separator()
    print(tr("AuthSuccess"))
    try:
        info = ipatool.auth_info()
        name = info.get("name", "")
        mail = info.get("email", "")
        print(f"  {name}  <{mail}>")
    except ipatool.IpatoolError as e:
        # Logged in, but the info lookup failed — say so instead of hiding it.
        error(str(e) or "auth info failed")


# ── shared sub-flows ────────────────────────────────────────────────────────────
def _print_app_table(apps) -> None:
    print(f"{'№':<4}{tr('HeaderAppName'):<32}{tr('HeaderAppID')}")
    for i, app in enumerate(apps, 1):
        print(f"{i:<4}{_trunc(app.name, 30):<32}{app.id}")


def search_apps_menu():
    """Search → show results → return the selected list of App objects (or None)."""
    separator()
    term = read_input(f"{tr('AskSearch')} {tr('CancelStep')}")
    if term == "0" or term == "":
        return None
    print(tr("Searching"))
    try:
        apps = ipatool.search(term, 20)
    except ipatool.IpatoolError as e:
        error(str(e) or tr("ErrorNoAppsFound"))
        return None
    if not apps:
        error(tr("ErrorNoAppsFound"))
        return None
    separator()
    _print_app_table(apps)
    sel = read_input(f"{tr('AskAppNum')} (1-{len(apps)}) {tr('CancelStep')}")
    if sel == "0":
        return None
    idx = parse_number_selection(sel, len(apps))
    if idx is None:
        error(tr("ErrorInvalidInput"))
        return None
    return [apps[i - 1] for i in idx]


def get_multiple_app_ids(prompt_key: str):
    """Prompt for one or more numeric app IDs (comma/space separated)."""
    separator()
    raw = read_input(f"{tr(prompt_key)} {tr('CancelStep')}")
    if raw == "0":
        return None
    parts = [p for p in re.split(r"[,\s]+", raw) if p]
    if not parts or not all(re.fullmatch(r"\d+", p) for p in parts):
        error(tr("ErrorInvalidInput"))
        return None
    return parts


def get_apps_from_list(mode: str):
    """Show a saved/full list and return the chosen [{Id,Name}] entries (or None).

    mode: "Purchase" uses the Purchased list; "Download" uses the Downloaded list.
    """
    separator()
    print(f"{tr('ListMenuTitle')} {tr('CancelStep')}")
    if mode == "Purchase":
        print(tr("PurchasedListMenu1"))
        print(tr("PurchasedListMenu2"))
        print(tr("PurchasedListMenu3"))
        saved = library.load_list("Purchased")
        empty_err = "ErrorPurchasedEmpty"
    else:
        print(tr("DownloadedListMenu1"))
        print(tr("DownloadedListMenu2"))
        print(tr("DownloadedListMenu3"))
        saved = library.load_list("Downloaded")
        empty_err = "ErrorHistoryEmpty"

    sub = read_input(tr("MenuTitle"))
    if sub == "0":
        return None

    entries: list[tuple[str, str]] = []  # (Name, Id)
    if sub == "1":
        entries = [(e["Name"], e["Id"]) for e in library.github_list()]
        if not entries:
            error(tr("ErrorListLoadError"))
            return None
    elif sub == "2":
        if not saved:
            error(tr(empty_err))
            return None
        entries = [(e.get("name", ""), str(e.get("appid", ""))) for e in saved]
    elif sub == "3":
        gh = library.github_list()
        if not gh:
            error(tr("ErrorListLoadError"))
            return None
        saved_ids = {str(e.get("appid", "")) for e in saved}
        entries = [(e["Name"], e["Id"]) for e in gh if str(e["Id"]) not in saved_ids]
        if not entries:
            error(tr("ErrorNoAppsFound"))
            return None
    else:
        error(tr("ErrorInvalidInput"))
        return None

    separator()
    for i, (name, app_id) in enumerate(entries, 1):
        print(f"{i:<4}{name}: {app_id}")
    sel = read_input(f"{tr('AskAppNum')} (1-{len(entries)}) {tr('CancelStep')}")
    if sel == "0":
        return None
    idx = parse_number_selection(sel, len(entries))
    if idx is None:
        error(tr("ErrorInvalidInput"))
        return None
    return [{"Id": entries[i - 1][1], "Name": entries[i - 1][0]} for i in idx]


# ── download / purchase / install primitives ────────────────────────────────────
def _do_download(app_id: str, app_name=None, external_version_id=None, purchase=True) -> None:
    print(tr("Downloading"))
    try:
        res = ipatool.download(
            app_id, config.APPS_DIR,
            external_version_id=external_version_id, purchase=purchase,
        )
    except ipatool.IpatoolError as e:
        error(str(e) or tr("DownloadFailed"))
        return
    info = library.finalize_download(res.output, fallback_name=app_name, app_id=str(app_id))
    separator()
    print(tr("FileSaved"))
    print(f"{tr('FileName')} {info.path.name}")
    if info.min_ios:
        print(f"{tr('MinIOS')} {info.min_ios}")
    name = info.name or app_name or library.github_name(str(app_id)) or "Unknown"
    status = library.save_to_list(str(app_id), name, "Downloaded")
    if status == "added":
        print(tr("AddedToDownloadedList", name, app_id))
    elif status == "already":
        print(tr("AlreadyInList", name, app_id))


def _do_purchase(app_id: str, name: str) -> None:
    try:
        ipatool.purchase(app_id)
        print(tr("PurchaseDone"))
    except ipatool.IpatoolError as e:
        error(str(e) or tr("PurchaseFailed"))
    status = library.save_to_list(str(app_id), name, "Purchased")
    if status == "added":
        print(tr("AddedToPurchasedList", name, app_id))
    elif status == "already":
        print(tr("AlreadyInList", name, app_id))


def download_with_version(app_id: str, app_name=None) -> None:
    """List-versions → metadata table → download the chosen older version(s)."""
    if not re.fullmatch(r"\d+", str(app_id)):
        error(tr("ErrorInvalidInput"))
        return
    try:
        versions = ipatool.list_versions(app_id)
    except ipatool.IpatoolError as e:
        error(str(e) or tr("ErrorNoAppsFound"))
        return
    if not versions:
        error(tr("ErrorNoAppsFound"))
        return

    separator()
    cnt_raw = read_input(f"{tr('AskVerCount')} {tr('CancelStep')}")
    if cnt_raw == "0":
        return
    if not re.fullmatch(r"\d+", cnt_raw) or int(cnt_raw) <= 0:
        error(tr("ErrorInvalidInput"))
        return
    qty = int(cnt_raw)
    # versions come oldest→newest; show the newest `qty`, latest first.
    latest = list(reversed(versions[-qty:]))

    separator()
    print(f"{'№':<4}{tr('HeaderVerID'):<14}{tr('HeaderVersion')}")
    mapping: list[tuple[str, str]] = []
    for i, vid in enumerate(latest, 1):
        try:
            meta = ipatool.get_version_metadata(app_id, vid)
            dv = meta.display_version or "NA"
        except ipatool.IpatoolError:
            dv = "NA"
        print(f"{i:<4}{vid:<14}{dv}")
        mapping.append((vid, dv))

    sel = read_input(f"{tr('AskVerNum')} (1-{len(mapping)}) {tr('CancelStep')}")
    if sel == "0":
        return
    idx = parse_number_selection(sel, len(mapping))
    if idx is None:
        error(tr("ErrorInvalidInput"))
        return
    for i in idx:
        vid, dv = mapping[i - 1]
        separator()
        print(f"{tr('SelectedVer')} {dv}")
        _do_download(app_id, app_name, external_version_id=vid, purchase=False)


def ios_min_version_table():
    """Show the Apps/ folder with each IPA's minimum iOS; return the IpaInfo list."""
    apps = library.list_apps()
    if not apps:
        error(tr("ErrorNoApps"))
        return None
    separator()
    print(f"{'№':<4}{tr('HeaderFileName'):<34}{tr('HeaderMinIOS')}")
    for i, info in enumerate(apps, 1):
        mi = (info.min_ios + "+") if info.min_ios else "—"
        print(f"{i:<4}{_trunc(info.path.name, 32):<34}{mi}")
    return apps


def install_flow() -> None:
    """Menu 11 — pick IPAs from Apps/ and install them onto the connected device."""
    apps = ios_min_version_table()
    if not apps:
        return
    # macOS-friendly pre-check: warn early when no device is connected.
    try:
        devices = device.list_devices()
    except device.DeviceError:
        devices = None  # idevice_id unavailable — let ideviceinstaller report instead
    if devices == []:
        error(tr("NoDevice"))
        print(tr("PairHint"))
        return
    if devices:
        separator()
        print(tr("DeviceFound", devices[0]))
    print(tr("PairHint"))

    sel = read_input(f"{tr('AskAppNum')} (1-{len(apps)}) {tr('CancelStep')}")
    if sel == "0":
        return
    idx = parse_number_selection(sel, len(apps))
    if idx is None:
        error(tr("ErrorInvalidInput"))
        return
    for i in idx:
        info = apps[i - 1]
        separator()
        print(f"{tr('InstallApp')} {info.path.name}")
        try:
            ok, _msg = device.install(info.path)
        except device.DeviceError as e:
            error(str(e) or tr("InstallFailed"))
            continue
        separator()
        print(tr("InstallSuccess") if ok else _color(tr("InstallFailed"), "31"))


def clear_data() -> None:
    separator()
    print(f"{tr('ClearMenuTitle')} {tr('CancelStep')}")
    print(tr("ClearMenu1"))
    print(tr("ClearMenu2"))
    print(tr("ClearMenu3"))
    choice = read_input(tr("MenuTitle"))
    if choice == "0":
        return
    if choice == "1":
        library.clear_list("Downloaded")
        separator()
        print(tr("DownloadedListCleared"))
    elif choice == "2":
        library.clear_list("Purchased")
        separator()
        print(tr("PurchasedListCleared"))
    elif choice == "3":
        if library.clear_apps():
            separator()
            print(tr("AppsCleared"))
        else:
            error(tr("ErrorNoApps"))
    else:
        error(tr("ErrorInvalidInput"))


# ── menu dispatch ───────────────────────────────────────────────────────────────
def ownership_scan_flow() -> None:
    """Menu 16 (macOS) — probe the catalog for apps this Apple ID owns, then split
    owned apps into removed-from-store vs still-in-store. See :mod:`scan` for the why."""
    entries = [(e["Id"], e["Name"]) for e in library.github_list()]
    if not entries:
        error(tr("ErrorListLoadError"))
        return
    separator()
    print(tr("ScanWarn", len(entries)))
    if read_input(tr("ScanConfirm")) != "1":
        return
    separator()
    print(tr("ScanFiltering"))

    def on_progress(i, total, app_id, name, owned):
        print(f"[{i}/{total}] {'✓' if owned else ' '} {_trunc(name, 48)}")

    try:
        result = scan.scan_catalog(entries, on_progress=on_progress)
    except KeyboardInterrupt:
        print()
        error(tr("ScanCancelled"))
        return

    recoverable = result["removed_owned"]
    not_owned = result["removed_not_owned"]
    scan.save_owned_scan(recoverable, not_owned)

    separator()
    print(tr("ScanDoneMsg", result["removed_total"], len(recoverable)))
    if not recoverable:
        print(tr("ScanNoRecoverable"))
    else:
        separator()
        print(tr("ScanRemovedHeader", len(recoverable)))
        for e in recoverable:
            print(f"  {e['appid']}  {e['name']}")
    separator()
    print(tr("ScanNotOwnedHeader", len(not_owned)))
    for e in not_owned:
        print(f"  {e['appid']}  {e['name']}")
    separator()
    print(tr("ScanSaved"))


def _print_menu() -> None:
    separator()
    print(tr("MenuTitle"))
    for n in range(1, 17):
        print(tr(f"Menu{n}"))


def dispatch(choice: str) -> None:
    if choice == "1":
        apps = search_apps_menu()
        for app in apps or []:
            separator()
            print(f"{tr('SelectedApp')} {app.name}")
            _do_purchase(app.id, app.name)
    elif choice == "2":
        apps = search_apps_menu()
        for app in apps or []:
            separator()
            print(f"{tr('SelectedApp')} {app.name}")
            _do_download(app.id, app.name, purchase=True)
    elif choice == "3":
        apps = search_apps_menu()
        for app in apps or []:
            separator()
            print(f"{tr('SelectedApp')} {app.name}")
            download_with_version(app.id, app.name)
    elif choice == "4":
        ids = get_multiple_app_ids("AskIdPurchase")
        for app_id in ids or []:
            separator()
            name = library.github_name(app_id) or "Unknown"
            print(f"{tr('SelectedApp')} {name} ({app_id})")
            _do_purchase(app_id, name)
    elif choice == "5":
        ids = get_multiple_app_ids("AskIdDownload")
        for app_id in ids or []:
            # Original item 5 calls download directly with no "Selected app" banner.
            separator()
            _do_download(app_id, None, purchase=True)
    elif choice == "6":
        ids = get_multiple_app_ids("AskIdSearch")
        for app_id in ids or []:
            separator()
            download_with_version(app_id, None)
    elif choice == "7":
        sel = get_apps_from_list("Purchase")
        for app in sel or []:
            separator()
            print(f"{tr('SelectedApp')} {app['Name']}")
            _do_purchase(app["Id"], app["Name"])
    elif choice == "8":
        sel = get_apps_from_list("Download")
        for app in sel or []:
            separator()
            print(f"{tr('SelectedApp')} {app['Name']}")
            _do_download(app["Id"], app["Name"], purchase=True)
    elif choice == "9":
        sel = get_apps_from_list("Download")
        for app in sel or []:
            separator()
            print(f"{tr('SelectedApp')} {app['Name']}")
            download_with_version(app["Id"], app["Name"])
    elif choice == "10":
        ios_min_version_table()
    elif choice == "11":
        install_flow()
    elif choice == "12":
        clear_data()
    elif choice == "13":
        separator()
        print(tr("LoggedOut"))
        try:
            ipatool.auth_revoke()
        except ipatool.IpatoolError:
            pass
        connect_apple_id()
    elif choice == "14":
        try:
            webbrowser.open(config.GITHUB_URL)
        except Exception:
            print(config.GITHUB_URL)
    elif choice == "15":
        _state["lang"] = "EN" if _state["lang"] == "RU" else "RU"
        config.save_language(_state["lang"])
        separator()
        print(tr("LangChanged"))
    elif choice == "16":
        ownership_scan_flow()
    else:
        error(tr("ErrorInvalidInput"))


# ── entry point ─────────────────────────────────────────────────────────────────
def main() -> int:
    config.ensure_dirs()
    config.cleanup_tmp()
    missing = config.missing_binaries()
    if missing:
        print(tr("ErrorMissingFiles"))
        for name in missing:
            print(f"  - {name}")
        return 1
    _state["lang"] = config.load_language()

    try:
        connect_apple_id()
        while config.is_logged_in():
            _print_menu()
            choice = read_input(tr("MenuTitle"))
            dispatch(choice)
    except KeyboardInterrupt:
        print()
        return 0
    return 0
