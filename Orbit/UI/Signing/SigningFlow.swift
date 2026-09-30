import SwiftUI

/// Drives one signing run. Stages advance only when the signer reports them.
@MainActor
final class SigningFlow: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running(SigningStage)
        case succeeded
        case failed(String)   // error id — the error itself is in `error`
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var done: Set<SigningStage> = []
    @Published private(set) var error: UserFacingError?

    func run(item: AppItem, env: AppEnvironment) async -> AppItem? {
        done = []; error = nil
        guard let cert = env.certificates.selected else { return fail(.noCertificate) }

        let files = env.library.fileStore
        let request = SigningRequest(
            ipa: files.absolute(item.originalIPAPath),
            appName: item.name,
            originalBundleID: item.bundleID,
            certificate: cert,
            p12: env.certificates.p12URL(cert),
            password: env.certificates.password(cert),
            profile: env.certificates.profileURL(cert),
            output: files.appFolder(item.id).appendingPathComponent("signed.ipa"),
            workDir: files.workFolder(),
            cleanWorkDir: env.settings.cleanTempAfterSigning)

        guard FileManager.default.fileExists(atPath: request.ipa.path) else {
            return fail(.init(title: "Исходный IPA удалён",
                              hint: "Добавьте приложение заново, чтобы подписать его ещё раз."))
        }

        do {
            let result = try await env.signer.sign(request) { [weak self] stage in
                await MainActor.run {
                    guard let self else { return }
                    if case .running(let prev) = self.phase { self.done.insert(prev) }
                    withAnimation(env.settings.animation) { self.phase = .running(stage) }
                }
            }
            if case .running(let last) = phase { done.insert(last) }

            var updated = item
            updated.signed = .init(ipaPath: files.relative(result.signedIPA), certificateID: cert.id,
                                   certificateName: cert.displayName, signedAt: Date(),
                                   expiresAt: result.expiresAt, signedBundleID: result.bundleID)
            updated.installedAt = nil
            env.library.update(updated)
            if env.settings.notificationsEnabled { Notifications.scheduleExpiryReminder(for: updated) }
            withAnimation(env.settings.animation) { phase = .succeeded }
            return updated
        } catch {
            return fail(UserFacingError.wrap(error))
        }
    }

    private func fail(_ e: UserFacingError) -> AppItem? {
        error = e
        withAnimation { phase = .failed(e.id.uuidString) }
        return nil
    }
}

/// Handles «Установить»: optional confirmation, then the chosen mechanism.
@MainActor
final class InstallFlow: ObservableObject {
    @Published var confirming: AppItem?
    @Published var shareURL: IdentifiableURL?
    @Published var isWorking = false
    @Published var error: UserFacingError?
    private var sharingItem: AppItem?

    func request(_ item: AppItem, env: AppEnvironment) {
        if env.settings.confirmBeforeInstall { confirming = item } else { Task { await perform(item, env: env) } }
    }

    func perform(_ item: AppItem, env: AppEnvironment) async {
        guard let signed = item.signed else { return }
        if item.status == .expired {
            error = .init(title: "Подпись истекла", hint: "Подпишите приложение заново действующим сертификатом.")
            return
        }
        let files = env.library.fileStore
        isWorking = true
        defer { isWorking = false }
        do {
            let outcome = try await env.installer.install(
                item, signedIPA: files.absolute(signed.ipaPath),
                icon: item.iconPath.map(files.absolute))
            switch outcome {
            case .presentShareSheet(let url):
                sharingItem = item
                shareURL = IdentifiableURL(url: url)
            case .handedToSystem:
                env.library.markInstalled(item.id, deleteIPA: env.settings.deleteIPAAfterInstall)
                env.banner = Banner(title: "Запрос на установку отправлен",
                                    subtitle: "Подтвердите установку в системном окне iOS", kind: .info)
            }
        } catch {
            self.error = UserFacingError.wrap(error)
        }
    }

    /// Called when the share sheet closes. We only know the file was handed to another app —
    /// installation itself happens there.
    func shareFinished(completed: Bool, env: AppEnvironment) {
        defer { sharingItem = nil; shareURL = nil }
        guard completed, let item = sharingItem else { return }
        env.library.markInstalled(item.id, deleteIPA: env.settings.deleteIPAAfterInstall)
        env.banner = Banner(title: "IPA передан", subtitle: "Завершите установку в выбранном приложении", kind: .info)
    }
}

extension View {
    /// Attaches the confirmation dialog, share sheet and error alert of an InstallFlow.
    func installFlow(_ flow: InstallFlow, env: AppEnvironment) -> some View {
        self
            .confirmationDialog("Установить приложение?",
                                isPresented: Binding(get: { flow.confirming != nil }, set: { if !$0 { flow.confirming = nil } }),
                                titleVisibility: .visible, presenting: flow.confirming) { item in
                Button("Установить «\(item.name)»") { Task { await flow.perform(item, env: env) } }
                Button("Отмена", role: .cancel) {}
            } message: { _ in
                Text("Способ: \(env.settings.installMethod.title)")
            }
            .sheet(item: Binding(get: { flow.shareURL }, set: { flow.shareURL = $0 })) { file in
                ShareSheet(items: [file.url]) { completed in flow.shareFinished(completed: completed, env: env) }
                    .presentationDetents([.medium, .large])
            }
            .alert(flow.error?.title ?? "",
                   isPresented: Binding(get: { flow.error != nil }, set: { if !$0 { flow.error = nil } })) {
                Button("OK", role: .cancel) {}
                if flow.error?.title != nil {
                    Button("Настройки установки") { env.selectedTab = .settings }
                }
            } message: {
                Text(flow.error?.hint ?? "")
            }
    }
}
