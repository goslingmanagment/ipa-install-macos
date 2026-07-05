"""Local IPA inspection, friendly naming, and saved-list bookkeeping.

This module never touches the network. It reads metadata out of downloaded ``.ipa``
files (a zip with a single ``Payload/<App>.app/Info.plist``), produces the same
human-friendly filenames the original tool used, and maintains the two saved-list
JSON files plus the bundled offline "GitHub" app-id list.

List files are kept byte-compatible with the Windows original: a JSON array of
``{"name": ..., "appid": ...}`` objects (lowercase keys), so lists can move between
the two tools unchanged.
"""

from __future__ import annotations

import json
import plistlib
import re
import zipfile
from dataclasses import dataclass
from pathlib import Path

from . import config


class LibraryError(Exception):
    """Raised when an ``.ipa`` cannot be opened or its Info.plist read."""


@dataclass
class IpaInfo:
    """What we know about a single ``.ipa`` on disk."""

    path: Path
    name: str
    version: str
    min_ios: str
    bundle_id: str


# First-level app bundle's Info.plist inside the IPA payload.
_INFO_PLIST_RE = re.compile(r"^Payload/[^/]+\.app/Info\.plist$")
# Characters that are illegal / unsafe in filenames across platforms.
_BAD_FILENAME_CHARS = set('\\/:*?"<>|')


# ── IPA metadata ────────────────────────────────────────────────────────────────
def read_ipa_metadata(ipa_path: str | Path) -> IpaInfo:
    """Read display name / version / min-iOS / bundle id from an ``.ipa``.

    Raises ``LibraryError`` on any failure (bad zip, missing Info.plist, unparsable
    plist) so callers can fall back to a best-effort listing.
    """
    ipa_path = Path(ipa_path)
    try:
        with zipfile.ZipFile(ipa_path) as zf:
            member = next(
                (n for n in zf.namelist() if _INFO_PLIST_RE.match(n)), None
            )
            if member is None:
                raise LibraryError(f"no Info.plist in {ipa_path.name}")
            plist = plistlib.loads(zf.read(member))
    except LibraryError:
        raise
    except Exception as exc:  # zip/plist/OS errors → uniform failure
        raise LibraryError(f"cannot read {ipa_path.name}: {exc}") from exc

    name = plist.get("CFBundleName") or plist.get("CFBundleDisplayName") or ""
    return IpaInfo(
        path=ipa_path,
        name=name,
        version=plist.get("CFBundleShortVersionString", ""),
        min_ios=plist.get("MinimumOSVersion", ""),
        bundle_id=plist.get("CFBundleIdentifier", ""),
    )


def list_apps() -> list[IpaInfo]:
    """Describe every ``*.ipa`` in ``Apps/`` (shared by menu items 10 and 11).

    Files whose metadata can't be read still appear, with the filename stem as the
    name and empty fields. Sorted by name (case-insensitive) then filename.
    """
    infos: list[IpaInfo] = []
    try:
        ipas = sorted(config.APPS_DIR.glob("*.ipa"))
    except OSError:
        return infos
    for ipa in ipas:
        try:
            infos.append(read_ipa_metadata(ipa))
        except LibraryError:
            infos.append(
                IpaInfo(path=ipa, name=ipa.stem, version="", min_ios="", bundle_id="")
            )
    infos.sort(key=lambda i: (i.name.lower(), i.path.name))
    return infos


# ── Friendly filenames ──────────────────────────────────────────────────────────
def sanitize_filename(s: str) -> str:
    """Strip filename-illegal chars and collapse whitespace runs to a single ``_``."""
    cleaned = "".join(ch for ch in s if ch not in _BAD_FILENAME_CHARS).strip()
    return re.sub(r"\s+", "_", cleaned)


def friendly_ipa_name(info: IpaInfo) -> str:
    """Build ``<Name>_<version>_iOS_<min>+.ipa`` with no whitespace left in it.

    Callers must supply a non-empty ``info.name`` (``finalize_download`` resolves a
    fallback first); the name itself is sanitized here.
    """
    base = f"{sanitize_filename(info.name)}_{info.version}_iOS_{info.min_ios}+.ipa"
    return re.sub(r"\s+", "_", base)


def finalize_download(
    output_path: str | Path,
    fallback_name: str | None = None,
    app_id: str | None = None,
) -> IpaInfo:
    """Rename a freshly-downloaded ``.ipa`` to its friendly name, in ``Apps/``.

    Reads metadata from ``output_path``; if the embedded name is empty, falls back to
    ``fallback_name`` then to the offline name list keyed by the numeric ``app_id``
    (matching the original's ``Get-GitHub-AppName -AppId``). The file is renamed only
    when the target differs and does not already exist; otherwise the original path is
    kept. Returns an ``IpaInfo`` pointing at the final location. Robust to unreadable
    metadata: returns a best-effort ``IpaInfo`` in that case.
    """
    output_path = Path(output_path)
    try:
        info = read_ipa_metadata(output_path)
    except LibraryError:
        # Metadata unreadable: keep the file where ipatool put it.
        name = fallback_name or (github_name(app_id) if app_id else None) or output_path.stem
        return IpaInfo(
            path=output_path, name=name, version="", min_ios="", bundle_id=""
        )

    if not info.name:
        # Prefer the caller's fallback; else the offline list keyed by numeric app id.
        info.name = fallback_name or (github_name(app_id) if app_id else None) or ""
    if not info.name:
        # Nothing to base a friendly name on — leave the file untouched.
        return info

    friendly = friendly_ipa_name(info)
    target = config.APPS_DIR / friendly
    if target.name != output_path.name and not target.exists():
        try:
            output_path.rename(target)
            info.path = target
        except OSError:
            # Rename failed (permissions, cross-volume, race): keep original path.
            pass
    return info


# ── Saved lists (original-compatible JSON: [{"name","appid"}, ...]) ──────────────
def _list_path(kind: str) -> Path:
    """Map a list ``kind`` to its on-disk JSON file."""
    return config.PURCHASED_LIST if kind == "Purchased" else config.DOWNLOADED_LIST


def load_list(kind: str) -> list[dict]:
    """Load a saved list ("Purchased"/"Downloaded"); ``[]`` if missing/invalid."""
    path = _list_path(kind)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    if not isinstance(data, list):
        return []
    return [e for e in data if isinstance(e, dict)]


def save_to_list(app_id: str, name: str, kind: str) -> str:
    """Add ``{name, appid}`` to a list, deduped by appid.

    Returns ``"skipped"`` for a blank or ``"Unknown"`` name (the original
    ``Save-App-To-List`` does not record those), ``"already"`` if the appid is
    present, else ``"added"`` after appending, sorting by name (case-insensitive)
    and writing UTF-8 JSON (``ensure_ascii=False``).
    """
    name = (name or "").strip()
    if not name or name == "Unknown":
        return "skipped"
    app_id = str(app_id)
    entries = load_list(kind)
    if any(str(e.get("appid")) == app_id for e in entries):
        return "already"
    entries.append({"name": name, "appid": app_id})
    entries.sort(key=lambda e: str(e.get("name", "")).lower())
    path = _list_path(kind)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8") as fh:
            json.dump(entries, fh, ensure_ascii=False, indent=2)
    except OSError:
        pass
    return "added"


def clear_list(kind: str) -> None:
    """Delete a saved list file; ignore if it is already absent."""
    try:
        _list_path(kind).unlink()
    except OSError:
        pass


def clear_apps() -> bool:
    """Delete every ``*.ipa`` in ``Apps/``; return True iff at least one was removed."""
    deleted = 0
    try:
        ipas = list(config.APPS_DIR.glob("*.ipa"))
    except OSError:
        return False
    for ipa in ipas:
        try:
            ipa.unlink()
            deleted += 1
        except OSError:
            pass
    return deleted >= 1


# ── Offline "GitHub" name list (assets/Apps_ID_List.txt) ─────────────────────────
# Lines look like ``Some App Name: 123456789``; parsed once and cached here.
_GITHUB_LIST_CACHE: list[dict] | None = None
_GITHUB_LINE_RE = re.compile(r"^(.+?):\s*(\d+)")


def github_list() -> list[dict]:
    """Parse the bundled app-id list into ``[{"Name","Id"}, ...]`` (cached).

    Returns ``[]`` when the file is missing or unreadable.
    """
    global _GITHUB_LIST_CACHE
    if _GITHUB_LIST_CACHE is not None:
        return _GITHUB_LIST_CACHE
    entries: list[dict] = []
    try:
        text = config.APPS_ID_LIST_TXT.read_text(encoding="utf-8")
    except OSError:
        _GITHUB_LIST_CACHE = entries
        return entries
    for line in text.splitlines():
        m = _GITHUB_LINE_RE.match(line)
        if m:
            entries.append({"Name": m.group(1).strip(), "Id": m.group(2).strip()})
    _GITHUB_LIST_CACHE = entries
    return entries


def github_name(app_id: str) -> str | None:
    """Return the offline-list Name for ``app_id``, or None if not present."""
    app_id = str(app_id)
    for entry in github_list():
        if entry.get("Id") == app_id:
            return entry.get("Name")
    return None
