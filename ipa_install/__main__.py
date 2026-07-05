"""``python3 -m ipa_install`` → run the terminal UI."""

import sys

from .tui import main

if __name__ == "__main__":
    sys.exit(main())
