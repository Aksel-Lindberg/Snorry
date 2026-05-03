import SwiftUI
import SwiftData

// MARK: - History list of past sessions
struct SessionsListView: View {

    @Environment(\.modelContext) private var context
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

    private var dateString: String {
        session.startDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var durationString: String {
        guard let dur = session.duration else { return "—" }
        let h = Int(dur) / 3600
        let m = Int(dur) % 3600 / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
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

            HStack(spacing: 20) {
                Label("\(session.eventCount) events", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(Theme.snoring)

                if session.avgBRPM > 0 {
                    Label(String(format: "%.0f BRPM", session.avgBRPM), systemImage: "lungs")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }

                snoreFractionBar
            }
        }
        .padding(.vertical, 4)
    }

    private var snoreFractionBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.surfaceSecondary)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.snoringGradient)
                    .frame(width: geo.size.width * CGFloat(session.snoreFraction), height: 6)
            }
        }
        .frame(height: 6)
    }
}
