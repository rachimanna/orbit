import Foundation
import ZIPFoundation

/// Reads metadata straight out of the .ipa without unpacking the whole archive.
struct IPAInspector {
    struct Metadata {
        var name: String
        var bundleID: String
        var version: String
        var build: String
        var minimumOS: String?
        var iconData: Data?
    }

    func inspect(_ ipa: URL) throws -> Metadata {
        let archive: Archive
        do { archive = try Archive(url: ipa, accessMode: .read) } catch { throw UserFacingError.invalidIPA }

        // Payload/<Name>.app/Info.plist — exactly one level deep.
        guard let infoEntry = archive.first(where: {
            let parts = $0.path.split(separator: "/")
            return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }) else { throw UserFacingError.invalidIPA }

        let appDir = infoEntry.path.split(separator: "/").prefix(2).joined(separator: "/")
        let infoData = try read(infoEntry, from: archive)
        guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String
        else { throw UserFacingError.invalidIPA }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? String(appDir.split(separator: "/").last ?? "App").replacingOccurrences(of: ".app", with: "")

        return Metadata(
            name: name,
            bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String ?? "1.0",
            build: info["CFBundleVersion"] as? String ?? "1",
            minimumOS: info["MinimumOSVersion"] as? String,
            iconData: iconData(info: info, appDir: appDir, archive: archive))
    }

    // MARK: - Icon

    /// Finds the largest icon referenced by Info.plist. Icons inside IPAs are "CgBI"
    /// optimised PNGs — UIImage on iOS decodes them natively.
    private func iconData(info: [String: Any], appDir: String, archive: Archive) -> Data? {
        var names: [String] = []
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            if let icons = info[key] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] {
                names += primary["CFBundleIconFiles"] as? [String] ?? []
                if let n = primary["CFBundleIconName"] as? String { names.append(n) }
            }
        }
        names += info["CFBundleIconFiles"] as? [String] ?? []
        if let n = info["CFBundleIconFile"] as? String { names.append(n) }

        let candidates = archive.filter { entry in
            let path = entry.path
            guard path.hasPrefix(appDir + "/"), path.lowercased().hasSuffix(".png") else { return false }
            let file = String(path.dropFirst(appDir.count + 1))
            guard !file.contains("/") else { return false }
            return names.contains { file.hasPrefix($0) } || file.hasPrefix("AppIcon")
        }
        guard let best = candidates.max(by: { $0.uncompressedSize < $1.uncompressedSize }) else { return nil }
        return try? read(best, from: archive)
    }

    private func read(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry, skipCRC32: true) { data.append($0) }
        return data
    }
}
