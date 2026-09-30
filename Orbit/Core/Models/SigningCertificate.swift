import Foundation

/// A signing identity: a .p12 (certificate + private key) paired with a .mobileprovision.
/// The .p12 password lives in the Keychain, never in this struct.
struct SigningCertificate: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String          // CN of the certificate, e.g. "Apple Development: …"
    var teamID: String
    var teamName: String
    var certificateExpiresAt: Date?  // from the X.509 NotAfter field
    var profile: ProvisioningProfile
    var source: Source
    var addedAt: Date

    var p12Path: String
    var profilePath: String

    enum Source: String, Codable { case manual, sideStore }

    /// The effective expiry for signed apps.
    var expiresAt: Date {
        [certificateExpiresAt, profile.expiresAt].compactMap { $0 }.min() ?? profile.expiresAt
    }

    enum Status: Equatable {
        case valid, expiringSoon, expired
        var title: String {
            switch self {
            case .valid: "Действителен"
            case .expiringSoon: "Скоро истечёт"
            case .expired: "Истёк"
            }
        }
    }

    var status: Status {
        let left = expiresAt.timeIntervalSinceNow
        if left <= 0 { return .expired }
        if left < 3 * 86_400 { return .expiringSoon }
        return .valid
    }
}

/// Fields parsed from the plist embedded in a CMS-signed .mobileprovision.
struct ProvisioningProfile: Codable, Hashable {
    var name: String
    var uuid: String
    var teamID: String
    var teamName: String
    var appIDName: String
    /// e.g. "ABCDE12345.*" or "ABCDE12345.com.example.app"
    var applicationIdentifier: String
    var createdAt: Date
    var expiresAt: Date
    var provisionedDeviceCount: Int?   // nil = enterprise / "ProvisionsAllDevices"
    var provisionsAllDevices: Bool
    var isDevelopment: Bool            // get-task-allow
    var entitlementKeys: [String]

    /// Bundle ID pattern without the team prefix.
    var bundlePattern: String {
        applicationIdentifier.split(separator: ".", maxSplits: 1).last.map(String.init) ?? applicationIdentifier
    }
    var isWildcard: Bool { bundlePattern == "*" || bundlePattern.hasSuffix(".*") }

    func allows(bundleID: String) -> Bool {
        if bundlePattern == "*" { return true }
        if bundlePattern.hasSuffix(".*") { return bundleID.hasPrefix(String(bundlePattern.dropLast())) }
        return bundlePattern == bundleID
    }
}
