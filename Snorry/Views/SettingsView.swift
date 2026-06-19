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
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                SubscriptionView()
            }
        }
    }

    // MARK: Content

    private func settingsContent(vm: SettingsViewModel) -> some View {
        List {
            alertChannelsSection(vm: vm)
            alertTimingsSection(vm: vm)
            alarmStyleSection(vm: vm)
            actionsSection(vm: vm)
            subscriptionSection()
            supportSection()
            legalSection()
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .clearsFloatingTabBar()
        .frame(maxWidth: horizontalSizeClass == .regular ? 820 : .infinity)
        .frame(maxWidth: .infinity)
        .confirmationDialog(
            "Delete all sleep logs and settings history?",
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
                "This permanently removes every saved sleep session, snore clips, and settings-change markers used in analytics. Your current Settings values are not changed."
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
                    Text("In-app alarm tone while monitoring")
                        .font(.caption)
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
            .tint(Theme.accent)

            SliderRow(
                label: "Repeat Push notification every",
                value: Binding(get: { vm.pushRepeatInterval },
                               set: { vm.pushRepeatInterval = $0 }),
                range: 1...10,
                unit: "s",
                step: 1
            )
            .disabled(!vm.pushNotificationEnabled)
            .opacity(vm.pushNotificationEnabled ? 1 : 0.45)
        } header: {
            Text("Alert channels")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Turn on one or both. With both on: push fires first, then sound after the configured delay. Sound-only skips push; push-only never plays sound.")
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

    private func alertTimingsSection(vm: SettingsViewModel) -> some View {
        Section {
            TimingInfoRow(label: "Send push notification after", value: "2 s")
                .opacity(vm.pushNotificationEnabled ? 1 : 0.45)
            SliderRow(
                label: "Sound alarm after",
                value: Binding(get: { vm.soundAlarmAfter },
                               set: { vm.soundAlarmAfter = $0 }),
                range: 1...30,
                unit: "s",
                step: 1
            )
            .disabled(!vm.soundAlarmEnabled)
            .opacity(vm.soundAlarmEnabled ? 1 : 0.45)
        } header: {
            Text("Alert Timings")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            Text(
                "Push notification fires after a fixed 2 s. Sound alarm fires after the selected delay " +
                "(from snoring start). Alerts stay active until snoring has stopped for 3 s."
            )
                .foregroundStyle(Theme.labelSecondary)
                .font(.caption)
        }
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
                "Delete All removes every sleep session, waveform, snore clip, and settings-change history. Current preferences stay as they are."
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
                Text(subscription.hasBasicAccess ? "Basic" : "Free")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(subscription.hasBasicAccess ? Theme.good : Theme.labelSecondary)
            }

            if subscription.hasBasicAccess {
                Link("Manage Subscription", destination: LegalLinks.manageSubscriptions)
                    .foregroundStyle(Theme.accent)
            } else {
                Button("Upgrade to Basic") {
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
                subscription.hasBasicAccess
                    ? "Basic includes full Sleep History and Analytics. Manage billing in your Apple ID subscriptions."
                    : "Free includes Monitor and your latest sleep session. Upgrade for full history and Analytics."
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

// MARK: - Reusable slider rows

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.labelPrimary)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(Theme.monoDigit(size: 13))
                    .foregroundStyle(Theme.accent)
            }
            Slider(value: $value, in: range, step: step)
                .tint(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}

/// Read-only row that displays a fixed timing value alongside its label.
private struct TimingInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.labelPrimary)
            Spacer()
            Text(value)
                .font(Theme.monoDigit(size: 13))
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}
