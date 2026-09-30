import UIKit

/// Integration with SideStore's official certificate export (SideStore ≥ 0.6.2,
/// PR SideStore/SideStore#959):
///
///   1. We open  sidestore://certificate?callback_template=<url-encoded template>
///   2. SideStore asks the user to allow the export.
///   3. SideStore replaces $(BASE64_CERT) and $(PASSWORD) in our template and opens it.
///
/// SideStore exports only the certificate (+ password), not a provisioning profile.
@MainActor
final class SideStoreBridge {
    struct Payload: Equatable {
        var p12: Data
        var password: String
        var profile: Data?
    }

    static let callbackHost = "sidestore-certificate"

    private var template: String {
        "\(Brand.urlScheme)://\(Self.callbackHost)?cert=$(BASE64_CERT)&password=$(PASSWORD)"
    }

    var exportURL: URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = template.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "sidestore://certificate?callback_template=\(encoded)")
    }

    var isSideStoreInstalled: Bool {
        guard let url = URL(string: "sidestore://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Opens SideStore. Throws if it isn't installed — the UI then offers the file fallback.
    func requestCertificate() async throws {
        guard let url = exportURL, isSideStoreInstalled else { throw UserFacingError.sideStoreMissing }
        let opened = await UIApplication.shared.open(url)
        if !opened { throw UserFacingError.sideStoreMissing }
    }

    func isCallback(_ url: URL) -> Bool {
        url.scheme == Brand.urlScheme && url.host == Self.callbackHost
    }

    func parseCallback(_ url: URL) throws -> Payload {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw UserFacingError.sideStoreEmpty
        }
        // URLComponents percent-decodes, but '+' in base64 may arrive as a space.
        func value(_ name: String) -> String? {
            comps.queryItems?.first { $0.name == name }?.value?.replacingOccurrences(of: " ", with: "+")
        }
        guard let certB64 = value("cert"), !certB64.isEmpty, !certB64.contains("$("),
              let p12 = Data(base64Encoded: certB64, options: .ignoreUnknownCharacters)
        else { throw UserFacingError.sideStoreEmpty }

        // The password may be passed raw or base64-encoded depending on the SideStore build;
        // pick whichever actually opens the .p12.
        let raw = value("password").flatMap { $0.contains("$(") ? nil : $0 } ?? ""
        var candidates = [raw]
        if let d = Data(base64Encoded: raw), let s = String(data: d, encoding: .utf8) { candidates.append(s) }
        candidates.append("")

        for candidate in candidates {
            if let prepared = try? P12Reader.prepare(p12, password: candidate) {
                return Payload(p12: prepared.data, password: candidate, profile: nil)
            }
        }
        throw UserFacingError.wrongPassword
    }
}
