import Foundation
import XCTest
@testable import RepFlowCore

final class RepDetectorTests: XCTestCase {
    func testStationaryWristAndSmallDeterministicNoiseDoNotCount() {
        for profile in MotionProfile.allCases {
            var detector = RepDetector(profile: profile)
            for index in 0..<2_000 {
                let t = Double(index) / 50
                let noise = 0.012 * sin(37 * t) + 0.006 * sin(71 * t)
                XCTAssertFalse(detector.process(MotionSample(timestamp: t, x: noise, y: -noise, z: noise * 0.5)))
            }
            XCTAssertEqual(detector.count, 0, "\(profile)")
        }
    }

    func testOneCountPerFullSignedCycleAcrossProfilesAxesAndPolarity() {
        for profile in MotionProfile.allCases {
            for axis in 0..<3 {
                for direction in [-1.0, 1.0] {
                    var detector = RepDetector(profile: profile)
                    let emitted = feedCycles(into: &detector, cycles: 8, axis: axis, direction: direction)
                    XCTAssertEqual(emitted, 8, "\(profile), axis \(axis), direction \(direction)")
                    XCTAssertEqual(detector.count, emitted)
                }
            }
        }
    }

    func testCountsAtDifferentReasonableTempos() {
        for period in [1.2, 2.0, 3.5] {
            var detector = RepDetector()
            XCTAssertEqual(feedCycles(into: &detector, cycles: 6, period: period), 6)
        }
    }

    func testAnIncompleteSingleExcursionDoesNotCount() {
        var detector = RepDetector()
        for index in 0..<250 {
            let t = Double(index) / 50
            let value = t < 1 ? 0.2 : 0
            XCTAssertFalse(detector.process(MotionSample(timestamp: t, x: value, y: 0, z: 0)))
        }
        XCTAssertEqual(detector.count, 0)
    }

    func testVeryFastAndVerySlowCyclesAreRejected() {
        var fast = RepDetector()
        _ = feedCycles(into: &fast, cycles: 15, period: 0.3)
        XCTAssertEqual(fast.count, 0)

        var slow = RepDetector()
        _ = feedCycles(into: &slow, cycles: 3, period: 12)
        XCTAssertEqual(slow.count, 0)
    }

    func testShortOppositeShocksDoNotCount() {
        var detector = RepDetector()
        for index in 0..<500 {
            let t = Double(index) / 50
            let value: Double = index == 40 ? 0.5 : (index == 60 ? -0.5 : 0)
            XCTAssertFalse(detector.process(MotionSample(timestamp: t, x: value, y: 0, z: 0)))
        }
        XCTAssertEqual(detector.count, 0)
    }

    func testInvalidValuesAndNonIncreasingTimestampsAreIgnored() {
        var detector = RepDetector()
        var reference = RepDetector()
        for index in 0...810 {
            let t = Double(index) / 50
            let valid = MotionSample(timestamp: t, x: 0.22 * sin(2 * .pi * t / 2), y: 0, z: 0)
            XCTAssertEqual(detector.process(valid), reference.process(valid))
            XCTAssertFalse(detector.process(valid))
            XCTAssertFalse(detector.process(MotionSample(timestamp: t - 1, x: -100, y: 10, z: 0)))
            XCTAssertFalse(detector.process(MotionSample(timestamp: .nan, x: 0, y: 0, z: 0)))
            XCTAssertFalse(detector.process(MotionSample(timestamp: .infinity, x: 0, y: 0, z: 0)))
            XCTAssertFalse(detector.process(MotionSample(timestamp: t + 0.001, x: .nan, y: 0, z: 0)))
            XCTAssertFalse(detector.process(MotionSample(timestamp: t + 0.001, x: 0, y: .infinity, z: 0)))
        }
        XCTAssertEqual(detector.count, reference.count)
        XCTAssertEqual(detector.count, 8)
    }

    func testSampleGapAbandonsPartialCycleAndPreservesCount() {
        var detector = RepDetector()
        _ = feedCycles(into: &detector, cycles: 2)
        XCTAssertEqual(detector.count, 2)
        for index in 1...30 {
            _ = detector.process(MotionSample(timestamp: 4 + Double(index) / 50, x: 0.2, y: 0, z: 0))
        }
        // The opposite excursion after a long gap must not complete the old cycle.
        for index in 0...100 {
            let value: Double = index < 30 ? -0.2 : 0
            XCTAssertFalse(detector.process(MotionSample(timestamp: 10 + Double(index) / 50, x: value, y: 0, z: 0)))
        }
        XCTAssertEqual(detector.count, 2)
        _ = feedCycles(into: &detector, cycles: 3, start: 13)
        XCTAssertEqual(detector.count, 5)
    }

    func testResetClearsCounterAndSensorState() {
        var detector = RepDetector()
        _ = feedCycles(into: &detector, cycles: 3)
        XCTAssertEqual(detector.count, 3)
        detector.reset()
        XCTAssertEqual(detector.count, 0)
        _ = feedCycles(into: &detector, cycles: 2, axis: 2, direction: -1)
        XCTAssertEqual(detector.count, 2)
    }

    func testSensitivityRejectsSmallMovementAtLowSetting() {
        var low = RepDetector(sensitivity: 0.5)
        var high = RepDetector(sensitivity: 2)
        _ = feedCycles(into: &low, cycles: 4, amplitude: 0.09)
        _ = feedCycles(into: &high, cycles: 4, amplitude: 0.09)
        XCTAssertEqual(low.count, 0)
        XCTAssertEqual(high.count, 4)
    }

    func testInvalidSensitivityFallsBackToDefault() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            var detector = RepDetector(sensitivity: value)
            XCTAssertEqual(feedCycles(into: &detector, cycles: 3), 3)
        }
    }

    func testDominantAxisCanChangeAfterQuietPeriod() {
        var detector = RepDetector()
        _ = feedCycles(into: &detector, cycles: 3, axis: 0)
        for index in 1...150 {
            _ = detector.process(MotionSample(timestamp: 6 + Double(index) / 50, x: 0, y: 0, z: 0))
        }
        _ = feedCycles(into: &detector, cycles: 3, start: 9.02, axis: 2)
        XCTAssertEqual(detector.count, 6)
    }

    func testDominantAxisDoesNotStayStuckWhenGripChanges() {
        var detector = RepDetector()
        _ = feedCycles(into: &detector, cycles: 3, axis: 0)
        // Less than the quiet-reset interval: a different moving axis should
        // still recover rather than disabling counting for the rest of the set.
        _ = feedCycles(into: &detector, cycles: 3, start: 6.42, axis: 2)
        XCTAssertEqual(detector.count, 6)
    }

    func testIrregularButContinuousSamplingKeepsOneCountPerCycle() {
        var detector = RepDetector()
        let intervals = [0.012, 0.031, 0.019, 0.023, 0.015]
        var timestamp = 0.0
        var index = 0
        while timestamp <= 12.4 {
            let value = timestamp <= 12 ? 0.22 * sin(.pi * timestamp) : 0
            _ = detector.process(MotionSample(timestamp: timestamp, x: value, y: value * 0.4, z: -value * 0.3))
            timestamp += intervals[index % intervals.count]
            index += 1
        }
        XCTAssertEqual(detector.count, 6)
    }

    @discardableResult
    private func feedCycles(
        into detector: inout RepDetector,
        cycles: Int,
        period: Double = 2,
        start: Double = 0,
        axis: Int = 0,
        direction: Double = 1,
        amplitude: Double = 0.22
    ) -> Int {
        var emitted = 0
        let duration = Double(cycles) * period
        // Let the low-pass filter settle when the final physical cycle stops.
        let sampleCount = Int((duration + 0.4) * 50)
        for index in 0...sampleCount {
            let elapsed = Double(index) / 50
            var components = [Double](repeating: 0, count: 3)
            components[axis] = elapsed <= duration ? direction * amplitude * sin(2 * .pi * elapsed / period) : 0
            // Smaller cross-axis movement must not double count a signed cycle.
            components[(axis + 1) % 3] = 0.008 * sin(13 * elapsed)
            let sample = MotionSample(timestamp: start + elapsed, x: components[0], y: components[1], z: components[2])
            if detector.process(sample) { emitted += 1 }
        }
        return emitted
    }
}
