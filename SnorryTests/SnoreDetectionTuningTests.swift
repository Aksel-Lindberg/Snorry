import Testing
@testable import Snorry

struct SnoreDetectionTuningTests {

    @Test func level5LockScreenUsesRelativeRiseAndSharedSafetyFloor() {
        let classifier = SnoreClassifier()
        let detector = SnoreEventDetector()

        SnoreDetectionTuning.apply(sensitivityLevel: 5, classifier: classifier, detector: detector)

        #expect(classifier.lockScreenRiseDB == 8)
        #expect(classifier.lockScreenSafetyFloorDB == -60)
    }

    @Test func level1LockScreenUsesHighestRise() {
        let classifier = SnoreClassifier()

        SnoreDetectionTuning.apply(
            sensitivityLevel: 1,
            classifier: classifier,
            detector: SnoreEventDetector()
        )

        #expect(classifier.lockScreenRiseDB == 14)
        #expect(classifier.lockScreenSafetyFloorDB == -60)
    }
}
