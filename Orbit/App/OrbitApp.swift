import SwiftUI

@main
struct OrbitApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(env.library)
                .environmentObject(env.certificates)
                .environmentObject(env.settings)
                .environmentObject(env.installer.tunnel)
                .tint(Brand.accent)
                .onOpenURL { env.handle(url: $0) }
        }
    }
}

/// Composition root: owns all services and stores. UI never creates services itself.
@MainActor
final class AppEnvironment: ObservableObject {
    let settings: SettingsStore
    let certificates: CertificateStore
    let library: AppLibrary
    let signer: AppSigner
    let installer: InstallCoordinator
    let sideStore = SideStoreBridge()

    @Published var selectedTab: RootTab = .home
    @Published var banner: Banner?
    /// App to open in the «Приложения» tab right after an import.
    @Published var pendingOpenApp: UUID?

    init() {
        let files = FileStore()
        let settings = SettingsStore()
        self.settings = settings
        certificates = CertificateStore(files: files)
        library = AppLibrary(files: files)
        signer = ZSignSigner()
        installer = InstallCoordinator(settings: settings)
    }

    /// Handles incoming URLs: SideStore certificate callback and IPA/.p12/.mobileprovision
    /// files opened via «Открыть в…» / «Поделиться».
    func handle(url: URL) {
        Task {
            do {
                if sideStore.isCallback(url) {
                    let payload = try sideStore.parseCallback(url)
                    try await certificates.importFromSideStore(payload)
                    selectedTab = .certificates
                    banner = Banner(title: "Сертификат импортирован", subtitle: "Из SideStore", kind: .success)
                    return
                }
                switch url.pathExtension.lowercased() {
                case "ipa", "tipa":
                    let item = try await library.importIPA(from: url)
                    selectedTab = .apps
                    pendingOpenApp = item.id
                    banner = Banner(title: "Приложение добавлено", subtitle: nil, kind: .success)
                case "p12", "mobileprovision":
                    certificates.pendingFileImport = url
                    selectedTab = .certificates
                default:
                    break
                }
            } catch {
                if certificates.pendingSideStoreP12 != nil { selectedTab = .certificates }
                banner = Banner(error: error)
            }
        }
    }
}
