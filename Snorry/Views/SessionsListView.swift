import SwiftUI
import SwiftData

// MARK: - History list of past sessions
struct SessionsListView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var vm: SessionsListViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                if let vm {
                    content(vm: vm)
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .navigationTitle("Sleep History")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                if vm == nil { vm = SessionsListViewModel(context: context) }
                vm?.loadSessions()
            }
        }
    }

    @ViewBuilder
    private func content(vm: SessionsListViewModel) -> some View {
        Group {
            if vm.sessions.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(vm.sessions) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRowView(session: session)
                        }
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.surfaceSecondary)
                    }
                    .onDelete { offsets in
                        for i in offsets { vm.deleteSession(vm.sessions[i]) }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 840 : .infinity)
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(Theme.labelTertiary)
            Text("No sessions yet")
                .font(.title3.bold())
                .foregroundStyle(Theme.labelSecondary)
            Text("Start monitoring to record your first sleep session.")
                .font(.subheadline)
                .foregroundStyle(Theme.labelTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

// MARK: - Single session row
private struct SessionRowView: View {

    let session: SnoreSession
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

    private var snoringPercentString: String {
        let percent = Int((session.snoreFraction * 100).rounded())
        return "\(percent)%"
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
                    Text("\(session.eventCount)")
                        .fontWeight(.bold)
                        .frame(width: 24, alignment: .trailing)
                    Text("events")
                }
                .font(.caption)
                .foregroundStyle(Theme.snoring)

                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "zzz")
                        Text(snoringPercentString)
                            .font(Theme.monoDigit(size: 12))
                            .fontWeight(.bold)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                    snoreFractionBar
                        .padding(.leading, 10)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Snoring \(snoringPercentString)")
            }
        }
        .padding(.vertical, 4)
    }

    private var snoreFractionBar: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.surfaceSecondary)
                .frame(width: miniBarWidth, height: 6)
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.snoringGradient)
                .frame(width: miniBarWidth * CGFloat(session.snoreFraction), height: 6)
        }
    }
}
