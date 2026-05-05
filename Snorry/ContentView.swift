import SwiftUI

// MARK: - App root: tab bar with Monitor / History / Analytics / Settings
struct RootView: View {

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab: Tab = .home

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
            HomeView()
                .tabItem {
                    Label("Monitor", systemImage: "waveform")
                }
                .tag(Tab.home)

            SessionsListView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tab.sessions)

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(Tab.analytics)

            SettingsView(onDone: { selectedTab = .home })
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
    }
}
