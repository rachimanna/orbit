import Foundation
import Network

/// Direct install over lockdownd through a local VPN loopback tunnel
/// (LocalDevVPN / StosVPN route 10.7.0.1 back to the device itself).
///
/// What this class does for real:
///   • imports and inspects the pairing file (the same one SideStore/Feather use);
///   • tests TCP reachability of lockdownd through the tunnel.
///
/// The actual AFC upload + installation_proxy calls require the `idevice` library
/// (github.com/jkcoxson/idevice, Rust, with C bindings). It isn't bundled because it
/// must be built for iOS with cargo. Until it is linked, `install` throws a clear
/// message — see README → «Установка через туннель».
@MainActor
final class TunnelInstaller: ObservableObject {
    enum ConnectionState: Equatable {
        case unknown, testing, reachable(latencyMS: Int), unreachable(String)

        var title: String {
            switch self {
            case .unknown: "Не проверено"
            case .testing: "Проверка…"
            case .reachable(let ms): "Подключено · \(ms) мс"
            case .unreachable: "Нет соединения"
            }
        }
    }

    struct PairingInfo {
        var udid: String?
        var hostID: String?
        var wifiMAC: String?
    }

    @Published private(set) var state: ConnectionState = .unknown
    @Published private(set) var pairing: PairingInfo?

    private let fm = FileManager.default
    private var pairingURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pairingFile.plist")
    }

    init() { pairing = readPairing() }

    var isEngineLinked: Bool {
        #if canImport(IDevice)
        true
        #else
        false
        #endif
    }

    func importPairingFile(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard (try? PropertyListSerialization.propertyList(from: data, format: nil)) is [String: Any] else {
            throw UserFacingError(title: "Это не pairing-файл",
                                  hint: "Нужен файл .mobiledevicepairing или .plist, созданный, например, в Impactor или jitterbugpair.")
        }
        try data.write(to: pairingURL, options: .completeFileProtection)
        pairing = readPairing()
    }

    func removePairingFile() {
        try? fm.removeItem(at: pairingURL)
        pairing = nil
    }

    private func readPairing() -> PairingInfo? {
        guard let data = try? Data(contentsOf: pairingURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return PairingInfo(udid: plist["UDID"] as? String,
                           hostID: plist["HostID"] as? String,
                           wifiMAC: plist["WiFiMACAddress"] as? String)
    }

    /// Opens a real TCP connection to host:port and measures the handshake time.
    func testConnection(host: String, port: Int, timeout: Double) async {
        state = .testing
        state = await Self.probe(host: host, port: port, timeout: timeout)
    }

    nonisolated static func probe(host: String, port: Int, timeout: Double) async -> ConnectionState {
        guard let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return .unreachable("Неверный порт") }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        let start = Date()
        return await withCheckedContinuation { cont in
            let once = OnceFlag()
            conn.stateUpdateHandler = { s in
                switch s {
                case .ready:
                    if once.fire() { cont.resume(returning: .reachable(latencyMS: Int(Date().timeIntervalSince(start) * 1000))) }
                    conn.cancel()
                case .failed(let e), .waiting(let e):
                    if once.fire() { cont.resume(returning: .unreachable(e.localizedDescription)) }
                    conn.cancel()
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.fire() { cont.resume(returning: .unreachable("Таймаут")) }
                conn.cancel()
            }
        }
    }

    func install(ipa: URL, host: String, port: Int, timeout: Double) async throws {
        guard pairing != nil else {
            throw UserFacingError(title: "Нет pairing-файла",
                                  hint: "Импортируйте pairing-файл в «Настройки → Подключение».")
        }
        if case .unreachable = await Self.probe(host: host, port: port, timeout: timeout) {
            throw UserFacingError.connectionFailed
        }
        guard isEngineLinked else {
            throw UserFacingError(title: "Прямая установка недоступна в этой сборке",
                                  hint: "Туннель работает, но модуль idevice не подключён. Выберите способ «Через „Поделиться“» — подписанный IPA можно установить через SideStore.")
        }
        #if canImport(IDevice)
        try await IDeviceInstall.install(ipa: ipa, pairingFile: pairingURL, host: host)
        #endif
    }
}

/// Thread-safe one-shot flag for continuation races.
final class OnceFlag: @unchecked Sendable {
    private var fired = false
    private let lock = NSLock()
    func fire() -> Bool { lock.lock(); defer { lock.unlock() }; if fired { return false }; fired = true; return true }
}
