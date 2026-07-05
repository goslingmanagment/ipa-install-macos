// Localization.swift — RU/EN string tables and lookup, mirroring ipa_install/i18n.py.
//
// The shared keys (Menu*, Header*, Error*, …) are copied verbatim from the Python
// i18n table so the GUI and the terminal stay in sync. GUI-only keys (tab titles,
// button labels, status lines) are added below each shared block.
//
// Default language is RU (matching the original). The choice is persisted to the
// SAME Lang_Config.txt the TUI uses, so switching language in either front-end
// carries over to the other.

import Foundation

enum Lang: String {
    case ru = "RU"
    case en = "EN"

    var other: Lang { self == .ru ? .en : .ru }
}

enum L10n {
    // Look up a key for a language; fall back to EN, then to the raw key. Positional
    // args fill {0}/{1}/… placeholders (same convention as i18n.py's str.format).
    static func t(_ key: String, _ lang: Lang, _ args: [String] = []) -> String {
        let table = strings[lang] ?? strings[.en]!
        var value = table[key] ?? strings[.en]?[key] ?? key
        for (i, a) in args.enumerated() {
            value = value.replacingOccurrences(of: "{\(i)}", with: a)
        }
        return value
    }

    static let strings: [Lang: [String: String]] = [
        .ru: [
            // ── Main menu labels (shared with the TUI; used for tooltips/headers) ──
            "Menu1": "Поиск приложения и покупка (без загрузки)",
            "Menu2": "Поиск приложения и загрузка последней версии",
            "Menu3": "Поиск приложения и загрузка (с выбором версии)",
            "Menu4": "Ввод ID приложений и покупка (без загрузки)",
            "Menu5": "Ввод ID приложений и загрузка последней версии",
            "Menu6": "Ввод ID приложений и загрузка (с выбором версии)",
            "Menu10": "Проверка минимальной версии iOS",
            "Menu11": "Установка приложений из папки Apps",
            "Menu12": "Очистка данных",
            "Menu14": "Страница проекта на GitHub",

            // ── Auth ──
            "AuthSuccess": "Вход в Apple ID выполнен.",
            "AuthFail": "Вход в Apple ID не выполнен.",
            "LoggedOut": "Выполнен выход из Apple ID.",

            // ── Table / column headers ──
            "HeaderAppName": "Название приложения",
            "HeaderAppID": "ID приложения",
            "HeaderVerID": "ID версии",
            "HeaderVersion": "Версия",
            "HeaderFileName": "Имя файла",
            "HeaderMinIOS": "Мин. iOS",
            "HeaderDate": "Дата",
            "HeaderBundleID": "Bundle ID",

            // ── Selection / file ──
            "SelectedApp": "Выбрано приложение:",
            "SelectedVer": "Выбрана версия:",
            "FileSaved": "Готово. Файл сохранён в папку Apps.",
            "AddedToDownloadedList": "Добавлено в список: {0} - {1}",
            "AddedToPurchasedList": "Добавлено в список покупок: {0} - {1}",
            "AlreadyInList": "Уже есть в списке: {0} - {1}",

            // ── Clear-data ──
            "ClearMenuTitle": "Очистка данных:",
            "ClearMenu1": "Список загруженных приложений",
            "ClearMenu2": "Список приобретённых приложений",
            "ClearMenu3": "Приложения в папке Apps",
            "DownloadedListCleared": "Готово. Список загруженных приложений очищен.",
            "PurchasedListCleared": "Готово. Список приобретённых приложений очищен.",
            "AppsCleared": "Готово. Приложения в папке Apps удалены.",

            // ── List sources (menus 7-9) ──
            "ListMenuTitle": "Список для отображения:",
            "DownloadedListMenu1": "Полный список приложений (каталог)",
            "DownloadedListMenu2": "Список загруженных приложений",
            "DownloadedListMenu3": "Список не загруженных приложений",
            "PurchasedListMenu2": "Список приобретённых приложений",
            "PurchasedListMenu3": "Список не приобретённых приложений",

            // ── Errors ──
            "ErrorInvalidInput": "Ошибка: Неверный ввод.",
            "ErrorNoAppsFound": "Ошибка: Приложения не найдены.",
            "ErrorNoApps": "Ошибка: В папке Apps отсутствуют приложения.",
            "ErrorHistoryEmpty": "Ошибка: История загрузок пуста.",
            "ErrorPurchasedEmpty": "Ошибка: История покупок пуста.",
            "ErrorListLoadError": "Ошибка загрузки списка приложений.",

            "LangChanged": "Язык успешно изменён на Русский.",

            // ── Device ──
            "NoDevice": "Устройство не найдено. Подключите iPhone/iPad по USB, разблокируйте и нажмите «Доверять».",
            "DeviceFound": "Устройство найдено: {0}",
            "InstallApp": "Установка:",
            "InstallSuccess": "Установка завершена успешно.",
            "InstallFailed": "Ошибка установки.",
            "PairHint": "Подключите по USB, разблокируйте устройство и нажмите «Доверять» (включите Developer Mode на iOS 16+).",

            // ── GUI: app + tabs ──
            "AppTitle": "IPA Install",
            "TabAccount": "Аккаунт",
            "TabStore": "Магазин",
            "TabLists": "Списки",
            "TabDevice": "Устройство",

            // ── GUI: account ──
            "SignInTitle": "Войдите с Apple ID",
            "DisposableHint": "Используйте тестовый/одноразовый Apple ID. Пароль передаётся в ipatool через аргументы командной строки и кратковременно виден другим локальным процессам — приложение его не хранит и не логирует.",
            "EmailField": "Email (Apple ID)",
            "PasswordField": "Пароль",
            "TwoFactorField": "Код двухфакторной аутентификации",
            "BtnSignIn": "Войти",
            "BtnLogOut": "Выйти",
            "SignedIn": "Выполнен вход",
            "NameLabel": "Имя",
            "AppleIDLabel": "Apple ID",
            "SignInHint": "Сначала войдите на вкладке «Аккаунт».",

            // ── GUI: store ──
            "SearchPlaceholder": "Поиск в App Store…",
            "ByIDPlaceholder": "…или введите числовой ID приложения",
            "LimitLabel": "Лимит",
            "BtnSearch": "Поиск",
            "BtnPurchase": "Купить",
            "BtnPurchaseByID": "Купить по ID",
            "BtnDownloadLatest": "Загрузить последнюю",
            "BtnDownloadByID": "Загрузить по ID",
            "BtnDownloadVersion": "Загрузить версию…",
            "VersionSheetTitle": "Версии: {0}",
            "VersionCountLabel": "Версий:",
            "LoadingVersions": "Загрузка версий…",
            "BtnDownload": "Загрузить",
            "BtnCancel": "Отмена",

            // ── GUI: lists ──
            "ListSourceLabel": "Источник",
            "BtnReload": "Обновить",
            "RecoverableSource": "Мои — удалены из App Store",
            "RemovedNotOwnedSource": "Удалены из стора — не куплены",
            "BtnScan": "Сканировать мои приложения",
            "ScanWarnTitle": "Проверка владения",
            "ScanWarnBody": "Сначала бесплатно (через iTunes) найдёт удалённые из App Store среди {0} приложений каталога, затем опросит App Store ТОЛЬКО по удалённым (несколько минут, с паузами). Это ваш ЛИЧНЫЙ Apple ID — частые обращения теоретически могут привести к временному ограничению аккаунта. Запустить?",
            "ScanContinue": "Запустить",
            "ScanFiltering": "Ищу удалённые из стора (iTunes, без риска для аккаунта)…",
            "ScanRunning": "Проверка владения по удалённым… {0}/{1}",
            "ScanDoneMsg": "Готово: удалено из стора — {0}, доступно вам — {1}.",
            "ScanCancelledMsg": "Сканирование отменено ({0}/{1}).",
            "OwnedEmptyHint": "Пусто. Нажмите «Сканировать мои приложения».",

            // ── GUI: device ──
            "DeviceLabel": "Устройство",
            "NoDeviceConnected": "Устройство не подключено",
            "AppsSection": "Загруженные приложения (Apps/)",
            "BtnInstall": "Установить на устройство",
            "BtnPair": "Сопряжение",
            "BtnRefresh": "Обновить",

            // ── GUI: toolbar / data ──
            "DataMenu": "Данные",
            "BtnClearDownloaded": "Очистить список загрузок",
            "BtnClearPurchased": "Очистить список покупок",
            "BtnClearApps": "Удалить приложения из Apps",
            "BtnGitHub": "GitHub",
            "LanguageMenu": "Язык",

            // ── GUI: status messages ──
            "StatusSigningIn": "Вход…",
            "StatusSearching": "Поиск…",
            "StatusDownloading": "Загрузка…",
            "StatusPurchasing": "Покупка: {0}…",
            "StatusInstalling": "Установка: {0}…",
            "StatusPairing": "Сопряжение…",
            "StatusSignedInAs": "Выполнен вход: {0}.",
            "StatusSignedOut": "Выполнен выход.",
            "StatusSigningOut": "Выход…",
            "StatusTwoFactor": "Требуется код 2FA — введите его и войдите снова.",
            "StatusPurchased": "Куплено: {0}.",
            "StatusSavedToApps": "Сохранено в Apps/: {0}.",
            "StatusInstalled": "Установлено: {0}.",
            "StatusInstallFailed": "Ошибка установки: {0}",
            "StatusInstalledN": "Установлено приложений: {0} из {1}.",
            "StatusDownloadedN": "Загружено приложений: {0} из {1}.",
            "StatusPurchasedN": "Куплено приложений: {0} из {1}.",
            "StatusFoundApps": "Найдено приложений: {0}.",
            "StatusNoneFound": "Приложения не найдены.",
            "StatusPaired": "Устройство сопряжено.",
            "StatusPairFailed": "Ошибка сопряжения: {0}",
            "ErrLicenseRequired": "Приложение не приобретено на этом Apple ID ранее. Если оно ещё есть в App Store — нажмите «Купить» или «Загрузить последнюю», чтобы получить лицензию.",
            "ErrAppNotFound": "Приложение удалено из App Store. Скачать его можно, только если этот Apple ID приобрёл его ранее (до удаления).",
            "ErrUnavailable": "Приложение недоступно: удалено из App Store и не было приобретено на этом Apple ID ранее.",
            "StatusSelectApp": "Сначала выберите приложение.",
            "StatusSelectInstall": "Выберите приложение для установки.",
            "StatusEnterTerm": "Введите запрос для поиска.",
            "StatusEnterID": "Введите числовой ID приложения.",
            "StatusEnterIDs": "Введите один или несколько числовых ID (через запятую).",
            "StatusBarSignedIn": "выполнен вход",
            "StatusBarSignedOut": "вход не выполнен",
            "Dash": "—",
        ],
        .en: [
            // ── Main menu labels ──
            "Menu1": "Search for app and purchase (without downloading)",
            "Menu2": "Search for app and download latest version",
            "Menu3": "Search for app and download (with version selection)",
            "Menu4": "Enter app IDs and purchase (without downloading)",
            "Menu5": "Enter app IDs and download latest version",
            "Menu6": "Enter app IDs and download (with version selection)",
            "Menu10": "Check minimum iOS version",
            "Menu11": "Install apps from Apps folder",
            "Menu12": "Clear data",
            "Menu14": "GitHub project page",

            // ── Auth ──
            "AuthSuccess": "Apple ID login successful.",
            "AuthFail": "Not authenticated with Apple ID.",
            "LoggedOut": "Successfully logged out of Apple ID.",

            // ── Table / column headers ──
            "HeaderAppName": "App Name",
            "HeaderAppID": "App ID",
            "HeaderVerID": "Version ID",
            "HeaderVersion": "Version",
            "HeaderFileName": "File name",
            "HeaderMinIOS": "Min. iOS",
            "HeaderDate": "Date",
            "HeaderBundleID": "Bundle ID",

            // ── Selection / file ──
            "SelectedApp": "Selected app:",
            "SelectedVer": "Selected version:",
            "FileSaved": "Done. File saved to Apps folder.",
            "AddedToDownloadedList": "Added to list: {0} - {1}",
            "AddedToPurchasedList": "Added to purchased list: {0} - {1}",
            "AlreadyInList": "Already in list: {0} - {1}",

            // ── Clear-data ──
            "ClearMenuTitle": "Clear data:",
            "ClearMenu1": "Downloaded apps list",
            "ClearMenu2": "Purchased apps list",
            "ClearMenu3": "Apps in Apps folder",
            "DownloadedListCleared": "Done. Downloaded apps list cleared.",
            "PurchasedListCleared": "Done. Purchased apps list cleared.",
            "AppsCleared": "Done. Apps folder has been cleared.",

            // ── List sources (menus 7-9) ──
            "ListMenuTitle": "List to display:",
            "DownloadedListMenu1": "Full apps list (catalog)",
            "DownloadedListMenu2": "Downloaded apps list",
            "DownloadedListMenu3": "Not downloaded apps list",
            "PurchasedListMenu2": "Purchased apps list",
            "PurchasedListMenu3": "Not purchased apps list",

            // ── Errors ──
            "ErrorInvalidInput": "Error: Invalid input.",
            "ErrorNoAppsFound": "Error: No apps found.",
            "ErrorNoApps": "Error: No apps found in Apps folder.",
            "ErrorHistoryEmpty": "Error: Download history is empty.",
            "ErrorPurchasedEmpty": "Error: Purchase history is empty.",
            "ErrorListLoadError": "Failed to load apps list.",

            "LangChanged": "Language successfully changed to English.",

            // ── Device ──
            "NoDevice": "No device found. Connect an iPhone/iPad via USB, unlock it and tap “Trust”.",
            "DeviceFound": "Device found: {0}",
            "InstallApp": "Installing:",
            "InstallSuccess": "Installation completed successfully.",
            "InstallFailed": "Installation failed.",
            "PairHint": "Connect over USB, unlock the device and tap “Trust” (enable Developer Mode on iOS 16+).",

            // ── GUI: app + tabs ──
            "AppTitle": "IPA Install",
            "TabAccount": "Account",
            "TabStore": "Store",
            "TabLists": "Lists",
            "TabDevice": "Device",

            // ── GUI: account ──
            "SignInTitle": "Sign in with your Apple ID",
            "DisposableHint": "Use a disposable/test Apple ID. The password is passed to ipatool on the command line, so it is briefly visible to other local processes — it is never stored or logged by this app.",
            "EmailField": "Apple ID email",
            "PasswordField": "Password",
            "TwoFactorField": "Two-factor code",
            "BtnSignIn": "Sign in",
            "BtnLogOut": "Log out",
            "SignedIn": "Signed in",
            "NameLabel": "Name",
            "AppleIDLabel": "Apple ID",
            "SignInHint": "Sign in on the Account tab first.",

            // ── GUI: store ──
            "SearchPlaceholder": "Search the App Store…",
            "ByIDPlaceholder": "…or enter a numeric app ID",
            "LimitLabel": "Limit",
            "BtnSearch": "Search",
            "BtnPurchase": "Purchase",
            "BtnPurchaseByID": "Purchase by ID",
            "BtnDownloadLatest": "Download latest",
            "BtnDownloadByID": "Download by ID",
            "BtnDownloadVersion": "Download version…",
            "VersionSheetTitle": "Versions of {0}",
            "VersionCountLabel": "Versions:",
            "LoadingVersions": "Loading versions…",
            "BtnDownload": "Download",
            "BtnCancel": "Cancel",

            // ── GUI: lists ──
            "ListSourceLabel": "Source",
            "BtnReload": "Reload",
            "RecoverableSource": "Mine — removed from App Store",
            "RemovedNotOwnedSource": "Removed from store — not owned",
            "BtnScan": "Scan my apps",
            "ScanWarnTitle": "Ownership scan",
            "ScanWarnBody": "First finds (free, via iTunes) which of the {0} catalog apps are removed from the App Store, then probes the App Store ONLY for those (a few minutes, with pauses). This is your PERSONAL Apple ID — frequent requests can in theory lead to a temporary account limit. Start?",
            "ScanContinue": "Start",
            "ScanFiltering": "Finding apps removed from the store (iTunes, no account risk)…",
            "ScanRunning": "Probing ownership of removed apps… {0}/{1}",
            "ScanDoneMsg": "Done: removed from the store — {0}, available to you — {1}.",
            "ScanCancelledMsg": "Scan cancelled ({0}/{1}).",
            "OwnedEmptyHint": "Empty. Tap “Scan my apps”.",

            // ── GUI: device ──
            "DeviceLabel": "Device",
            "NoDeviceConnected": "No device connected",
            "AppsSection": "Downloaded apps (Apps/)",
            "BtnInstall": "Install to device",
            "BtnPair": "Pair",
            "BtnRefresh": "Refresh",

            // ── GUI: toolbar / data ──
            "DataMenu": "Data",
            "BtnClearDownloaded": "Clear downloaded list",
            "BtnClearPurchased": "Clear purchased list",
            "BtnClearApps": "Delete apps in Apps/",
            "BtnGitHub": "GitHub",
            "LanguageMenu": "Language",

            // ── GUI: status messages ──
            "StatusSigningIn": "Signing in…",
            "StatusSearching": "Searching…",
            "StatusDownloading": "Downloading…",
            "StatusPurchasing": "Purchasing {0}…",
            "StatusInstalling": "Installing {0}…",
            "StatusPairing": "Pairing…",
            "StatusSignedInAs": "Signed in as {0}.",
            "StatusSignedOut": "Signed out.",
            "StatusSigningOut": "Signing out…",
            "StatusTwoFactor": "Two-factor code required — enter it and sign in again.",
            "StatusPurchased": "Purchased: {0}.",
            "StatusSavedToApps": "Saved {0} to Apps/.",
            "StatusInstalled": "Installed {0}.",
            "StatusInstallFailed": "Install failed: {0}",
            "StatusInstalledN": "Installed {0} of {1} app(s).",
            "StatusDownloadedN": "Downloaded {0} of {1} app(s).",
            "StatusPurchasedN": "Purchased {0} of {1} app(s).",
            "StatusFoundApps": "Found {0} app(s).",
            "StatusNoneFound": "No apps found.",
            "StatusPaired": "Device paired.",
            "StatusPairFailed": "Pairing failed: {0}",
            "ErrLicenseRequired": "This app was not acquired on this Apple ID before. If it is still in the App Store, tap “Purchase” or “Download latest” to obtain a license.",
            "ErrAppNotFound": "App removed from the App Store. It can only be downloaded if this Apple ID acquired it earlier (before removal).",
            "ErrUnavailable": "App unavailable: removed from the App Store and not acquired on this Apple ID before.",
            "StatusSelectApp": "Select an app first.",
            "StatusSelectInstall": "Select an app to install.",
            "StatusEnterTerm": "Enter a search term.",
            "StatusEnterID": "Enter a numeric app ID.",
            "StatusEnterIDs": "Enter one or more numeric app IDs (comma-separated).",
            "StatusBarSignedIn": "signed in",
            "StatusBarSignedOut": "signed out",
            "Dash": "—",
        ],
    ]
}
