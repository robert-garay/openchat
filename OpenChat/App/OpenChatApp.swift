import SwiftUI
import SwiftData

@main
struct OpenChatApp: App {
    let modelContainer: ModelContainer
    @State private var providerStore = ProviderStore()
    @AppStorage("com.openchat.appearance") private var appearance: AppAppearance = .system

    init() {
        do {
            modelContainer = try ModelContainer(for: Conversation.self, ChatMessage.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(providerStore)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(modelContainer)
    }
}
