"""ipa_install — macOS port of IPA_Downloader.

A stdlib-only Python 3 terminal app that logs into the App Store with an Apple ID,
downloads app IPAs (latest or a chosen older version) via ``ipatool`` (ipatool-cpp),
and installs them onto a connected iPhone/iPad over USB via ``ideviceinstaller``.

Entry point: ``python3 -m ipa_install`` → :func:`ipa_install.tui.main`.
"""

__version__ = "0.1.0"
