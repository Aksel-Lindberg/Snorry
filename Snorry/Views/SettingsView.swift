import SwiftUI
import SwiftData
import UIKit

// MARK: - Alert threshold configuration
struct SettingsView: View {

    /// When embedded in a tab, `dismiss()` does nothing — call this to return to the Monitor tab.
    var onDone: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppEnvironment.self) private var appEnv
    @State private var vm: SettingsViewModel?
    @State private var confirmDeleteAllLogs = false
    @State private var showSubscription = false
    @AppStorage(UserPreferences.displayNameKey) private var userDisplayName = ""
    @AppStorage(UserPreferences.appUIThemeKey) private var appUIThemeRaw = AppUITheme.defaultTheme.rawValue

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                if let vm {
                    settingsContent(vm: vm)
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        vm?.cancel()
                        dismiss()
                        onDone?()
                    }
                    .foregroundStyle(Theme.labelSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        vm?.save()
                        dismiss()
                        onDone?()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
            .onAppear {
                if vm == nil { vm = SettingsViewModel(context: context) }
            }
            .onDisappear {
                vm?.stopAlarmStylePreview()
            }
            .sheet(isPresented: $showSubscription) {
                SubscriptionView(paywallSource: "settings")
            }
        }
    }

    // MARK: Content

    private func settingsContent(vm: SettingsViewModel) -> some View {
        List {
            profileSection
            alertChannelsSection(vm: vm)
            alarmStyleSection(vm: vm)
            actionsSection(vm: vm)
            subscriptionSection()
            supportSection()
            discoverSection
            appSection
            legalSection()
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .clearsFloatingTabBar()
        .frame(maxWidth: horizontalSizeClass == .regular ? 820 : .infinity)
        .frame(maxWidth: .infinity)
        .confirmationDialog(
            "Delete all sleep and settings logs?",
            isPresented: $confirmDeleteAllLogs,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                vm.deleteAllSleepAndSettingsLogs()
            }
            .disabled(vm.isDeletingLogs)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently removes every saved sleep session, snore clip, waveform, and Insights settings-change marker. Your current Settings values are not changed. Stop recording before deleting."
            )
        }
        .alert(
            "Couldn’t Delete Logs",
            isPresented: Binding(
                get: { vm.deleteLogsFailedMessage != nil },
                set: { if !$0 { vm.clearDeleteLogsError() } }
            )
        ) {
            Button("OK", role: .cancel) { vm.clearDeleteLogsError() }
        } message: {
            Text(vm.deleteLogsFailedMessage ?? "")
        }
        .alert(
            "Notifications",
            isPresented: Binding(
                get: { vm.pushNotificationsBlockedMessage != nil },
                set: { if !$0 { vm.clearPushNotificationsBlockedMessage() } }
            )
        ) {
            Button("Open Settings") {
                vm.clearPushNotificationsBlockedMessage()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { vm.clearPushNotificationsBlockedMessage() }
        } message: {
            Text(vm.pushNotificationsBlockedMessage ?? "")
        }
    }

    // MARK: Sections

    private var profileSection: some View {
        Section {
            TextField("Your name", text: $userDisplayName)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .foregroundStyle(Theme.labelPrimary)
        } header: {
            Text("Profile")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            Text("Optional. Used for a personal “Good night” greeting when you start recording.")
                .foregroundStyle(Theme.labelSecondary)
                .font(.caption)
        }
        .listRowBackground(Theme.surface)
    }

    private var discoverSection: some View {
        Section {
            NavigationLink {
                SleepAllyPromoView()
            } label: {
                SleepAllyDiscoverPromoLabel()
            }
            .foregroundStyle(Theme.labelPrimary)
        } header: {
            Text("Discover our advanced Sleep Assistant")
                .foregroundStyle(Theme.labelSecondary)
        }
        .listRowBackground(SleepAllyDiscoverPromoRowBackground())
    }

    private func alertChannelsSection(vm: SettingsViewModel) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { vm.pushNotificationEnabled },
                set: { newValue in
                    Task { await vm.setPushNotificationEnabled(newValue) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push notifications")
                        .font(.subheadline)
                    Text("Local alerts on this iPhone")
                        .font(.caption)
                        .foregroundStyle(Theme.labelSecondary)
                    Text(
                        "Allow notifications on your connected watch in order to get the snore alerts mirrored to your watch on your wrist"
                    )
                        .font(.caption)
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
            .tint(Theme.accent)

            Toggle(isOn: Binding(
                get: { vm.soundAlarmEnabled },
                set: {
                    vm.soundAlarmEnabled = $0
                    if !$0 { vm.stopAlarmStylePreview() }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sound alarm")
                        .font(.subheadline)
                    Text("In-app alarm tone while recording")
                        .font(.caption)
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
            .tint(Theme.accent)
        } header: {
            Text("Alert Channels")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "Turn on one or both. With both on: push is sent after 2 s of snoring, then the sound alarm after 5 s. "
                        + "While snoring continues, push and sound fire together on the same pulse and alerts clear after 3 s of silence."
                )
                    .foregroundStyle(Theme.labelSecondary)
                Text("The first time you turn on push, iOS asks whether Snorry may send notifications.")
                    .foregroundStyle(Theme.labelSecondary)
                if !vm.pushNotificationEnabled && !vm.soundAlarmEnabled {
                    Text("No alerts will fire until you enable push and/or sound.")
                        .foregroundStyle(Theme.snoring)
                }
            }
            .font(.caption)
        }
        .listRowBackground(Theme.surface)
    }

    private func alarmStyleSection(vm: SettingsViewModel) -> some View {
        Section {
            ForEach(AlarmStyle.allCases, id: \.rawValue) { style in
                HStack(spacing: 12) {
                    Button {
                        vm.alarmStyle = style
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: vm.alarmStyle == style
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .foregroundStyle(vm.alarmStyle == style
                                                 ? Theme.accent : Theme.labelTertiary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.labelPrimary)
                                Text(style.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Theme.labelSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(vm.isPreviewing(style: style) ? "Stop" : "Play") {
                        vm.toggleAlarmStylePreview(for: style)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(vm.isPreviewing(style: style)
                                  ? Theme.snoring.opacity(0.18)
                                  : Theme.accent.opacity(0.18))
                    )
                    .foregroundStyle(vm.isPreviewing(style: style) ? Theme.snoring : Theme.accent)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Alarm Style")
                .foregroundStyle(Theme.labelSecondary)
        }
        .opacity(vm.soundAlarmEnabled ? 1 : 0.45)
        .disabled(!vm.soundAlarmEnabled)
        .listRowBackground(Theme.surface)
    }

    private func actionsSection(vm: SettingsViewModel) -> some View {
        Section {
            Button("Reset to Defaults") {
                vm.reset()
            }
            .foregroundStyle(Theme.snoring)
            .disabled(vm.isDeletingLogs)

            Button("Delete All Sleep & Settings Logs", role: .destructive) {
                confirmDeleteAllLogs = true
            }
            .disabled(vm.isDeletingLogs)

            if vm.isDeletingLogs {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.accent)
                    Text("Deleting logs…")
                        .foregroundStyle(Theme.labelSecondary)
                        .font(.footnote)
                }
            }
        } footer: {
            Text(
                "Removes every sleep session, snore clip, waveform, and Insights settings-change marker. Current Settings values are not changed."
            )
            .foregroundStyle(Theme.labelSecondary)
            .font(.caption)
        }
        .listRowBackground(Theme.surface)
    }

    private func subscriptionSection() -> some View {
        let subscription = appEnv.subscription

        return Section {
            HStack {
                Text("Current Plan")
                    .foregroundStyle(Theme.labelPrimary)
                Spacer()
                Text(subscription.hasPremiumAccess ? "Premium" : "Free")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(subscription.hasPremiumAccess ? Theme.good : Theme.labelSecondary)
            }

            if subscription.hasPremiumAccess {
                Link("Manage Subscription", destination: LegalLinks.manageSubscriptions)
                    .foregroundStyle(Theme.accent)
            } else {
                Button("Upgrade to Premium") {
                    AppAnalytics.logPaywallViewed(source: "settings")
                    showSubscription = true
                }
                .foregroundStyle(Theme.accent)
            }

            Button("Restore Purchases") {
                Task { await subscription.restorePurchases() }
            }
            .foregroundStyle(Theme.labelPrimary)
            .disabled(
                subscription.purchaseState == .restoring ||
                subscription.purchaseState == .purchasing
            )

            if subscription.purchaseState == .restoring {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.accent)
                    Text("Restoring purchases…")
                        .foregroundStyle(Theme.labelSecondary)
                        .font(.footnote)
                }
            }
        } header: {
            Text("Subscription")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            Text(
                subscription.hasPremiumAccess
                    ? "Premium includes unlimited recording, full Sleep History, and Insights. Manage billing in your Apple ID subscriptions."
                    : "Free includes up to \(MonitoringUsageTracker.freeLimit) recording sessions and your latest sleep session. Upgrade for unlimited recording, full Sleep History, and Insights."
            )
            .foregroundStyle(Theme.labelSecondary)
            .font(.caption)
        }
        .listRowBackground(Theme.surface)
        .alert(
            "Subscription",
            isPresented: Binding(
                get: { subscription.errorMessage != nil },
                set: { if !$0 { subscription.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { subscription.clearError() }
        } message: {
            Text(subscription.errorMessage ?? "")
        }
    }

    private var appSection: some View {
        Section {
            Picker(
                "App UI Theme",
                selection: Binding(
                    get: { AppUITheme(rawValue: appUIThemeRaw) ?? .defaultTheme },
                    set: { appUIThemeRaw = $0.rawValue }
                )
            ) {
                ForEach(AppUITheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.inline)
            .foregroundStyle(Theme.labelPrimary)

            HStack {
                Text("App version")
                    .foregroundStyle(Theme.labelPrimary)
                Spacer()
                Text(AppMetadata.versionLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.labelSecondary)
            }
        } header: {
            Text("App")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            Text("System matches your iPhone light or dark appearance.")
                .foregroundStyle(Theme.labelSecondary)
                .font(.caption)
        }
        .listRowBackground(Theme.surface)
    }

    private func legalSection() -> some View {
        Section {
            Link("Terms of Use (EULA)", destination: LegalLinks.termsOfUse)
                .foregroundStyle(Theme.accent)
            Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
                .foregroundStyle(Theme.accent)
        } header: {
            Text("Legal")
                .foregroundStyle(Theme.labelSecondary)
        }
        .listRowBackground(Theme.surface)
    }

    private func supportSection() -> some View {
        Section {
            Link(destination: LegalLinks.support) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lifepreserver.fill")
                        .font(.body)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Support")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.labelPrimary)
                        Text("Contact support and get help with setup, permissions, alerts, logs, and troubleshooting.")
                            .font(.caption)
                            .foregroundStyle(Theme.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(Theme.labelTertiary)
                        .padding(.top, 4)
                }
                .padding(.vertical, 2)
            }
            .foregroundStyle(Theme.labelPrimary)

            Link(destination: URL(string: "mailto:\(LegalLinks.supportEmail)")!) {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    Text(LegalLinks.supportEmail)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(Theme.labelTertiary)
                }
            }
            .foregroundStyle(Theme.accent)
        } header: {
            Text("Support")
                .foregroundStyle(Theme.labelSecondary)
        }
        .listRowBackground(Theme.surface)
    }
}

// MARK: - SleepAlly discover promo (animated Settings row)

private struct SleepAllyDiscoverPromoLabel: View {
    @State private var glowPulse = false
    @State private var sparkleTwinkle = false
    @State private var floatUp = false
    @State private var shimmerOffset: CGFloat = -0.6

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accentGlow)
                    .frame(width: 42, height: 42)
                    .scaleEffect(glowPulse ? 1.18 : 0.86)
                    .opacity(glowPulse ? 0.95 : 0.35)

                Image(systemName: "moon.stars.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accentGradient)
                    .symbolEffect(.bounce, options: .repeating.speed(0.45))
                    .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.55))

                Image(systemName: "sparkles")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.warning)
                    .offset(x: 15, y: -13)
                    .scaleEffect(sparkleTwinkle ? 1.15 : 0.65)
                    .opacity(sparkleTwinkle ? 1 : 0.4)
                    .rotationEffect(.degrees(sparkleTwinkle ? 8 : -8))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("SleepAlly")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.labelPrimary)
                    .overlay { titleShimmer }
                    .clipShape(Rectangle())

                Text(
                    "Fall-asleep audio, wake-up alarms, habits, and advanced Snore Stop "
                        + "— from the makers of Snorry."
                )
                .font(.caption)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .offset(y: floatUp ? -1.5 : 1.5)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                sparkleTwinkle = true
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                floatUp = true
            }
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.35
            }
        }
    }

    private var titleShimmer: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, Theme.accent.opacity(0.65), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(geo.size.width * 0.5, 36))
            .offset(x: shimmerOffset * geo.size.width)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

private struct SleepAllyDiscoverPromoRowBackground: View {
    @State private var borderPulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Theme.surface,
                        Theme.surfaceSecondary.opacity(borderPulse ? 0.85 : 0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Theme.accent.opacity(borderPulse ? 0.95 : 0.3),
                                Color(red: 0.55, green: 0.35, blue: 1.0).opacity(borderPulse ? 0.8 : 0.22),
                                Theme.warning.opacity(borderPulse ? 0.65 : 0.18),
                                Theme.accent.opacity(borderPulse ? 0.95 : 0.3)
                            ],
                            center: .center
                        ),
                        lineWidth: borderPulse ? 1.5 : 1
                    )
            }
            .shadow(color: Theme.accentGlow.opacity(borderPulse ? 0.5 : 0.12), radius: borderPulse ? 9 : 3)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    borderPulse = true
                }
            }
    }
}

// MARK: - SleepAlly discover promo (animated Settings row)
