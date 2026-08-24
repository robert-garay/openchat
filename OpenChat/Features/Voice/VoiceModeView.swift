import SwiftUI
import SwiftData

/// Full-screen, immersive voice-mode call UI. Presented as a `fullScreenCover`
/// from `ChatView`; owns a `VoiceConversationController` for its lifetime.
struct VoiceModeView: View {
    let conversation: Conversation
    let modelContext: ModelContext
    let providerStore: ProviderStore
    let webSearchStore: WebSearchStore
    let skillsStore: SkillsStore
    let rulesStore: RulesStore
    let memoryStore: MemoryStore

    @Environment(\.dismiss) private var dismiss
    @State private var controller: VoiceConversationController?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()
                orb
                statusText
                Spacer()
            }

            VStack {
                HStack {
                    Spacer()
                    closeButton
                }
                Spacer()
            }
            .padding(20)
        }
        .task {
            guard controller == nil else { return }
            let controller = makeController()
            self.controller = controller
            await controller.start()
        }
        .onDisappear {
            let controllerToEnd = controller
            Task { await controllerToEnd?.end() }
        }
    }

    private func makeController() -> VoiceConversationController {
        VoiceConversationController(
            conversation: conversation,
            modelContext: modelContext,
            providerStore: providerStore,
            webSearchStore: webSearchStore,
            skillsStore: skillsStore,
            rulesStore: rulesStore,
            memoryStore: memoryStore
        )
    }

    private var orb: some View {
        let level = CGFloat(max(controller?.inputLevel ?? 0, controller?.outputLevel ?? 0))
        return Circle()
            .fill(orbColor)
            .frame(width: 160 + level * 60, height: 160 + level * 60)
            .animation(.easeOut(duration: 0.12), value: level)
            .animation(Theme.springFast, value: orbColorKey)
    }

    /// Drives the color-change animation without requiring `ConnectionState` to be Hashable-driven directly.
    private var orbColorKey: Int {
        switch controller?.state {
        case .assistantSpeaking: return 1
        case .userSpeaking: return 2
        case .failed: return 3
        default: return 0
        }
    }

    private var orbColor: Color {
        switch controller?.state {
        case .assistantSpeaking: return .accentColor
        case .userSpeaking: return .green
        case .failed: return .red
        default: return Color(.tertiaryLabel)
        }
    }

    private var statusText: some View {
        Text(statusLabel)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .padding(.horizontal, 32)
            .animation(Theme.springFast, value: statusLabel)
    }

    private var statusLabel: String {
        switch controller?.state {
        case .none, .idle:
            return "Starting…"
        case .connecting:
            return "Connecting…"
        case .listening:
            return "Listening"
        case .userSpeaking:
            return "Listening…"
        case .assistantSpeaking:
            let transcript = controller?.partialAssistantTranscript ?? ""
            return transcript.isEmpty ? "Speaking…" : transcript
        case .runningTool(let label):
            return label
        case .reconnecting:
            return "Reconnecting…"
        case .ended:
            return "Call ended"
        case .failed(let message):
            return message
        }
    }

    private var closeButton: some View {
        Button {
            Haptics.medium()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.15), in: Circle())
        }
        .accessibilityLabel("End voice mode")
    }
}
