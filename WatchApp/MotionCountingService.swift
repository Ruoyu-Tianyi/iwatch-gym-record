import Foundation
import CoreMotion
import RepFlowCore

/// Motion samples never leave this process. Only confirmed sets are persisted or synchronized.
@MainActor
final class MotionCountingService {
    private let manager = CMMotionManager()
    private var detector = RepDetector()
    private var generation = UUID()
    var onRep: (() -> Void)?
    var onError: ((String) -> Void)?
    private(set) var isRunning = false

    func start(profile: MotionProfile) {
        stop()
        guard manager.isDeviceMotionAvailable else {
            onError?("当前设备无法读取运动传感器，请使用 + / − 手动记录次数。")
            return
        }
        detector = RepDetector(profile: profile)
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        isRunning = true
        let token = generation
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            Task { @MainActor in
                guard let self, self.isRunning, self.generation == token else { return }
                if let error {
                    self.stop()
                    self.onError?("自动估计已停止，请手动计次：\(error.localizedDescription)")
                    return
                }
                guard let motion else { return }
                let acceleration = motion.userAcceleration
                let sample = MotionSample(timestamp: motion.timestamp, x: acceleration.x,
                                          y: acceleration.y, z: acceleration.z)
                if self.detector.process(sample) { self.onRep?() }
            }
        }
    }

    func stop() {
        generation = UUID()
        manager.stopDeviceMotionUpdates()
        isRunning = false
        detector.reset()
    }
}
