# ipatool‑cpp reference (the download engine)

- **Repo:** https://github.com/Sorvigolova/ipatool (commit `74f4247161c48aa836d8dea4fe028c0acb3e4ed9`, pinned — `bin/ipatool` is built from it)
- **Local clone:** `/Users/dmitriy/code/archive/ipatool-cpp` (re-clone from GitHub if missing)
- **Language/deps:** C++ · libcurl · OpenSSL · nlohmann/json · minizip
- **Why this fork:** exact engine the original bundles; proven with `ideviceinstaller`; has
  `get-version-metadata` (majd's Go ipatool does not).

> Source of truth is the repo's own `README.md` + `main.cpp`. Details below are transcribed from
> them; **confirm JSON key names at runtime** before hard‑coding parsers.

## Build (macOS)

```sh
brew install curl nlohmann-json minizip openssl@3 cmake   # already installed in this env

cmake -S /Users/dmitriy/code/ipatool-cpp -B /Users/dmitriy/code/ipatool-cpp/build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-Dexplicit_bzero=bzero" \
  -DCMAKE_CXX_FLAGS="-Dexplicit_bzero=bzero" \
  -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" \
  -DOPENSSL_USE_STATIC_LIBS=TRUE
cmake --build /Users/dmitriy/code/ipatool-cpp/build -j

# output: /Users/dmitriy/code/ipatool-cpp/build/ipatool  → copy to ipa_install_claude/bin/ipatool
```

⚠️ **Doc bug in upstream README:** its macOS snippet uses `^` line continuations (Windows `cmd`
syntax). On macOS/zsh use `\` (as above) or put it all on one line.

`IOKit`/`CoreFoundation` are built into macOS (used for the hardware ID); no extra deps.
Apple Silicon: not explicitly advertised but the CMake build has no arch restrictions — build native
arm64. No prebuilt binaries are published; you must compile.

## CLI surface

```
ipatool [global flags] <command> [flags]

Commands:
  auth login            Authenticate with the App Store
  auth info             Show currently saved account info
  auth revoke           Delete saved credentials
  search                Search for apps on the App Store
  purchase              Acquire a free app license
  download              Download an app IPA
  list-versions         List available versions of an app
  get-version-metadata  Get metadata for a specific app version

Global flags:
  --format text|json        Output format (default: text). USE json FOR PARSING.
  --keychain-passphrase     Optional extra passphrase for the encrypted account file
  --debug                   Print raw server responses (troubleshooting)
```

### auth login
```
ipatool auth login -e EMAIL -p PASSWORD [--auth-code CODE] [--keychain-passphrase PASS]
```
- Saves `~/.ipatool/account` (always encrypted, **machine‑bound** via hardware ID).
- 2FA: omit `--auth-code` → prompted interactively. (TUI must keep stdin attached, or collect the
  code and pass `--auth-code`.)

### auth info / auth revoke
```
ipatool auth info [--keychain-passphrase PASS]   # shows name + email of saved account
ipatool auth revoke                              # deletes ~/.ipatool/account
```

### search
```
ipatool search <term> [-l LIMIT]                 # default limit 5; original uses -l 20
```

### purchase
```
ipatool purchase (-b BUNDLE_ID | -i APP_ID)      # acquire free license; run once before downloading
```
Paid apps cannot be "purchased" here — they must already be in the account's library.

### download
```
ipatool download (-b BUNDLE_ID | -i APP_ID) [-o OUTPUT] [--external-version-id ID] [--purchase]
```
- `-i` uses the numeric App Store ID directly (skips iTunes lookup); `-b` looks up by bundle id.
- `-o` is a file path or directory (defaults to CWD).
- Output filename format: **`{bundleID}_{appID}_{version}.ipa`**.
- `--purchase` auto‑acquires the license if needed, then downloads.
- **Resumable**: interrupted downloads leave `*.ipa.tmp`; re‑run continues. (Clean stray `.ipa.tmp`
  on startup, like the original.)
- TTY progress bar: `Downloading:  42% | ... | (50/119 MB, 8.3 MB/s)`.
- **IPA patching** (what makes it installable) — writes into the zip:
  - `iTunesMetadata.plist` (full account info, purchase date, `com.apple.iTunesStore.downloadInfo`)
  - `iTunesArtwork` (600×600 PNG icon, no extension)
  - **Sinf DRM token** → `Payload/<App>.app/SC_Info/` (the per‑Apple‑ID license)

### list-versions / get-version-metadata
```
ipatool list-versions (-b BUNDLE_ID | -i APP_ID)                      # all external version IDs
ipatool get-version-metadata (-b|-i) --external-version-id ID         # display version + release date
```
Together these drive the "download a specific older version" (downgrade) flow.

## Session / credentials

| File | Notes |
|---|---|
| `~/.ipatool/account` | encrypted credentials, bound to this machine's hardware ID |
| `~/.ipatool/cookies` | libcurl cookie jar (`CookieJarFileName` constant in source) |

Home dir resolved from `$HOME` (`getenv("HOME")`) on macOS — same `~/.ipatool` path as Windows uses
via `%USERPROFILE%`. Treat presence of `~/.ipatool/account` as the "logged in" signal.

## Confirmed JSON output shapes (read from `main.cpp`, 2026‑06‑14)

Build succeeded on this Mac (Apple Silicon, OpenSSL static, `-Dexplicit_bzero=bzero`) → 4.8 MB
`bin/ipatool`. The `--format json` output keys were read directly from the command handlers in
`main.cpp` and are now pinned in `ipa_install/ipatool.py`:

| command | exact stdout JSON (one line) | notes |
|---|---|---|
| `auth login` | `{"name","email","success":true}` | we run it **attached** (interactive password/2FA), not via JSON capture |
| `auth info` | `{"name","email","success":true}` | |
| `auth revoke` | `{"success":true}` | `Not logged in.`→stderr+exit 1 when no session |
| `search` | `{"count":N,"apps":[{"id","bundleID","name","version","price"}]}` | `id`/`price` may be JSON numbers → **coerce to str** |
| `purchase` | `Purchasing: <name> (<bundle>)\n` **then** `{"success":true}` | a **non‑JSON line precedes** the JSON → parser scans stdout lines for the object |
| `download` | `{"output","purchased":bool,"success":true}` | progress bar drawn to **stderr only when stdout is a TTY**; we instead run attached (native bar) and locate the new file by directory diff |
| `list-versions` | `{"externalVersionIdentifiers":[...],"bundleID","success":true}` | `bundleID` is empty when `-i APP_ID` is used; identifiers may be numbers → **coerce to str** |
| `get-version-metadata` | `{"externalVersionID","displayVersion","releaseDate","success":true}` | |

Arg‑parser quirk (custom parser in `main.cpp`): a `--flag` whose next token starts with `-` (or is
absent) is set to the literal `"true"`; a value beginning with `-` is **not** consumed. So put
boolean flags like `--purchase` **last**, and never pass values that start with `-`. Two‑word
commands (`auth login`/`auth info`/`auth revoke`) come from positionals, so `--format json` may
appear anywhere.

## Output format notes (from `main.cpp`)

- Global `g_format` defaults to `"text"`; `--format json` switches to raw JSON.
- `log_output()` emits either zerolog‑style console text or `{"key":"value",...}` JSON.
- `search` emits a JSON **array** of apps mirroring the original zerolog structure.
- **Action item for the implementer:** run each command once with `--format json`, capture the exact
  keys (e.g. for an app object: id / bundleID / name / version / price — *verify*), and pin those in
  `ipatool.py`. Use `--debug` if a response is unclear.

## Fallback engine

If the C++ build ever breaks: `brew install ipatool` (majd, Go) provides `auth/search/purchase/
download/list-versions` and a `--format json` flag, but **no `get-version-metadata`**. The
version‑selection UI degrades to "list IDs, pick one" without the human version/date preview.
