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
            .toolbarColorScheme(.dark, for: .navigationBar)
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
    private let miniBarWidth: CGFloat = 116

    private var dateString: String {
        session.startDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var durationString: String {
        guard let dur = session.duration else { return "—" }
        let h = Int(dur) / 3600
        let m = Int(dur) % 3600 / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var snoreDurationString: String { session.displayTotalSnoreTime }

    private var barFill: CGFloat {
        guard maxSnoreDuration > 0 else { return 0 }
        return min(1, CGFloat(session.totalSnoreDuration / maxSnoreDuration))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateString)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.labelPrimary)
                Spacer()
                Text(durationString)
                    .font(Theme.monoDigit(size: 13))
                    .foregroundStyle(Theme.labelSecondary)
            }

            HStack(spacing: 27) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                    Text("\(session.displayEventCount)")
                        .fontWeight(.bold)
                        .frame(width: 24, alignment: .trailing)
                    Text("events")
                }
                .font(.caption)
                .foregroundStyle(Theme.snoring)

                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "zzz")
                        Text(snoreDurationString)
                            .font(Theme.monoDigit(size: 12))
                            .fontWeight(.bold)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                    snoreDurationBar
                        .padding(.leading, 10)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Snore duration \(snoreDurationString)")
            }
        }
        .padding(.vertical, 4)
    }

    private var snoreDurationBar: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.surfaceSecondary)
                .frame(width: miniBarWidth, height: 6)
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.snoringGradient)
                .frame(width: miniBarWidth * barFill, height: 6)
        }
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
