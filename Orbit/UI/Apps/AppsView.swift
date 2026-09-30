import SwiftUI
import UniformTypeIdentifiers

/// Reusable "pick an IPA and import it" behaviour.
struct IPAImporter: ViewModifier {
    @Binding var isPresented: Bool
    var onImported: (AppItem) -> Void
    @EnvironmentObject private var env: AppEnvironment

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.ipa, .tipa, .zip]) { result in
            guard case .success(let url) = result else { return }
            Task {
                do { onImported(try await env.library.importIPA(from: url)) }
                catch { env.banner = Banner(error: error) }
            }
        }
    }
}

extension View {
    func ipaImporter(isPresented: Binding<Bool>, onImported: @escaping (AppItem) -> Void) -> some View {
        modifier(IPAImporter(isPresented: isPresented, onImported: onImported))
    }
}

// MARK: - «Мои приложения»

struct AppsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var install = InstallFlow()
    @State private var path: [UUID] = []
    @State private var importing = false
    @State private var search = ""

    private var filtered: [AppItem] {
        search.isEmpty ? library.items
            : library.items.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.items.isEmpty {
                    EmptyStateView(symbol: "square.stack.3d.up",
                                   title: "Ваши приложения появятся здесь",
                                   message: "Добавьте .ipa-файл, чтобы подписать и установить его на это устройство.",
                                   actionTitle: "Добавить IPA") { importing = true }
                } else {
                    list
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Мои приложения")
            .navigationDestination(for: UUID.self) { AppDetailView(appID: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { importing = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                        .accessibilityLabel("Добавить приложение")
                }
            }
            .overlay { if library.isImporting { LoadingOverlay(text: "Чтение IPA…") } }
            .animation(settings.animation, value: library.isImporting)
        }
        .ipaImporter(isPresented: $importing) { path.append($0.id) }
        .installFlow(install, env: env)
        .onChange(of: env.pendingOpenApp) { _ in openPending() }
        .onAppear { openPending() }
    }

    private func openPending() {
        guard let id = env.pendingOpenApp else { return }
        path = [id]
        env.pendingOpenApp = nil
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Button { importing = true } label: {
                    Label("Добавить приложение", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, 4)

                ForEach(filtered) { item in
                    NavigationLink(value: item.id) {
                        AppRow(item: item) { primaryAction(item) }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { withAnimation(settings.animation) { library.remove(item.id) } } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .animation(settings.animation, value: library.items)
        }
        .searchable(text: $search, prompt: "Поиск")
    }

    private func primaryAction(_ item: AppItem) {
        switch item.status {
        case .signed, .installed, .expiringSoon: install.request(item, env: env)
        case .notSigned, .expired: path.append(item.id)
        }
    }
}

struct AppRow: View {
    let item: AppItem
    var action: () -> Void
    @EnvironmentObject private var library: AppLibrary

    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 14) {
                AppIconView(url: item.iconPath.map(library.url), size: 58)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.headline).lineLimit(1)
                    Text("Версия \(item.version)").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        StatusPill(text: item.status.title, symbol: item.status.symbol, color: item.status.color)
                        if let exp = item.signed?.expiresAt {
                            Text(exp.relativeExpiry).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 8)
                Button(buttonTitle, action: action).buttonStyle(PillButtonStyle(filled: item.signed != nil))
            }
        }
    }

    private var buttonTitle: String {
        switch item.status {
        case .notSigned: "Подписать"
        case .signed, .expiringSoon: "Установить"
        case .installed: "Ещё раз"
        case .expired: "Обновить"
        }
    }
}
