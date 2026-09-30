import Foundation

/// A .mobileprovision is a CMS (PKCS#7) envelope around an XML plist. iOS has no
/// public CMS decoder, but the payload is stored unencrypted, so we locate the
/// plist bytes directly. We never trust it for security — only for display and
/// for pairing with the .p12.
enum ProvisioningProfileParser {
    struct Parsed {
        var profile: ProvisioningProfile
        var entitlements: [String: Any]
        /// DER blobs of certificates allowed to sign with this profile.
        var developerCertificates: [Data]
    }

    static func parse(_ data: Data) throws -> Parsed {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { throw UserFacingError.invalidProfile }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let expires = plist["ExpirationDate"] as? Date
        else { throw UserFacingError.invalidProfile }

        let ent = plist["Entitlements"] as? [String: Any] ?? [:]
        let teamID = (plist["TeamIdentifier"] as? [String])?.first ?? ""
        let devices = plist["ProvisionedDevices"] as? [String]

        let profile = ProvisioningProfile(
            name: plist["Name"] as? String ?? "Без названия",
            uuid: plist["UUID"] as? String ?? "",
            teamID: teamID,
            teamName: plist["TeamName"] as? String ?? teamID,
            appIDName: plist["AppIDName"] as? String ?? "",
            applicationIdentifier: ent["application-identifier"] as? String ?? "\(teamID).*",
            createdAt: plist["CreationDate"] as? Date ?? Date(),
            expiresAt: expires,
            provisionedDeviceCount: devices?.count,
            provisionsAllDevices: plist["ProvisionsAllDevices"] as? Bool ?? false,
            isDevelopment: ent["get-task-allow"] as? Bool ?? false,
            entitlementKeys: ent.keys.sorted())

        return Parsed(profile: profile, entitlements: ent,
                      developerCertificates: plist["DeveloperCertificates"] as? [Data] ?? [])
    }
}
