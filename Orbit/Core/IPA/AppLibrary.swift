import Foundation

/// The user's collection of IPAs and their signed copies. UI observes this.
@MainActor
final class AppLibrary: ObservableObject {
    @Published private(set) var items: [AppItem] = []
    @Published private(set) var isImporting = false

    private let files: FileStore
    private let inspector = IPAInspector()
    private let indexName = "apps.json"

    init(files: FileStore) {
        self.files = files
        items = files.load([AppItem].self, from: indexName) ?? []
        // Drop entries whose files were removed via the Files app.
        items.removeAll { item in
            let hasOriginal = files.fm.fileExists(atPath: files.absolute(item.originalIPAPath).path)
            let hasSigned = item.signed.map { files.fm.fileExists(atPath: files.absolute($0.ipaPath).path) } ?? false
            return !hasOriginal && !hasSigned
        }
    }

    func url(_ relative: String) -> URL { files.absolute(relative) }
    var fileStore: FileStore { files }

    @discardableResult
    func importIPA(from source: URL) async throws -> AppItem {
        isImporting = true
        defer { isImporting = false }

        let id = UUID()
        let folder = files.appFolder(id)
        let files = self.files
        let inspector = self.inspector

        do {
            // Heavy I/O off the main actor.
            let (meta, size, ipa) = try await Task.detached(priority: .userInitiated) {
                let ipa = try files.copyIn(source, to: folder.appendingPathComponent("original.ipa"))
                let meta = try inspector.inspect(ipa)
                let attrs = try? files.fm.attributesOfItem(atPath: ipa.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                return (meta, size, ipa)
            }.value

            var iconPath: String?
            if let data = meta.iconData {
                let iconURL = folder.appendingPathComponent("icon.png")
                try? data.write(to: iconURL)
                iconPath = files.relative(iconURL)
            }

            let item = AppItem(id: id, name: meta.name, bundleID: meta.bundleID, version: meta.version,
                               build: meta.build, minimumOS: meta.minimumOS, sizeBytes: size,
                               addedAt: Date(), originalIPAPath: files.relative(ipa), iconPath: iconPath,
                               signed: nil, installedAt: nil)
            items.insert(item, at: 0)
            persist()
            return item
        } catch {
            try? files.fm.removeItem(at: folder)
            throw error
        }
    }

    func item(_ id: UUID) -> AppItem? { items.first { $0.id == id } }

    func update(_ item: AppItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
        persist()
    }

    func markInstalled(_ id: UUID, deleteIPA: Bool) {
        guard var item = item(id) else { return }
        item.installedAt = Date()
        update(item)
        if deleteIPA { try? files.fm.removeItem(at: files.absolute(item.originalIPAPath)) }
    }

    func remove(_ id: UUID) {
        try? files.fm.removeItem(at: files.appFolder(id))
        items.removeAll { $0.id == id }
        persist()
    }

    private func persist() { files.save(items, to: indexName) }
}
