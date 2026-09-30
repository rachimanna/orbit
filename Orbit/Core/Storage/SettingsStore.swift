import SwiftUI

/// All user preferences. Persisted in UserDefaults via @AppStorage-style properties.
@MainActor
final class SettingsStore: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { ["system": "Как в системе", "light": "Светлая", "dark": "Тёмная"][rawValue]! }
        var colorScheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
    }

    enum InstallMethod: String, CaseIterable, Identifiable {
        /// Hand the signed IPA to another app via the system share sheet (always available).
        case share
        /// Apple's OTA install (itms-services) served from an on-device HTTPS server.
        case otaServer
        /// Direct install over a lockdownd connection through a local VPN tunnel.
        case pairing

        var id: String { rawValue }
        var title: String {
            switch self {
            case .share: "Через «Поделиться»"
            case .otaServer: "OTA (itms-services)"
            case .pairing: "Напрямую через туннель"
            }
        }
        var subtitle: String {
            switch self {
            case .share: "Передать подписанный IPA в SideStore, TrollStore или другой установщик"
            case .otaServer: "Штатная установка iOS. Нужен свой домен и TLS-сертификат"
            case .pairing: "Нужны pairing-файл и VPN-туннель (LocalDevVPN)"
            }
        }
    }

    private let d = UserDefaults.standard

    @Published var appearance: Appearance { didSet { d.set(appearance.rawValue, forKey: "appearance") } }
    @Published var animationsEnabled: Bool { didSet { d.set(animationsEnabled, forKey: "animations") } }
    @Published var notificationsEnabled: Bool { didSet { d.set(notificationsEnabled, forKey: "notifications") } }

    @Published var installMethod: InstallMethod { didSet { d.set(installMethod.rawValue, forKey: "installMethod") } }
    @Published var autoInstallAfterSigning: Bool { didSet { d.set(autoInstallAfterSigning, forKey: "autoInstall") } }
    @Published var confirmBeforeInstall: Bool { didSet { d.set(confirmBeforeInstall, forKey: "confirmInstall") } }
    @Published var cleanTempAfterSigning: Bool { didSet { d.set(cleanTempAfterSigning, forKey: "cleanTemp") } }
    @Published var deleteIPAAfterInstall: Bool { didSet { d.set(deleteIPAAfterInstall, forKey: "deleteIPA") } }

    // Connection (pairing / tunnel)
    @Published var deviceHost: String { didSet { d.set(deviceHost, forKey: "host") } }
    @Published var devicePort: Int { didSet { d.set(devicePort, forKey: "port") } }
    @Published var connectionTimeout: Double { didSet { d.set(connectionTimeout, forKey: "timeout") } }

    // OTA server
    @Published var otaDomain: String { didSet { d.set(otaDomain, forKey: "otaDomain") } }
    @Published var otaPort: Int { didSet { d.set(otaPort, forKey: "otaPort") } }

    init() {
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        animationsEnabled = d.object(forKey: "animations") as? Bool ?? true
        notificationsEnabled = d.object(forKey: "notifications") as? Bool ?? true
        installMethod = InstallMethod(rawValue: d.string(forKey: "installMethod") ?? "") ?? .share
        autoInstallAfterSigning = d.bool(forKey: "autoInstall")
        confirmBeforeInstall = d.object(forKey: "confirmInstall") as? Bool ?? true
        cleanTempAfterSigning = d.object(forKey: "cleanTemp") as? Bool ?? true
        deleteIPAAfterInstall = d.bool(forKey: "deleteIPA")
        // 10.7.0.1 is the device address LocalDevVPN/StosVPN route back to; 62078 = lockdownd.
        deviceHost = d.string(forKey: "host") ?? "10.7.0.1"
        devicePort = d.object(forKey: "port") as? Int ?? 62078
        connectionTimeout = d.object(forKey: "timeout") as? Double ?? 3
        otaDomain = d.string(forKey: "otaDomain") ?? ""
        otaPort = d.object(forKey: "otaPort") as? Int ?? 8443
    }

    /// Animation helper that respects the «Анимации» toggle.
    var animation: Animation? { animationsEnabled ? .spring(response: 0.42, dampingFraction: 0.86) : nil }
}
