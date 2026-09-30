import Foundation

/// Every error the user can see goes through this type: a human title, a human hint,
/// and (optionally) technical details hidden behind «Подробнее».
struct UserFacingError: LocalizedError, Identifiable {
    let id = UUID()
    let title: String
    let hint: String
    var details: String?

    var errorDescription: String? { title }
    var recoverySuggestion: String? { hint }

    // MARK: Catalog
    static func signingFailed(_ details: String? = nil) -> Self {
        .init(title: "Не удалось подписать приложение",
              hint: "Проверьте сертификат и provisioning profile.", details: details)
    }
    static let signingEngineMissing = Self(
        title: "Движок подписи не подключён",
        hint: "Эта сборка собрана без zsign. Подпись невозможна — см. раздел «Помощь → Частые ошибки».")
    static let invalidIPA = Self(
        title: "Файл не похож на приложение",
        hint: "Выберите корректный .ipa-файл: внутри должна быть папка Payload с .app.")
    static let wrongPassword = Self(
        title: "Неверный пароль сертификата",
        hint: "Введите пароль, который был задан при экспорте .p12.")
    static let invalidP12 = Self(
        title: "Не удалось прочитать сертификат",
        hint: "Файл .p12 повреждён или не содержит закрытый ключ.")
    static let invalidProfile = Self(
        title: "Не удалось прочитать provisioning profile",
        hint: "Выберите корректный файл .mobileprovision.")
    static let profileMismatch = Self(
        title: "Сертификат и профиль не совпадают",
        hint: "Этот .mobileprovision выпущен для другого сертификата. Скачайте профиль, в который включён ваш сертификат.")
    static let certificateExpired = Self(
        title: "Сертификат истёк",
        hint: "Добавьте новый сертификат или обновите его в SideStore и импортируйте снова.")
    static let noCertificate = Self(
        title: "Сертификат не выбран",
        hint: "Добавьте сертификат для подписания в разделе «Сертификаты».")
    static let sideStoreMissing = Self(
        title: "SideStore не найден",
        hint: "Установите SideStore 0.6.2 или новее либо экспортируйте .p12 вручную и импортируйте файлом.")
    static let sideStoreEmpty = Self(
        title: "SideStore не передал сертификат",
        hint: "Откройте SideStore, войдите в Apple ID и повторите. Если запрос не появился — оставьте SideStore открытым в фоне и нажмите кнопку ещё раз.")
    static let installUnavailable = Self(
        title: "Установка не началась",
        hint: "Выбранный способ установки недоступен. Откройте «Настройки → Установка» и выберите другой.")
    static let appleIDSignedOut = Self(
        title: "Вход в Apple ID не выполнен",
        hint: "Войдите в Apple ID в «Настройки → Apple ID» — профили выдаются через него.")
    static let udidMissing = Self(
        title: "Неизвестен UDID устройства",
        hint: "Apple выдаёт профиль только для зарегистрированного устройства. Получите pairing-файл из SideStore в «Настройки → Подключение» — в нём есть UDID.")
    static let anisetteServerInvalid = Self(
        title: "Неверный адрес anisette-сервера",
        hint: "Укажите адрес целиком, например \(AppleAccountService.defaultAnisetteServer).")
    static let connectionFailed = Self(
        title: "Нет подключения к устройству",
        hint: "Включите VPN-туннель (например, LocalDevVPN) и проверьте IP-адрес и порт в «Настройки → Подключение».")

    /// Maps any error to something presentable.
    static func wrap(_ error: Error) -> UserFacingError {
        if let e = error as? UserFacingError { return e }
        return .init(title: "Что-то пошло не так",
                     hint: "Попробуйте ещё раз. Если ошибка повторяется — отправьте отчёт в «Настройки → Разработчик».",
                     details: (error as NSError).debugDescription)
    }
}

/// Lightweight toast shown at the top of the screen.
struct Banner: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String?
    var kind: Kind
    enum Kind { case success, error, info }

    init(title: String, subtitle: String?, kind: Kind) {
        self.title = title; self.subtitle = subtitle; self.kind = kind
    }
    init(error: Error) {
        let e = UserFacingError.wrap(error)
        self.init(title: e.title, subtitle: e.hint, kind: .error)
    }
}
