# macOS toolchain

## Verified environment (this machine, 2026‑06‑14)

- **Hardware/OS:** Apple Silicon (arm64), Homebrew prefix `/opt/homebrew`, Darwin 25.5.0 (macOS Tahoe).
- **Installed & confirmed working:**

| Tool | Version | Source |
|---|---|---|
| ideviceinstaller | 1.2.0 | `brew` (pulls `libimobiledevice`, `libplist`, `libzip`) |
| cmake | 4.3.3 | `brew` |
| nlohmann-json | 3.12.0 | `brew` |
| minizip | 1.3.2_1 | `brew` |
| openssl@3 | 3.x (`brew --prefix openssl@3`) | `brew` |
| python3 | 3.14.4 | `brew` |
| git | 2.50.1 (Apple Git‑155) | Xcode CLT |

All Homebrew bottles were `arm64_tahoe` (native, no Rosetta).

## Bootstrap from scratch (fresh Mac)

```sh
# 1. Homebrew (if missing): https://brew.sh
# 2. Backend + build deps
brew install ideviceinstaller cmake nlohmann-json minizip openssl@3

# 3. Get the download engine source
git clone https://github.com/Sorvigolova/ipatool.git ~/code/ipatool-cpp
# (pin for reproducibility) git -C ~/code/ipatool-cpp checkout 74f4247

# 4. (reference, optional) the original
git clone https://github.com/kda2495/IPA_Downloader.git ~/code/IPA_Downloader
```

## Build ipatool‑cpp

```sh
cmake -S ~/code/ipatool-cpp -B ~/code/ipatool-cpp/build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-Dexplicit_bzero=bzero" \
  -DCMAKE_CXX_FLAGS="-Dexplicit_bzero=bzero" \
  -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" \
  -DOPENSSL_USE_STATIC_LIBS=TRUE
cmake --build ~/code/ipatool-cpp/build -j

# install into the project
mkdir -p ~/code/ipa-install-macos/bin
cp ~/code/ipatool-cpp/build/ipatool ~/code/ipa-install-macos/bin/ipatool
ln -sf "$(which ideviceinstaller)" ~/code/ipa-install-macos/bin/ideviceinstaller   # or copy
```

- Output binary: `~/code/ipatool-cpp/build/ipatool`.
- `-Dexplicit_bzero=bzero`: shim — macOS libc has `bzero`, not `explicit_bzero`.
- `OPENSSL_*`: point CMake at Homebrew's OpenSSL 3 and link it statically (macOS ships LibreSSL as
  `/usr/bin/openssl`, which is **not** what we want).
- ⚠️ Upstream README's macOS snippet uses Windows `^` continuations — use `\` as above.
- **Status: not yet built** (interrupted to write docs). This is Phase 0's last open item.

## Smoke tests

```sh
~/code/ipa-install-macos/bin/ipatool --help
~/code/ipa-install-macos/bin/ipatool --format json search "telegram" -l 3   # needs login first
ideviceinstaller --version          # expect: 1.2.0
idevice_id -l                       # list connected device UDIDs (empty if none)
```

## libimobiledevice tools you'll use

Installed alongside `ideviceinstaller` / `libimobiledevice`:

| Command | Use |
|---|---|
| `idevice_id -l` | list connected device UDIDs |
| `idevicepair pair` / `idevicepair validate` | pair / check trust with the Mac |
| `ideviceinfo` | device info (needs pairing) |
| `ideviceinstaller list` | apps installed on the device |
| `ideviceinstaller install <ipa>` | **install an IPA** |
| `ideviceinstaller uninstall <bundleid>` | remove an app |

> If device communication misbehaves, consider the `--HEAD` formulae
> (`brew install --HEAD libimobiledevice ideviceinstaller usbmuxd`) which track newer iOS support.
> Stable 1.2.0 / 1.4.0 are installed here; only switch to HEAD if a real device fails to talk.

## Suggested `.gitignore` (when the repo is initialized)

```
bin/
Apps/
Lists/
*.ipa
*.ipa.tmp
__pycache__/
.DS_Store
```
