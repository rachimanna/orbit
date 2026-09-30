import Foundation
import ZIPFoundation

/// Stages shown on the signing screen. Each is reported only when it really starts.
enum SigningStage: Int, CaseIterable {
    case preparing, provisioning, verifying, signing, packaging

    var title: String {
        switch self {
        case .preparing: "Подготовка приложения…"
        case .provisioning: "Получение профиля от Apple…"
        case .verifying: "Проверка сертификата…"
        case .signing: "Подписание…"
        case .packaging: "Подготовка к установке…"
        }
    }
    var symbol: String {
        switch self {
        case .preparing: "shippingbox"
        case .provisioning: "person.badge.key"
        case .verifying: "checkmark.shield"
        case .signing: "signature"
        case .packaging: "arrow.down.app"
        }
    }
}

struct SigningRequest {
    var ipa: URL
    var appName: String
    var originalBundleID: String
    var certificate: SigningCertificate
    var p12: URL
    var password: String
    var profile: ProfileSource
    var output: URL
    var workDir: URL
    var cleanWorkDir: Bool
}

enum ProfileSource {
    /// A .mobileprovision the user imported with the certificate.
    case file(URL)
    /// Fetched from Apple for this app: (bundle ID, extension bundle IDs) → profiles.
    case appleAccount(@Sendable (_ bundleID: String, _ extensionBundleIDs: [String]) async throws -> AppleAccountService.Provisioned)
}

struct SigningResult {
    var signedIPA: URL
    var bundleID: String
    var expiresAt: Date
}

/// Abstraction so the UI never knows which engine signs.
protocol AppSigner {
    var isAvailable: Bool { get }
    func sign(_ request: SigningRequest, progress: @escaping @Sendable (SigningStage) async -> Void) async throws -> SigningResult
}

/// On-device signing with zsign: unzip → verify → sign .app → zip.
struct ZSignSigner: AppSigner {
    var isAvailable: Bool { ZSignBridge.isAvailable() }

    func sign(_ r: SigningRequest, progress: @escaping @Sendable (SigningStage) async -> Void) async throws -> SigningResult {
        guard isAvailable else { throw UserFacingError.signingEngineMissing }
        let fm = FileManager.default
        defer { if r.cleanWorkDir { try? fm.removeItem(at: r.workDir) } }

        // 1. Unpack
        await progress(.preparing)
        try await Task.detached(priority: .userInitiated) {
            try fm.unzipItem(at: r.ipa, to: r.workDir)
        }.value
        let payload = r.workDir.appendingPathComponent("Payload")
        guard let appName = try fm.contentsOfDirectory(atPath: payload.path).first(where: { $0.hasSuffix(".app") }) else {
            throw UserFacingError.invalidIPA
        }
        let appDir = payload.appendingPathComponent(appName)

        // 2. Profiles: the imported one, or fresh ones from Apple for this exact app
        let profileURLs: [URL]
        var fixedBundleID: String?
        switch r.profile {
        case .file(let url):
            profileURLs = [url]
        case .appleAccount(let provision):
            await progress(.provisioning)
            let provisioned = try await provision(r.originalBundleID, try Self.extensionBundleIDs(in: appDir, of: r.originalBundleID))
            profileURLs = try provisioned.profiles.enumerated().map { index, data in
                let url = r.workDir.appendingPathComponent("profile-\(index).mobileprovision")
                try data.write(to: url)
                return url
            }
            fixedBundleID = provisioned.bundleID
        }

        // 3. Verify certificate & profile (real checks, not decoration)
        await progress(.verifying)
        let cert = r.certificate
        if cert.status == .expired { throw UserFacingError.certificateExpired }
        guard let p12Data = try? Data(contentsOf: r.p12) else { throw UserFacingError.invalidP12 }
        let p12Info = try P12Reader.read(p12Data, password: r.password)
        guard let mainProfile = profileURLs.first else { throw UserFacingError.invalidProfile }
        let parsed = try ProvisioningProfileParser.parse(Data(contentsOf: mainProfile))
        if !parsed.developerCertificates.isEmpty, !parsed.developerCertificates.contains(p12Info.certificateDER) {
            throw UserFacingError.profileMismatch
        }
        // A non-wildcard profile can only sign its own bundle ID — rewrite it if needed.
        let pattern = parsed.profile.bundlePattern
        let targetBundleID: String
        if let fixedBundleID {
            targetBundleID = fixedBundleID
        } else if parsed.profile.allows(bundleID: r.originalBundleID) {
            targetBundleID = r.originalBundleID
        } else if pattern.hasSuffix(".*") {
            targetBundleID = String(pattern.dropLast()) + r.originalBundleID
        } else {
            targetBundleID = pattern
        }
        let expiresAt = min(cert.expiresAt, parsed.profile.expiresAt)

        // 4. Sign
        await progress(.signing)
        try await Task.detached(priority: .userInitiated) {
            do {
                try ZSignBridge.signApp(atPath: appDir.path, p12Path: r.p12.path, password: r.password,
                                        profilePaths: profileURLs.map(\.path),
                                        bundleID: targetBundleID == r.originalBundleID ? nil : targetBundleID,
                                        displayName: nil)
            } catch {
                throw UserFacingError.signingFailed((error as NSError).localizedDescription)
            }
        }.value

        // 5. Re-pack
        await progress(.packaging)
        if fm.fileExists(atPath: r.output.path) { try fm.removeItem(at: r.output) }
        try await Task.detached(priority: .userInitiated) {
            try fm.zipItem(at: payload, to: r.output, shouldKeepParent: true, compressionMethod: .deflate)
        }.value

        return SigningResult(signedIPA: r.output, bundleID: targetBundleID, expiresAt: expiresAt)
    }

    /// Bundle IDs of app extensions (PlugIns/, Extensions/) nested under the main bundle ID.
    private static func extensionBundleIDs(in appDir: URL, of bundleID: String) throws -> [String] {
        let fm = FileManager.default
        var ids: [String] = []
        for folder in ["PlugIns", "Extensions"] {
            let dir = appDir.appendingPathComponent(folder)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".appex") {
                let plist = dir.appendingPathComponent(name).appendingPathComponent("Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let id = info["CFBundleIdentifier"] as? String,
                      id.hasPrefix(bundleID + ".") else { continue }
                ids.append(id)
            }
        }
        return ids
    }
}
