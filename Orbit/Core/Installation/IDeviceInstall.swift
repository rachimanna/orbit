#if canImport(IDevice)
import Foundation
import IDevice

/// Direct install through lockdownd over the VPN loopback tunnel, using idevice
/// (github.com/jkcoxson/idevice, MIT): upload the IPA with AFC to /PublicStaging,
/// then ask installation_proxy to install it — the same path SideStore takes.
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

        var pairing: OpaquePointer?
        try check(idevice_pairing_file_read(pairingFile.path, &pairing), step: "Чтение pairing-файла")

        // The provider takes ownership of the pairing file.
        var provider: OpaquePointer?
        let providerError = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                idevice_tcp_provider_new($0, pairing, Brand.name, &provider)
            }
        }
        if providerError != nil { idevice_pairing_file_free(pairing) }
        try check(providerError, step: "Подключение к устройству")
        defer { idevice_provider_free(provider) }

        // 1. Upload
        let remotePath = "/PublicStaging/\(UUID().uuidString).ipa"
        var afc: OpaquePointer?
        try check(afc_client_connect(provider, &afc), step: "Подключение к AFC")
        defer { afc_client_free(afc) }

        var file: OpaquePointer?
        if let firstError = afc_file_open(afc, remotePath, AfcWrOnly, &file) {
            // /PublicStaging may be missing, or afcd may have dropped the connection.
            // Create the folder on its own connection (afcd may close it afterwards),
            // then retry on a fresh one.
            idevice_error_free(firstError)
            afc_client_free(afc)
            afc = nil
            var mkdirClient: OpaquePointer?
            if afc_client_connect(provider, &mkdirClient) == nil {
                idevice_error_free(afc_make_directory(mkdirClient, "/PublicStaging"))
                afc_client_free(mkdirClient)
            }
            try check(afc_client_connect(provider, &afc), step: "Подключение к AFC")
            try check(afc_file_open(afc, remotePath, AfcWrOnly, &file), step: "Создание файла на устройстве")
        }

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
        var proxy: OpaquePointer?
        try check(installation_proxy_connect(provider, &proxy), step: "Подключение к службе установки")
        defer { installation_proxy_client_free(proxy) }
        try check(installation_proxy_install(proxy, remotePath, nil), step: "Установка")
    }

    /// Converts an idevice error into a user-facing one and frees it.
    private static func check(_ error: UnsafeMutablePointer<IdeviceFfiError>?, step: String) throws {
        guard let error else { return }
        let message = error.pointee.message.map { String(cString: $0) } ?? "код \(error.pointee.code)"
        let code = error.pointee.code
        idevice_error_free(error)
        throw UserFacingError(title: "Установка не удалась",
                              hint: "\(step): \(message)",
                              details: "idevice error \(code)")
    }
}
#endif
