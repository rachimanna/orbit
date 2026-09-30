import SwiftUI

/// Single source of truth for branding. Rename the app here (and in project.yml),
/// replace `BrandLogo` / `AppIcon` in Assets.xcassets — nothing else needs touching.
enum Brand {
    static let name = "Orbit"
    static let tagline = "Подписывайте и устанавливайте свои приложения"
    static let developer = "Your Name"
    static let website = URL(string: "https://example.com")!
    static let github = URL(string: "https://github.com/your-name/orbit")!
    static let supportEmail = "support@example.com"

    /// URL scheme registered in Info.plist — used for the SideStore certificate callback.
    static let urlScheme = "orbit"

    static let accent = Color("AccentColor")
    static let logo = Image("BrandLogo")

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
