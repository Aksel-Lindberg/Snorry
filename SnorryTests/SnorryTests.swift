//
//  SnorryTests.swift
//  SnorryTests
//
//  Created by Aksel Lindberg on 02/05/2026.
//

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

}
