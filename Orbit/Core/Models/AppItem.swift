import Foundation

/// An IPA the user added, plus the state of its signed copy.
struct AppItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bundleID: String
    var version: String
    var build: String
    var minimumOS: String?
    var sizeBytes: Int64
    var addedAt: Date

    /// Relative paths inside the app container (see FileStore).
    var originalIPAPath: String
    var iconPath: String?

    var signed: SignedInfo?
    var installedAt: Date?

    struct SignedInfo: Codable, Hashable {
        var ipaPath: String
        var certificateID: UUID
        var certificateName: String
        var signedAt: Date
        /// Signature validity = the earlier of certificate and profile expiry.
        var expiresAt: Date
        var signedBundleID: String
    }

    enum Status: Equatable {
        case notSigned, signed, installed, expiringSoon, expired

        var title: String {
            switch self {
            case .notSigned: "Не подписано"
            case .signed: "Готово к установке"
            case .installed: "Передано на установку"
            case .expiringSoon: "Скоро истечёт"
            case .expired: "Подпись истекла"
            }
        }
        var symbol: String {
            switch self {
            case .notSigned: "signature"
            case .signed: "checkmark.seal"
            case .installed: "checkmark.circle.fill"
            case .expiringSoon: "clock.badge.exclamationmark"
            case .expired: "exclamationmark.triangle.fill"
            }
        }
    }

    var status: Status {
        guard let signed else { return .notSigned }
        let now = Date()
        if signed.expiresAt <= now { return .expired }
        if signed.expiresAt.timeIntervalSince(now) < 3 * 86_400 { return .expiringSoon }
        return installedAt == nil ? .signed : .installed
    }

    var sizeText: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }
}
