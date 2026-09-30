import SwiftUI

/// Overview: brand header, signing readiness, big «Добавить приложение», recent apps.
struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var certificates: CertificateStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var importing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    Button { importing = true } label: { Label("Добавить приложение", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle())
                    certificateCard
                    stats
                    recent
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(Brand.name)
            .overlay { if library.isImporting { LoadingOverlay(text: "Чтение IPA…") } }
        }
        .ipaImporter(isPresented: $importing) { item in
            env.selectedTab = .apps
            env.pendingOpenApp = item.id
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            Brand.logo.resizable().scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.title3.weight(.semibold))
                Text(Brand.tagline).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Доброе утро"
        case 12..<18: "Добрый день"
        default: "Добрый вечер"
        }
    }

    @ViewBuilder private var certificateCard: some View {
        if let c = certificates.selected {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: c.status.symbol).font(.title).foregroundStyle(c.status.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.displayName).font(.headline).lineLimit(1)
                        Text("\(c.status.title) · до \(c.expiresAt.shortDate)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .onTapGesture { env.selectedTab = .certificates }
        } else {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Добавьте сертификат для подписания", systemImage: "lock.shield")
                        .font(.headline)
                    Text("Без сертификата и provisioning profile подписать приложение нельзя.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Добавить сертификат") { env.selectedTab = .certificates }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            stat(value: library.items.count, title: "Приложений", symbol: "square.stack.3d.up.fill", color: .blue)
            stat(value: library.items.filter { $0.signed != nil && $0.status != .expired }.count,
                 title: "Подписано", symbol: "checkmark.seal.fill", color: .green)
            stat(value: library.items.filter { $0.status == .expired || $0.status == .expiringSoon }.count,
                 title: "Истекает", symbol: "clock.fill", color: .orange)
        }
    }

    private func stat(value: Int, title: String, symbol: String, color: Color) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(color)
                Text("\(value)").font(.title2.weight(.bold)).contentTransition(.numericText())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var recent: some View {
        Text("Недавние").font(.title3.weight(.semibold)).padding(.top, 4)
        if library.items.isEmpty {
            Card {
                HStack {
                    Image(systemName: "tray").foregroundStyle(.secondary)
                    Text("Ваши приложения появятся здесь").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        } else {
            ForEach(library.items.prefix(3)) { item in
                AppRow(item: item) { env.selectedTab = .apps; env.pendingOpenApp = item.id }
                    .onTapGesture { env.selectedTab = .apps; env.pendingOpenApp = item.id }
            }
        }
    }
}
