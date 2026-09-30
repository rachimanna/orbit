#if canImport(IDevice)
import Foundation
import IDevice

/// Direct install through lockdownd over the VPN loopback tunnel, using idevice
/// (github.com/jkcoxson/idevice, MIT): upload the IPA with AFC to PublicStaging,
/// then ask installation_proxy to install it — the same path SideStore takes.
///
/// Over the network (unlike USB) iOS drops service connections of a client that doesn't
/// keep the heartbeat service (marco/polo) alive, so a heartbeat runs during the install.
enum IDeviceInstall {
    static func install(ipa: URL, pairingFile: URL, host: String, port: Int) async throws {
        try await Task.detached(priority: .userInitiated) {
            try installSync(ipa: ipa, pairingFile: pairingFile, host: host, port: port)
        }.value
    }

    private static func installSync(ipa: URL, pairingFile: URL, host: String, port: Int) throws {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(clamping: port).bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            throw UserFacingError(title: "Неверный IP-адрес устройства",
                                  hint: "Проверьте адрес в «Настройки → Подключение».")
        }

        let heartbeat = try Heartbeat(pairingFile: pairingFile, address: addr)
        defer { heartbeat.stop() }
        heartbeat.waitForFirstBeat(timeout: 12)

        let remotePath = "PublicStaging/\(UUID().uuidString).ipa"

        // 1. Upload (own provider per service, like SideStore)
        let afcProvider = try makeProvider(pairingFile: pairingFile, address: addr)
        defer { idevice_provider_free(afcProvider) }
        var afc: OpaquePointer?
        try check(afc_client_connect(afcProvider, &afc), step: "Подключение к AFC")
        defer { afc_client_free(afc) }

        idevice_error_free(afc_make_directory(afc, "PublicStaging"))   // usually exists already
        var file: OpaquePointer?
        try check(afc_file_open(afc, remotePath, AfcWr, &file), step: "Создание файла на устройстве")

        let reader: FileHandle
        do { reader = try FileHandle(forReadingFrom: ipa) } catch {
            idevice_error_free(afc_file_close(file))
            throw error
        }
        defer { try? reader.close() }
        do {
            while true {
                let chunk = reader.readData(ofLength: 4 << 20)
                if chunk.isEmpty { break }
                let err = chunk.withUnsafeBytes { raw in
                    afc_file_write(file, raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
                }
                try check(err, step: "Загрузка IPA на устройство")
            }
        } catch {
            idevice_error_free(afc_file_close(file))
            idevice_error_free(afc_remove_path(afc, remotePath))
            throw error
        }
        try check(afc_file_close(file), step: "Загрузка IPA на устройство")
        defer { idevice_error_free(afc_remove_path(afc, remotePath)) }

        // 2. Install
        let proxyProvider = try makeProvider(pairingFile: pairingFile, address: addr)
        defer { idevice_provider_free(proxyProvider) }
        var proxy: OpaquePointer?
        try check(installation_proxy_connect(proxyProvider, &proxy), step: "Подключение к службе установки")
        defer { installation_proxy_client_free(proxy) }
        try check(installation_proxy_install(proxy, remotePath, nil), step: "Установка")
    }

    /// A lockdown TCP provider. It owns its own copy of the pairing file.
    fileprivate static func makeProvider(pairingFile: URL, address: sockaddr_in) throws -> OpaquePointer? {
        var pairing: OpaquePointer?
        try check(idevice_pairing_file_read(pairingFile.path, &pairing), step: "Чтение pairing-файла")

        var addr = address
        var provider: OpaquePointer?
        let err = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                idevice_tcp_provider_new($0, pairing, Brand.name, &provider)
            }
        }
        if err != nil { idevice_pairing_file_free(pairing) }
        try check(err, step: "Подключение к устройству")
        return provider
    }

    /// Converts an idevice error into a user-facing one and frees it.
    fileprivate static func check(_ error: UnsafeMutablePointer<IdeviceFfiError>?, step: String) throws {
        guard let error else { return }
        let message = error.pointee.message.map { String(cString: $0) } ?? "код \(error.pointee.code)"
        let code = error.pointee.code
        idevice_error_free(error)
        throw UserFacingError(title: "Установка не удалась",
                              hint: "\(step): \(message)",
                              details: "idevice error \(code)")
    }
}

/// Keeps com.apple.mobile.heartbeat alive (marco → polo) on its own thread until stopped.
private final class Heartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private let firstBeat = DispatchSemaphore(value: 0)
    private let provider: OpaquePointer?
    private let client: OpaquePointer?

    init(pairingFile: URL, address: sockaddr_in) throws {
        let provider = try IDeviceInstall.makeProvider(pairingFile: pairingFile, address: address)
        var client: OpaquePointer?
        if let err = heartbeat_connect(provider, &client) {
            idevice_provider_free(provider)
            try IDeviceInstall.check(err, step: "Запуск heartbeat")
        }
        self.provider = provider
        self.client = client
        Thread.detachNewThread { [self] in run() }
    }

    func waitForFirstBeat(timeout: TimeInterval) {
        _ = firstBeat.wait(timeout: .now() + timeout)
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }; return stopped
    }

    private func run() {
        var interval: UInt64 = 10
        var signalled = false
        while !isStopped {
            var next: UInt64 = 0
            if let err = heartbeat_get_marco(client, interval + 5, &next) {
                idevice_error_free(err)
                break
            }
            if let err = heartbeat_send_polo(client) {
                idevice_error_free(err)
                break
            }
            interval = max(next, 1)
            if !signalled { signalled = true; firstBeat.signal() }
        }
        if !signalled { firstBeat.signal() }
        heartbeat_client_free(client)
        idevice_provider_free(provider)
    }
}
#endif
