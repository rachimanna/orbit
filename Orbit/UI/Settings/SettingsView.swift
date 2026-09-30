import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appleAccount: AppleAccountService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Brand.logo.resizable().scaledToFit().frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Brand.name).font(.title3.weight(.semibold))
                            Text("Версия \(Brand.version) (\(Brand.build))").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    NavigationLink { AppleAccountView() } label: {
                        HStack {
                            SettingsLabel(title: "Apple ID", symbol: "person.crop.circle.fill", color: .blue)
                            Spacer()
                            Text(appleAccount.account?.appleID ?? "Не выполнен вход")
                                .foregroundStyle(.secondary).font(.subheadline).lineLimit(1)
                        }
                    }
                    NavigationLink { CertificateSettingsView() } label: {
                        HStack {
                            SettingsLabel(title: "Сертификаты", symbol: "lock.shield.fill", color: .green)
                            Spacer()
                            if let c = certificates.selected {
                                Text(c.expiresAt.relativeExpiry).foregroundStyle(c.status.color).font(.subheadline)
                            }
                        }
                    }
                    NavigationLink { DeviceSettingsView() } label: {
                        SettingsLabel(title: "Устройство", symbol: "iphone", color: .gray)
                    }
                    NavigationLink { ConnectionSettingsView() } label: {
                        SettingsLabel(title: "Подключение", symbol: "network", color: .blue)
                    }
                    NavigationLink { InstallSettingsView() } label: {
                        HStack {
                            SettingsLabel(title: "Установка", symbol: "arrow.down.app.fill", color: .indigo)
                            Spacer()
                            Text(settings.installMethod.title).foregroundStyle(.secondary).font(.subheadline).lineLimit(1)
                        }
                    }
                    NavigationLink { InterfaceSettingsView() } label: {
                        SettingsLabel(title: "Интерфейс", symbol: "paintbrush.fill", color: .pink)
                    }
                }

                Section {
                    NavigationLink { HelpView() } label: {
                        SettingsLabel(title: "Помощь", symbol: "questionmark.circle.fill", color: .orange)
                    }
                    NavigationLink { DeveloperView() } label: {
                        SettingsLabel(title: "Разработчик", symbol: "hammer.fill", color: .brown)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Настройки")
        }
    }
}

// MARK: - Сертификаты

struct CertificateSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var certificates: CertificateStore

    var body: some View {
        List {
            Section("Активный сертификат") {
                if let c = certificates.selected {
                    CertificateRow(cert: c, selected: false)
                    LabeledContent("Истекает") { Text(c.expiresAt.relativeExpiry).foregroundStyle(c.status.color) }
                    if let profile = c.profile {
                        LabeledContent("Профиль истекает", value: profile.expiresAt.shortDate)
                    } else {
                        LabeledContent("Профили", value: "Через Apple ID")
                    }
                } else {
                    Text("Сертификат не добавлен").foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Управление сертификатами") { env.selectedTab = .certificates }
                Button("Добавить сертификат") { env.selectedTab = .certificates; certificates.pendingFileImport = nil }
                Button("Импорт из SideStore") { Task { try? await env.sideStore.requestCertificate(); env.selectedTab = .certificates } }
            } footer: {
                Text("Бесплатный Apple ID даёт подпись на 7 дней, платный Developer-аккаунт — до года.")
            }
        }
        .navigationTitle("Сертификаты")
    }
}

// MARK: - Устройство

struct DeviceSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var tunnel: TunnelInstaller

    var body: some View {
        let info = DeviceInfo.current
        return List {
            Section("Это устройство") {
                LabeledContent("Модель", value: info.model)
                LabeledContent("Идентификатор модели", value: info.modelIdentifier)
                LabeledContent("\(info.systemName)", value: info.systemVersion)
                if let v = info.vendorID {
                    LabeledContent("ID для поставщика") { Text(v).font(.caption.monospaced()).textSelection(.enabled) }
                }
            }
            Section {
                if let udid = tunnel.pairing?.udid {
                    LabeledContent("UDID") { Text(udid).font(.caption.monospaced()).textSelection(.enabled) }
                    if let c = certificates.selected, let profile = c.profile {
                        let included = profile.provisionsAllDevices || profileContains(udid, c)
                        LabeledContent("В профиле «\(profile.name)»") {
                            Label(included ? "Да" : "Нет", systemImage: included ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(included ? .green : .red)
                        }
                    }
                } else {
                    Text("UDID недоступен").foregroundStyle(.secondary)
                }
            } header: { Text("UDID и подпись") } footer: {
                Text("iOS не даёт приложениям читать UDID. Он показывается только из pairing-файла, который вы сами импортировали в «Подключение». Там же видно, включено ли устройство в выбранный профиль.")
            }
        }
        .navigationTitle("Устройство")
    }

    private func profileContains(_ udid: String, _ c: SigningCertificate) -> Bool {
        guard let url = certificates.profileURL(c), let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let devices = plist["ProvisionedDevices"] as? [String] else { return false }
        return devices.contains { $0.caseInsensitiveCompare(udid) == .orderedSame }
    }
}

// MARK: - Подключение

struct ConnectionSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var tunnel: TunnelInstaller
    @State private var importing = false
    @State private var error: UserFacingError?

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Статус")
                    Spacer()
                    Label(tunnel.state.title, systemImage: statusSymbol).foregroundStyle(statusColor).font(.subheadline)
                }
                Button {
                    Task { await tunnel.testConnection(host: settings.deviceHost, port: settings.devicePort, timeout: settings.connectionTimeout) }
                } label: {
                    if tunnel.state == .testing { ProgressView() } else { Text("Проверить подключение") }
                }
                if case .unreachable(let reason) = tunnel.state {
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Проверка открывает реальное TCP-соединение к указанному адресу через туннель.")
            }

            Section("Адрес") {
                LabeledContent("IP-адрес") {
                    TextField("10.7.0.1", text: $settings.deviceHost)
                        .multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                LabeledContent("Порт") {
                    TextField("62078", value: $settings.devicePort, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing).keyboardType(.numberPad)
                }
            }

            Section {
                LabeledContent("Туннель", value: "LocalDevVPN / StosVPN")
                Link("Как настроить туннель", destination: URL(string: "https://docs.sidestore.io")!)
            } header: { Text("Туннель") } footer: {
                Text("VPN-туннель заворачивает трафик на 10.7.0.1 обратно на это устройство, чтобы приложение могло говорить с системной службой установки.")
            }

            Section {
                if let p = tunnel.pairing {
                    LabeledContent("Pairing-файл", value: "Импортирован")
                    if let h = p.hostID { LabeledContent("Host ID") { Text(h).font(.caption.monospaced()).lineLimit(1) } }
                    if let udid = p.udid { LabeledContent("UDID") { Text(udid).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle) } }
                    Button("Удалить pairing-файл", role: .destructive) { tunnel.removePairingFile() }
                } else {
                    Button("Получить из SideStore") {
                        Task {
                            do { try await env.sideStore.requestPairingFile() }
                            catch { self.error = UserFacingError.wrap(error) }
                        }
                    }
                    Button("Импортировать pairing-файл") { importing = true }
                }
            } header: { Text("Pairing") } footer: {
                Text("Pairing-файл нужен для прямой установки и для регистрации устройства через Apple ID (в нём UDID). SideStore 0.6.2+ отдаёт его по запросу, также его создают Impactor или jitterbugpair.")
            }

            Section("Дополнительно") {
                Stepper(value: $settings.connectionTimeout, in: 1...15, step: 1) {
                    LabeledContent("Таймаут", value: "\(Int(settings.connectionTimeout)) с")
                }
                Button("Сбросить адрес по умолчанию") {
                    settings.deviceHost = "10.7.0.1"; settings.devicePort = 62078
                }
            }
        }
        .navigationTitle("Подключение")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pairing, .propertyList, .data]) { result in
            guard case .success(let url) = result else { return }
            do { try tunnel.importPairingFile(url) } catch { self.error = UserFacingError.wrap(error) }
        }
        .alert(error?.title ?? "", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error?.hint ?? "") }
    }

    private var statusSymbol: String {
        switch tunnel.state {
        case .reachable: "circle.fill"
        case .unreachable: "exclamationmark.circle.fill"
        default: "circle.dashed"
        }
    }
    private var statusColor: Color {
        switch tunnel.state {
        case .reachable: .green
        case .unreachable: .red
        default: .secondary
        }
    }
}

// MARK: - Установка

struct InstallSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: AppLibrary
    @State private var tempSize: Int64 = 0
    @State private var importingTLS = false
    @State private var tlsPassword = ""
    @State private var askTLSPassword = false
    @State private var pickedTLS: URL?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(SettingsStore.InstallMethod.allCases) { m in
                    Button { settings.installMethod = m } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.title).foregroundStyle(.primary)
                                Text(m.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.installMethod == m {
                                Image(systemName: "checkmark").foregroundStyle(Brand.accent).font(.body.weight(.semibold))
                            }
                        }
                    }
                }
            } header: { Text("Способ установки") } footer: {
                Text("iOS не позволяет обычному приложению ставить другие приложения молча. Каждый способ передаёт подписанный IPA системе или другому установщику — и iOS всегда спрашивает подтверждение.")
            }

            if settings.installMethod == .otaServer {
                Section {
                    LabeledContent("Домен") {
                        TextField("local.example.com", text: $settings.otaDomain)
                            .multilineTextAlignment(.trailing).autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    LabeledContent("Порт") {
                        TextField("8443", value: $settings.otaPort, format: .number.grouping(.never))
                            .multilineTextAlignment(.trailing).keyboardType(.numberPad)
                    }
                    Button(OTAServer.hasIdentity ? "Заменить TLS-сертификат" : "Импортировать TLS-сертификат (.p12)") { importingTLS = true }
                } header: { Text("OTA-сервер") } footer: {
                    Text("Домен должен указывать на 127.0.0.1, а TLS-сертификат — быть выпущен для него доверенным центром (например, Let's Encrypt).")
                }
            }

            Section("Поведение") {
                Toggle("Устанавливать после подписи", isOn: $settings.autoInstallAfterSigning)
                Toggle("Подтверждать перед установкой", isOn: $settings.confirmBeforeInstall)
            }

            Section {
                Toggle("Очищать временные файлы", isOn: $settings.cleanTempAfterSigning)
                Toggle("Удалять IPA после установки", isOn: $settings.deleteIPAAfterInstall)
                Button {
                    library.fileStore.clearWork()
                    tempSize = library.fileStore.workSize()
                } label: {
                    LabeledContent("Очистить сейчас", value: ByteCountFormatter.string(fromByteCount: tempSize, countStyle: .file))
                }
            } header: { Text("Хранилище") } footer: {
                Text("«Удалять IPA» удаляет исходный файл, подписанная копия остаётся для переустановки.")
            }
        }
        .navigationTitle("Установка")
        .onAppear { tempSize = library.fileStore.workSize() }
        .fileImporter(isPresented: $importingTLS, allowedContentTypes: [.p12, .pkcs12]) { result in
            if case .success(let url) = result { pickedTLS = url; askTLSPassword = true }
        }
        .alert("Пароль TLS-сертификата", isPresented: $askTLSPassword) {
            SecureField("Пароль", text: $tlsPassword)
            Button("Импортировать") {
                guard let url = pickedTLS else { return }
                do { try OTAServer.importIdentity(from: url, password: tlsPassword); message = "TLS-сертификат импортирован" }
                catch { message = UserFacingError.wrap(error).title }
                tlsPassword = ""
            }
            Button("Отмена", role: .cancel) { tlsPassword = "" }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: - Интерфейс

struct InterfaceSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var notificationStatus = "—"

    var body: some View {
        List {
            Section("Оформление") {
                Picker("Тема", selection: $settings.appearance) {
                    ForEach(SettingsStore.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                Toggle("Анимации", isOn: $settings.animationsEnabled)
            } footer: {
                Text("Системная настройка «Уменьшение движения» учитывается автоматически.")
            }
            Section {
                Toggle("Уведомления", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { on in if on { Task { await Notifications.request() } } }
                LabeledContent("Разрешение iOS", value: notificationStatus)
            } header: { Text("Уведомления") } footer: {
                Text("Напоминание за день до истечения подписи приложений.")
            }
        }
        .navigationTitle("Интерфейс")
        .task { notificationStatus = await Notifications.statusText() }
    }
}
