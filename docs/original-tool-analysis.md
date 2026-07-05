# Original tool analysis — IPA_Downloader (Windows)

Reverse‑engineered from the source so the macOS port stays faithful.

- **Repo:** https://github.com/kda2495/IPA_Downloader (commit `446a038`, pinned at analysis time)
- **Discussion:** 4PDA thread `showtopic=1119329` (Cloudflare‑gated; not readable by fetch tools)
- **License:** MIT
- **What it is:** a single PowerShell script (`IPA_Downloader.ps1`, ~1040 lines) driving a numbered
  menu, plus two bundled binaries and an app‑ID/name list.

## Repo contents

| File | Role |
|---|---|
| `IPA_Downloader.ps1` | the whole app: menu loop, i18n, file mgmt, calls the binaries |
| `MainApp/ipatool.exe` | **ipatool‑cpp** (Sorvigolova/ipatool) — download engine |
| `MainApp/ideviceinstaller.exe` | **libimobiledevice** — device installer |
| `MainApp/Lang_Config.txt` | one line: `RU` or `EN` (persisted language; bundled value is `RU`) |
| `Apps_ID_List.txt` | ~20 KB app‑ID → name map, lines like `App Name: 123456789` |
| `Start_IPA_Downloader.bat` | launcher |
| `README.md` / `README_EN.md` | docs (RU/EN) |

## Identity of the two binaries (verified)

- `ipatool.exe` → strings contain `ipatool-cpp` and `get-version-metadata`; README credits
  `ipatool-cpp` → it is **Sorvigolova/ipatool**, *not* majd's Go ipatool (which lacks
  `get-version-metadata`).
- `ideviceinstaller.exe` → libimobiledevice's installer.

## The 15‑item main menu → backend mapping

The main loop runs while `~/.ipatool/account` exists (i.e., while logged in). Menu (RU label / EN
label / what it does):

| # | RU | EN | Backend action |
|---|---|---|---|
| 1 | Поиск приложения и покупка (без загрузки) | Search for app and purchase (without downloading) | `search` → for each pick: `purchase -i <id>` |
| 2 | Поиск приложения и загрузка последней версии | Search and download latest version | `search` → `download -i <id>` |
| 3 | Поиск приложения и загрузка (с выбором версии) | Search and download (with version selection) | `search` → `list-versions` + `get-version-metadata` → `download -i <id> --external-version-id <vid>` |
| 4 | Ввод ID приложений и покупка (без загрузки) | Enter app IDs and purchase | for each id: `purchase -i <id>` |
| 5 | Ввод ID приложений и загрузка последней версии | Enter app IDs and download latest | for each id: `download -i <id>` |
| 6 | Ввод ID приложений и загрузка (с выбором версии) | Enter app IDs and download (version selection) | per id: version flow then `download --external-version-id` |
| 7 | Вывод списка ID приложений и покупка | Show app‑ID list and purchase | from saved list → `purchase -i <id>` |
| 8 | Вывод списка ID приложений и загрузка последней версии | Show list and download latest | from saved list → `download -i <id>` |
| 9 | Вывод списка ID приложений и загрузка (с выбором версии) | Show list and download (version selection) | from saved list → version flow → `download` |
| 10 | Проверка минимальной версии iOS для приложений в папке Apps | Check min iOS version for apps in Apps folder | read `MinimumOSVersion` from each `.ipa` in `Apps/` |
| 11 | **Установка приложений из папки Apps** | **Install apps from Apps folder** | **`ideviceinstaller install <ipa>`** ← the install goal |
| 12 | Очистка данных | Clear data | delete saved lists / downloaded apps |
| 13 | Выход из Apple ID | Log out of Apple ID | `auth revoke` |
| 14 | Страница проекта на GitHub | GitHub project page | open URL |
| 15 | Сменить язык (Change Language) | Change Language | toggle RU/EN in `Lang_Config.txt` |

Plus auth at startup (`Connect-AppleID`): if `~/.ipatool/account` exists → `auth info`, else loop
`auth login` until it succeeds (clearing stale `cookies` between tries).

## Conventions to replicate (with PS1 line refs)

- **Directories created on startup** (`:208`): `./Apps`, `./Lists`, `~/.ipatool`.
- **Startup cleanup** (`:232`): delete stray `*.ipa.tmp` (interrupted resumable downloads).
- **Required binaries check** (`:215`): `ipatool(.exe)`, `ideviceinstaller(.exe)`.
- **Min‑iOS metadata** (`Get-IPA-Metadata`, `:258`–`:289`): unzip the `.ipa`, read
  `Payload/*.app/Info.plist`, regex `MinimumOSVersion` →
  `<key>MinimumOSVersion</key>\s*<string>([^<]+)</string>`. (In Python prefer `plistlib` over regex.)
- **Saved lists** (`Save-App-To-List`, `:314`): JSON files `Lists/Purchased_IDs.json` and
  `Lists/Downloaded_IDs.json`, each an array of `{Id, Name, ...}`.
- **App‑name lookup** (`Initialize-GitHub-List`/`Get-GitHub-AppName`, `:343`–`:367`): parse a
  name↔id list (the bundled `Apps_ID_List.txt`, format `Name: 123456`, regex `^(.+?):\s*(\d+)`) to
  label apps whose name isn't otherwise known.
- **Post‑download** (`:377`–`:393`): move downloaded `*.ipa` into `Apps/`, read metadata, fall back
  to the name list if the name is unknown.
- **Install flow** (`:975`–`:983`): copy selected `.ipa` to a temp file, run
  `ideviceinstaller install <temp>`, then delete the temp.

## Windows‑specific cruft that DISAPPEARS on macOS

Listed in the original README as requirements — none apply to the port:
- **AppleMobileDeviceSupport driver** (from iTunes) → macOS has `usbmuxd` built in.
- **UpdRootsCert** (updating Windows root certificates so Apple TLS works) → macOS roots are current.
- **.NET Framework 4.8** and **KB3191566** (Windows PowerShell upgrade) → irrelevant; we use Python.

## Behavioral details worth keeping

- "Purchase (without downloading)" just acquires the free license — useful to batch‑claim apps to the
  account, then download later.
- Version selection requires `list-versions` (to get external version IDs) + `get-version-metadata`
  (to show human version string + release date so the user picks the right one) before `download
  --external-version-id`.
- Default language is RU; menu numbering is stable 1–15 (good for muscle memory — keep it).
