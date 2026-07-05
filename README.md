# IPA Install for macOS

[English version](README_EN.md)

Нативное macOS-приложение, которое **скачивает купленные вами приложения из App Store в виде
.ipa** и **устанавливает их на iPhone/iPad по USB-кабелю**. Порт Windows-инструмента
[IPA_Downloader](https://github.com/kda2495/IPA_Downloader) — без iTunes и виртуалок:
на macOS `usbmuxd` встроен в систему.

Зачем это нужно: скачать старую версию приложения, поставить приложение, удалённое из App Store
(но купленное вашим Apple ID), держать локальный архив .ipa своих покупок.

## Возможности

- **Поиск и скачивание** приложений App Store под вашим Apple ID (вход с 2FA поддержан)
- **Старые версии**: список исторических версий приложения и скачивание любой из них
- **Установка на устройство** по USB одним пунктом меню (`ideviceinstaller`)
- **Пакетные операции**: по списку ID, по сохранённым спискам, диапазонами (`1,3-5`)
- **Скан владения** (только в этой версии): находит ваши купленные приложения, которые уже
  удалены из App Store, и показывает, какие из них ещё можно скачать
- **Два интерфейса**: графическое приложение `IpaInstall.app` и терминальное меню на 15 пунктов
- **Русский и английский** интерфейс, переключение на лету
- Оффлайн-каталог из 450+ популярных приложений в комплекте

## Установка

### Вариант 1: готовое приложение (рекомендуется)

1. Скачайте `IpaInstall.app.zip` из [Releases](../../releases), распакуйте.
2. Снимите карантин (приложение подписано ad-hoc, без нотаризации Apple):
   ```sh
   xattr -cr ~/Downloads/IpaInstall.app
   ```
3. Для установки на устройство поставьте libimobiledevice:
   ```sh
   brew install ideviceinstaller
   ```
4. Запускайте. Движок скачивания уже внутри приложения; данные хранятся в
   `~/Library/Application Support/IpaInstall`, скачанные .ipa — в `~/Downloads/IPA`.

Требования: macOS 13+, Apple Silicon (для Intel соберите из исходников).

### Вариант 2: из исходников

```sh
git clone https://github.com/goslingmanagment/ipa-install-macos
cd ipa-install-macos

# движок скачивания (одна команда, см. docs/toolchain-macos.md):
#   соберите ipatool из github.com/Sorvigolova/ipatool → bin/ipatool
brew install ideviceinstaller && ln -sf "$(command -v ideviceinstaller)" bin/ideviceinstaller

# терминальная версия (Python 3, только стандартная библиотека):
python3 -m ipa_install

# или графическая:
cd gui && ./build_app.sh && open IpaInstall.app
```

## Установка приложения на iPhone/iPad

1. Подключите устройство по USB, разблокируйте, нажмите **Доверять**.
2. На iOS 16+ включите **Настройки → Конфиденциальность и безопасность → Режим разработчика**,
   если система попросит.
3. В GUI: вкладка **Device** → выберите .ipa → Install. В терминале: пункт меню **11**.

Устройство должно быть залогинено в тот же Apple ID, которым куплено приложение —
.ipa подписан лицензией FairPlay вашего аккаунта.

## Безопасность и приватность

- Пароль Apple ID и код 2FA **никогда не сохраняются и не логируются** приложением: в терминале
  их запрашивает сам `ipatool` (скрытый ввод), в GUI они передаются движку через
  псевдотерминал — не через аргументы командной строки.
- Сессия хранится в `~/.ipatool/` (шифруется ipatool, привязана к машине).
- Рекомендуем отдельный/запасной Apple ID: Apple может помечать аккаунты,
  использующие сторонние клиенты App Store.

## Легальность

Инструмент работает **только с приложениями, лицензированными вашему Apple ID** — это цифровые
покупки вашего аккаунта. Он не снимает DRM, не переподписывает .ipa и не даёт доступа к чужим
приложениям. Это не инструмент пиратства.

## Как это устроено

```
IpaInstall.app / python3 -m ipa_install
        ├── ipatool (C++, github.com/Sorvigolova/ipatool) — протокол App Store: вход, поиск,
        │            покупка, скачивание .ipa с FairPlay-лицензией аккаунта
        └── ideviceinstaller (libimobiledevice) → usbmuxd (встроен в macOS) → iPhone/iPad
```

Для разработчиков: карта документации в [docs/](docs/), архитектура —
[docs/architecture.md](docs/architecture.md), гид для AI-сессий — [CLAUDE.md](CLAUDE.md).
Оффлайн-тесты: `python3 tests/run_checks.py` (без сети, Apple ID и устройства);
селфтест GUI: `gui/IpaInstall.app/Contents/MacOS/IpaInstall --selftest`.

## Благодарности

- [kda2495/IPA_Downloader](https://github.com/kda2495/IPA_Downloader) — оригинальный
  Windows-инструмент, UX меню взят оттуда
- [Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool) — движок скачивания
  (закреплён на коммите `74f4247`)
- [libimobiledevice](https://libimobiledevice.org) — связь с устройством

## Лицензия

[MIT](LICENSE)
