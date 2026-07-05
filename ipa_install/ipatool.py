"""Thin Python wrapper around the ``ipatool`` (ipatool-cpp) download engine.

Every backend call goes through the absolute path resolved in :mod:`config`, with
arguments passed as a list (never a shell string). Machine-readable commands run
with ``--format json`` and parse the JSON object out of stdout; the two
interactive/streaming commands (``auth login`` and ``download``) deliberately run
*attached* to the terminal so ipatool can draw its hidden-password / 2FA prompts
and native progress bar.

Guardrail: the Apple ID password and the 2FA ``--auth-code`` are never echoed,
stored, or placed into any exception message. We only ever forward them straight
to the subprocess argv.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Union

from . import config


class IpatoolError(Exception):
    """Raised when an ipatool invocation fails or returns no usable JSON."""


# ── Result shapes (decoupled from ipatool's raw JSON keys) ──────────────────────
@dataclass
class App:
    """A single search result row."""

    id: str
    bundle_id: str
    name: str
    version: str
    price: str


@dataclass
class DownloadResult:
    """Outcome of a download: the saved file path and whether we purchased first."""

    output: str
    purchased: bool


@dataclass
class VersionMeta:
    """Metadata for one historical app version."""

    external_version_id: str
    display_version: str
    release_date: str


# ── JSON helper ─────────────────────────────────────────────────────────────────
def _run_json(cmd_args: list) -> dict:
    """Run ``ipatool --format json <cmd_args>`` and return the parsed JSON object.

    On a non-zero exit we surface ipatool's own stderr/stdout text. Some commands
    (notably ``purchase``) print a human line *before* the JSON, so if the whole
    stream is not valid JSON we scan stdout bottom-up for the first line that is a
    JSON object — that is the result, and later lines win over earlier noise.
    """
    args = [config.IPATOOL, "--format", "json", *cmd_args]
    proc = subprocess.run(args, capture_output=True, text=True, encoding="utf-8")
    if proc.returncode != 0:
        message = (proc.stderr or "").strip() or (proc.stdout or "").strip() or "ipatool failed"
        raise IpatoolError(message)

    stdout = proc.stdout or ""
    # Fast path: the entire stream is a single JSON document.
    try:
        return json.loads(stdout)
    except (ValueError, json.JSONDecodeError):
        pass

    # Slow path: find the JSON object among other printed lines (bottom-up).
    for line in reversed(stdout.splitlines()):
        stripped = line.strip()
        if not stripped.startswith("{"):
            continue
        try:
            return json.loads(stripped)
        except (ValueError, json.JSONDecodeError):
            continue

    raise IpatoolError("ipatool returned no parseable JSON")


# ── Authentication ──────────────────────────────────────────────────────────────
def auth_login(
    email: str,
    password: Optional[str] = None,
    auth_code: Optional[str] = None,
) -> None:
    """Log in to the App Store.

    Runs ipatool with stdin/stdout/stderr *inherited* (not captured) so it can
    prompt for the password and 2FA code interactively on the terminal. Pass
    ``password``/``auth_code`` only when you already have them; they are forwarded
    to argv and never logged or stored.
    """
    args = [config.IPATOOL, "auth", "login", "-e", email]
    if password:
        args += ["-p", password]
    if auth_code:
        args += ["--auth-code", auth_code]
    # Attached: no capture_output, so ipatool owns the terminal for its prompts.
    proc = subprocess.run(args)
    if proc.returncode != 0:
        # Deliberately generic — never reference the secret arguments.
        raise IpatoolError("login failed")
    return None


def auth_info() -> dict:
    """Return the current session info ``{"name","email","success"}``."""
    return _run_json(["auth", "info"])


def auth_revoke() -> None:
    """Log out. Quietly succeeds when there is no active session to revoke."""
    args = [config.IPATOOL, "auth", "revoke"]
    # Capture so a "Not logged in." failure doesn't spill onto the screen.
    subprocess.run(args, capture_output=True, text=True, encoding="utf-8")
    return None


# ── Search / purchase / download / versions ─────────────────────────────────────
def search(term: str, limit: int = 20) -> list:
    """Search the App Store and return up to ``limit`` :class:`App` rows."""
    data = _run_json(["search", term, "-l", str(limit)])
    results = []
    for a in data.get("apps", []) or []:
        results.append(
            App(
                id=str(a.get("id", "")),
                bundle_id=a.get("bundleID", ""),
                name=a.get("name", ""),
                version=a.get("version", ""),
                price=str(a.get("price", "")),
            )
        )
    return results


def purchase(app_id: str) -> None:
    """Acquire a (free) license for ``app_id`` without downloading it."""
    data = _run_json(["purchase", "-i", str(app_id)])
    if not data.get("success"):
        raise IpatoolError("purchase failed")
    return None


def download(
    app_id: str,
    output_dir: Union[str, Path],
    external_version_id: Optional[str] = None,
    purchase: bool = True,
) -> DownloadResult:
    """Download an app's IPA into ``output_dir`` and return the saved file path.

    This intentionally does *not* use ``--format json``: ipatool draws a live
    progress bar when attached to a TTY, so we run with stdin/stdout/stderr
    inherited. To identify the produced file unambiguously, ipatool writes into
    a private temp subdirectory (so the only ``*.ipa`` there is ours), and the
    finished file is then moved up into ``output_dir``. A failed/aborted run
    therefore never leaves partial files in ``output_dir`` either.
    """
    out_dir = Path(output_dir)
    tmp_dir = out_dir / f".dl-{os.getpid()}-{uuid.uuid4().hex[:8]}"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    args = [config.IPATOOL, "download", "-i", str(app_id), "-o", str(tmp_dir)]
    if external_version_id is not None:
        args += ["--external-version-id", str(external_version_id)]
    if purchase:
        # Boolean flag goes last so ipatool's parser doesn't swallow a following value.
        args += ["--purchase"]

    try:
        # Attached run: lets the native progress bar render to the user's terminal.
        proc = subprocess.run(args)
        if proc.returncode != 0:
            raise IpatoolError("download failed")

        produced = sorted(
            tmp_dir.glob("*.ipa"),
            key=lambda p: p.stat().st_mtime,
        )
        if not produced:
            raise IpatoolError("download produced no file")

        # Same app+version re-downloaded → same name; replacing is the intent.
        final = out_dir / produced[-1].name
        produced[-1].replace(final)
        return DownloadResult(output=str(final), purchased=purchase)
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def list_versions(app_id: str) -> list:
    """Return all available external version identifiers for ``app_id`` as strings."""
    data = _run_json(["list-versions", "-i", str(app_id)])
    return [str(v) for v in data.get("externalVersionIdentifiers", []) or []]


def get_version_metadata(app_id: str, external_version_id: str) -> VersionMeta:
    """Return display version / release date for a specific historical version."""
    data = _run_json(
        [
            "get-version-metadata",
            "-i",
            str(app_id),
            "--external-version-id",
            str(external_version_id),
        ]
    )
    return VersionMeta(
        external_version_id=str(data.get("externalVersionID", external_version_id)),
        display_version=data.get("displayVersion", ""),
        release_date=data.get("releaseDate", ""),
    )
