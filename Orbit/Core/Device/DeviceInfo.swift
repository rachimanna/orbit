import UIKit

/// Only what a regular App Store–style app may read. No UDID, no serial number:
/// iOS doesn't expose them. The UDID is shown only if the user imported a pairing
/// file (which contains it) — and we say where it came from.
struct DeviceInfo {
    let modelIdentifier: String   // e.g. "iPhone16,1"
    let model: String             // "iPhone" / "iPad"
    let systemName: String
    let systemVersion: String
    let vendorID: String?         // identifierForVendor — per-developer, not the UDID

    @MainActor static var current: DeviceInfo {
        var sys = utsname()
        uname(&sys)
        let id = withUnsafeBytes(of: &sys.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let d = UIDevice.current
        return DeviceInfo(modelIdentifier: id, model: d.model, systemName: d.systemName,
                          systemVersion: d.systemVersion, vendorID: d.identifierForVendor?.uuidString)
    }

    var isSimulator: Bool { modelIdentifier == "x86_64" || modelIdentifier == "arm64" }
}
