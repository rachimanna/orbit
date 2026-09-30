import UIKit

/// Decides how a signed IPA reaches the system installer, per the user's chosen method.
/// Never reports success on its own: the only "success" we can observe is iOS
/// accepting the itms-services request or the user handing the file to another app.
@MainActor
final class InstallCoordinator: ObservableObject {
    enum Outcome {
        /// Show the system share sheet with this file (SideStore / TrollStore / Files…).
        case presentShareSheet(URL)
        /// iOS accepted the install request and shows its own confirmation alert.
        case handedToSystem
    }

    private let settings: SettingsStore
    let ota = OTAServer()
    let tunnel = TunnelInstaller()

    init(settings: SettingsStore) { self.settings = settings }

    func install(_ item: AppItem, signedIPA: URL, icon: URL?, method: SettingsStore.InstallMethod? = nil) async throws -> Outcome {
        switch method ?? settings.installMethod {
        case .share:
            return .presentShareSheet(signedIPA)

        case .otaServer:
            let url = try await ota.serve(ipa: signedIPA, icon: icon, bundleID: item.signed?.signedBundleID ?? item.bundleID,
                                          version: item.version, title: item.name,
                                          domain: settings.otaDomain, port: settings.otaPort)
            guard await UIApplication.shared.open(url) else { throw UserFacingError.installUnavailable }
            return .handedToSystem

        case .pairing:
            try await tunnel.install(ipa: signedIPA,
                                     host: settings.deviceHost, port: settings.devicePort,
                                     timeout: settings.connectionTimeout)
            return .handedToSystem
        }
    }
}
