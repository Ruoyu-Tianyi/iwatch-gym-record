import Foundation

/// Core Motion `userAcceleration`, in g, with the sensor's monotonic timestamp.
/// Do not feed gravity-inclusive accelerometer values or wall-clock dates here.
public struct MotionSample: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let x: Double
    public let y: Double
    public let z: Double

    public init(timestamp: TimeInterval, x: Double, y: Double, z: Double) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.z = z
    }
}

/// An experimental wrist-motion estimator, not a validated exercise classifier.
///
/// A low-pass filter suppresses short shocks. A signed, dominant-axis cycle must
/// contain sustained opposite excursions followed by a return toward center.
/// Using a signed axis avoids the two peaks per period caused by vector magnitude.
/// The axis stays locked during a candidate cycle. Quiet or sustained loss of
/// movement on that axis lets a later cycle choose another axis.
///
/// Acceleration cycles do not universally correspond to exercise repetitions:
/// grip, wrist rotation, tempo, machines, and a wrist fixed against a bar can cause
/// missed or extra counts. All profiles require real-device validation and manual
/// correction. Wide/narrow variants deliberately share the same heuristic profile.
/// Start with `reset()` at each set; process samples only during the active set.
public struct RepDetector: Sendable {
    public private(set) var count = 0

    private let parameters: Parameters
    private var previousTimestamp: TimeInterval?
    private var filtered = [Double](repeating: 0, count: 3)
    private var axis: Int?
    private var direction: Double = 1
    private var phase = Phase.firstExcursion
    private var cycleStartedAt: TimeInterval?
    private var excursionStartedAt: TimeInterval?
    private var quietStartedAt: TimeInterval?
    private var crossedCenter = false
    private var axisLossStartedAt: TimeInterval?
    private var lastCountAt: TimeInterval?

    private enum Phase: Sendable {
        case firstExcursion, oppositeExcursion, returnToCenter
    }

    private struct Parameters: Sendable {
        let threshold: Double
        let minimumCycle: TimeInterval
        let maximumCycle: TimeInterval
        let minimumExcursion: TimeInterval
        let filterTimeConstant: TimeInterval = 0.075
        let maximumSampleGap: TimeInterval = 0.35
        let quietReset: TimeInterval = 1.5

        var release: Double { threshold * 0.4 }
        var refractory: TimeInterval { minimumCycle * 0.7 }

        init(profile: MotionProfile, sensitivity: Double) {
            let baseThreshold: Double
            switch profile {
            case .benchPress:
                baseThreshold = 0.055
                minimumCycle = 0.75
                maximumCycle = 7
            case .latPulldown:
                baseThreshold = 0.065
                minimumCycle = 0.8
                maximumCycle = 7
            case .seatedRow:
                baseThreshold = 0.055
                minimumCycle = 0.75
                maximumCycle = 7
            case .curl:
                baseThreshold = 0.07
                minimumCycle = 0.65
                maximumCycle = 6
            case .lateralRaise:
                baseThreshold = 0.045
                minimumCycle = 0.85
                maximumCycle = 7
            case .squat:
                baseThreshold = 0.045
                minimumCycle = 1
                maximumCycle = 8
            case .generic:
                baseThreshold = 0.065
                minimumCycle = 0.75
                maximumCycle = 7
            }
            let boundedSensitivity = sensitivity.isFinite ? min(2, max(0.5, sensitivity)) : 1
            threshold = baseThreshold / boundedSensitivity
            minimumExcursion = 0.08
        }
    }

    /// Higher sensitivity lowers the excursion threshold. Values are clamped to 0.5...2.
    public init(profile: MotionProfile = .generic, sensitivity: Double = 1) {
        parameters = Parameters(profile: profile, sensitivity: sensitivity)
    }

    /// Returns true once per accepted complete motion cycle.
    /// Nonfinite, duplicate, and backwards timestamps are ignored. A sample gap
    /// abandons an incomplete cycle rather than joining movement across a pause.
    public mutating func process(_ sample: MotionSample) -> Bool {
        guard sample.timestamp.isFinite,
              sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else { return false }

        let values = [sample.x, sample.y, sample.z]
        guard let previous = previousTimestamp else {
            previousTimestamp = sample.timestamp
            // Begin from zero so one initial sensor spike cannot prime a cycle.
            return false
        }
        let interval = sample.timestamp - previous
        guard interval > 0 else { return false }
        previousTimestamp = sample.timestamp
        guard interval <= parameters.maximumSampleGap else {
            clearTracking()
            previousTimestamp = sample.timestamp
            return false
        }

        let alpha = 1 - exp(-interval / parameters.filterTimeConstant)
        for index in 0..<3 {
            filtered[index] += alpha * (values[index] - filtered[index])
        }
        guard filtered.allSatisfy({ $0.isFinite }) else {
            clearTracking()
            previousTimestamp = sample.timestamp
            return false
        }

        let largestAxis = (0..<3).max(by: { abs(filtered[$0]) < abs(filtered[$1]) }) ?? 0
        if abs(filtered[largestAxis]) < parameters.release {
            if quietStartedAt == nil { quietStartedAt = sample.timestamp }
            if sample.timestamp - (quietStartedAt ?? sample.timestamp) >= parameters.quietReset {
                clearCycle(unlockAxis: true)
            }
        } else {
            quietStartedAt = nil
        }

        if let started = cycleStartedAt,
           sample.timestamp - started > parameters.maximumCycle {
            clearCycle(unlockAxis: true)
            return false
        }

        if case .firstExcursion = phase,
           let selectedAxis = axis,
           largestAxis != selectedAxis,
           abs(filtered[selectedAxis]) < parameters.release,
           abs(filtered[largestAxis]) >= parameters.threshold {
            if axisLossStartedAt == nil { axisLossStartedAt = sample.timestamp }
            if sample.timestamp - (axisLossStartedAt ?? sample.timestamp) >= 0.5 {
                // Recover from a grip/orientation change between cycles without
                // rotating the coordinate frame during an unfinished repetition.
                clearCycle(unlockAxis: true)
            }
        } else {
            axisLossStartedAt = nil
        }

        if axis == nil {
            guard abs(filtered[largestAxis]) >= parameters.threshold else { return false }
            axis = largestAxis
            direction = filtered[largestAxis] >= 0 ? 1 : -1
        }
        guard let selectedAxis = axis else { return false }
        let value = filtered[selectedAxis] * direction

        switch phase {
        case .firstExcursion:
            if value >= parameters.threshold {
                if excursionStartedAt == nil {
                    excursionStartedAt = sample.timestamp
                    cycleStartedAt = sample.timestamp
                }
                if sample.timestamp - (excursionStartedAt ?? sample.timestamp) >= parameters.minimumExcursion {
                    phase = .oppositeExcursion
                    excursionStartedAt = nil
                }
            } else if value < parameters.release {
                excursionStartedAt = nil
                cycleStartedAt = nil
            }
        case .oppositeExcursion:
            if value <= -parameters.release { crossedCenter = true }
            if crossedCenter && value >= parameters.release {
                // A weak or too brief opposite lobe ends this candidate. Without
                // this reset, rapid vibrations could be joined across periods.
                clearCycle(unlockAxis: false)
                return false
            }
            if value <= -parameters.threshold {
                if excursionStartedAt == nil { excursionStartedAt = sample.timestamp }
                if sample.timestamp - (excursionStartedAt ?? sample.timestamp) >= parameters.minimumExcursion {
                    phase = .returnToCenter
                    excursionStartedAt = nil
                }
            } else if value > -parameters.release {
                excursionStartedAt = nil
            }
        case .returnToCenter:
            if value >= -parameters.release {
                let elapsed = sample.timestamp - (cycleStartedAt ?? sample.timestamp)
                let outsideRefractory = lastCountAt.map { sample.timestamp - $0 >= parameters.refractory } ?? true
                let accepted = elapsed >= parameters.minimumCycle && elapsed <= parameters.maximumCycle && outsideRefractory
                clearCycle(unlockAxis: false)
                if accepted {
                    count += 1
                    lastCountAt = sample.timestamp
                    return true
                }
            }
        }
        return false
    }

    /// Clears the count, filter history, selected axis, and any incomplete cycle.
    public mutating func reset() {
        count = 0
        clearTracking()
    }

    private mutating func clearCycle(unlockAxis: Bool) {
        phase = .firstExcursion
        cycleStartedAt = nil
        excursionStartedAt = nil
        crossedCenter = false
        axisLossStartedAt = nil
        if unlockAxis {
            axis = nil
            direction = 1
        }
    }

    private mutating func clearTracking() {
        previousTimestamp = nil
        filtered = [0, 0, 0]
        quietStartedAt = nil
        lastCountAt = nil
        clearCycle(unlockAxis: true)
    }
}
