import SwiftUI

struct WelcomeView: View {
    @State private var showingAddProvider = false

    private let highlights: [(icon: String, title: String, subtitle: String)] = [
        ("bolt.fill", "Any Model, Instantly", "OpenAI, Claude, Gemini, or the newest Chinese open models — DeepSeek, Qwen, Kimi, GLM."),
        ("lock.fill", "Your Keys, Your Device", "API keys are stored in the iOS Keychain. OpenChat talks directly to providers — no middleman server."),
        ("bubble.left.and.bubble.right.fill", "Familiar, Fast Chat", "A clean, native chat experience with streaming replies and full markdown & code support."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            OpenChatLogoView(size: 108)
                .padding(.top, 8)

            Text("OpenChat")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 20)

            Text("One app for every AI model you want to talk to.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)

            VStack(spacing: 20) {
                ForEach(highlights, id: \.title) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 28)

            Spacer(minLength: 24)

            Button {
                Haptics.light()
                showingAddProvider = true
            } label: {
                Text("Connect a Model")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            Text("Takes about 30 seconds")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingAddProvider) {
            AddProviderView()
        }
    }
}
