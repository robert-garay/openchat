import SwiftUI
import SwiftData

@main
struct OpenChatApp: App {
    let modelContainer: ModelContainer
    @State private var providerStore = ProviderStore()
    @State private var dataSourceStore = AgentDataSourceStore()
    @State private var webSearchStore = WebSearchStore()
    @State private var rulesStore = RulesStore()
    @State private var memoryStore = MemoryStore()
    @State private var skillsStore = SkillsStore()
    @AppStorage("com.openchat.appearance") private var appearance: AppAppearance = .system

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Conversation.self,
                ChatMessage.self,
                MemoryItem.self,
                RuleItem.self,
                Skill.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(providerStore)
                .environment(dataSourceStore)
                .environment(webSearchStore)
                .environment(rulesStore)
                .environment(memoryStore)
                .environment(skillsStore)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear { appearance.applyToAllWindows() }
                .onChange(of: appearance) { _, newValue in
                    newValue.applyToAllWindows()
                }
        }
        .modelContainer(modelContainer)
    }
}
