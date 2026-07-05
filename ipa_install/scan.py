"""Ownership scan — which catalog apps does the signed-in Apple ID own, and which
of those are gone from the App Store.

This is the macOS-port addition that makes the bundled catalog actionable: it tells
you which of the ~462 known apps *this* Apple ID can re-download (it owns them), and
splits those into "removed from the App Store" (recoverable ONLY via this tool) vs
"still in the store".

Mechanism — ``ipatool download -i <id>`` WITHOUT ``--purchase``:
  • not owned → fails fast ("you must purchase this app first")
  • owned     → starts transferring the IPA

We watch a throwaway temp dir for the first file (or the process still running),
classify, and abort early — no IPA is kept, the project's ``Apps/`` is never touched.
Classifying owned apps (removed vs in-store) uses the PUBLIC iTunes Lookup API, so it
involves no Apple ID and carries no account risk.

Guardrail: a probe is a real (aborted) download request to Apple. Scanning the whole
catalog is hundreds of requests; callers must gate it behind explicit user consent and
keep the per-request delay. Recommended on a disposable Apple ID.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

from . import config

PROBE_SECS = 6.0   # max wait to detect a download starting
DELAY = 0.7        # pause between probes — be gentle on the account


def probe_ownership(app_id: str) -> bool:
    """True iff the signed-in Apple ID owns ``app_id`` (download starts without --purchase)."""
    base = Path(tempfile.mkdtemp(prefix="ipa_probe_"))
    outdir = base / "out"
    outdir.mkdir(parents=True, exist_ok=True)
    try:
        proc = subprocess.Popen(
            [config.IPATOOL, "--format", "json", "download", "-i", str(app_id), "-o", str(outdir)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
        )
        owned = False
        t0 = time.time()
        while proc.poll() is None and time.time() - t0 < PROBE_SECS:
            try:
                if any(outdir.iterdir()):
                    owned = True
                    break
            except OSError:
                pass
            time.sleep(0.15)
        if proc.poll() is None:           # still transferring after the window → owned
            owned = True
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        if not owned:                     # a tiny app may have finished within the window
            try:
                if any(outdir.iterdir()):
                    owned = True
            except OSError:
                pass
        return owned
    finally:
        shutil.rmtree(base, ignore_errors=True)


def store_availability(ids, country: str = "ru") -> set:
    """Subset of ``ids`` currently available in the ``country`` App Store storefront.

    Uses the public iTunes Lookup API (no Apple ID). Network failures degrade to
    "not found" for that chunk; callers treat absence as "removed".
    """
    found: set = set()
    ids = [str(i) for i in ids]
    for i in range(0, len(ids), 20):
        chunk = ids[i:i + 20]
        url = "https://itunes.apple.com/lookup?" + urllib.parse.urlencode(
            {"id": ",".join(chunk), "country": country}
        )
        try:
            with urllib.request.urlopen(url, timeout=20) as resp:
                data = json.load(resp)
            for res in data.get("results", []):
                tid = str(res.get("trackId", ""))
                if tid:
                    found.add(tid)
        except Exception:
            pass
        time.sleep(0.3)
    return found


def scan_catalog(entries, on_progress=None, should_cancel=None, delay: float = DELAY,
                 country: str = "ru") -> dict:
    """Find the catalog apps that are gone from the store, then probe ONLY those for ownership.

    We only care about apps removed from the App Store (the in-store ones can be
    installed normally), so step 1 filters the catalog via the free iTunes API (no
    account touched), and step 2 probes ownership only on the removed subset — far
    fewer requests against the Apple ID than probing the whole catalog.

    ``on_progress(i, removed_total, app_id, name, owned)`` is called after each probe;
    ``should_cancel()`` (if given) stops it early. Returns
    ``{"removed_owned", "removed_not_owned", "removed_total", "in_store_count",
    "scanned", "cancelled"}`` (app lists hold ``{"appid","name"}``).
    """
    # Step 1 — free, no account risk: which catalog apps are removed from the store.
    all_ids = [str(a) for a, _ in entries]
    in_store = store_availability(all_ids, country=country)
    removed_entries = [(str(a), n) for a, n in entries if str(a) not in in_store]

    # Step 2 — probe ownership ONLY on the removed apps.
    removed_owned: list[dict] = []
    removed_not_owned: list[dict] = []
    total = len(removed_entries)
    scanned = 0
    cancelled = False
    for i, (app_id, name) in enumerate(removed_entries, 1):
        if should_cancel and should_cancel():
            cancelled = True
            break
        owned = False
        try:
            owned = probe_ownership(app_id)
        except Exception:
            owned = False
        (removed_owned if owned else removed_not_owned).append({"appid": app_id, "name": name})
        scanned = i
        if on_progress:
            on_progress(i, total, app_id, name, owned)
        time.sleep(delay)

    return {
        "removed_owned": removed_owned,
        "removed_not_owned": removed_not_owned,
        "removed_total": total,
        "in_store_count": len(in_store),
        "scanned": scanned, "cancelled": cancelled,
    }


def save_owned_scan(removed_owned: list[dict], removed_not_owned: list[dict]) -> None:
    """Persist the scan to ``Lists/Owned_scan.json`` (shared with the GUI)."""
    try:
        config.OWNED_SCAN.parent.mkdir(parents=True, exist_ok=True)
        config.OWNED_SCAN.write_text(
            json.dumps({"removedOwned": removed_owned, "removedNotOwned": removed_not_owned},
                       ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except OSError:
        pass


def load_owned_scan() -> dict | None:
    """Load a previously saved scan, or ``None`` if absent/unreadable."""
    try:
        data = json.loads(config.OWNED_SCAN.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    return {
        "removedOwned": data.get("removedOwned", []) or [],
        "removedNotOwned": data.get("removedNotOwned", []) or [],
    }
