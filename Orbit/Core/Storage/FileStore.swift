import Foundation

/// Owns the on-disk layout inside the app container:
///
///   Documents/Apps/<uuid>/original.ipa, icon.png, signed.ipa
///   Documents/Certificates/<uuid>/cert.p12, profile.mobileprovision
///   Documents/pairingFile.plist
///   Library/Application Support/*.json   — indexes
///   tmp/Work/<uuid>/                      — unpacked bundles during signing
final class FileStore {
    let fm = FileManager.default
    let documents: URL
    let support: URL
    let work: URL

    init() {
        documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        work = fm.temporaryDirectory.appendingPathComponent("Work", isDirectory: true)
        [appsRoot, certificatesRoot, support, work].forEach {
            try? fm.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    var appsRoot: URL { documents.appendingPathComponent("Apps", isDirectory: true) }
    var certificatesRoot: URL { documents.appendingPathComponent("Certificates", isDirectory: true) }
    var pairingFile: URL { documents.appendingPathComponent("pairingFile.plist") }

    func appFolder(_ id: UUID) -> URL { mkdir(appsRoot.appendingPathComponent(id.uuidString)) }
    func certificateFolder(_ id: UUID) -> URL { mkdir(certificatesRoot.appendingPathComponent(id.uuidString)) }
    func workFolder() -> URL { mkdir(work.appendingPathComponent(UUID().uuidString)) }

    func absolute(_ relative: String) -> URL { documents.appendingPathComponent(relative) }
    func relative(_ url: URL) -> String {
        url.standardizedFileURL.path.replacingOccurrences(of: documents.standardizedFileURL.path + "/", with: "")
    }

    // MARK: JSON index persistence

    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = support.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: support.appendingPathComponent(name), options: .atomic)
    }

    /// Copies a file picked via the document picker / share sheet into our container.
    /// Handles security-scoped URLs.
    @discardableResult
    func copyIn(_ source: URL, to destination: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.copyItem(at: source, to: destination)
        return destination
    }

    func clearWork() {
        try? fm.removeItem(at: work)
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        // Files handed to us by «Открыть в…» land in Documents/Inbox.
        try? fm.removeItem(at: documents.appendingPathComponent("Inbox"))
    }

    func workSize() -> Int64 {
        let urls = [work, documents.appendingPathComponent("Inbox")]
        return urls.reduce(0) { $0 + folderSize($1) }
    }

    func folderSize(_ url: URL) -> Int64 {
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    private func mkdir(_ url: URL) -> URL {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
