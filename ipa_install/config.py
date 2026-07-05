"""Paths, binary resolution, and small persistent settings for ipa_install.

This module holds no logic of its own beyond locating things on disk. Everything
is computed relative to the project root (the parent of this package) so the tool
works regardless of the current working directory.

Guardrail: nothing here ever reads, writes, or logs Apple ID credentials, the
keychain passphrase, cookies, or the contents of ``~/.ipatool``. We only test for
the *presence* of ``~/.ipatool/account`` to know whether a session exists.
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
# PROJECT_ROOT = the repo root that contains bin/, Apps/, Lists/, assets/.
PROJECT_ROOT = Path(__file__).resolve().parent.parent

BIN_DIR = PROJECT_ROOT / "bin"
APPS_DIR = PROJECT_ROOT / "Apps"
LISTS_DIR = PROJECT_ROOT / "Lists"
ASSETS_DIR = PROJECT_ROOT / "assets"

# ipatool's own session store (managed by ipatool itself). Outside the repo tree.
IPATOOL_HOME = Path.home() / ".ipatool"
ACCOUNT_FILE = IPATOOL_HOME / "account"
COOKIES_FILE = IPATOOL_HOME / "cookies"

LANG_CONFIG_FILE = PROJECT_ROOT / "Lang_Config.txt"
PURCHASED_LIST = LISTS_DIR / "Purchased_IDs.json"
DOWNLOADED_LIST = LISTS_DIR / "Downloaded_IDs.json"
OWNED_SCAN = LISTS_DIR / "Owned_scan.json"
APPS_ID_LIST_TXT = ASSETS_DIR / "Apps_ID_List.txt"

GITHUB_URL = "https://github.com/kda2495/IPA_Downloader"


# ── Binary resolution ──────────────────────────────────────────────────────────
def resolve_binary(name: str) -> str:
    """Resolve a backend binary: prefer project-local ``bin/<name>``, else PATH.

    Returns an absolute path when found, otherwise the bare ``name`` (so callers
    still produce a sensible error if it is genuinely absent).
    """
    local = BIN_DIR / name
    try:
        if local.exists() and os.access(local, os.X_OK):
            return str(local)
    except OSError:
        pass
    found = shutil.which(name)
    if found:
        return found
    return name


IPATOOL = resolve_binary("ipatool")
IDEVICEINSTALLER = resolve_binary("ideviceinstaller")
IDEVICE_ID = resolve_binary("idevice_id")
IDEVICEPAIR = resolve_binary("idevicepair")


def _is_usable(path: str) -> bool:
    """True if ``path`` points at an executable file or is resolvable on PATH."""
    p = Path(path)
    if p.is_absolute():
        return p.exists() and os.access(p, os.X_OK)
    return shutil.which(path) is not None


def missing_binaries() -> list[str]:
    """Names of the *required* backends that could not be located.

    Only the two essential tools are required to start: ``ipatool`` (download) and
    ``ideviceinstaller`` (install). The ``idevice_id``/``idevicepair`` helpers are
    only needed for device operations and are reported lazily by ``device.py``.
    """
    required = {
        "ipatool": IPATOOL,
        "ideviceinstaller": IDEVICEINSTALLER,
    }
    return [name for name, path in required.items() if not _is_usable(path)]


# ── Startup housekeeping ────────────────────────────────────────────────────────
def ensure_dirs() -> None:
    """Create the directories the tool expects (mirrors the original's startup)."""
    for d in (APPS_DIR, LISTS_DIR, IPATOOL_HOME):
        try:
            d.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass


def cleanup_tmp() -> None:
    """Delete stray ``*.ipa.tmp`` files left by interrupted resumable downloads."""
    for base in (PROJECT_ROOT, APPS_DIR):
        try:
            for tmp in base.glob("*.ipa.tmp"):
                try:
                    tmp.unlink()
                except OSError:
                    pass
        except OSError:
            pass


def is_logged_in() -> bool:
    """Logged in iff ipatool has a saved account file (same gate as the original)."""
    return ACCOUNT_FILE.exists()


# ── Language persistence (Lang_Config.txt: one line, "RU" or "EN") ──────────────
def load_language() -> str:
    """Return the saved UI language ("RU"/"EN"), defaulting to "RU".

    Creates the config file with the default when it is missing. Never raises.
    """
    try:
        if LANG_CONFIG_FILE.exists():
            saved = LANG_CONFIG_FILE.read_text(encoding="utf-8").strip().upper()
            if saved in ("RU", "EN"):
                return saved
        else:
            save_language("RU")
    except OSError:
        pass
    return "RU"


def save_language(lang: str) -> None:
    """Persist the UI language. Only "RU"/"EN" are accepted; others are ignored."""
    lang = (lang or "").strip().upper()
    if lang not in ("RU", "EN"):
        return
    try:
        LANG_CONFIG_FILE.write_text(lang + "\n", encoding="utf-8")
    except OSError:
        pass
