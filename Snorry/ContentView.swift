import SwiftUI
import SwiftData

// MARK: - App root: tab bar with Tonight / History / Insights / Settings
struct RootView: View {

    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab: Tab = .home
    @State private var monitorVM: MonitorViewModel?
    @State private var showRecordingScreen = false

    enum Tab: String {
        case home, sessions, analytics, settings
    }

    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingView { hasCompletedOnboarding = true }
        } else {
            mainTabView
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            Group {
                if let monitorVM {
                    HomeView(
                        vm: monitorVM,
                        showRecordingScreen: $showRecordingScreen,
                        onOpenSettings: { selectedTab = .settings }
                    )
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                }
            }
            .tabItem {
                Label("Tonight", systemImage: "moon.stars.fill")
            }
            .tag(Tab.home)
            .modifier(RecordingTabBadgeModifier(count: recordingTabBadge))

            SessionsListView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tab.sessions)

            AnalyticsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(Tab.analytics)

            SettingsView(onDone: { selectedTab = .home })
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let monitorVM, monitorVM.isMonitoring, !showRecordingScreen {
                RecordingInProgressBanner(elapsedSeconds: monitorVM.elapsedSeconds) {
                    selectedTab = .home
                    showRecordingScreen = true
                }
            }
        }
        .task {
            // Existing users who completed onboarding before ATT was added.
            await TrackingAuthorizationManager.requestTrackingAuthorizationIfNeeded()
        }
        .onAppear {
            setupMonitorViewModelIfNeeded()
        }
        .onChange(of: selectedTab) { _, tab in
            AppAnalytics.logTabSelected(tab.analyticsName)
        }
    }

    /// Shown on Tonight when a session is active but Recording is not on screen.
    private var recordingTabBadge: Int? {
        guard let monitorVM, monitorVM.isMonitoring, !showRecordingScreen else { return nil }
        return 1
    }

    private func setupMonitorViewModelIfNeeded() {
        guard monitorVM == nil else { return }
        let vm = MonitorViewModel(modelContext: modelContext)
        monitorVM = vm
        Task { await vm.syncNotificationAuthorizationFromSystem() }
    }
}

private extension RootView.Tab {
    var analyticsName: String {
        switch self {
        case .home: return "monitor"
        case .sessions: return "history"
        case .analytics: return "insights"
        case .settings: return "settings"
        }
    }
}

/// Applies a tab badge only when a recording session is active off-screen.
private struct RecordingTabBadgeModifier: ViewModifier {
    let count: Int?

    func body(content: Content) -> some View {
        if let count {
            content.badge(count)
        } else {
            content
        }
    }
}
