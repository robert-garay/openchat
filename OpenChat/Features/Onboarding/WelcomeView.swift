import SwiftUI

struct WelcomeView: View {
    @Environment(ProviderStore.self) private var providerStore
    @State private var showingFreeModelsSignup = false
    @State private var showingAddProvider = false

    private var hasManagedFreeTier: Bool {
        AppSecrets.managedOpenRouterAPIKey != nil
    }

    private let highlights: [(icon: String, title: String, subtitle: String)] = [
        ("eye.fill", "Qwen3.7 Flash Included", "Multimodal chat with a 1M context window — included for every new user."),
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

            Text(hasManagedFreeTier
                  ? "Qwen3.7 Flash is ready — start chatting, or connect any other provider."
                  : "Free models for every new user — plus any provider you connect.")
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
                if hasManagedFreeTier {
                    providerStore.bootstrapManagedFreeTierIfNeeded(apiKey: AppSecrets.managedOpenRouterAPIKey)
                } else {
                    showingFreeModelsSignup = true
                }
            } label: {
                Text(hasManagedFreeTier ? "Start Chatting" : "Start with Free Models")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            Button {
                Haptics.light()
                showingAddProvider = true
            } label: {
                Text("Connect another provider")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.bottom, 8)

            Text(hasManagedFreeTier ? "Includes Qwen3.7 Flash" : "Free OpenRouter key · about 30 seconds")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingFreeModelsSignup) {
            FreeModelsSignupView()
        }
        .sheet(isPresented: $showingAddProvider) {
            AddProviderView()
        }
    }
}
