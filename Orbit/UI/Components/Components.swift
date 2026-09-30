import SwiftUI
import UniformTypeIdentifiers

// MARK: - Buttons

/// Large, rounded, full-width primary action — the main CTA on every screen.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Brand.accent
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(tint.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Brand.accent)
            .background(Brand.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Compact capsule button used inside rows ("Установить", "Обновить").
struct PillButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).frame(height: 32)
            .foregroundStyle(filled ? .white : Brand.accent)
            .background(filled ? Brand.accent : Brand.accent.opacity(0.12), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Cards

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Icons

struct AppIconView: View {
    var url: URL?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let url, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(.systemGray4), Color(.systemGray5)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "app.dashed").font(.system(size: size * 0.4)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }
}

/// Colored rounded-square SF Symbol — like the icons in iOS Settings.
struct SettingsIcon: View {
    var symbol: String
    var color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SettingsLabel: View {
    var title: String
    var symbol: String
    var color: Color
    var body: some View {
        Label { Text(title) } icon: { SettingsIcon(symbol: symbol, color: color) }
    }
}

// MARK: - Status

struct StatusPill: View {
    var text: String
    var symbol: String
    var color: Color
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

extension AppItem.Status {
    var color: Color {
        switch self {
        case .notSigned: .secondary
        case .signed: .blue
        case .installed: .green
        case .expiringSoon: .orange
        case .expired: .red
        }
    }
}

extension SigningCertificate.Status {
    var color: Color { self == .valid ? .green : self == .expiringSoon ? .orange : .red }
    var symbol: String { self == .valid ? "checkmark.seal.fill" : self == .expiringSoon ? "clock.fill" : "xmark.seal.fill" }
}

// MARK: - Empty & loading

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String
    var action: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Brand.accent.opacity(0.10)).frame(width: 120, height: 120)
                Image(systemName: symbol)
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(Brand.accent)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(appeared ? 1 : 0.8).opacity(appeared ? 1 : 0)
            VStack(spacing: 6) {
                Text(title).font(.title3.weight(.semibold))
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button(actionTitle, action: action)
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 280)
                .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { appeared = true } }
    }
}

struct LoadingOverlay: View {
    var text: String
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

// MARK: - Error card

struct ErrorCard: View {
    var error: UserFacingError
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.orange)
            Text(error.title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(error.hint).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let details = error.details {
                Button(showDetails ? "Скрыть подробности" : "Подробнее") { withAnimation { showDetails.toggle() } }
                    .font(.footnote)
                if showDetails {
                    Text(details).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled).padding(10)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Banner (toast)

struct BannerView: View {
    var banner: Banner
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.subheadline.weight(.semibold))
                if let s = banner.subtitle { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(.horizontal)
    }
    private var icon: String {
        switch banner.kind { case .success: "checkmark.circle.fill"; case .error: "exclamationmark.circle.fill"; case .info: "info.circle.fill" }
    }
    private var color: Color {
        switch banner.kind { case .success: .green; case .error: .red; case .info: Brand.accent }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    var onComplete: (Bool) -> Void = { _ in }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in onComplete(completed) }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct IdentifiableURL: Identifiable { let url: URL; var id: String { url.path } }

// MARK: - File types

extension UTType {
    static let ipa = UTType(filenameExtension: "ipa") ?? .data
    static let tipa = UTType(filenameExtension: "tipa") ?? .data
    static let p12 = UTType(filenameExtension: "p12") ?? .data
    static let mobileProvision = UTType(filenameExtension: "mobileprovision") ?? .data
    static let pairing = UTType(filenameExtension: "mobiledevicepairing") ?? .data
}

// MARK: - Formatting

extension Date {
    var shortDate: String { formatted(date: .abbreviated, time: .omitted) }

    /// "через 6 дн." / "истёк 2 дн. назад"
    var relativeExpiry: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
