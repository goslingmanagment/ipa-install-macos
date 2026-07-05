"""Device side: list, pair, and install onto a connected iPhone/iPad over USB.

Thin wrappers around the libimobiledevice binaries resolved in :mod:`config`:
``idevice_id`` (enumerate), ``idevicepair`` (pair/validate trust), and
``ideviceinstaller`` (install an ``.ipa``). The install step is the whole point
of the tool — see ``IPA_Downloader.ps1:981`` for the original's single line.

These functions never touch Apple ID credentials; they speak only USB/usbmuxd.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

from . import config


class DeviceError(Exception):
    """Raised when a libimobiledevice binary is missing or cannot be launched."""


def list_devices() -> list[str]:
    """Return the UDIDs of connected, trusted devices (``idevice_id -l``).

    A non-zero exit with no output means "no devices" → ``[]``. A missing or
    unlaunchable binary is a real problem → ``DeviceError``.
    """
    try:
        proc = subprocess.run(
            [config.IDEVICE_ID, "-l"],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
    except (FileNotFoundError, OSError) as exc:
        raise DeviceError(f"idevice_id not available: {exc}") from exc
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def pair_validate(udid: str | None = None) -> bool:
    """True if the device is already paired/trusted (``idevicepair validate``).

    Returns ``False`` for the ordinary not-yet-paired case — it never raises on
    that, since "not paired" is a normal, expected outcome the caller handles.
    """
    cmd = [config.IDEVICEPAIR]
    if udid:
        cmd += ["-u", udid]
    cmd += ["validate"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    except (FileNotFoundError, OSError) as exc:
        raise DeviceError(f"idevicepair not available: {exc}") from exc
    return proc.returncode == 0


def pair(udid: str | None = None) -> tuple[bool, str]:
    """Pair with the device (``idevicepair pair``); user must tap "Trust".

    Returns ``(ok, message)`` where ``message`` is the combined stdout+stderr so
    the caller can surface libimobiledevice's own guidance on failure.
    """
    cmd = [config.IDEVICEPAIR]
    if udid:
        cmd += ["-u", udid]
    cmd += ["pair"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    except (FileNotFoundError, OSError) as exc:
        raise DeviceError(f"idevicepair not available: {exc}") from exc
    message = ((proc.stdout or "") + (proc.stderr or "")).strip()
    return proc.returncode == 0, message


def install(ipa_path: str | Path, udid: str | None = None) -> tuple[bool, str]:
    """Install an ``.ipa`` onto the device (``ideviceinstaller install``).

    Streams are inherited (not captured) so the user sees ideviceinstaller's
    native progress output live in the terminal. Returns ``(ok, "")`` — the empty
    string keeps the signature uniform with :func:`pair` while there is nothing
    extra to report once output went straight to the console.

    Note: the original Windows tool copied the IPA to a temp path before
    installing as a workaround; on macOS we install the file directly and
    intentionally drop that copy-to-temp step.
    """
    cmd = [config.IDEVICEINSTALLER]
    if udid:
        cmd += ["-u", udid]
    cmd += ["install", str(ipa_path)]
    try:
        # No capture: stdout/stderr are inherited so the user sees live progress.
        proc = subprocess.run(cmd)
    except (FileNotFoundError, OSError) as exc:
        raise DeviceError(f"ideviceinstaller not available: {exc}") from exc
    return proc.returncode == 0, ""
