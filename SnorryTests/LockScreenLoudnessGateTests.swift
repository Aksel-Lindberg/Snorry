import Testing
@testable import Snorry

struct LockScreenLoudnessGateTests {

    @Test func quietNightSnorePassesRelativeGateNotFixedFloor() {
        let ambient: Float = -60
        let rise: Float = 8
        let snoreDB: Float = -50

        #expect(LockScreenLoudnessGate.isLockScreenLoud(db: snoreDB, ambient: ambient, riseDB: rise))
        #expect(snoreDB < -46)
    }

    @Test func twoMicsTenDBApartSameRiseBothPass() {
        let rise: Float = 10
        let weakAmbient: Float = -60
        let strongAmbient: Float = -50
        let weakSnore: Float = -50
        let strongSnore: Float = -40

        #expect(LockScreenLoudnessGate.isLockScreenLoud(db: weakSnore, ambient: weakAmbient, riseDB: rise))
        #expect(LockScreenLoudnessGate.isLockScreenLoud(db: strongSnore, ambient: strongAmbient, riseDB: rise))
    }

    @Test func steadyToneOnAmbientFailsEvenWhenAmbientIsLoud() {
        let ambient: Float = -40
        let rise: Float = 8

        #expect(!LockScreenLoudnessGate.isLockScreenLoud(db: ambient, ambient: ambient, riseDB: rise))
    }

    @Test func belowSafetyFloorFailsDespiteClearingRise() {
        let ambient: Float = -80
        let rise: Float = 8
        let db: Float = -70

        #expect(db >= ambient + rise)
        #expect(!LockScreenLoudnessGate.isLockScreenLoud(db: db, ambient: ambient, riseDB: rise))
    }

    @Test func nextAmbientSeedsThenTracksQuietAndPeaks() {
        let first = LockScreenLoudnessGate.nextAmbient(current: nil, sample: -55)
        #expect(first == -55)

        let quieter = LockScreenLoudnessGate.nextAmbient(current: first, sample: -58)
        #expect(quieter < first)

        let peak = LockScreenLoudnessGate.nextAmbient(current: quieter, sample: -40)
        #expect(peak > quieter)
        #expect(peak - quieter < 18)
    }
}
