import SwiftUI

/// Full-screen progress for one signing run, ending in a big «Установить» button
/// or a human-readable error.
struct SigningView: View {
    let item: AppItem
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appleAccount: AppleAccountService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flow = SigningFlow()
    @StateObject private var install = InstallFlow()
    @State private var signedItem: AppItem?
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 12)
                header
                stages
                Spacer()
                footer
            }
            .padding(24)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isRunning { Button("Закрыть") { dismiss() } }
                }
            }
            .interactiveDismissDisabled(isRunning)
            // Apple may ask for a 2FA code while profiles are being fetched.
            .sheet(item: $appleAccount.codePrompt) { TwoFactorSheet(prompt: $0) }
        }
        .installFlow(install, env: env)
        .task { await start() }
    }

    private var isRunning: Bool { if case .running = flow.phase { return true }; return flow.phase == .idle }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ringColor.opacity(0.15))
                    .frame(width: 132, height: 132)
                    .scaleEffect(pulse && isRunning ? 1.08 : 1)
                    .animation(isRunning && settings.animationsEnabled
                               ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default, value: pulse)
                AppIconView(url: item.iconPath.map(env.library.url), size: 84)
                if flow.phase == .succeeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34)).foregroundStyle(.white, .green)
                        .offset(x: 42, y: 42)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .onAppear { pulse = true }

            VStack(spacing: 4) {
                Text(item.name).font(.title2.weight(.bold))
                Text(headline).font(.subheadline).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
    }

    private var ringColor: Color {
        switch flow.phase {
        case .succeeded: .green
        case .failed: .orange
        default: Brand.accent
        }
    }

    private var headline: String {
        switch flow.phase {
        case .idle: "Запуск…"
        case .running(let s): s.title
        case .succeeded: "Приложение подписано"
        case .failed: "Подпись не выполнена"
        }
    }

    // MARK: Stages

    @ViewBuilder private var stages: some View {
        if case .failed = flow.phase, let error = flow.error {
            ErrorCard(error: error).transition(.opacity)
        } else {
            Card(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(flow.stages, id: \.self) { stage in
                        StageRow(stage: stage, state: state(for: stage))
                        if stage != flow.stages.last { Divider().padding(.leading, 52) }
                    }
                }
            }
        }
    }

    private func state(for stage: SigningStage) -> StageRow.State {
        if flow.done.contains(stage) || flow.phase == .succeeded { return .done }
        if case .running(let s) = flow.phase, s == stage { return .active }
        return .pending
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        switch flow.phase {
        case .succeeded:
            VStack(spacing: 12) {
                Button {
                    if let s = signedItem { install.request(s, env: env) }
                } label: {
                    if install.isWorking { ProgressView().tint(.white) }
                    else { Label("Установить", systemImage: "arrow.down.circle.fill") }
                }
                .buttonStyle(PrimaryButtonStyle(tint: .green))
                .disabled(install.isWorking)
                Text(settings.installMethod.subtitle)
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .failed:
            VStack(spacing: 10) {
                Button("Повторить") { Task { await start() } }.buttonStyle(PrimaryButtonStyle())
                Button("Открыть сертификаты") { dismiss(); env.selectedTab = .certificates }
                    .buttonStyle(SecondaryButtonStyle())
            }
        default:
            Text("Не закрывайте приложение").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func start() async {
        signedItem = await flow.run(item: item, env: env)
        if let s = signedItem, settings.autoInstallAfterSigning {
            install.request(s, env: env)
        }
    }
}

private struct StageRow: View {
    enum State { case pending, active, done }
    let stage: SigningStage
    let state: State

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                case .active:
                    ProgressView()
                case .pending:
                    Image(systemName: stage.symbol).foregroundStyle(.tertiary)
                }
            }
            .font(.title3)
            .frame(width: 28, height: 28)

            Text(stage.title.replacingOccurrences(of: "…", with: ""))
                .font(.body.weight(state == .active ? .semibold : .regular))
                .foregroundStyle(state == .pending ? .secondary : .primary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 14)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state)
    }
}
