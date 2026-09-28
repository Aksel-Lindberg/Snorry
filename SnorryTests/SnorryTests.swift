//
//  SnorryTests.swift
//  SnorryTests
//
//  Created by Aksel Lindberg on 02/05/2026.
//

import Foundation
import Testing
@testable import Snorry

struct SnorryTests {

    @Test func eventDurationFillIsRelativeToLongestBout() {
        #expect(EventMetricScale.durationFill(duration: 47, maxDuration: 47) == 1)
        #expect(abs(EventMetricScale.durationFill(duration: 10, maxDuration: 47) - 10.0 / 47.0) < 0.0001)
        #expect(EventMetricScale.durationFill(duration: 0, maxDuration: 47) == 0)
        #expect(EventMetricScale.durationFill(duration: 20, maxDuration: 0) == 0)
    }

    @Test func eventDurationFillDoesNotUseATenMinuteCeiling() {
        // Typical snore bouts are tens of seconds; a 10-minute absolute scale hid them.
        let shortNightFill = EventMetricScale.durationFill(duration: 41, maxDuration: 47)
        #expect(shortNightFill > 0.8)
        #expect(shortNightFill <= 1)
    }

    @Test func loudnessWordsFollowIPhoneRecordingBands() {
        #expect(EventMetricScale.loudnessWord(dBFS: -160) == nil)
        #expect(EventMetricScale.loudnessWord(dBFS: -80) == .soft)
        #expect(EventMetricScale.loudnessWord(dBFS: -50) == .soft)
        #expect(EventMetricScale.loudnessWord(dBFS: -49.9) == .moderate)
        #expect(EventMetricScale.loudnessWord(dBFS: -40) == .moderate)
        #expect(EventMetricScale.loudnessWord(dBFS: -39.9) == .loud)
        #expect(EventMetricScale.loudnessWord(dBFS: -30) == .loud)
        #expect(EventMetricScale.loudnessWord(dBFS: -29.9) == .veryLoud)
    }

    @Test func nightLoudnessUsesPeakAndDurationWeightedAverage() {
        let samples = [
            EventMetricScale.LoudnessSample(peakDB: -48, avgDB: -55, duration: 10),
            EventMetricScale.LoudnessSample(peakDB: -28, avgDB: -35, duration: 30)
        ]
        let summary = EventMetricScale.nightLoudness(samples: samples)
        #expect(summary?.loudest == .veryLoud)
        // (-55×10 + -35×30) / 40 = -40 → Moderate.
        #expect(summary?.average == .moderate)
    }

    @Test func nightLoudnessHidesWhenEveryBoutLacksALevel() {
        let samples = [
            EventMetricScale.LoudnessSample(peakDB: -160, avgDB: -160, duration: 12)
        ]
        #expect(EventMetricScale.nightLoudness(samples: samples) == nil)
    }

    @Test func durationWeightedAverageFallsBackWhenDurationsAreZero() {
        let samples = [
            EventMetricScale.LoudnessSample(peakDB: -40, avgDB: -50, duration: 0),
            EventMetricScale.LoudnessSample(peakDB: -30, avgDB: -40, duration: 0)
        ]
        let average = EventMetricScale.durationWeightedAverageDB(samples: samples)
        #expect(average == -45)
    }

    @Test func rowLoudnessHidesPeakWhenInSameBandAsAverage() {
        let row = EventMetricScale.rowLoudness(avgDB: -55, peakDB: -52)
        #expect(row?.average == .soft)
        #expect(row?.louderPeak == nil)
    }

    @Test func rowLoudnessShowsPeakWhenLouderBandThanAverage() {
        let row = EventMetricScale.rowLoudness(avgDB: -55, peakDB: -35)
        #expect(row?.average == .soft)
        #expect(row?.louderPeak == .loud)
    }

    @Test func indexOfLoudestPeakPicksEarliestOnTie() {
        let samples = [
            EventMetricScale.LoudnessSample(peakDB: -35, avgDB: -50, duration: 10),
            EventMetricScale.LoudnessSample(peakDB: -35, avgDB: -45, duration: 20),
            EventMetricScale.LoudnessSample(peakDB: -40, avgDB: -40, duration: 15)
        ]
        #expect(EventMetricScale.indexOfLoudestPeak(in: samples) == 0)
    }

    @Test func indexOfLoudestPeakPicksStrictlyLoudest() {
        let samples = [
            EventMetricScale.LoudnessSample(peakDB: -40, avgDB: -50, duration: 10),
            EventMetricScale.LoudnessSample(peakDB: -28, avgDB: -45, duration: 20)
        ]
        #expect(EventMetricScale.indexOfLoudestPeak(in: samples) == 1)
    }

}
