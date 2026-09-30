import SwiftUI

struct CertificatesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var adding = false
    @State private var sideStoreHelp = false
    @State private var completingSideStore = false

    var body: some View {
        NavigationStack {
            Group {
                if certificates.certificates.isEmpty {
                    ScrollView {
                        EmptyStateView(symbol: "lock.shield",
                                       title: "Добавьте сертификат для подписания",
                                       message: "Нужны файл .p12 и provisioning profile (.mobileprovision) — или импорт из SideStore.",
                                       actionTitle: "Добавить сертификат") { adding = true }
                        Button { requestSideStore() } label: {
                            Label("Добавить из SideStore", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(maxWidth: 280)
                    }
                } else {
                    list
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Сертификаты")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { adding = true } label: { Label("Добавить свой сертификат", systemImage: "doc.badge.plus") }
                        Button { requestSideStore() } label: { Label("Добавить из SideStore", systemImage: "arrow.triangle.2.circlepath") }
                    } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                }
            }
            .navigationDestination(for: UUID.self) { CertificateDetailView(id: $0) }
        }
        .sheet(isPresented: $adding) { AddCertificateSheet(prefill: certificates.pendingFileImport) }
        .sheet(isPresented: $sideStoreHelp) { SideStoreFallbackSheet(onPickFiles: { sideStoreHelp = false; adding = true }) }
        .sheet(isPresented: $completingSideStore) { SideStoreProfileSheet() }
        .onChange(of: certificates.pendingFileImport) { url in if url != nil { adding = true } }
        .onChange(of: certificates.pendingSideStoreP12) { p in completingSideStore = p != nil }
        .onAppear {
            if certificates.pendingFileImport != nil { adding = true }
            if certificates.pendingSideStoreP12 != nil { completingSideStore = true }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(certificates.certificates) { c in
                    NavigationLink(value: c.id) { CertificateRow(cert: c, selected: c.id == certificates.selectedID) }
                        .swipeActions {
                            Button(role: .destructive) { withAnimation(settings.animation) { certificates.delete(c) } } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            if c.id != certificates.selectedID {
                                Button { certificates.selectedID = c.id } label: { Label("Выбрать", systemImage: "checkmark") }
                                    .tint(Brand.accent)
                            }
                        }
                }
            } header: { Text("Мои сертификаты") } footer: {
                Text("Выбранный сертификат используется для подписи. Смахните влево, чтобы выбрать или удалить.")
            }

            Section {
                Button { adding = true } label: { SettingsLabel(title: "Добавить свой сертификат", symbol: "doc.badge.plus", color: .blue) }
                Button { requestSideStore() } label: { SettingsLabel(title: "Добавить из SideStore", symbol: "arrow.triangle.2.circlepath", color: .purple) }
            }
            .foregroundStyle(.primary)
        }
        .listStyle(.insetGrouped)
    }

    private func requestSideStore() {
        Task {
            do { try await env.sideStore.requestCertificate() }
            catch { sideStoreHelp = true }
        }
    }
}

struct CertificateRow: View {
    let cert: SigningCertificate
    let selected: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: cert.status.symbol).font(.title2).foregroundStyle(cert.status.color).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(cert.displayName).font(.body.weight(.medium)).lineLimit(1)
                Text("\(cert.teamName) · до \(cert.expiresAt.shortDate)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if selected { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Brand.accent) }
        }
        .padding(.vertical, 4)
    }
}

struct CertificateDetailView: View {
    let id: UUID
    @EnvironmentObject private var certificates: CertificateStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        if let c = certificates.certificates.first(where: { $0.id == id }) {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: c.status.symbol).font(.system(size: 52)).foregroundStyle(c.status.color)
                        Text(c.displayName).font(.headline).multilineTextAlignment(.center)
                        StatusPill(text: c.status.title, symbol: "circle.fill", color: c.status.color)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }
                Section("Сертификат") {
                    LabeledContent("Команда", value: c.teamName)
                    LabeledContent("Team ID") { Text(c.teamID).textSelection(.enabled) }
                    if let exp = c.certificateExpiresAt { LabeledContent("Действует до", value: exp.shortDate) }
                    LabeledContent("Источник", value: c.source == .sideStore ? "SideStore" : "Файл")
                    LabeledContent("Добавлен", value: c.addedAt.shortDate)
                }
                Section("Provisioning Profile") {
                    LabeledContent("Название", value: c.profile.name)
                    LabeledContent("App ID") { Text(c.profile.bundlePattern).textSelection(.enabled) }
                    LabeledContent("Тип", value: c.profile.isDevelopment ? "Development" : "Distribution")
                    LabeledContent("Устройства", value: c.profile.provisionsAllDevices ? "Все (Enterprise)" : "\(c.profile.provisionedDeviceCount ?? 0)")
                    LabeledContent("Истекает", value: c.profile.expiresAt.shortDate)
                    LabeledContent("UUID") { Text(c.profile.uuid).font(.caption.monospaced()).textSelection(.enabled) }
                }
                if !c.profile.entitlementKeys.isEmpty {
                    Section("Entitlements") {
                        ForEach(c.profile.entitlementKeys, id: \.self) { Text($0).font(.caption.monospaced()) }
                    }
                }
                Section {
                    if certificates.selectedID != c.id {
                        Button("Использовать для подписи") { certificates.selectedID = c.id }
                    }
                    Button("Удалить сертификат", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Сертификат")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Удалить сертификат?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { certificates.delete(c); dismiss() }
            } message: { Text("Уже подписанные приложения продолжат работать до истечения подписи.") }
        }
    }
}

// MARK: - Add sheet

struct AddCertificateSheet: View {
    var prefill: URL?
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var certificates: CertificateStore
    @Environment(\.dismiss) private var dismiss

    @State private var p12: URL?
    @State private var profile: URL?
    @State private var password = ""
    @State private var picking: Kind?
    @State private var working = false
    @State private var error: UserFacingError?

    enum Kind: Identifiable { case p12, profile; var id: Self { self } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    fileRow(title: "Сертификат (.p12)", url: p12, symbol: "key.fill", color: .orange) { picking = .p12 }
                    fileRow(title: "Профиль (.mobileprovision)", url: profile, symbol: "doc.text.fill", color: .blue) { picking = .profile }
                } header: { Text("Файлы") } footer: {
                    Text("Оба файла выдаются в Apple Developer Portal. Файлы также можно открыть в \(Brand.name) через «Поделиться».")
                }
                Section {
                    SecureField("Пароль (если есть)", text: $password)
                        .textContentType(.password)
                } header: { Text("Пароль сертификата") } footer: {
                    Text("Пароль хранится в Связке ключей и не покидает устройство.")
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
            .navigationTitle("Новый сертификат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { close() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Добавить") { Task { await save() } }.disabled(p12 == nil || profile == nil)
                    }
                }
            }
            .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                          allowedContentTypes: picking == .p12 ? [.p12, .pkcs12] : [.mobileProvision, .data]) { result in
                guard case .success(let url) = result else { return }
                if picking == .p12 || url.pathExtension.lowercased() == "p12" { p12 = url } else { profile = url }
                picking = nil
            }
            .onAppear {
                guard let prefill else { return }
                if prefill.pathExtension.lowercased() == "p12" { p12 = prefill } else { profile = prefill }
            }
        }
    }

    private func fileRow(title: String, url: URL?, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                SettingsLabel(title: title, symbol: symbol, color: color)
                Spacer()
                if let url {
                    Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("Выбрать").foregroundStyle(Brand.accent)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func save() async {
        guard let p12, let profile else { return }
        working = true; error = nil
        defer { working = false }
        do {
            let c = try await certificates.importFiles(p12: p12, profile: profile, password: password)
            env.banner = Banner(title: "Сертификат добавлен", subtitle: c.displayName, kind: .success)
            close()
        } catch {
            withAnimation { self.error = UserFacingError.wrap(error) }
        }
    }

    private func close() {
        certificates.pendingFileImport = nil
        dismiss()
    }
}

// MARK: - SideStore sheets

/// Shown when SideStore isn't installed or refused the URL — explains the manual path.
struct SideStoreFallbackSheet: View {
    var onPickFiles: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Автоматический импорт требует SideStore 0.6.2 или новее, установленный на этом устройстве.",
                          systemImage: "info.circle")
                }
                Section("Если SideStore установлен") {
                    step(1, "Откройте SideStore и убедитесь, что вы вошли в Apple ID.")
                    step(2, "Вернитесь в \(Brand.name) и нажмите «Добавить из SideStore» ещё раз.")
                    step(3, "В SideStore нажмите «Export» — сертификат вернётся сюда автоматически.")
                }
                Section("Вручную") {
                    step(1, "Экспортируйте сертификат .p12 и профиль .mobileprovision.")
                    step(2, "Откройте их в \(Brand.name) через «Поделиться» или выберите файлами.")
                    Button("Выбрать файлы") { onPickFiles() }
                }
            }
            .navigationTitle("Импорт из SideStore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.footnote.weight(.bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Brand.accent, in: Circle())
            Text(text).font(.subheadline)
        }
    }
}

/// SideStore returns only the certificate; this sheet collects the matching profile.
struct SideStoreProfileSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var certificates: CertificateStore
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var error: UserFacingError?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(.green)
                Text("Сертификат получен из SideStore").font(.title3.weight(.semibold))
                Text("Чтобы подписывать приложения, добавьте provisioning profile, выпущенный для этого сертификата.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let error { ErrorCard(error: error) }
                Spacer()
                Button("Выбрать .mobileprovision") { picking = true }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { certificates.pendingSideStoreP12 = nil; dismiss() }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.mobileProvision, .data]) { result in
                guard case .success(let url) = result else { return }
                do {
                    try certificates.completeSideStoreImport(profile: url)
                    env.banner = Banner(title: "Сертификат импортирован", subtitle: "Из SideStore", kind: .success)
                    dismiss()
                } catch { self.error = UserFacingError.wrap(error) }
            }
        }
    }
}
