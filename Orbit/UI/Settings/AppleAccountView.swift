import SwiftUI
import SideSign

/// «Настройки → Apple ID»: sign in to get provisioning profiles the way SideStore does.
struct AppleAccountView: View {
    @EnvironmentObject private var account: AppleAccountService
    @EnvironmentObject private var tunnel: TunnelInstaller
    @EnvironmentObject private var settings: SettingsStore
    @State private var confirmSignOut = false

    var body: some View {
        List {
            if let stored = account.account {
                Section {
                    LabeledContent("Apple ID", value: stored.appleID)
                    LabeledContent("Имя", value: stored.name)
                    LabeledContent("Команда", value: stored.team.name)
                    LabeledContent("Team ID") { Text(stored.team.identifier).textSelection(.enabled) }
                    LabeledContent("Тип", value: stored.team.type == .free ? "Бесплатный" : "Платный")
                } header: { Text("Аккаунт") } footer: {
                    Text("Для каждого подписываемого приложения \(Brand.name) регистрирует App ID и получает свежий профиль. Бесплатный аккаунт: до 10 App ID за 7 дней, подпись действует 7 дней.")
                }
                Section {
                    if let usage = account.appIDUsage {
                        if let limit = usage.limit {
                            LabeledContent("App ID занято") {
                                Text("\(usage.used) из \(limit)")
                                    .foregroundStyle(usage.available == 0 ? .red : .secondary)
                            }
                            if let next = usage.nextFree {
                                LabeledContent("Следующий освободится",
                                               value: next.formatted(date: .abbreviated, time: .shortened))
                            }
                        } else {
                            LabeledContent("App ID", value: "\(usage.used), без недельного лимита")
                        }
                    } else {
                        LabeledContent("App ID") { ProgressView() }
                    }
                    Toggle("Подписывать без расширений", isOn: $settings.removeExtensions)
                } header: { Text("App ID") } footer: {
                    Text("Каждое приложение и каждое его расширение (виджет, уведомления, «Поделиться») занимают отдельный App ID. Без расширений приложению нужен один App ID, но виджеты и подобные функции работать не будут.")
                }
                .task { await account.refreshAppIDUsage() }
                Section {
                    Button("Выйти", role: .destructive) { confirmSignOut = true }
                }
            } else {
                AppleSignInForm()
            }

            Section {
                if let udid = tunnel.pairing?.udid {
                    LabeledContent("UDID") { Text(udid).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle) }
                } else {
                    NavigationLink { ConnectionSettingsView() } label: {
                        Label("Добавьте pairing-файл — нужен UDID", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: { Text("Устройство") } footer: {
                Text("Apple выдаёт профиль только для зарегистрированного устройства. UDID берётся из pairing-файла, его можно получить из SideStore в «Подключение».")
            }

            Section {
                TextField(AppleAccountService.defaultAnisetteServer, text: $account.anisetteServer)
                    .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                if account.anisetteServer != AppleAccountService.defaultAnisetteServer {
                    Button("Сбросить по умолчанию") { account.anisetteServer = AppleAccountService.defaultAnisetteServer }
                }
            } header: { Text("Anisette-сервер") } footer: {
                Text("Apple требует данные «Mac-устройства» при входе. Их выдаёт anisette-сервер (тот же, что у SideStore). Логин и пароль на него не передаются.")
            }
        }
        .navigationTitle("Apple ID")
        .confirmationDialog("Выйти из Apple ID?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { account.signOut() }
        } message: {
            Text("Уже подписанные приложения продолжат работать. Для новой подписи понадобится войти снова.")
        }
    }
}

/// Apple ID + password form. Used in settings and in the SideStore import sheet.
struct AppleSignInForm: View {
    var onSignedIn: () -> Void = {}
    @EnvironmentObject private var account: AppleAccountService
    @State private var appleID = ""
    @State private var password = ""
    @State private var error: UserFacingError?

    var body: some View {
        Section {
            TextField("Apple ID (e-mail)", text: $appleID)
                .textContentType(.username).keyboardType(.emailAddress)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            SecureField("Пароль", text: $password)
                .textContentType(.password)
            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    Text("Войти")
                    Spacer()
                    if account.isWorking { ProgressView() }
                }
            }
            .disabled(appleID.isEmpty || password.isEmpty || account.isWorking)
        } header: { Text("Вход в Apple ID") } footer: {
            Text("Пароль передаётся только Apple (по протоколу SRP) и хранится в Связке ключей этого устройства, чтобы обновлять профили. Рекомендуется отдельный Apple ID, как и для SideStore.")
        }
        if let error {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.title).font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                    Text(error.hint).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func signIn() async {
        error = nil
        do {
            try await account.signIn(appleID: appleID.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
            onSignedIn()
        } catch {
            withAnimation { self.error = UserFacingError.wrap(error) }
        }
    }
}

/// Verification code sheet, shown whenever Apple asks for 2FA.
struct TwoFactorSheet: View {
    let prompt: AppleAccountService.CodePrompt
    @EnvironmentObject private var account: AppleAccountService
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: prompt.sentBySMS ? "message.fill" : "lock.iphone")
                    .font(.system(size: 46)).foregroundStyle(Brand.accent)
                Text("Код подтверждения").font(.title3.weight(.semibold))
                Text(prompt.sentBySMS
                     ? "Введите 6-значный код из SMS."
                     : "Введите 6-значный код, который появился на вашем другом устройстве Apple.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let error = prompt.error {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                TextField("000000", text: $code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onChange(of: code) { value in
                        if value.filter(\.isNumber).count == 6 { account.submitCode(value) }
                    }
                Button("Подтвердить") { account.submitCode(code) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(code.filter(\.isNumber).count < 6)
                if prompt.canRequestSMS {
                    Button("Получить код по SMS") { account.requestSMS() }
                        .font(.subheadline)
                }
                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { account.cancelCode() } }
            }
            .onAppear { focused = true }
        }
        .interactiveDismissDisabled()
    }
}
