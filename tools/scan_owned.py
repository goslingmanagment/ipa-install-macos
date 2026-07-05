#!/usr/bin/env python3
"""CLI wrapper around ipa_install.scan — probe which catalog apps this Apple ID owns,
classify the owned ones (removed-from-store vs in-store), and save the shared
Lists/Owned_scan.json (also read by the GUI and the TUI's menu 16).

  python3 tools/scan_owned.py            # full catalog
  python3 tools/scan_owned.py --limit 5  # first 5 (mechanism check)
  python3 tools/scan_owned.py --ids 6749261529,686449807
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from ipa_install import library, scan  # noqa: E402


def main() -> int:
    args = sys.argv[1:]
    limit = int(args[args.index("--limit") + 1]) if "--limit" in args else None
    ids = args[args.index("--ids") + 1].split(",") if "--ids" in args else None

    catalog = [(e["Id"], e["Name"]) for e in library.github_list()]
    if ids:
        names = {a: n for a, n in catalog}
        entries = [(i, names.get(i, "")) for i in ids]
    else:
        entries = catalog[:limit] if limit else catalog

    def on_progress(i, total, app_id, name, owned):
        print(f"[{i}/{total}] {'OWNED' if owned else 'no':5} {app_id}  {name}", flush=True)

    res = scan.scan_catalog(entries, on_progress=on_progress)
    scan.save_owned_scan(res["removed"], res["in_store"])

    print(f"\nowned: {len(res['owned'])} | removed: {len(res['removed'])} | "
          f"in_store: {len(res['in_store'])} | scanned: {res['scanned']}/{res['total']}")
    print(f"\n=== OWNED but REMOVED from the App Store ({len(res['removed'])}) ===")
    for e in sorted(res["removed"], key=lambda x: x["name"].lower()):
        print(f"  {e['appid']}  {e['name']}")
    print("\nsaved → Lists/Owned_scan.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
