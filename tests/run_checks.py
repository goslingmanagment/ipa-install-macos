#!/usr/bin/env python3
"""Offline verification for ipa_install — no Apple ID, no device required.

Drives the real wrapper modules and the TUI against *fake* ``ipatool`` /
``ideviceinstaller`` / ``idevice_id`` binaries that emit the exact JSON shapes the
real ipatool-cpp produces (verified from main.cpp). Covers: input-grammar parsing,
library/list/plist logic, the ipatool JSON wrappers (including the ``purchase``
leading-line and the ``download`` directory-diff), and a scripted run through the
menu dispatcher for several items.

Run:  python3 tests/run_checks.py
"""

from __future__ import annotations

import builtins
import io
import os
import plistlib
import stat
import sys
import tempfile
import zipfile
from contextlib import redirect_stdout
from pathlib import Path

# Make the package importable when run from anywhere.
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from ipa_install import config, ipatool, device, library, tui  # noqa: E402

_failures: list[str] = []


def check(label: str, cond: bool, detail: str = "") -> None:
    mark = "ok " if cond else "FAIL"
    print(f"  [{mark}] {label}" + (f" — {detail}" if detail and not cond else ""))
    if not cond:
        _failures.append(label + (f" — {detail}" if detail else ""))


# ── A valid minimal .ipa fixture ────────────────────────────────────────────────
def make_ipa(path: Path, name="Alpha", version="1.0", min_ios="14.0", bundle="com.a"):
    info = {
        "CFBundleName": name,
        "CFBundleDisplayName": name,
        "CFBundleShortVersionString": version,
        "MinimumOSVersion": min_ios,
        "CFBundleIdentifier": bundle,
    }
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr(f"Payload/{name}.app/Info.plist", plistlib.dumps(info))
        zf.writestr(f"Payload/{name}.app/{name}", b"\x00fake-macho\x00")


# ── Fake ipatool (python script) ────────────────────────────────────────────────
FAKE_IPATOOL = r'''#!/usr/bin/env python3
import os, sys, plistlib, zipfile
A = sys.argv[1:]
# Drop the global "--format <value>" pair (the real parser consumes it) so the
# command word is found correctly.
if "--format" in A:
    i = A.index("--format")
    del A[i:i+2]
def has(f): return f in A
def val(f):
    return A[A.index(f)+1] if f in A and A.index(f)+1 < len(A) else None
acct = os.environ["IPA_TEST_ACCOUNT"]
pos = [a for a in A if not a.startswith("-")]
# command words
cmd = pos[0] if pos else ""
two = (pos[0]+" "+pos[1]) if len(pos) >= 2 and pos[0] == "auth" else cmd

if two == "auth login":
    open(acct, "w").write("fake-account")
    print('{"name":"Test User","email":"test@example.com","success":true}')
    sys.exit(0)
if two == "auth info":
    if os.path.exists(acct):
        print('{"name":"Test User","email":"test@example.com","success":true}'); sys.exit(0)
    sys.stderr.write("Not logged in.\n"); sys.exit(1)
if two == "auth revoke":
    try: os.remove(acct)
    except OSError: pass
    print('{"success":true}'); sys.exit(0)
if cmd == "search":
    term = pos[1] if len(pos) >= 2 else ""
    if term == "ERROR":
        sys.stderr.write("Search error: boom\n"); sys.exit(1)
    print('{"count":2,"apps":[{"id":111,"bundleID":"com.a","name":"Alpha","version":"1.0","price":"0"},{"id":222,"bundleID":"com.b","name":"Beta App","version":"2.0","price":"0"}]}')
    sys.exit(0)
if cmd == "purchase":
    # NOTE: a non-JSON line precedes the JSON, exactly like the real tool.
    print("Purchasing: Alpha (com.a)")
    print('{"success":true}')
    sys.exit(0)
if cmd == "list-versions":
    print('{"externalVersionIdentifiers":[1001,1002,1003],"bundleID":"","success":true}')
    sys.exit(0)
if cmd == "get-version-metadata":
    vid = val("--external-version-id")
    print('{"externalVersionID":"%s","displayVersion":"1.2.%s","releaseDate":"2024-01-0%s","success":true}' % (vid, vid[-1], vid[-1]))
    sys.exit(0)
if cmd == "download":
    out = val("-o") or val("--output") or "."
    appid = val("-i") or "111"
    sys.stderr.write("Downloading: 100%% (1/1 MB)\n")  # progress noise on stderr
    p = os.path.join(out, "com.a_%s_1.0.ipa" % appid)
    info = {"CFBundleName":"Alpha","CFBundleDisplayName":"Alpha","CFBundleShortVersionString":"1.0","MinimumOSVersion":"14.0","CFBundleIdentifier":"com.a"}
    with zipfile.ZipFile(p, "w") as zf:
        zf.writestr("Payload/Alpha.app/Info.plist", plistlib.dumps(info))
        zf.writestr("Payload/Alpha.app/Alpha", b"\x00macho\x00")
    print('{"output":"%s","purchased":%s,"success":true}' % (p, "true" if has("--purchase") else "false"))
    sys.exit(0)
sys.stderr.write("Unknown command\n"); sys.exit(1)
'''

FAKE_TRUE = "#!/bin/sh\nexit 0\n"
FAKE_IDEVICE_ID = "#!/bin/sh\n# print one fake UDID\necho 00008030-FAKEUDID\n"


def write_exec(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


# ── 1. Input grammar ────────────────────────────────────────────────────────────
def test_parse_selection():
    print("parse_number_selection")
    p = tui.parse_number_selection
    check("single", p("3", 5) == [3])
    check("range", p("1-3", 5) == [1, 2, 3])
    check("reverse range", p("3-1", 5) == [1, 2, 3])
    check("mixed + dedupe + sort", p("1,3-5,7,4", 10) == [1, 3, 4, 5, 7])
    check("spaces tolerated", p(" 2 , 4 ", 5) == [2, 4])
    check("out-of-range filtered", p("0,6,3", 5) == [3])
    check("all-out-of-range -> None", p("9,10", 5) is None)
    check("garbage -> None", p("abc", 5) is None)
    check("partial garbage -> None", p("1,x", 5) is None)
    check("empty -> None", p("", 5) is None)


# ── 2. Library / lists / plist ───────────────────────────────────────────────────
def test_library(tmp: Path):
    print("library + lists + plist")
    apps_dir = tmp / "Apps"
    lists_dir = tmp / "Lists"
    apps_dir.mkdir()
    lists_dir.mkdir()
    config.APPS_DIR = apps_dir
    config.LISTS_DIR = lists_dir
    config.PURCHASED_LIST = lists_dir / "Purchased_IDs.json"
    config.DOWNLOADED_LIST = lists_dir / "Downloaded_IDs.json"

    check("sanitize strips bad chars", library.sanitize_filename('A/B:C* D') == "ABC_D",
          library.sanitize_filename('A/B:C* D'))
    info = library.IpaInfo(path=apps_dir / "x.ipa", name="My App", version="1.0",
                           min_ios="14.0", bundle_id="com.a")
    check("friendly name", library.friendly_ipa_name(info) == "My_App_1.0_iOS_14.0+.ipa",
          library.friendly_ipa_name(info))

    # real asset name list
    gl = library.github_list()
    check("github_list parses bundled asset (>=400)", len(gl) >= 400, str(len(gl)))
    check("github_name lookup works", library.github_name("481627348") == "2ГИС",
          repr(library.github_name("481627348")))
    check("github_name miss -> None", library.github_name("999999999999") is None)

    # saved lists round-trip + dedupe + original-compatible shape
    check("save added", library.save_to_list("111", "Alpha", "Downloaded") == "added")
    check("save dup -> already", library.save_to_list("111", "Alpha", "Downloaded") == "already")
    # blank/"Unknown" names are not recorded (matches the original Save-App-To-List)
    check("save Unknown -> skipped", library.save_to_list("999", "Unknown", "Downloaded") == "skipped")
    check("save blank -> skipped", library.save_to_list("998", "  ", "Downloaded") == "skipped")
    check("skipped not persisted", not any(e["appid"] in {"999", "998"} for e in library.load_list("Downloaded")))
    library.save_to_list("222", "Beta", "Downloaded")
    loaded = library.load_list("Downloaded")
    check("list sorted by name + keys", [e["name"] for e in loaded] == ["Alpha", "Beta"]
          and set(loaded[0].keys()) == {"name", "appid"}, str(loaded))
    raw = (lists_dir / "Downloaded_IDs.json").read_text(encoding="utf-8")
    check("list json uses lowercase name/appid", '"appid"' in raw and '"name"' in raw)

    # metadata from a real synthetic ipa + finalize rename
    make_ipa(apps_dir / "com.a_111_1.0.ipa")
    meta = library.read_ipa_metadata(apps_dir / "com.a_111_1.0.ipa")
    check("read_ipa_metadata name/min_ios", meta.name == "Alpha" and meta.min_ios == "14.0",
          f"{meta.name}/{meta.min_ios}")
    fin = library.finalize_download(apps_dir / "com.a_111_1.0.ipa")
    check("finalize renames to friendly", fin.path.name == "Alpha_1.0_iOS_14.0+.ipa",
          fin.path.name)
    check("finalized file exists", fin.path.exists())

    # name fallback keyed by NUMERIC app id when CFBundleName is empty — matches original.
    noname = apps_dir / "noname_111.ipa"
    with zipfile.ZipFile(noname, "w") as zf:
        zf.writestr("Payload/App.app/Info.plist", plistlib.dumps(
            {"CFBundleName": "", "CFBundleDisplayName": "",
             "CFBundleShortVersionString": "3.0", "MinimumOSVersion": "15.0",
             "CFBundleIdentifier": "com.x"}))
    meta_noname = library.read_ipa_metadata(noname)
    check("empty CFBundleName reads as ''", meta_noname.name == "", repr(meta_noname.name))
    fin2 = library.finalize_download(noname, app_id="481627348")
    check("finalize falls back to github_name(app_id)", fin2.name == "2ГИС", fin2.name)

    # list_apps tolerates a junk .ipa
    (apps_dir / "broken.ipa").write_text("not a zip")
    names = [a.path.name for a in library.list_apps()]
    check("list_apps includes broken file", "broken.ipa" in names, str(names))

    # clear
    check("clear_apps removes ipas", library.clear_apps() is True)
    check("clear_apps empty -> False", library.clear_apps() is False)
    library.clear_list("Downloaded")
    check("clear_list -> empty load", library.load_list("Downloaded") == [])


# ── 3. ipatool wrappers vs the fake binary ───────────────────────────────────────
def test_ipatool(tmp: Path, fake_ipatool: Path):
    print("ipatool wrappers (fake binary)")
    config.IPATOOL = str(fake_ipatool)
    apps_dir = tmp / "Apps2"
    apps_dir.mkdir()
    config.APPS_DIR = apps_dir

    apps = ipatool.search("alpha", 20)
    check("search count", len(apps) == 2, str(len(apps)))
    check("search id coerced to str", apps[0].id == "111" and isinstance(apps[0].id, str))
    check("search fields", apps[1].name == "Beta App" and apps[1].bundle_id == "com.b")

    try:
        ipatool.search("ERROR")
        check("search error raises", False)
    except ipatool.IpatoolError as e:
        check("search error raises IpatoolError", "boom" in str(e), str(e))

    # purchase: must scan past the leading "Purchasing:" line
    try:
        ipatool.purchase("111")
        check("purchase parses past leading line", True)
    except ipatool.IpatoolError as e:
        check("purchase parses past leading line", False, str(e))

    vers = ipatool.list_versions("111")
    check("list_versions coerced to str", vers == ["1001", "1002", "1003"], str(vers))
    vm = ipatool.get_version_metadata("111", "1002")
    check("version metadata", vm.display_version == "1.2.2" and vm.external_version_id == "1002",
          f"{vm.display_version}/{vm.external_version_id}")

    # download: dir-diff must locate the freshly created ipa
    res = ipatool.download("111", apps_dir, purchase=True)
    check("download found file", Path(res.output).exists() and res.output.endswith(".ipa"),
          res.output)
    check("download purchased flag", res.purchased is True)

    info = ipatool.auth_info()
    check("auth_info shape", info.get("email") == "test@example.com")


# ── 4. Scripted TUI dispatch ─────────────────────────────────────────────────────
def run_dispatch(choice: str, inputs: list[str]) -> str:
    it = iter(inputs)
    buf = io.StringIO()

    def fake_input(prompt=""):
        try:
            return next(it)
        except StopIteration:
            raise EOFError

    orig = builtins.input
    builtins.input = fake_input
    try:
        with redirect_stdout(buf):
            tui.dispatch(choice)
    finally:
        builtins.input = orig
    return buf.getvalue()


def test_tui(tmp: Path, fake_ipatool: Path):
    print("TUI dispatch (scripted input, fake backend)")
    config.IPATOOL = str(fake_ipatool)
    apps_dir = tmp / "Apps3"
    lists_dir = tmp / "Lists3"
    apps_dir.mkdir()
    lists_dir.mkdir()
    config.APPS_DIR = apps_dir
    config.LISTS_DIR = lists_dir
    config.PURCHASED_LIST = lists_dir / "Purchased_IDs.json"
    config.DOWNLOADED_LIST = lists_dir / "Downloaded_IDs.json"
    library._GITHUB_LIST_CACHE = None  # reset cache
    tui._state["lang"] = "EN"

    # Item 2: search → select #1 → download latest
    out = run_dispatch("2", ["alpha", "1"])
    ipas = list(apps_dir.glob("*.ipa"))
    check("item2 downloaded an ipa", len(ipas) == 1, str([p.name for p in ipas]))
    check("item2 friendly-named", ipas and ipas[0].name == "Alpha_1.0_iOS_14.0+.ipa",
          ipas[0].name if ipas else "none")
    check("item2 saved to Downloaded list",
          any(e["appid"] == "111" for e in library.load_list("Downloaded")))
    check("item2 printed FileSaved", "File saved" in out, out[-200:])

    # Item 3: search → select #1 → versions: show 3 → pick 2
    out = run_dispatch("3", ["alpha", "1", "3", "1,2"])
    check("item3 version table shown", "Version ID" in out and "1.2." in out, out[:300])

    # Item 1: search → select #2 → purchase (saves to Purchased)
    out = run_dispatch("1", ["alpha", "2"])
    check("item1 purchase saved", any(e["appid"] == "222" for e in library.load_list("Purchased")),
          str(library.load_list("Purchased")))

    # Item 5: enter ids → download latest
    out = run_dispatch("5", ["111"])
    check("item5 download via id ok", "File saved" in out, out[-160:])

    # Item 10: list Apps min-iOS table
    out = run_dispatch("10", [])
    check("item10 lists min-iOS", "Min. iOS" in out and "14.0+" in out, out[:300])

    # Item 12 → option 1: clear downloaded list
    out = run_dispatch("12", ["1"])
    check("item12 cleared downloaded list", library.load_list("Downloaded") == [])

    # Item 15: toggle language EN→RU
    run_dispatch("15", [])
    check("item15 toggled language", tui._state["lang"] == "RU", tui._state["lang"])

    # invalid choice
    out = run_dispatch("99", [])
    check("invalid choice -> error", "Invalid input" in out or "Неверный" in out, out[:120])


def test_install_no_device(tmp: Path, fake_ipatool: Path, bind: Path):
    print("install flow without a device")
    apps_dir = tmp / "Apps4"
    apps_dir.mkdir()
    config.APPS_DIR = apps_dir
    make_ipa(apps_dir / "Alpha_1.0_iOS_14.0+.ipa")
    # idevice_id that reports NO devices
    no_dev = bind / "idevice_id_empty"
    write_exec(no_dev, "#!/bin/sh\nexit 0\n")
    config.IDEVICE_ID = str(no_dev)
    tui._state["lang"] = "EN"
    out = run_dispatch("11", ["1"])
    check("item11 warns no device", "No device" in out, out[:200])


def main() -> int:
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        bind = tmp / "bin"
        bind.mkdir()
        acct = tmp / "account"
        os.environ["IPA_TEST_ACCOUNT"] = str(acct)
        acct.write_text("fake")  # logged-in state
        config.ACCOUNT_FILE = acct
        config.COOKIES_FILE = tmp / "cookies"

        fake_ipatool = bind / "ipatool"
        write_exec(fake_ipatool, FAKE_IPATOOL)
        write_exec(bind / "ideviceinstaller", FAKE_TRUE)
        write_exec(bind / "idevice_id", FAKE_IDEVICE_ID)
        write_exec(bind / "idevicepair", FAKE_TRUE)
        config.IDEVICEINSTALLER = str(bind / "ideviceinstaller")
        config.IDEVICE_ID = str(bind / "idevice_id")
        config.IDEVICEPAIR = str(bind / "idevicepair")

        test_parse_selection()
        test_library(tmp)
        test_ipatool(tmp, fake_ipatool)
        test_tui(tmp, fake_ipatool)
        test_install_no_device(tmp, fake_ipatool, bind)

    print()
    if _failures:
        print(f"FAILED: {len(_failures)} check(s)")
        for f in _failures:
            print("  - " + f)
        return 1
    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
