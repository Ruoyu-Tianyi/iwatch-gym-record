import Foundation
import Combine
import HealthKit

/// A HealthKit session is optional. A failed authorization or save must never lose local sets.
@MainActor
final class HealthWorkoutService: NSObject, ObservableObject {
    struct Metrics {
        var activeEnergyKcal: Double?
        var averageHeartRate: Double?
    }

    @Published private(set) var heartRate: Double?
    @Published private(set) var activeEnergyKcal: Double?
    @Published private(set) var isRunning = false
    @Published private(set) var hasFailed = false
    var onError: ((String) -> Void)?
    var onExternalPause: (() -> Void)?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var averageHeartRate: Double?
    private var finishing = false
    private var endWaiter: CheckedContinuation<Void, Error>?
    private var endTimeoutTask: Task<Void, Never>?

    var metrics: Metrics {
        Metrics(activeEnergyKcal: activeEnergyKcal, averageHeartRate: averageHeartRate)
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw ServiceError.unavailable }
        let heartRate = HKQuantityType(.heartRate)
        let energy = HKQuantityType(.activeEnergyBurned)
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), energy]
        let read: Set<HKObjectType> = [heartRate, energy]
        try await healthStore.requestAuthorization(toShare: share, read: read)
        // HealthKit does not reveal read permission. Missing heart rate is shown as unavailable.
        guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            throw ServiceError.notAuthorized
        }
    }

    func start(at date: Date) async throws {
        guard session == nil, !finishing else { throw ServiceError.alreadyRunning }
        hasFailed = false
        heartRate = nil
        activeEnergyKcal = nil
        averageHeartRate = nil
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let workoutBuilder = workoutSession.associatedWorkoutBuilder()
        workoutSession.delegate = self
        workoutBuilder.delegate = self
        workoutBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session = workoutSession
        builder = workoutBuilder
        workoutSession.startActivity(with: date)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                workoutBuilder.beginCollection(withStart: date) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume() }
                    else { continuation.resume(throwing: ServiceError.collectionFailed) }
                }
            }
            guard !hasFailed else { throw ServiceError.collectionFailed }
            isRunning = true
        } catch {
            workoutSession.end()
            workoutBuilder.discardWorkout()
            session = nil
            builder = nil
            isRunning = false
            throw error
        }
    }

    func pause() { if session?.state == .running { session?.pause() } }
    func resume() { if !hasFailed && session?.state == .paused { session?.resume() } }

    /// Called once, only after the user confirms finishing. The caller saves locally first.
    func finish(at date: Date) async throws -> Metrics {
        guard let builder, let session, !finishing else { return metrics }
        finishing = true
        defer {
            completeEndWait(ServiceError.collectionFailed)
            self.session = nil
            self.builder = nil
            isRunning = false
            finishing = false
        }
        do {
            // HealthKit finishes collection only after the session reports its ended state.
            try await endSession(session)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.endCollection(withEnd: date) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume() }
                    else { continuation.resume(throwing: ServiceError.collectionFailed) }
                }
            }
            let workout: HKWorkout = try await withCheckedThrowingContinuation { continuation in
                builder.finishWorkout { workout, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let workout { continuation.resume(returning: workout) }
                    else { continuation.resume(throwing: ServiceError.saveFailed) }
                }
            }
            updateStatistics(from: builder)
            if let quantity = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
                activeEnergyKcal = quantity.doubleValue(for: .kilocalorie())
            }
            return metrics
        } catch {
            builder.discardWorkout()
            throw error
        }
    }

    /// Explicitly discards only the current, unfinished Health workout.
    /// Already saved workouts in Apple Health are never deleted by app reset.
    func discard() {
        let oldSession = session
        let oldBuilder = builder
        session = nil
        builder = nil
        completeEndWait(ServiceError.collectionFailed)
        oldSession?.end()
        oldBuilder?.discardWorkout()
        isRunning = false
        finishing = false
    }

    private func endSession(_ session: HKWorkoutSession) async throws {
        if session.state == .ended { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            endWaiter = continuation
            endTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                self?.completeEndWait(ServiceError.sessionEndTimeout)
            }
            session.end()
        }
    }

    private func completeEndWait(_ error: Error? = nil) {
        let waiter = endWaiter
        endWaiter = nil
        endTimeoutTask?.cancel()
        endTimeoutTask = nil
        guard let waiter else { return }
        if let error { waiter.resume(throwing: error) }
        else { waiter.resume() }
    }

    private func updateStatistics(from builder: HKLiveWorkoutBuilder) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        if let stats = builder.statistics(for: HKQuantityType(.heartRate)) {
            heartRate = stats.mostRecentQuantity()?.doubleValue(for: bpm)
            averageHeartRate = stats.averageQuantity()?.doubleValue(for: bpm)
        }
        if let energy = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
            activeEnergyKcal = energy.doubleValue(for: .kilocalorie())
        }
    }

    enum ServiceError: LocalizedError {
        case unavailable, notAuthorized, alreadyRunning, collectionFailed, saveFailed, sessionEndTimeout
        var errorDescription: String? {
            switch self {
            case .unavailable: return "此设备暂不支持健康数据。"
            case .notAuthorized: return "未获得写入体能训练的权限。"
            case .alreadyRunning: return "已有健康训练正在进行。"
            case .collectionFailed: return "健康数据采集未能完成。"
            case .saveFailed: return "体能训练未能写入 Apple 健康。"
            case .sessionEndTimeout: return "等待健康训练结束超时，请稍后检查 Apple 健康。"
            }
        }
    }
}

extension HealthWorkoutService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                   from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            if toState == .ended { self.completeEndWait() }
            self.isRunning = !self.hasFailed && (toState == .running || toState == .paused)
            if !self.finishing && (toState == .ended || toState == .stopped) {
                self.hasFailed = true
                self.onError?("系统已结束健康数据采集。")
            } else if !self.finishing && toState == .paused {
                self.onExternalPause?()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.isRunning = false
            self.hasFailed = true
            self.completeEndWait(error)
            if !self.finishing { self.onError?("健康训练发生错误，组数仍可记录：\(error.localizedDescription)") }
        }
    }
}

extension HealthWorkoutService: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor [weak self] in
            guard let self, self.builder === workoutBuilder else { return }
            self.updateStatistics(from: workoutBuilder)
        }
    }
}
