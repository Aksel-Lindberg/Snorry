import Testing
@testable import Snorry

struct SnoreDetectionTuningTests {

    @Test func level5LockScreenFloorMatchesEnergyFallback() {
        let classifier = SnoreClassifier()
        let detector = SnoreEventDetector()

        SnoreDetectionTuning.apply(sensitivityLevel: 5, classifier: classifier, detector: detector)

        #expect(classifier.energyFallbackThresholdDB == -46)
        #expect(classifier.backgroundMinimumLevelDB == -46)
        #expect(max(classifier.energyFallbackThresholdDB, classifier.backgroundMinimumLevelDB) == -46)
    }

    @Test func level1LockScreenFloorMatchesEnergyFallback() {
        let classifier = SnoreClassifier()

        SnoreDetectionTuning.apply(
            sensitivityLevel: 1,
            classifier: classifier,
            detector: SnoreEventDetector()
        )

        #expect(classifier.energyFallbackThresholdDB == -28)
        #expect(classifier.backgroundMinimumLevelDB == -28)
    }
}
