import SwiftUI

struct HelpTopic: Identifiable {
    let id = UUID()
    let symbol: String
    let color: Color
    let title: String
    let steps: [String]
    var note: String? = nil
}

enum HelpContent {
    static let topics: [HelpTopic] = [
        .init(symbol: "plus.app.fill", color: .blue, title: "Как добавить IPA?", steps: [
            "Откройте вкладку «Приложения» и нажмите «Добавить приложение».",
            "Выберите .ipa-файл в «Файлах».",
            "Или в любом приложении нажмите «Поделиться» → «\(Brand.name)» на .ipa-файле.",
        ]),
        .init(symbol: "key.fill", color: .orange, title: "Как добавить сертификат?", steps: [
            "Откройте «Сертификаты» → «+» → «Добавить свой сертификат».",
            "Выберите файл .p12 (сертификат с закрытым ключом).",
            "Выберите .mobileprovision, выпущенный для этого сертификата.",
            "Введите пароль .p12, если он задан, и нажмите «Добавить».",
        ], note: "\(Brand.name) проверяет, что профиль действительно содержит ваш сертификат, — несовместимую пару добавить не получится."),
        .init(symbol: "signature", color: .purple, title: "Как подписать приложение?", steps: [
            "Откройте приложение из списка.",
            "Проверьте выбранный сертификат в разделе «Подпись».",
            "Нажмите «Подписать» и дождитесь окончания всех этапов.",
        ], note: "Если профиль выпущен под конкретный Bundle ID, он будет заменён автоматически — иначе iOS не установит приложение."),
        .init(symbol: "arrow.down.app.fill", color: .green, title: "Как установить приложение?", steps: [
            "После подписи нажмите «Установить».",
            "«Через „Поделиться“»: выберите SideStore, TrollStore или другой установщик.",
            "«OTA»: подтвердите установку в системном окне iOS.",
            "«Напрямую»: включите VPN-туннель — установка пройдёт через системную службу.",
        ]),
        .init(symbol: "arrow.triangle.2.circlepath", color: .indigo, title: "Как добавить сертификат из SideStore?", steps: [
            "Убедитесь, что установлен SideStore 0.6.2 или новее и вы вошли в Apple ID.",
            "В «Сертификатах» нажмите «Добавить из SideStore».",
            "В SideStore нажмите «Export» — вы вернётесь в \(Brand.name).",
            "Выберите provisioning profile для этого сертификата.",
        ], note: "SideStore передаёт только сертификат. Если окно экспорта не появилось, оставьте SideStore открытым в фоне и повторите."),
        .init(symbol: "clock.badge.exclamationmark.fill", color: .red, title: "Что делать, если сертификат истёк?", steps: [
            "Получите новый сертификат и профиль (или обновите их в SideStore).",
            "Добавьте их в «Сертификатах» и выберите как активный.",
            "Откройте нужные приложения и нажмите «Подписать заново», затем «Установить».",
        ], note: "Бесплатный Apple ID даёт подпись на 7 дней."),
        .init(symbol: "exclamationmark.arrow.circlepath", color: .pink, title: "Что делать, если установка не начинается?", steps: [
            "Проверьте способ установки в «Настройки → Установка».",
            "Для прямой установки: включите VPN-туннель и нажмите «Проверить подключение».",
            "Для OTA: домен должен указывать на 127.0.0.1, а TLS-сертификат быть действующим.",
            "Убедитесь, что устройство есть в provisioning profile («Настройки → Устройство»).",
            "Если ничего не помогло — выберите «Через „Поделиться“».",
        ]),
    ]

    static let errors: [(String, String)] = [
        ("Не удалось подписать приложение", "Сертификат и профиль не подходят друг к другу или профиль повреждён. Переимпортируйте оба файла."),
        ("Неверный пароль сертификата", "Введите пароль, заданный при экспорте .p12. У сертификатов из SideStore пароль передаётся автоматически."),
        ("Сертификат и профиль не совпадают", "Скачайте профиль, в который при создании был включён именно этот сертификат."),
        ("Движок подписи не подключён", "Сборка приложения собрана без zsign/OpenSSL. Это проблема сборки, а не ваших файлов."),
        ("«Невозможно установить приложение»", "Устройство не входит в профиль, подпись истекла или у приложения есть расширения, не разрешённые профилем."),
        ("Приложение установилось, но не открывается", "На iOS 16+ включите «Режим разработчика» в Настройки → Конфиденциальность и безопасность, и доверьте разработчику в Настройки → Основные → VPN и управление устройством."),
    ]
}

struct HelpView: View {
    var body: some View {
        List {
            Section("Инструкции") {
                ForEach(HelpContent.topics) { topic in
                    NavigationLink { HelpTopicView(topic: topic) } label: {
                        SettingsLabel(title: topic.title, symbol: topic.symbol, color: topic.color)
                    }
                }
            }
            Section("Частые ошибки") {
                ForEach(HelpContent.errors, id: \.0) { e in
                    DisclosureGroup {
                        Text(e.1).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 4)
                    } label: {
                        Text(e.0).font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .navigationTitle("Помощь")
    }
}

struct HelpTopicView: View {
    let topic: HelpTopic
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsIcon(symbol: topic.symbol, color: topic.color).scaleEffect(1.6).padding(.leading, 8).padding(.top, 8)
                Text(topic.title).font(.title2.weight(.bold))
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(topic.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(i + 1)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                .frame(width: 28, height: 28).background(topic.color, in: Circle())
                            Text(step).font(.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let note = topic.note {
                    Card {
                        Label(note, systemImage: "lightbulb.fill").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
