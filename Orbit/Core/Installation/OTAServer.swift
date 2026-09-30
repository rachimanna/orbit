import Foundation
import Network
import UIKit

/// Apple's over-the-air install (itms-services) served from the device itself.
///
/// iOS only accepts a manifest served over HTTPS with a certificate it trusts. So this
/// method needs, from the user:
///   • a domain whose DNS A-record points to 127.0.0.1 (e.g. local.yourdomain.com), and
///   • a TLS certificate + key for that domain, exported as server.p12 and imported
///     in «Настройки → Установка → TLS-сертификат OTA».
/// Without them we refuse clearly instead of pretending.
@MainActor
final class OTAServer {
    private var listener: NWListener?
    private var files: [String: (URL, String)] = [:]    // path → (file, content-type)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    static var identityURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ota-server.p12")
    }
    static var hasIdentity: Bool { FileManager.default.fileExists(atPath: identityURL.path) }

    static func importIdentity(from url: URL, password: String) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        _ = try P12Reader.read(data, password: password)   // validates password
        try data.write(to: identityURL, options: .completeFileProtection)
        UserDefaults.standard.set(password, forKey: "otaIdentityPassword")
    }

    /// Starts (or reuses) the HTTPS listener and returns the itms-services URL to open.
    func serve(ipa: URL, icon: URL?, bundleID: String, version: String, title: String,
               domain: String, port: Int) async throws -> URL {
        guard !domain.isEmpty, Self.hasIdentity else {
            throw UserFacingError(title: "OTA-установка не настроена",
                                  hint: "Укажите домен и импортируйте TLS-сертификат в «Настройки → Установка», либо выберите способ «Через „Поделиться“».")
        }
        let base = "https://\(domain):\(port)"
        files = ["/app.ipa": (ipa, "application/octet-stream")]
        if let icon { files["/icon.png"] = (icon, "image/png") }

        let manifestURL = FileManager.default.temporaryDirectory.appendingPathComponent("manifest.plist")
        try manifest(ipaURL: "\(base)/app.ipa", iconURL: icon == nil ? nil : "\(base)/icon.png",
                     bundleID: bundleID, version: version, title: title).write(to: manifestURL)
        files["/manifest.plist"] = (manifestURL, "text/xml")

        try startIfNeeded(port: port)

        // Keep serving while iOS downloads the app in the background.
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ota") { [weak self] in
                self?.stop()
            }
        }

        var comps = URLComponents(string: "itms-services://")!
        comps.queryItems = [.init(name: "action", value: "download-manifest"),
                            .init(name: "url", value: "\(base)/manifest.plist")]
        return comps.url!
    }

    func stop() {
        listener?.cancel(); listener = nil
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }

    // MARK: - Server

    private func startIfNeeded(port: Int) throws {
        if listener != nil { return }
        let data = try Data(contentsOf: Self.identityURL)
        let pw = UserDefaults.standard.string(forKey: "otaIdentityPassword") ?? ""
        var items: CFArray?
        guard SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: pw] as CFDictionary, &items) == errSecSuccess,
              let dict = (items as? [[String: Any]])?.first,
              let identityRef = dict[kSecImportItemIdentity as String],
              let secIdentity = sec_identity_create(identityRef as! SecIdentity)
        else { throw UserFacingError.invalidP12 }

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
        let params = NWParameters(tls: tls)
        params.requiredInterfaceType = .loopback

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { throw UserFacingError.installUnavailable }
        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in self?.handle(conn) }
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8),
                  let line = request.split(separator: "\r\n").first else { conn.cancel(); return }
            let parts = line.split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]).components(separatedBy: "?")[0] : "/"
            Task { @MainActor in
                guard let self, let entry = self.files[path] else {
                    OTAServer.send(conn, status: "404 Not Found", type: "text/plain", body: Data("Not found".utf8))
                    return
                }
                OTAServer.stream(entry.0, type: entry.1, over: conn)
            }
        }
    }

    nonisolated private static func send(_ conn: NWConnection, status: String, type: String, body: Data) {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    /// Streams a (possibly large) file in 1 MB chunks.
    nonisolated private static func stream(_ url: URL, type: String, over conn: NWConnection) {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        else { send(conn, status: "500 Internal Server Error", type: "text/plain", body: Data()); return }

        let head = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(size)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in })

        func next() {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty {
                try? handle.close()
                conn.send(content: nil, contentContext: .finalMessage, isComplete: true,
                          completion: .contentProcessed { _ in conn.cancel() })
                return
            }
            conn.send(content: chunk, completion: .contentProcessed { error in
                if error == nil { next() } else { try? handle.close(); conn.cancel() }
            })
        }
        next()
    }

    private func manifest(ipaURL: String, iconURL: String?, bundleID: String, version: String, title: String) throws -> Data {
        var assets: [[String: String]] = [["kind": "software-package", "url": ipaURL]]
        if let iconURL {
            assets.append(["kind": "display-image", "url": iconURL])
            assets.append(["kind": "full-size-image", "url": iconURL])
        }
        let plist: [String: Any] = ["items": [[
            "assets": assets,
            "metadata": ["bundle-identifier": bundleID, "bundle-version": version,
                         "kind": "software", "title": title]
        ]]]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
