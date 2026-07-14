import Testing
@testable import Snorry

struct SoundAlertVolumeEscalationTests {

    @Test func burstVolumeTiers() {
        #expect(SoundAlertVolumeEscalation.volumeFraction(burstIndex: 1) == 0.125)
        #expect(SoundAlertVolumeEscalation.volumeFraction(burstIndex: 2) == 0.375)
        #expect(SoundAlertVolumeEscalation.volumeFraction(burstIndex: 3) == 0.625)
        #expect(SoundAlertVolumeEscalation.volumeFraction(burstIndex: 4) == 0.875)
        #expect(SoundAlertVolumeEscalation.volumeFraction(burstIndex: 5) == 1.00)
        #expect(SoundAlertVolumeEscalation.volumeFraction(burstIndex: 20) == 1.00)
    }

    @Test func elapsedVolumeTiers() {
        #expect(SoundAlertVolumeEscalation.volumeFraction(elapsed: 0) == 0.125)
        #expect(SoundAlertVolumeEscalation.volumeFraction(elapsed: 2.9) == 0.125)
        #expect(SoundAlertVolumeEscalation.volumeFraction(elapsed: 3) == 0.375)
        #expect(SoundAlertVolumeEscalation.volumeFraction(elapsed: 5.9) == 0.375)
        #expect(SoundAlertVolumeEscalation.volumeFraction(elapsed: 6) == 0.625)
        #expect(SoundAlertVolumeEscalation.volumeFraction(elapsed: 8.9) == 0.625)
        #expect(SoundAlertVolumeEscalation.volumeFraction(elapsed: 9) == 0.875)
        #expect(SoundAlertVolumeEscalation.volumeFraction(elapsed: 11.9) == 0.875)
        #expect(SoundAlertVolumeEscalation.volumeFraction(elapsed: 12) == 1.00)
        #expect(SoundAlertVolumeEscalation.volumeFraction(elapsed: 120) == 1.00)
    }

    @Test func effectiveVolumeClamping() {
        #expect(
            abs(
                SoundAlertVolumeEscalation.effectiveVolume(baseVolume: 1.0, fraction: 0.125) - 0.125
            ) < 0.001
        )
        #expect(
            abs(
                SoundAlertVolumeEscalation.effectiveVolume(baseVolume: 0.05, fraction: 1.0) - 0.10
            ) < 0.001
        )
        #expect(
            abs(
                SoundAlertVolumeEscalation.effectiveVolume(baseVolume: 1.5, fraction: 1.0) - 1.0
            ) < 0.001
        )
    }

    @Test func displayPercent() {
        #expect(SoundAlertVolumeEscalation.displayPercent(forFraction: 0.125) == 13)
        #expect(SoundAlertVolumeEscalation.displayPercent(forFraction: 1.0) == 100)
    }
}
