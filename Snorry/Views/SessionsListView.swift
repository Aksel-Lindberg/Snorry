import SwiftUI
import SwiftData

// MARK: - History list of past sessions
struct SessionsListView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppEnvironment.self) private var appEnv

    @State private var showSubscription = false

    /// Live-updates when logs are bulk-deleted from Settings (no stale `SnoreSession` references).
    @Query(sort: \SnoreSession.startDate, order: .reverse)
    private var sessions: [SnoreSession]

    private var hasPremiumAccess: Bool { appEnv.subscription.hasPremiumAccess }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                content
            }
            .navigationTitle("Sleep History")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .sheet(isPresented: $showSubscription) {
                SubscriptionView(paywallSource: "history_locked_session")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                List {
                    let maxSnore = sessions.map(\.totalSnoreDuration).max() ?? 0
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        sessionRow(index: index, session: session, maxSnore: maxSnore)
                            .listRowBackground(Theme.surface)
                            .listRowSeparatorTint(Theme.surfaceSecondary)
                    }
                    .onDelete(perform: deleteSessions)

                    if !hasPremiumAccess, sessions.count > 1 {
                        Section {
                            EmptyView()
                        } footer: {
                            Text("Upgrade to Premium to view older sleep sessions.")
                                .foregroundStyle(Theme.labelSecondary)
                                .font(.caption)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .clearsFloatingTabBar()
            }
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 840 : .infinity)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func sessionRow(index: Int, session: SnoreSession, maxSnore: Double) -> some View {
        if hasPremiumAccess || index == 0 {
            NavigationLink(destination: SessionDetailView(session: session)) {
                SessionRowView(session: session, maxSnoreDuration: maxSnore)
            }
        } else {
            Button {
                AppAnalytics.logPaywallViewed(source: "history_locked_session")
                showSubscription = true
            } label: {
                LockedSessionRowView(session: session, maxSnoreDuration: maxSnore)
            }
            .buttonStyle(.plain)
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        let store = SessionStore(context: context)
        for index in offsets {
            store.deleteSession(sessions[index])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(Theme.labelTertiary)
            Text("No sessions yet")
                .font(.title3.bold())
                .foregroundStyle(Theme.labelSecondary)
            Text("Start recording to capture your first sleep session.")
                .font(.subheadline)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

// MARK: - Single session row
struct SessionRowView: View {

    let session: SnoreSession
    /// Maximum `totalSnoreDuration` across all visible sessions, used to normalise the bar.
    let maxSnoreDuration: Double

    private var dateString: String {
        session.startDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var recordingDurationString: String {
        session.displayDurationSummary
    }

    private var snoreDurationString: String { session.displayTotalSnoreTime }

    private var eventCountLabel: String {
        let count = session.displayEventCount
        return count == 1 ? "1 snore event" : "\(count) snore events"
    }

    private var barFill: CGFloat {
        guard maxSnoreDuration > 0 else { return 0 }
        return min(1, CGFloat(session.totalSnoreDuration / maxSnoreDuration))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateString)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.labelPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Label {
                    Text(recordingDurationString)
                        .font(Theme.monoDigit(size: 13))
                } icon: {
                    Image(systemName: "moon.zzz")
                        .font(.caption2)
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Theme.labelSecondary)
            }

            HStack(spacing: 20) {
                Label {
                    Text(eventCountLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } icon: {
                    Image(systemName: "waveform.badge.exclamationmark")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.snoring)
                .labelStyle(.titleAndIcon)

                Label {
                    Text(snoreDurationString)
                        .font(Theme.monoDigit(size: 12, weight: .bold))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "zzz")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.accent)
                .labelStyle(.titleAndIcon)
            }

            snoreDurationBar
                .accessibilityLabel("Snore duration relative to your longest night")
        }
        .padding(.vertical, 6)
    }

    private var snoreDurationBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.surfaceSecondary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.snoringGradient)
                    .frame(width: max(geo.size.width * barFill, barFill > 0 ? 8 : 0))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Locked session row (Free plan — older sessions)
private struct LockedSessionRowView: View {
    let session: SnoreSession
    let maxSnoreDuration: Double

    var body: some View {
        HStack(spacing: 12) {
            SessionRowView(session: session, maxSnoreDuration: maxSnoreDuration)
                .opacity(0.4)
                .allowsHitTesting(false)

            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(Theme.labelTertiary)
        }
        .accessibilityLabel("Locked sleep session. Upgrade to Premium to view.")
        .accessibilityAddTraits(.isButton)
    }
}
