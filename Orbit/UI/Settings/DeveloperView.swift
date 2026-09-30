import SwiftUI

struct DeveloperView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Brand.logo.resizable().scaledToFit().frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text(Brand.name).font(.title2.weight(.bold))
                    Text("от \(Brand.developer)").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            Section("О приложении") {
                LabeledContent("Разработчик", value: Brand.developer)
                LabeledContent("Версия", value: Brand.version)
                LabeledContent("Сборка", value: Brand.build)
            }
            Section("Связь") {
                Link(destination: Brand.website) { SettingsLabel(title: "Сайт", symbol: "globe", color: .blue) }
                Link(destination: Brand.github) { SettingsLabel(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", color: .black) }
                Link(destination: URL(string: "mailto:\(Brand.supportEmail)")!) { SettingsLabel(title: "Написать разработчику", symbol: "envelope.fill", color: .teal) }
            }
            .foregroundStyle(.primary)
            Section {
                NavigationLink { LicensesView() } label: { SettingsLabel(title: "Лицензии Open Source", symbol: "doc.plaintext.fill", color: .gray) }
                Button { reportBug() } label: { SettingsLabel(title: "Сообщить об ошибке", symbol: "ladybug.fill", color: .red) }
                    .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Разработчик")
    }

    @MainActor private func reportBug() {
        let d = DeviceInfo.current
        let body = """


        ---
        \(Brand.name) \(Brand.version) (\(Brand.build))
        \(d.modelIdentifier), \(d.systemName) \(d.systemVersion)
        """
        var c = URLComponents(string: "mailto:\(Brand.supportEmail)")!
        c.queryItems = [.init(name: "subject", value: "\(Brand.name): ошибка"), .init(name: "body", value: body)]
        if let url = c.url { openURL(url) }
    }
}

struct LicensesView: View {
    private let licenses: [(String, String, String)] = [
        ("zsign", "MIT", "https://github.com/zhlynn/zsign"),
        ("ZIPFoundation", "MIT", "https://github.com/weichsel/ZIPFoundation"),
        ("OpenSSL", "Apache 2.0", "https://github.com/openssl/openssl"),
        ("zlib", "zlib License", "https://zlib.net"),
        ("minizip", "zlib License", "https://github.com/madler/zlib/tree/master/contrib/minizip"),
        ("idevice", "MIT", "https://github.com/jkcoxson/idevice"),
        ("SideSign", "GPL-3.0", "https://github.com/SideStore/SideSign"),
        ("AnisetteKit", "AGPL-3.0", "https://github.com/mahee96/AnisetteKit"),
        ("GSACryptoKit", "AGPL-3.0", "https://github.com/mahee96/GSACryptoKit"),
        ("CodeSignKit", "AGPL-3.0", "https://github.com/mahee96/CodeSignKit"),
        ("swift-crypto", "Apache 2.0", "https://github.com/apple/swift-crypto"),
        ("libdeflate", "MIT", "https://github.com/SideStore/libdeflate"),
        ("Unicorn Engine", "GPL-2.0", "https://github.com/unicorn-engine/unicorn"),
    ]
    var body: some View {
        List(licenses, id: \.0) { l in
            Link(destination: URL(string: l.2)!) {
                LabeledContent(l.0, value: l.1)
            }
            .foregroundStyle(.primary)
        }
        .safeAreaInset(edge: .top) {
            Link(destination: URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!) {
                Text("\(Brand.name) распространяется под GNU AGPL-3.0. Исходный код открыт.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal).padding(.top, 8)
            }
        }
        .navigationTitle("Лицензии")
    }
}
