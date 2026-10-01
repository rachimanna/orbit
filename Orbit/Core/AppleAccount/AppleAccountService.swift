import Foundation
import UIKit
import SideSign

/// Apple ID sign-in and on-demand provisioning profiles — what SideStore does to sign apps
/// with a free account. Built on SideSign (github.com/SideStore/SideSign, GPL-3.0).
///
/// The password goes only to Apple (SRP — it is never sent in clear, even to Apple).
/// The anisette server supplies device-identification headers Apple requires; it never
/// sees the Apple ID or password.
@MainActor
final class AppleAccountService: ObservableObject {
    struct StoredAccount: Codable, Equatable {
        var appleID: String
        var name: String
        var team: Team
    }

    /// Apple asked for a verification code; the UI shows a sheet while this is set.
    struct CodePrompt: Identifiable, Equatable {
        let id = UUID()
        var sentBySMS: Bool
        var error: String?
        var canRequestSMS: Bool
    }

    /// Profiles fetched for one signing run.
    struct Provisioned {
        /// Bundle ID the app is re-signed with (free App IDs must be unique across Apple).
        var bundleID: String
        /// Main app profile first, then one per extension.
        var profiles: [Data]
    }

    /// Free accounts may hold 10 App IDs; each expires 7 days after creation.
    nonisolated static let freeAppIDLimit = 10

    struct AppIDUsage: Equatable {
        var used: Int
        var limit: Int?            // nil = paid team, no weekly limit
        var nextFree: Date?
        var available: Int? { limit.map { max(0, $0 - used) } }
    }

    nonisolated static let defaultAnisetteServer = "https://ani.sidestore.io"
    private static let xcodeVersion = "26.0 (26A242)"

    @Published private(set) var account: StoredAccount?
    @Published private(set) var isWorking = false
    @Published var codePrompt: CodePrompt?
    @Published private(set) var appIDUsage: AppIDUsage?
    @Published var anisetteServer: String {
        didSet { UserDefaults.standard.set(anisetteServer, forKey: Keys.anisetteServer) }
    }

    var isSignedIn: Bool { account != nil }

    private let portal = DeveloperPortal.shared
    private var codeContinuation: CheckedContinuation<TwoFactorResponse, Never>?
    private var phoneNumbers: [TrustedPhoneNumber] = []

    private enum Keys {
        static let account = "appleAccount"
        static let anisetteServer = "anisetteServer"
        static let anisetteID = "anisetteIdentifier"
        static let password = "appleID.password"
        static let session = "appleID.session"
        static let adiBlob = "anisette.adi"
    }

    init() {
        anisetteServer = UserDefaults.standard.string(forKey: Keys.anisetteServer) ?? Self.defaultAnisetteServer
        if let data = UserDefaults.standard.data(forKey: Keys.account) {
            account = try? JSONDecoder().decode(StoredAccount.self, from: data)
        }
    }

    // MARK: - Sign in / out

    func signIn(appleID: String, password: String) async throws {
        isWorking = true
        defer { isWorking = false }
        do {
            let auth = try await authenticate(appleID: appleID, password: password)
            let teams = try await portal.fetchTeams(for: auth.account, session: auth.session)
            guard let team = teams.first(where: { $0.type == .free }) ?? teams.first else {
                throw DeveloperPortalError.noTeams
            }
            Keychain.set(Data(password.utf8), for: Keys.password)
            store(session: auth.session)
            let stored = StoredAccount(appleID: auth.account.appleID,
                                       name: auth.account.name.isEmpty ? auth.account.appleID : auth.account.name,
                                       team: team)
            UserDefaults.standard.set(try JSONEncoder().encode(stored), forKey: Keys.account)
            account = stored
        } catch {
            throw Self.userFacing(error)
        }
    }

    func signOut() {
        account = nil
        UserDefaults.standard.removeObject(forKey: Keys.account)
        Keychain.set(nil, for: Keys.password)
        Keychain.set(nil, for: Keys.session)
        AnisetteDataManager.shared.clearCache()
    }

    // MARK: - Two-factor prompt (driven by the UI)

    func submitCode(_ code: String) { resumeCode(.verificationCode(code.filter(\.isNumber))) }
    func requestSMS() { resumeCode(.requestSMS(phoneID: phoneNumbers.first?.id ?? "1")) }
    func cancelCode() { resumeCode(.cancel) }

    private func resumeCode(_ response: TwoFactorResponse) {
        codePrompt = nil
        let continuation = codeContinuation
        codeContinuation = nil
        continuation?.resume(returning: response)
    }

    private func handleTwoFactor(_ request: TwoFactorRequest) async -> TwoFactorResponse {
        switch request {
        case .selectDeliveryMethod(let preferred, let phones):
            phoneNumbers = phones
            // Ask for the code the way Apple suggests; the sheet offers SMS as a fallback.
            return preferred == .trustedDevice ? .requestTrustedDevice : .requestSMS(phoneID: phones.first?.id ?? "1")
        case .trustedDevice(let error):
            return await askForCode(CodePrompt(sentBySMS: false, error: error, canRequestSMS: true))
        case .sms(let phones, _, let error), .voice(let phones, _, let error):
            phoneNumbers = phones
            return await askForCode(CodePrompt(sentBySMS: true, error: error, canRequestSMS: false))
        }
    }

    private func askForCode(_ prompt: CodePrompt) async -> TwoFactorResponse {
        await withCheckedContinuation { continuation in
            codeContinuation?.resume(returning: .cancel)
            codeContinuation = continuation
            codePrompt = prompt
        }
    }

    // MARK: - Provisioning

    /// Registers this device and App IDs for the app (and its extensions), then downloads
    /// fresh development profiles — like SideStore does on every install.
    func provision(bundleID: String, appName: String, extensionBundleIDs: [String], udid: String?) async throws -> Provisioned {
        guard let udid, !udid.isEmpty else { throw UserFacingError.udidMissing }
        do {
            return try await withPortal { session, team in
                let deviceType: DeviceType = UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
                try await self.registerDeviceIfNeeded(udid: udid, type: deviceType, team: team, session: session)

                // Free App IDs are global, so the original ID is almost always taken by its developer.
                let target = "\(bundleID).\(team.identifier)"
                var existing = try await self.portal.fetchAppIDs(for: team, session: session)
                let usage = Self.usage(of: existing, team: team)
                self.appIDUsage = usage

                var profiles: [Data] = []
                // Extensions keep their suffix: com.app.widget → com.app.TEAMID.widget (zsign renames them the same way).
                let bundles: [(String, String)] = [(target, appName)] + extensionBundleIDs.map { ext in
                    (target + ext.dropFirst(bundleID.count), "\(appName) \(ext.split(separator: ".").last ?? "")")
                }

                // Check the weekly quota up front, so a big app doesn't burn App IDs and then fail halfway.
                func exists(_ id: String) -> Bool {
                    existing.contains { $0.bundleIdentifier.caseInsensitiveCompare(id) == .orderedSame }
                }
                let missing = bundles.filter { !exists($0.0) }.count
                if let available = usage.available, missing > available {
                    throw Self.quotaError(appName: appName, missing: missing, available: available,
                                          extensions: extensionBundleIDs.count,
                                          mainMissing: exists(target) ? 0 : 1, nextFree: usage.nextFree)
                }
                for (identifier, name) in bundles {
                    let appID: AppID
                    if let found = existing.first(where: { $0.bundleIdentifier.caseInsensitiveCompare(identifier) == .orderedSame }) {
                        appID = found
                    } else {
                        appID = try await self.portal.addAppID(withName: Self.appIDName(name), bundleIdentifier: identifier,
                                                               team: team, session: session)
                        existing.append(appID)
                    }
                    let profile = try await self.portal.downloadProvisioningProfile(for: appID, deviceType: deviceType,
                                                                                    team: team, session: session)
                    profiles.append(profile.data)
                }
                self.appIDUsage = Self.usage(of: existing, team: team)
                return Provisioned(bundleID: target, profiles: profiles)
            }
        } catch {
            throw Self.userFacing(error)
        }
    }

    /// Refreshes `appIDUsage` (shown in «Настройки → Apple ID»).
    func refreshAppIDUsage() async {
        let usage = try? await withPortal { session, team in
            let appIDs = try await self.portal.fetchAppIDs(for: team, session: session)
            return Self.usage(of: appIDs, team: team)
        }
        if let usage { appIDUsage = usage }
    }

    private static func usage(of appIDs: [AppID], team: Team) -> AppIDUsage {
        guard !team.isPaid else { return AppIDUsage(used: appIDs.count, limit: nil, nextFree: nil) }
        let now = Date()
        let active = appIDs.filter { ($0.expirationDate ?? .distantFuture) > now }
        return AppIDUsage(used: active.count, limit: freeAppIDLimit,
                          nextFree: active.compactMap(\.expirationDate).min())
    }

    private static func quotaError(appName: String, missing: Int, available: Int, extensions: Int,
                                   mainMissing: Int, nextFree: Date?) -> UserFacingError {
        var hint = "Для «\(appName)» нужно новых App ID: \(missing)"
        if extensions > 0 { hint += " (приложение и расширений: \(extensions))" }
        hint += ", а свободно \(available) из \(freeAppIDLimit). Бесплатный Apple ID даёт 10 App ID на 7 дней."
        if let nextFree { hint += " Следующий освободится \(nextFree.formatted(date: .abbreviated, time: .shortened))." }
        let canSkipExtensions = extensions > 0 && mainMissing <= available
        if canSkipExtensions {
            hint += mainMissing == 0
                ? " Без расширений (виджетов, уведомлений и т. п.) новые App ID не нужны."
                : " Без расширений (виджетов, уведомлений и т. п.) нужен всего 1."
        }
        var error = UserFacingError(title: "Не хватает App ID", hint: hint)
        error.suggestsRemovingExtensions = canSkipExtensions
        return error
    }

    private func registerDeviceIfNeeded(udid: String, type: DeviceType, team: Team, session: Session) async throws {
        let devices = try await portal.fetchDevices(for: team, types: type, session: session)
        guard !devices.contains(where: { $0.identifier.caseInsensitiveCompare(udid) == .orderedSame }) else { return }
        let name = UIDevice.current.name
        do {
            _ = try await portal.registerDevice(name: name, identifier: udid, type: type, team: team, session: session)
        } catch DeveloperPortalError.deviceAlreadyRegistered {
            // Registered meanwhile / listed under another type — fine.
        }
    }

    /// App ID names allow only letters, digits and spaces.
    private static func appIDName(_ name: String) -> String {
        let cleaned = String(name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " })
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "\(Brand.name) App" : cleaned
    }

    // MARK: - Session

    /// Runs portal calls with a valid session. If Apple rejects the stored token, signs in
    /// again with the saved password (may ask for a 2FA code) and retries once.
    private func withPortal<T>(_ body: @escaping (Session, Team) async throws -> T) async throws -> T {
        guard let account else { throw UserFacingError.appleIDSignedOut }
        isWorking = true
        defer { isWorking = false }

        if let stored = storedSession(), stored.isValid {
            var session = stored
            session.anisetteData = try await anisetteData()
            do {
                return try await body(session, account.team)
            } catch let error where Self.isExpiredSession(error) {
                // fall through to a fresh sign-in
            }
        }
        let session = try await reauthenticate(account)
        return try await body(session, account.team)
    }

    private func reauthenticate(_ account: StoredAccount) async throws -> Session {
        guard let data = Keychain.data(for: Keys.password) else { throw UserFacingError.appleIDSignedOut }
        let auth = try await authenticate(appleID: account.appleID, password: String(decoding: data, as: UTF8.self))
        store(session: auth.session)
        return auth.session
    }

    private func authenticate(appleID: String, password: String) async throws -> AuthSession {
        let anisette = try await anisetteData()
        return try await portal.authenticate(
            appleID: appleID, password: password, anisetteData: anisette, xcodeVersion: Self.xcodeVersion,
            verificationHandler: { [weak self] request in
                guard let self else { return .cancel }
                return await self.handleTwoFactor(request)
            })
    }

    private func storedSession() -> Session? {
        Keychain.data(for: Keys.session).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }

    private func store(session: Session) {
        Keychain.set(try? JSONEncoder().encode(session), for: Keys.session)
    }

    private static func isExpiredSession(_ error: Error) -> Bool {
        if case ServerError.underlyingError(let code, let message) = error {
            return code == 1100 || code == 1101 || message.localizedCaseInsensitiveContains("session")
        }
        return false
    }

    // MARK: - Anisette

    private func anisetteData() async throws -> AnisetteData {
        guard let server = URL(string: anisetteServer.trimmingCharacters(in: .whitespaces)), server.scheme != nil else {
            throw UserFacingError.anisetteServerInvalid
        }
        let identifier: UUID
        if let saved = UserDefaults.standard.string(forKey: Keys.anisetteID).flatMap(UUID.init(uuidString:)) {
            identifier = saved
        } else {
            identifier = UUID()
            UserDefaults.standard.set(identifier.uuidString, forKey: Keys.anisetteID)
        }
        let (data, blob) = try await AnisetteDataManager.shared.fetchAnisetteDataWithFailover(
            servers: [server], identifier: identifier, existingAdiBlob: Keychain.data(for: Keys.adiBlob))
        if let blob { Keychain.set(blob, for: Keys.adiBlob) }
        return data
    }

    // MARK: - Errors

    private static func userFacing(_ error: Error) -> Error {
        if error is UserFacingError { return error }
        let details = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        switch error {
        case DeveloperPortalError.incorrectCredentials:
            return UserFacingError(title: "Неверный Apple ID или пароль",
                                   hint: "Проверьте данные. Пароль приложений (app-specific) здесь не подходит — нужен обычный пароль Apple ID.",
                                   details: details)
        case DeveloperPortalError.userCancelled:
            return UserFacingError(title: "Вход отменён", hint: "Код подтверждения не был введён.")
        case DeveloperPortalError.incorrectVerificationCode:
            return UserFacingError(title: "Неверный код подтверждения", hint: "Попробуйте войти ещё раз.", details: details)
        case DeveloperPortalError.maximumAppIDLimitReached,
             ServerError.underlyingError(9120, _):
            return UserFacingError(title: "Лимит App ID исчерпан",
                                   hint: "Бесплатный Apple ID позволяет создать 10 App ID за 7 дней. Подождите, пока старые истекут.",
                                   details: details)
        case DeveloperPortalError.accountRepairRequired(_, let message):
            return UserFacingError(title: "Apple просит обновить аккаунт",
                                   hint: "Войдите на appleid.apple.com и примите условия или обновите данные. \(message)",
                                   details: details)
        case is AnisetteError, DeveloperPortalError.invalidAnisetteData:
            return UserFacingError(title: "Сервер anisette недоступен",
                                   hint: "Проверьте интернет или укажите другой сервер в «Настройки → Apple ID».",
                                   details: details)
        case is URLError:
            return UserFacingError(title: "Нет связи с Apple", hint: "Проверьте подключение к интернету и попробуйте снова.",
                                   details: details)
        default:
            return UserFacingError(title: "Apple отклонила запрос", hint: details, details: String(describing: error))
        }
    }
}
