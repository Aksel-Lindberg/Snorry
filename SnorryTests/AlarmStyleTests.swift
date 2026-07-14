import Testing
@testable import Snorry

struct AlarmStyleTests {

    @Test func songTracksUseContinuousLivePlayback() {
        let songs: [AlarmStyle] = [
            .quietFoundUs,
            .indigoWindow,
            .copperLightAtSix,
            .lateNightCurb,
            .rapidWake,
            .marimbaIntrumental
        ]
        for style in songs {
            #expect(style.usesContinuousLivePlayback)
        }
    }

    @Test func shortClipsUseBurstLivePlayback() {
        let shortClips: [AlarmStyle] = [
            .bell,
            .birds,
            .marimba,
            .piano,
            .tornado
        ]
        for style in shortClips {
            #expect(!style.usesContinuousLivePlayback)
        }
    }

    @Test func synthesizedTonesUseBurstLivePlayback() {
        for style in [AlarmStyle.gentle, .classic, .alert] {
            #expect(!style.usesContinuousLivePlayback)
        }
    }

    @Test func playbackModeSubtitles() {
        #expect(AlarmStyle.bell.subtitle == "Short clip · bursts")
        #expect(AlarmStyle.quietFoundUs.subtitle == "Song · loops continuously")
        #expect(AlarmStyle.gentle.subtitle == "440 Hz · soft slow pulse")
    }
}
