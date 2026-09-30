import SwiftUI

/// Screen shown after choosing an IPA: metadata, certificate choice, «Подписать».
struct AppDetailView: View {
    let appID: UUID
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var install = InstallFlow()
    @State private var signing = false
    @State private var confirmDelete = false

    var body: some View {
        if let item = library.item(appID) {
            content(item)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ item: AppItem) -> some View {
        List {
            Section {
                VStack(spacing: 12) {
                    AppIconView(url: item.iconPath.map(library.url), size: 96)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    Text(item.name).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    StatusPill(text: item.status.title, symbol: item.status.symbol, color: item.status.color)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("О приложении") {
                LabeledContent("Версия", value: "\(item.version) (\(item.build))")
                LabeledContent("Размер", value: item.sizeText)
                LabeledContent("Bundle ID") { Text(item.bundleID).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }
                if let os = item.minimumOS { LabeledContent("Минимальная iOS", value: os) }
            }

            Section {
                if certificates.certificates.isEmpty {
                    Button { env.selectedTab = .certificates } label: {
                        Label("Добавить сертификат", systemImage: "plus.circle")
                    }
                } else {
                    Picker("Сертификат", selection: $certificates.selectedID) {
                        ForEach(certificates.certificates) { c in
                            Text(c.displayName).tag(Optional(c.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    if let c = certificates.selected {
                        LabeledContent("Действует до") {
                            Text(c.expiresAt.shortDate).foregroundStyle(c.status.color)
                        }
                        if !c.profile.allows(bundleID: item.bundleID) {
                            Label("Профиль не подходит к этому Bundle ID — он будет заменён на \(c.profile.bundlePattern.replacingOccurrences(of: "*", with: item.bundleID))",
                                  systemImage: "info.circle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
            } header: { Text("Подпись") }

            if let s = item.signed {
                Section("Подписанная копия") {
                    LabeledContent("Сертификат", value: s.certificateName)
                    LabeledContent("Подписано", value: s.signedAt.shortDate)
                    LabeledContent("Подпись истекает") { Text(s.expiresAt.relativeExpiry).foregroundStyle(item.status.color) }
                    if s.signedBundleID != item.bundleID { LabeledContent("Новый Bundle ID", value: s.signedBundleID) }
                }
            }

            Section {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить приложение", systemImage: "trash") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actions(item) }
        .fullScreenCover(isPresented: $signing) { SigningView(item: item) }
        .installFlow(install, env: env)
        .confirmationDialog("Удалить «\(item.name)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { library.remove(item.id); dismiss() }
        } message: { Text("Будут удалены исходный и подписанный IPA. Установленное приложение останется на устройстве.") }
    }

    private func actions(_ item: AppItem) -> some View {
        VStack(spacing: 10) {
            if item.signed != nil, item.status != .expired {
                Button { install.request(item, env: env) } label: {
                    if install.isWorking { ProgressView().tint(.white) }
                    else { Label("Установить", systemImage: "arrow.down.circle.fill") }
                }
                .buttonStyle(PrimaryButtonStyle(tint: .green))
                Button("Подписать заново") { signing = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(certificates.selected == nil)
            } else {
                Button { signing = true } label: { Label("Подписать", systemImage: "signature") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(certificates.selected == nil)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
        .background(.bar)
    }
}
