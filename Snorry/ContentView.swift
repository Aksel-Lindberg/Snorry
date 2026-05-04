import SwiftUI

// MARK: - App root: tab bar with Monitor / Sessions / Settings
struct RootView: View {
    @State private var selectedTab: Tab = .home

    enum Tab: String {
        case home, sessions, settings
    }

    var body: some View {
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

            SettingsView(onDone: { selectedTab = .home })
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
    }
}
