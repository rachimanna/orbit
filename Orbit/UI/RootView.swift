import SwiftUI

enum RootTab: Hashable { case home, apps, certificates, settings }

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appleAccount: AppleAccountService

    var body: some View {
        TabView(selection: $env.selectedTab) {
            HomeView()
                .tabItem { Label("Главная", systemImage: "house.fill") }
                .tag(RootTab.home)
            AppsView()
                .tabItem { Label("Приложения", systemImage: "square.stack.3d.up.fill") }
                .tag(RootTab.apps)
            CertificatesView()
                .tabItem { Label("Сертификаты", systemImage: "lock.shield.fill") }
                .tag(RootTab.certificates)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
                .tag(RootTab.settings)
        }
        .overlay(alignment: .top) {
            if let banner = env.banner {
                BannerView(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { env.banner = nil }
                    .task(id: banner.id) {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        if env.banner?.id == banner.id { env.banner = nil }
                    }
            }
        }
        .animation(settings.animation, value: env.banner)
        // Apple may ask for a 2FA code during any sign-in or profile refresh.
        .sheet(item: $appleAccount.codePrompt) { TwoFactorSheet(prompt: $0) }
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}
