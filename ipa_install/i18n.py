"""RU/EN string tables and a tiny lookup helper.

Strings are ported verbatim from the original ``IPA_Downloader.ps1`` ``$LangStrings``
table (RU + EN), plus a handful of macOS-specific additions for device guidance and
clearer status messages. Default language is RU (matching the original).

Use ``t(key, lang, *args)`` everywhere instead of literals so both languages stay
in sync. Templated strings use ``{0}``/``{1}`` placeholders.
"""

from __future__ import annotations

STRINGS: dict[str, dict[str, str]] = {
    "RU": {
        # ── Main menu (15 items) ──
        "Menu1": "1. Поиск приложения и покупка (без загрузки)",
        "Menu2": "2. Поиск приложения и загрузка последней версии",
        "Menu3": "3. Поиск приложения и загрузка (с выбором версии)",
        "Menu4": "4. Ввод ID приложений и покупка (без загрузки)",
        "Menu5": "5. Ввод ID приложений и загрузка последней версии",
        "Menu6": "6. Ввод ID приложений и загрузка (с выбором версии)",
        "Menu7": "7. Вывод списка ID приложений и покупка (без загрузки)",
        "Menu8": "8. Вывод списка ID приложений и загрузка последней версии",
        "Menu9": "9. Вывод списка ID приложений и загрузка (с выбором версии)",
        "Menu10": "10. Проверка минимальной версии iOS для приложений в папке Apps",
        "Menu11": "11. Установка приложений из папки Apps",
        "Menu12": "12. Очистка данных",
        "Menu13": "13. Выход из Apple ID",
        "Menu14": "14. Страница проекта на GitHub",
        "Menu15": "15. Сменить язык (Change Language)",
        "Menu16": "16. Найти мои приложения (скан владения) [macOS]",
        "MenuTitle": "Введите команду:",
        # ── Auth ──
        "AuthSuccess": "Вход в Apple ID выполнен.\nДанные аккаунта:",
        "AuthFail": "Вход в Apple ID не выполнен.",
        "LoggedOut": "Выполнен выход из Apple ID.",
        # ── Prompts ──
        "AskSearch": "Введите название приложения для поиска",
        "AskIdSearch": "Введите ID приложения для поиска",
        "AskIdDownload": "Введите ID приложения для загрузки",
        "AskIdPurchase": "Введите ID приложения для покупки",
        "AskAppNum": "Введите номера приложений",
        "AskVerCount": "Введите количество версий для отображения",
        "AskVerNum": "Введите номера версий для загрузки",
        "CancelStep": "(0: Отмена/Возврат в главное меню)",
        # ── Table headers ──
        "HeaderAppName": "Название приложения",
        "HeaderAppID": "ID приложения",
        "HeaderVerID": "ID версии",
        "HeaderVersion": "Версия",
        "HeaderFileName": "Имя файла",
        "HeaderMinIOS": "Мин. iOS",
        # ── Selection / display ──
        "SelectedApp": "Выбрано приложение:",
        "SelectedVer": "Выбрана версия:",
        # ── File / save ──
        "FileSaved": "Готово. Файл сохранен в папку Apps.",
        "FileName": "Имя файла:",
        "MinIOS": "Минимальная версия iOS:",
        "AddedToDownloadedList": "Добавлено в список: {0} - {1}",
        "AddedToPurchasedList": "Добавлено в список покупок: {0} - {1}",
        "AlreadyInList": "Уже есть в списке: {0} - {1}",
        "InstallApp": "Установка:",
        # ── Clear-data submenu ──
        "ClearMenuTitle": "Выберите данные для очистки:",
        "ClearMenu1": "1. Список загруженных приложений",
        "ClearMenu2": "2. Список приобретенных приложений",
        "ClearMenu3": "3. Приложения в папке Apps",
        "DownloadedListCleared": "Готово. Список загруженных приложений очищен.",
        "PurchasedListCleared": "Готово. Список приобретенных приложений очищен.",
        "AppsCleared": "Готово. Приложения в папке Apps удалены.",
        # ── View-list submenu ──
        "ListMenuTitle": "Выберите список для отображения:",
        "DownloadedListMenu1": "1. Полный список приложений (GitHub)",
        "DownloadedListMenu2": "2. Список загруженных приложений",
        "DownloadedListMenu3": "3. Список не загруженных приложений",
        "PurchasedListMenu1": "1. Полный список приложений (GitHub)",
        "PurchasedListMenu2": "2. Список приобретенных приложений",
        "PurchasedListMenu3": "3. Список не приобретенных приложений",
        # ── Errors ──
        "ErrorInvalidInput": "Ошибка: Неверный ввод.",
        "ErrorNoAppsFound": "Ошибка: Приложения не найдены.",
        "ErrorNoApps": "Ошибка: В папке Apps отсутствуют приложения.",
        "ErrorHistoryEmpty": "Ошибка: История загрузок пуста.",
        "ErrorPurchasedEmpty": "Ошибка: История покупок пуста.",
        "ErrorListLoadError": "Ошибка загрузки списка приложений.",
        "ErrorMissingFiles": "Ошибка: Не найдены необходимые исполняемые файлы:",
        # ── Navigation ──
        "PressEnter": "Нажмите Enter для выхода",
        "LangChanged": "Язык успешно изменен на Русский.",
        # ── macOS additions ──
        "AskEmail": "Введите email (Apple ID):",
        "AskPassword": "Введите пароль:",
        "Auth2FAHint": "Пароль и код 2FA (при наличии) запросит ipatool — введите их в терминале.",
        "Downloading": "Загрузка...",
        "DownloadFailed": "Ошибка загрузки.",
        "PurchaseFailed": "Ошибка покупки.",
        "PurchaseDone": "Покупка выполнена.",
        "NoDevice": "Устройство не найдено. Подключите iPhone/iPad по USB, разблокируйте и нажмите «Доверять».",
        "DeviceFound": "Устройство найдено: {0}",
        "InstallSuccess": "Установка завершена успешно.",
        "InstallFailed": "Ошибка установки.",
        "PairHint": "При запросе нажмите «Доверять» на устройстве (и включите Developer Mode на iOS 16+).",
        "Searching": "Поиск...",
        "Back": "Назад",
        "MenuPrompt": "Введите команду:",
        # ── Ownership scan (macOS addition) ──
        "ScanWarn": "Сначала бесплатно (через iTunes) найдёт удалённые из App Store среди {0} приложений каталога, затем опросит App Store ТОЛЬКО по удалённым (несколько минут, с паузами).\nЭто ваш ЛИЧНЫЙ Apple ID — частые запросы могут привести к временному ограничению аккаунта.",
        "ScanConfirm": "Запустить скан? (1 — да, 0 — отмена)",
        "ScanFiltering": "Ищу удалённые из стора (iTunes, без риска для аккаунта)...",
        "ScanDoneMsg": "Готово: удалено из стора — {0}, из них доступно вам — {1}.",
        "ScanRemovedHeader": "Удалены из стора и доступны вам ({0}) — восстановить можно так:",
        "ScanNotOwnedHeader": "Удалены из стора, но не куплены вами ({0}):",
        "ScanNoRecoverable": "Среди удалённых из стора нет приложений, которыми владеет этот Apple ID.",
        "ScanCancelled": "Скан прерван.",
        "ScanSaved": "Результат сохранён: Lists/Owned_scan.json",
    },
    "EN": {
        # ── Main menu (15 items) ──
        "Menu1": "1. Search for app and purchase (without downloading)",
        "Menu2": "2. Search for app and download latest version",
        "Menu3": "3. Search for app and download (with version selection)",
        "Menu4": "4. Enter app IDs and purchase (without downloading)",
        "Menu5": "5. Enter app IDs and download latest version",
        "Menu6": "6. Enter app IDs and download (with version selection)",
        "Menu7": "7. Show list of app IDs and purchase (without downloading)",
        "Menu8": "8. Show list of app IDs and download latest version",
        "Menu9": "9. Show list of app IDs and download (with version selection)",
        "Menu10": "10. Check minimum iOS version for apps in Apps folder",
        "Menu11": "11. Install apps from Apps folder",
        "Menu12": "12. Clear data",
        "Menu13": "13. Log out of Apple ID",
        "Menu14": "14. GitHub project page",
        "Menu15": "15. Change Language (Сменить язык)",
        "Menu16": "16. Find my apps (ownership scan) [macOS]",
        "MenuTitle": "Enter a command:",
        # ── Auth ──
        "AuthSuccess": "Apple ID login successful.\nAccount details:",
        "AuthFail": "Not authenticated with Apple ID.",
        "LoggedOut": "Successfully logged out of Apple ID.",
        # ── Prompts ──
        "AskSearch": "Enter app name to search",
        "AskIdSearch": "Enter app IDs to search",
        "AskIdDownload": "Enter app IDs to download",
        "AskIdPurchase": "Enter app IDs to purchase",
        "AskAppNum": "Enter app index numbers",
        "AskVerCount": "Enter number of versions to display",
        "AskVerNum": "Enter version numbers to download",
        "CancelStep": "(0: Cancel/Return to main menu)",
        # ── Table headers ──
        "HeaderAppName": "App Name",
        "HeaderAppID": "App ID",
        "HeaderVerID": "Version ID",
        "HeaderVersion": "Version",
        "HeaderFileName": "File name",
        "HeaderMinIOS": "Min. iOS",
        # ── Selection / display ──
        "SelectedApp": "Selected app:",
        "SelectedVer": "Selected version:",
        # ── File / save ──
        "FileSaved": "Done. File saved to Apps folder.",
        "FileName": "File name:",
        "MinIOS": "Minimum iOS version:",
        "AddedToDownloadedList": "Added to list: {0} - {1}",
        "AddedToPurchasedList": "Added to purchased list: {0} - {1}",
        "AlreadyInList": "Already in list: {0} - {1}",
        "InstallApp": "Installing:",
        # ── Clear-data submenu ──
        "ClearMenuTitle": "Select data to clear:",
        "ClearMenu1": "1. Downloaded apps list",
        "ClearMenu2": "2. Purchased apps list",
        "ClearMenu3": "3. Apps in Apps folder",
        "DownloadedListCleared": "Done. Downloaded apps list cleared.",
        "PurchasedListCleared": "Done. Purchased apps list cleared.",
        "AppsCleared": "Done. Apps folder has been cleared.",
        # ── View-list submenu ──
        "ListMenuTitle": "Select list to display:",
        "DownloadedListMenu1": "1. Full apps list (GitHub)",
        "DownloadedListMenu2": "2. Downloaded apps list",
        "DownloadedListMenu3": "3. Not downloaded apps list",
        "PurchasedListMenu1": "1. Full apps list (GitHub)",
        "PurchasedListMenu2": "2. Purchased apps list",
        "PurchasedListMenu3": "3. Not purchased apps list",
        # ── Errors ──
        "ErrorInvalidInput": "Error: Invalid input.",
        "ErrorNoAppsFound": "Error: No apps found.",
        "ErrorNoApps": "Error: No apps found in Apps folder.",
        "ErrorHistoryEmpty": "Error: Download history is empty.",
        "ErrorPurchasedEmpty": "Error: Purchase history is empty.",
        "ErrorListLoadError": "Failed to load apps list.",
        "ErrorMissingFiles": "Error: Required binaries were not found:",
        # ── Navigation ──
        "PressEnter": "Press Enter to exit",
        "LangChanged": "Language successfully changed to English.",
        # ── macOS additions ──
        "AskEmail": "Enter email (Apple ID):",
        "AskPassword": "Enter password:",
        "Auth2FAHint": "ipatool will prompt for your password and 2FA code (if any) — type them in the terminal.",
        "Downloading": "Downloading...",
        "DownloadFailed": "Download failed.",
        "PurchaseFailed": "Purchase failed.",
        "PurchaseDone": "Purchase complete.",
        "NoDevice": "No device found. Connect an iPhone/iPad via USB, unlock it and tap “Trust”.",
        "DeviceFound": "Device found: {0}",
        "InstallSuccess": "Installation completed successfully.",
        "InstallFailed": "Installation failed.",
        "PairHint": "If prompted, tap “Trust” on the device (and enable Developer Mode on iOS 16+).",
        "Searching": "Searching...",
        "Back": "Back",
        "MenuPrompt": "Enter a command:",
        # ── Ownership scan (macOS addition) ──
        "ScanWarn": "First finds (free, via iTunes) which of the {0} catalog apps are removed from the App Store, then probes the App Store ONLY for those (a few minutes, with pauses).\nThis is your PERSONAL Apple ID — frequent requests can lead to a temporary account limit.",
        "ScanConfirm": "Start the scan? (1 = yes, 0 = cancel)",
        "ScanFiltering": "Finding apps removed from the store (iTunes, no account risk)...",
        "ScanDoneMsg": "Done: removed from the store — {0}, of those available to you — {1}.",
        "ScanRemovedHeader": "Removed from the store and available to you ({0}) — recoverable this way:",
        "ScanNotOwnedHeader": "Removed from the store but not owned by you ({0}):",
        "ScanNoRecoverable": "None of the removed-from-store apps are owned by this Apple ID.",
        "ScanCancelled": "Scan aborted.",
        "ScanSaved": "Result saved: Lists/Owned_scan.json",
    },
}


def t(key: str, lang: str = "RU", *args: object) -> str:
    """Look up a UI string by key for ``lang`` ("RU"/"EN").

    Falls back to EN, then to the raw key, so a missing translation never crashes.
    If positional ``args`` are given, they fill ``{0}``/``{1}`` placeholders.
    """
    table = STRINGS.get(lang) or STRINGS["EN"]
    value = table.get(key)
    if value is None:
        value = STRINGS["EN"].get(key, key)
    if args:
        try:
            return value.format(*args)
        except (IndexError, KeyError):
            return value
    return value
