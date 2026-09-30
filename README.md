# Orbit — установщик IPA для iOS

Нативное SwiftUI-приложение (iOS 16+): импорт IPA, менеджер сертификатов, подпись на устройстве через zsign и установка поддерживаемыми способами iOS. «Orbit» — рабочее название, меняется в одном месте.

## Сборка (нужен Mac с Xcode 15+)

```bash
brew install xcodegen
cd Orbit-project
xcodegen generate
open Orbit.xcodeproj
```

1. В Signing & Capabilities выберите свою команду (Team).
2. Xcode сам скачает пакеты ZIPFoundation и OpenSSL.
3. Соберите на устройство. Готовый IPA для распространения: Product → Archive.

> Проект собран без Xcode под рукой — компиляцию на реальном Mac я не проверял. Если Xcode ругнётся, пришлите текст ошибки — поправлю.

## Своё название и логотип

| Что | Где |
|---|---|
| Название, разработчик, сайт, GitHub, e-mail | `Orbit/App/Brand.swift` |
| Имя на рабочем столе, Bundle ID | `project.yml` → `BRAND_NAME`, `BUNDLE_ID` |
| Иконка приложения (1024×1024 PNG) | `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` |
| Логотип внутри приложения | `Resources/Assets.xcassets/BrandLogo.imageset/BrandLogo.png` |
| Фирменный цвет (светлая/тёмная тема) | `Resources/Assets.xcassets/AccentColor.colorset` |
| URL-схема для SideStore | `Brand.urlScheme` **и** `CFBundleURLSchemes` в `Info.plist` |

## Архитектура

```
Orbit/
├─ App/            точка входа, Brand, AppEnvironment (композиция сервисов, обработка URL)
├─ Core/           логика, без SwiftUI
│  ├─ IPA/           чтение метаданных и иконки из IPA, библиотека приложений
│  ├─ Certificates/  .p12 (SecPKCS12Import), .mobileprovision, X.509 срок, хранилище
│  ├─ Signing/       протокол AppSigner + ZSignSigner (unzip → проверка → zsign → zip)
│  ├─ Installation/  InstallCoordinator, OTA-сервер, туннель/pairing
│  ├─ SideStore/     официальный экспорт сертификата из SideStore
│  ├─ Storage/       файлы, Keychain (пароли .p12), настройки
│  └─ Errors/        понятные пользователю ошибки
├─ UI/             SwiftUI-экраны: Главная, Приложения, Сертификаты, Настройки, Помощь
└─ Vendor/zsign    zsign (MIT), подключён исходниками
```

UI не знает, как именно подписывается и ставится приложение, — только протоколы `AppSigner` и `InstallCoordinator`.

## Что реально, а что нет

**Подпись** — настоящая, через zsign на устройстве. Перед подписью проверяется пароль .p12, срок действия и то, что профиль действительно выпущен для этого сертификата. Если профиль под конкретный Bundle ID — он подставляется автоматически.

**Установка.** iOS не даёт обычному приложению ставить другие приложения молча, поэтому есть три способа, и ни один не изображает успех:

1. **Через «Поделиться»** (по умолчанию, работает всегда) — подписанный IPA отдаётся в SideStore, TrollStore и т. п.
2. **OTA (itms-services)** — штатный механизм Apple. Приложение поднимает HTTPS-сервер на 127.0.0.1 и открывает `itms-services://`. iOS требует доверенный TLS, поэтому нужен свой домен с A-записью на `127.0.0.1` и сертификат для него (например, Let's Encrypt), импортированный как .p12 в «Настройки → Установка». Без этого приложение честно говорит, что способ не настроен.
3. **Напрямую через туннель** — pairing-файл + LocalDevVPN/StosVPN. Импорт pairing-файла и реальная проверка TCP-соединения работают. Сама загрузка IPA через AFC + installation_proxy требует библиотеки [idevice](https://github.com/jkcoxson/idevice) (Rust, собирается cargo под iOS) — она не вложена. Пока её нет, кнопка объясняет это и предлагает способ 1. Точка подключения — `TunnelInstaller.install` (`#if canImport(IDevice)`).

**SideStore.** Используется официальная схема из SideStore 0.6.2+ (PR SideStore#959): `sidestore://certificate?callback_template=…`, SideStore спрашивает разрешение и возвращает `orbit://sidestore-certificate?cert=…&password=…`. SideStore отдаёт только сертификат, поэтому после возврата приложение просит выбрать .mobileprovision (или берёт уже импортированный подходящий). Если SideStore не установлен — показывается ручной путь через файлы / «Открыть в…».

**Apple ID (бесплатный аккаунт).** «Настройки → Apple ID»: вход по Apple ID и паролю (+ код 2FA) через [SideSign](https://github.com/SideStore/SideSign) — ту же библиотеку, что у SideStore. Сертификат, полученный из SideStore без профиля, помечается «профили через Apple ID»: при каждой подписи Orbit регистрирует устройство (UDID из pairing-файла — его можно получить из SideStore в «Настройки → Подключение»), создаёт App ID `<bundle id>.<Team ID>` (и для расширений) и скачивает свежий профиль. Ограничения Apple для бесплатных аккаунтов: 10 App ID за 7 дней, подпись на 7 дней. Пароль уходит только Apple (SRP) и хранится в Связке ключей; anisette-сервер (по умолчанию `ani.sidestore.io`) выдаёт только заголовки устройства.

**Устройство.** UDID обычному приложению недоступен и не запрашивается. Показывается только из pairing-файла, который пользователь импортировал сам, — и проверяется, есть ли устройство в выбранном профиле.

## Лицензия

Orbit распространяется под **GNU AGPL-3.0** (см. `LICENSE`): он использует SideSign (GPL-3.0) и его зависимости AnisetteKit, GSACryptoKit, CodeSignKit (AGPL-3.0).

Прочие компоненты: zsign — MIT, ZIPFoundation — MIT, OpenSSL — Apache 2.0, zlib/minizip — zlib License, swift-crypto — Apache 2.0, libdeflate — MIT, Unicorn Engine — GPL-2.0. Список виден в «Настройки → Разработчик → Лицензии».
