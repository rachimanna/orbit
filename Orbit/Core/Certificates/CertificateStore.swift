import Foundation

/// Manages imported signing identities. Validates that the .p12 opens with the
/// given password and that the profile actually lists that certificate.
@MainActor
final class CertificateStore: ObservableObject {
    @Published private(set) var certificates: [SigningCertificate] = []
    @Published var selectedID: UUID? { didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedCert") } }
    /// A .p12/.mobileprovision handed to us via «Открыть в…», waiting for the import sheet.
    @Published var pendingFileImport: URL?

    private let files: FileStore
    private let indexName = "certificates.json"

    init(files: FileStore) {
        self.files = files
        certificates = files.load([SigningCertificate].self, from: indexName) ?? []
        selectedID = UUID(uuidString: UserDefaults.standard.string(forKey: "selectedCert") ?? "")
        if selected == nil { selectedID = certificates.first?.id }
    }

    var selected: SigningCertificate? { certificates.first { $0.id == selectedID } }

    func p12URL(_ c: SigningCertificate) -> URL { files.absolute(c.p12Path) }
    func profileURL(_ c: SigningCertificate) -> URL? { c.profilePath.map(files.absolute) }
    func password(_ c: SigningCertificate) -> String { Keychain.password(for: c.id) }

    // MARK: Import

    /// Import from two files the user picked.
    func importFiles(p12: URL, profile: URL, password: String) async throws -> SigningCertificate {
        let p12Data = try read(p12)
        let profileData = try read(profile)
        return try add(p12Data: p12Data, profileData: profileData, password: password, source: .manual)
    }

    /// Import from the SideStore callback. SideStore only exports the certificate, so the
    /// profile comes from the signed-in Apple ID, the user, or an already imported match.
    func importFromSideStore(_ payload: SideStoreBridge.Payload, appleAccount: Bool) async throws {
        if appleAccount {
            _ = try add(p12Data: payload.p12, profileData: nil, password: payload.password, source: .sideStore)
            return
        }
        let info = try P12Reader.read(payload.p12, password: payload.password)

        // Reuse a stored profile that lists this certificate, if any.
        if let existing = certificates.first(where: {
            guard let url = profileURL($0) else { return false }
            return (try? ProvisioningProfileParser.parse(Data(contentsOf: url)))?
                .developerCertificates.contains(info.certificateDER) == true
        }), let url = profileURL(existing) {
            let profileData = try Data(contentsOf: url)
            _ = try add(p12Data: payload.p12, profileData: profileData, password: payload.password, source: .sideStore)
            return
        }
        if let profileData = payload.profile {
            _ = try add(p12Data: payload.p12, profileData: profileData, password: payload.password, source: .sideStore)
            return
        }
        // No profile yet — park the .p12 and ask for a .mobileprovision.
        pendingSideStoreP12 = payload
        throw UserFacingError(title: "Нужен provisioning profile",
                              hint: "SideStore передал сертификат. Выберите подходящий .mobileprovision, чтобы завершить импорт.")
    }
    @Published var pendingSideStoreP12: SideStoreBridge.Payload?

    /// `profile == nil`: profiles will be fetched through the Apple ID for each app.
    func completeSideStoreImport(profile: URL?) throws {
        guard let payload = pendingSideStoreP12 else { return }
        _ = try add(p12Data: payload.p12, profileData: try profile.map(read), password: payload.password, source: .sideStore)
        pendingSideStoreP12 = nil
    }

    @discardableResult
    private func add(p12Data rawP12: Data, profileData: Data?, password: String,
                     source: SigningCertificate.Source) throws -> SigningCertificate {
        let (p12Data, info) = try P12Reader.prepare(rawP12, password: password)
        let parsed = try profileData.map(ProvisioningProfileParser.parse)

        if let parsed, !parsed.developerCertificates.isEmpty,
           !parsed.developerCertificates.contains(info.certificateDER) {
            throw UserFacingError.profileMismatch
        }

        // Replace an older copy of the same cert + profile.
        if let dup = certificates.first(where: { $0.profile?.uuid == parsed?.profile.uuid && $0.displayName == info.commonName }) {
            delete(dup)
        }

        let id = UUID()
        let folder = files.certificateFolder(id)
        let p12URL = folder.appendingPathComponent("certificate.p12")
        try p12Data.write(to: p12URL, options: .completeFileProtection)
        var profilePath: String?
        if let profileData {
            let profURL = folder.appendingPathComponent("profile.mobileprovision")
            try profileData.write(to: profURL, options: .completeFileProtection)
            profilePath = files.relative(profURL)
        }
        Keychain.setPassword(password, for: id)

        let teamID = parsed?.profile.teamID ?? info.teamID ?? ""
        let cert = SigningCertificate(
            id: id, displayName: info.commonName, teamID: teamID,
            teamName: parsed?.profile.teamName ?? teamID, certificateExpiresAt: info.notAfter,
            profile: parsed?.profile, source: source, addedAt: Date(),
            p12Path: files.relative(p12URL), profilePath: profilePath)
        certificates.insert(cert, at: 0)
        if selected == nil { selectedID = id }
        persist()
        return cert
    }

    func delete(_ c: SigningCertificate) {
        try? files.fm.removeItem(at: files.certificateFolder(c.id))
        Keychain.delete(c.id)
        certificates.removeAll { $0.id == c.id }
        if selectedID == c.id { selectedID = certificates.first?.id }
        persist()
    }

    private func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private func persist() { files.save(certificates, to: indexName) }
}
