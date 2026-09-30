import Foundation
import ZIPFoundation

/// Stages shown on the signing screen. Each is reported only when it really starts.
enum SigningStage: Int, CaseIterable {
    case preparing, verifying, signing, packaging

    var title: String {
        switch self {
        case .preparing: "Подготовка приложения…"
        case .verifying: "Проверка сертификата…"
        case .signing: "Подписание…"
        case .packaging: "Подготовка к установке…"
        }
    }
    var symbol: String {
        switch self {
        case .preparing: "shippingbox"
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
    var profile: URL
    var output: URL
    var workDir: URL
    var cleanWorkDir: Bool
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

        // 2. Verify certificate & profile (real checks, not decoration)
        await progress(.verifying)
        let cert = r.certificate
        if cert.status == .expired { throw UserFacingError.certificateExpired }
        guard let p12Data = try? Data(contentsOf: r.p12) else { throw UserFacingError.invalidP12 }
        let p12Info = try P12Reader.read(p12Data, password: r.password)
        let parsed = try ProvisioningProfileParser.parse(Data(contentsOf: r.profile))
        if !parsed.developerCertificates.isEmpty, !parsed.developerCertificates.contains(p12Info.certificateDER) {
            throw UserFacingError.profileMismatch
        }
        // A non-wildcard profile can only sign its own bundle ID — rewrite it if needed.
        let pattern = parsed.profile.bundlePattern
        let targetBundleID: String
        if parsed.profile.allows(bundleID: r.originalBundleID) {
            targetBundleID = r.originalBundleID
        } else if pattern.hasSuffix(".*") {
            targetBundleID = String(pattern.dropLast()) + r.originalBundleID
        } else {
            targetBundleID = pattern
        }

        // 3. Sign
        await progress(.signing)
        try await Task.detached(priority: .userInitiated) {
            do {
                try ZSignBridge.signApp(atPath: appDir.path, p12Path: r.p12.path, password: r.password,
                                        profilePath: r.profile.path,
                                        bundleID: targetBundleID == r.originalBundleID ? nil : targetBundleID,
                                        displayName: nil)
            } catch {
                throw UserFacingError.signingFailed((error as NSError).localizedDescription)
            }
        }.value

        // 4. Re-pack
        await progress(.packaging)
        if fm.fileExists(atPath: r.output.path) { try fm.removeItem(at: r.output) }
        try await Task.detached(priority: .userInitiated) {
            try fm.zipItem(at: payload, to: r.output, shouldKeepParent: true, compressionMethod: .deflate)
        }.value

        return SigningResult(signedIPA: r.output, bundleID: targetBundleID, expiresAt: cert.expiresAt)
    }
}
