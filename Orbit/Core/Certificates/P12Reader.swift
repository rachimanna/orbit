import Foundation
import Security

/// Opens a .p12 with the system (SecPKCS12Import) — this validates the password
/// and that a private key is present, without adding anything to the keychain.
enum P12Reader {
    struct Info {
        var commonName: String
        var certificateDER: Data
        var notAfter: Date?
    }

    /// Returns .p12 data that both iOS and zsign can open with `password`, plus its info.
    ///
    /// Files iOS already accepts are kept byte-for-byte. Others are re-packed by OpenSSL:
    /// SideStore's certificate export, for one, has no MAC and an unencrypted key bag,
    /// which SecPKCS12Import rejects as if the password were wrong; OpenSSL 3's default
    /// PBES2/AES output is rejected by some iOS versions too.
    static func prepare(_ data: Data, password: String) throws -> (data: Data, info: Info) {
        let systemError: Error
        do {
            return (data, try read(data, password: password))
        } catch {
            systemError = error
        }
        let repacked: Data
        do {
            repacked = try ZSignBridge.normalizedP12(data, password: password)
        } catch {
            // OpenSSL could not open it either: report what iOS said (wrong password / invalid).
            if (error as NSError).code == 1 { throw UserFacingError.wrongPassword }
            throw systemError
        }
        return (repacked, try read(repacked, password: password))
    }

    static func read(_ data: Data, password: String) throws -> Info {
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &items)

        switch status {
        case errSecSuccess: break
        case errSecAuthFailed, errSecPkcs12VerifyFailure: throw UserFacingError.wrongPassword
        default: throw UserFacingError.invalidP12
        }

        guard let dict = (items as? [[String: Any]])?.first,
              let identityRef = dict[kSecImportItemIdentity as String]
        else { throw UserFacingError.invalidP12 }

        // swiftlint:disable:next force_cast
        let identity = identityRef as! SecIdentity
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else {
            throw UserFacingError.invalidP12
        }

        var cn: CFString?
        SecCertificateCopyCommonName(cert, &cn)
        let der = SecCertificateCopyData(cert) as Data
        return Info(commonName: (cn as String?) ?? "Сертификат",
                    certificateDER: der,
                    notAfter: X509.notAfter(der))
    }
}

/// Minimal DER walker — just enough to read Validity.notAfter from an X.509 certificate,
/// since iOS has no public API for certificate dates.
enum X509 {
    static func notAfter(_ der: Data) -> Date? {
        let bytes = [UInt8](der)
        // Certificate ::= SEQUENCE { tbsCertificate SEQUENCE { ... } ... }
        guard let cert = tlv(bytes, 0), cert.tag == 0x30,
              let tbs = tlv(bytes, cert.contentStart), tbs.tag == 0x30 else { return nil }
        var p = tbs.contentStart
        var field = 0
        while p < tbs.end, let t = tlv(bytes, p) {
            // [0] version is optional; skip it without counting.
            if t.tag == 0xA0 { p = t.end; continue }
            // serial(0), signature(1), issuer(2), validity(3)
            if field == 3, t.tag == 0x30,
               let notBefore = tlv(bytes, t.contentStart),
               let notAfter = tlv(bytes, notBefore.end) {
                return time(Array(bytes[notAfter.contentStart..<notAfter.end]), tag: notAfter.tag)
            }
            field += 1
            p = t.end
        }
        return nil
    }

    private struct TLV { var tag: UInt8; var contentStart: Int; var end: Int }

    private static func tlv(_ b: [UInt8], _ i: Int) -> TLV? {
        guard i + 1 < b.count else { return nil }
        var len = Int(b[i + 1]); var start = i + 2
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n > 0, n <= 4, i + 2 + n <= b.count else { return nil }
            len = b[(i + 2)..<(i + 2 + n)].reduce(0) { $0 << 8 | Int($1) }
            start = i + 2 + n
        }
        guard start + len <= b.count else { return nil }
        return TLV(tag: b[i], contentStart: start, end: start + len)
    }

    private static func time(_ b: [UInt8], tag: UInt8) -> Date? {
        let s = String(decoding: b, as: UTF8.self)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = tag == 0x17 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"  // UTCTime : GeneralizedTime
        return f.date(from: s)
    }
}
