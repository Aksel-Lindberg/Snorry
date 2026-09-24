#if DEBUG
import Foundation
import SwiftData

// MARK: - Demo nights + habits for App Store captures (launch with -SeedAppStoreDemo)

enum AppStoreDemoSeeder {

    private static let defaultsKey = "seedAppStoreDemo"
    private static let insightsMonthKey = "appStoreDemoInsightsMonth"
    private static let marketingChromeKey = "appStoreDemoMarketingChrome"
    static let recordingScreenKey = "appStoreDemoRecordingScreen"

    /// Persists after seeding — enables readable Snore Clock arcs and playback UI in captures.
    static var showsMarketingChrome: Bool {
        UserDefaults.standard.bool(forKey: marketingChromeKey)
    }

    static var shouldOpenRecordingScreen: Bool {
        UserDefaults.standard.bool(forKey: recordingScreenKey)
    }

    static func consumeRecordingScreenFlag() {
        UserDefaults.standard.set(false, forKey: recordingScreenKey)
    }

    static var shouldRun: Bool {
        CommandLine.arguments.contains("-SeedAppStoreDemo")
            || UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func seedIfRequested(context: ModelContext) throws {
        guard shouldRun else { return }

        try clearDemoData(context: context)
        try insertDemoData(context: context)
        try context.save()
        UserDefaults.standard.set(true, forKey: insightsMonthKey)
        UserDefaults.standard.set(true, forKey: marketingChromeKey)
        UserDefaults.standard.set(false, forKey: defaultsKey)
    }

    private static func clearDemoData(context: ModelContext) throws {
        // Detach events before batch delete — SwiftData rejects batch delete while sessions still reference them.
        let sessions = try context.fetch(FetchDescriptor<SnoreSession>())
        for session in sessions {
            session.events.removeAll()
        }
        try context.save()

        try context.delete(model: SnoreEvent.self, where: #Predicate { _ in true })
        try context.delete(model: SnoreSession.self, where: #Predicate { _ in true })
        try context.delete(model: HabitLog.self, where: #Predicate { _ in true })
        try context.delete(model: MyofascialExerciseCompletion.self, where: #Predicate { _ in true })
    }

    private static func insertDemoData(context: ModelContext) throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Past 24 nights — enough for Month insights and habit correlation.
        // Each offset gets a distinct habit mix so screenshots show varied selections.
        let habitMix: [Int: [HabitKind]] = [
            1:  [.caffeineLate, .drankAlcohol, .sleptOnBack],           // last night — Habits frame
            2:  [.myofascialExercise, .breathAndHum],
            3:  [.ateLate, .congested],
            4:  [.caffeineLate, .ateLate],
            5:  [.drankAlcohol, .sleptOnBack],
            6:  [.myofascialExercise, .nasalSpray],
            7:  [.congested, .sleptOnBack],
            8:  [.breathAndHum, .nasalClip],
            9:  [.drankAlcohol, .ateLate, .caffeineLate],
            10: [.myofascialExercise],
            11: [.caffeineLate],
            12: [.drankAlcohol, .congested],
            13: [.ateLate, .sleptOnBack],
            14: [.myofascialExercise, .breathAndHum, .nasalSpray],
            15: [.caffeineLate, .sleptOnBack],
            16: [.drankAlcohol],
            17: [.ateLate, .congested],
            18: [.myofascialExercise, .nasalClip],
            19: [.caffeineLate, .drankAlcohol],
            20: [.breathAndHum, .sleptOnBack],
            21: [.ateLate],
            22: [.drankAlcohol, .caffeineLate, .congested],
            23: [.myofascialExercise, .ateLate],
            24: [.nasalSpray, .breathAndHum],
        ]

        for offset in 1...24 {
            guard let night = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayStart = calendar.startOfDay(for: night)
            let habits = habitMix[offset] ?? []

            var snoreMinutes = 8.0
            if habits.contains(.drankAlcohol) { snoreMinutes += 14 }
            if habits.contains(.caffeineLate) { snoreMinutes += 10 }
            if habits.contains(.sleptOnBack) { snoreMinutes += 6 }
            if habits.contains(.congested) { snoreMinutes += 5 }
            if habits.contains(.myofascialExercise) || habits.contains(.breathAndHum) { snoreMinutes -= 4 }
            if habits.contains(.ateLate) { snoreMinutes += 4 }
            snoreMinutes = max(2, snoreMinutes)

            let sleepHours = offset == 1 ? 9.0 : 7.0
            let session = makeSession(
                dayStart: dayStart,
                sleepHours: sleepHours,
                snoreMinutes: offset == 1 ? 14 : snoreMinutes,
                isHero: offset == 1
            )
            context.insert(session)

            for habit in habits {
                log(habit, on: dayStart, context: context)
            }
        }
    }

    private static func makeSession(
        dayStart: Date,
        sleepHours: Double,
        snoreMinutes: Double,
        isHero: Bool
    ) -> SnoreSession {
        let start = dayStart.addingTimeInterval(23 * 3600) // 11 pm
        let end = start.addingTimeInterval(sleepHours * 3600)
        let session = SnoreSession(id: UUID(), startDate: start)
        session.endDate = end
        session.avgBRPM = 28
        session.peakDB = -38
        session.snapshotPushEnabled = true
        session.snapshotSoundEnabled = true
        session.snapshotAlarmStyleRaw = AlarmStyle.classic.rawValue
        session.snapshotSoundAlarmAfterSeconds = 5
        session.snapshotPushRepeatIntervalSeconds = 30

        if isHero {
            session.events = heroEvents(sessionStart: start)
        } else {
            session.events = nightEvents(
                sessionStart: start,
                sleepHours: sleepHours,
                targetSnoreMinutes: snoreMinutes
            )
        }

        session.eventCount = session.events.count
        session.totalSnoreDuration = session.events.reduce(into: 0.0) { total, event in
            total += event.duration ?? 0
        }

        return session
    }

    /// Clustered bouts like a real night — early, mid-sleep, and pre-wake episodes.
    private static func heroEvents(sessionStart: Date) -> [SnoreEvent] {
        boutEvents(
            sessionStart: sessionStart,
            bouts: [
                BoutSpec(startMinutes: 28, eventCount: 3, spacingSeconds: 55, durationSeconds: 25...42),
                BoutSpec(startMinutes: 210, eventCount: 6, spacingSeconds: 48, durationSeconds: 32...52),
                BoutSpec(startMinutes: 330, eventCount: 10, spacingSeconds: 42, durationSeconds: 38...68),
            ]
        )
    }

    /// Lighter bout pattern for non-hero nights, scaled to target snore minutes.
    private static func nightEvents(
        sessionStart: Date,
        sleepHours: Double,
        targetSnoreMinutes: Double
    ) -> [SnoreEvent] {
        let boutCount: Int
        switch targetSnoreMinutes {
        case ..<6:  boutCount = 1
        case ..<14: boutCount = 2
        default:    boutCount = 3
        }

        let sleepMinutes = sleepHours * 60
        let spacing = sleepMinutes / Double(boutCount + 1)
        var bouts: [BoutSpec] = []
        for index in 0..<boutCount {
            let startMinutes = spacing * Double(index + 1)
            let eventsInBout = max(2, Int(targetSnoreMinutes / Double(boutCount * 2)))
            bouts.append(
                BoutSpec(
                    startMinutes: startMinutes,
                    eventCount: eventsInBout,
                    spacingSeconds: 50,
                    durationSeconds: 22...48
                )
            )
        }
        return boutEvents(sessionStart: sessionStart, bouts: bouts)
    }

    private struct BoutSpec {
        let startMinutes: Double
        let eventCount: Int
        let spacingSeconds: Double
        let durationSeconds: ClosedRange<Int>
    }

    private static func boutEvents(sessionStart: Date, bouts: [BoutSpec]) -> [SnoreEvent] {
        var events: [SnoreEvent] = []
        var index = 0
        for bout in bouts {
            for eventIndex in 0..<bout.eventCount {
                let offset = bout.startMinutes * 60 + Double(eventIndex) * bout.spacingSeconds
                let eventStart = sessionStart.addingTimeInterval(offset)
                let span = bout.durationSeconds.upperBound - bout.durationSeconds.lowerBound
                let duration = Double(bout.durationSeconds.lowerBound + (index * 5) % max(1, span + 1))
                let event = SnoreEvent(id: UUID(), startDate: eventStart)
                event.endDate = eventStart.addingTimeInterval(duration)
                event.brpm = 24 + Double(index % 6)
                event.peakDB = -40 - Float(index % 4)
                event.avgDB = -54 - Float(index % 3)
                // Low-frequency rumble typical of snoring (85–400 Hz band).
                event.rumbleFrequencyHz = 92 + Double(index % 7) * 6
                event.spectralPeakHz = 108 + Double(index % 5) * 10
                event.soundKind = .snoring
                events.append(event)
                index += 1
            }
        }
        return events.sorted { $0.startDate < $1.startDate }
    }

    private static func log(_ habit: HabitKind, on dayStart: Date, context: ModelContext) {
        let entry = HabitLog(habitID: habit.rawValue, dayStart: dayStart)
        context.insert(entry)
    }
}
#endif
