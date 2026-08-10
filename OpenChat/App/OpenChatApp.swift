import SwiftUI
import SwiftData
import UserNotifications

/// Early-launch delegate that wires up notification handling before the app finishes launching.
final class OpenChatAppDelegate: NSObject, UIApplicationDelegate {
    @MainActor
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Re-create the shared background session so its delegate is wired up, then stash the
        // completion handler so the session can call it after all events are delivered.
        _ = BackgroundNetworkSession.shared
        BackgroundNetworkSession.backgroundSessionCompletionHandler = completionHandler
    }
}

@main
struct OpenChatApp: App {
    @UIApplicationDelegateAdaptor(OpenChatAppDelegate.self) private var appDelegate

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
                .task {
                    BackgroundGenerationService.shared.configure(
                        providerStore: providerStore,
                        dataSourceStore: dataSourceStore,
                        webSearchStore: webSearchStore,
                        rulesStore: rulesStore,
                        memoryStore: memoryStore,
                        skillsStore: skillsStore,
                        modelContainer: modelContainer
                    )
                }
        }
        .modelContainer(modelContainer)
    }
}
