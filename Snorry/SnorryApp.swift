import SwiftUI
import SwiftData
import UserNotifications
import FirebaseCore
import FirebaseAnalytics

@main
struct SnorryApp: App {

    @State private var appEnv = AppEnvironment()

    #if DEBUG
    /// True when Xcode passes Firebase’s debug launch flag (see shared Snorry scheme).
    private static var isFirebaseAnalyticsDebugMode: Bool {
        CommandLine.arguments.contains("-FIRAnalyticsDebugEnabled")
    }
    #endif

    init() {
        FirebaseApp.configure()
        #if DEBUG
        // Collection off unless the Snorry scheme passes -FIRAnalyticsDebugEnabled (DebugView).
        Analytics.setAnalyticsCollectionEnabled(Self.isFirebaseAnalyticsDebugMode)
        #else
        // Disabled until ATT is resolved (see TrackingAuthorizationManager).
        Analytics.setAnalyticsCollectionEnabled(false)
        #endif
        // Required so snoring alerts show as system banners while Snorry is on-screen (foreground).
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SnoreSession.self,
            SnoreEvent.self,
            WaveformSample.self,
            AlertSettings.self,
            AlertSettingsChange.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // First attempt — succeeds if the on-disk store matches the current schema.
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }

        // Schema mismatch (e.g. leftover template "Item" store) — delete and recreate.
        let storeURL = URL.applicationSupportDirectory
            .appendingPathComponent("default.store")
        let candidates = [storeURL,
                          storeURL.appendingPathExtension("shm"),
                          storeURL.appendingPathExtension("wal")]
        candidates.forEach { try? FileManager.default.removeItem(at: $0) }

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer even after store reset: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnv)
                .preferredColorScheme(.dark)
                .task {
                    let store = SessionStore(context: sharedModelContainer.mainContext)
                    store.recoverOrphanedSession()
                    store.reconcileEndedSessionsOnLaunch()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Services container (injected as environment object)
@Observable
final class AppEnvironment {
    let notifications = NotificationManager.shared
    // Services that depend on SwiftData context are instantiated per-view-model.
}

extension Notification.Name {
    /// Posted after Settings saves `AlertSettings` so monitoring can refresh snore tuning.
    static let snorryAlertSettingsDidSave = Notification.Name("snorryAlertSettingsDidSave")
}
