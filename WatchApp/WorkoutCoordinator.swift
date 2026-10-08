import Foundation
import Combine
import SwiftUI
import WatchKit
import RepFlowCore

@MainActor
final class WorkoutCoordinator: ObservableObject {
    @Published private(set) var engine: WorkoutEngine?
    @Published private(set) var isStarting = false
    @Published private(set) var isFinishing = false
    @Published private(set) var usesHealth = false
    @Published private(set) var isAutoCounting = false
    @Published private(set) var now = Date()
    @Published var message: String?
    @Published var completedRecord: WorkoutRecord?
    @Published private(set) var pendingRecord: WorkoutRecord?
    let health = HealthWorkoutService()

    private let store: AppStore
    private let motion = MotionCountingService()
    private var timer: Timer?
    private var lastDraftSave = Date.distantPast
    private var motionExerciseID: UUID?

    init(store: AppStore) {
        self.store = store
        if var restored = store.loadDraft(), restored.phase != .finished {
            if restored.phase != .paused { restored.pause() }
            engine = restored
            message = "已恢复上次进度并暂停。继续后只保存本地训练记录；中断的健康数据不会补录。"
        }
        motion.onRep = { [weak self] in
            guard let self, self.engine?.phase == .active else { return }
            self.engine?.incrementRep()
            self.persistDraft(throttled: true)
            WKInterfaceDevice.current().play(.click)
        }
        motion.onError = { [weak self] text in
            self?.isAutoCounting = false
            self?.message = text
        }
        health.onError = { [weak self] text in
            guard let self else { return }
            self.pause()
            self.message = text + " 训练已暂停；继续时请保持 App 在前台。"
        }
        health.onExternalPause = { [weak self] in
            guard let self, self.engine?.phase != .paused, !self.isFinishing else { return }
            self.pause()
            self.message = "健康训练已由系统暂停，计次也已暂停。"
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var remainingRest: Int {
        guard let end = engine?.restEndsAt else { return 0 }
        return max(0, Int(ceil(end.timeIntervalSince(now))))
    }

    func start(plan: TrainingPlan, withHealth: Bool) async {
        guard engine == nil, !isStarting, !isFinishing else { return }
        guard !plan.exercises.isEmpty else {
            message = "请先为计划添加一个动作。"
            return
        }
        isStarting = true
        defer { isStarting = false }
        completedRecord = nil
        usesHealth = false
        if withHealth {
            do {
                try await health.requestAuthorization()
                try await health.start(at: Date())
                usesHealth = true
            } catch {
                message = "\(error.localizedDescription) 本次继续保存本地组数与次数；可稍后在系统设置中检查健康权限。"
            }
        }
        engine = WorkoutEngine(plan: plan, now: Date())
        persistDraft()
        WKInterfaceDevice.current().play(.start)
    }

    func startSet() {
        guard !isFinishing else { return }
        engine?.startSet(now: Date())
        reconcileMotion()
        persistDraft()
        WKInterfaceDevice.current().play(.start)
    }

    func adjustReps(by amount: Int) {
        guard engine?.phase == .active, let count = engine?.currentReps, !isFinishing else { return }
        engine?.setReps(max(0, count + amount))
        persistDraft()
    }

    func completeSet() {
        guard engine?.canCompleteSet == true, !isFinishing else { return }
        stopMotion()
        engine?.completeSet(now: Date())
        now = Date()
        persistDraft()
        WKInterfaceDevice.current().play(.success)
    }

    func skipRest() {
        guard !isFinishing else { return }
        engine?.skipRest(now: Date())
        persistDraft()
    }

    func nextExercise() {
        guard !isFinishing else { return }
        stopMotion()
        engine?.nextExercise(now: Date())
        persistDraft()
        WKInterfaceDevice.current().play(.directionUp)
    }

    func pause() {
        guard !isFinishing else { return }
        stopMotion()
        engine?.pause(now: Date())
        if usesHealth { health.pause() }
        persistDraft()
    }

    func resume() {
        guard !isFinishing else { return }
        engine?.resume(now: Date())
        if usesHealth { health.resume() }
        reconcileMotion()
        persistDraft()
    }

    func finish() async {
        guard engine != nil, !isFinishing, pendingRecord == nil else { return }
        isFinishing = true
        stopMotion()
        let endedAt = Date()
        let live = health.metrics
        guard var record = engine?.finish(now: endedAt, activeEnergyKcal: usesHealth ? live.activeEnergyKcal : nil,
                                          averageHeartRate: usesHealth ? live.averageHeartRate : nil) else {
            isFinishing = false
            return
        }
        // Persist first: authorization/save state cannot erase manually confirmed sets.
        store.errorMessage = nil
        store.addRecord(record)
        var savedLocally = store.history.contains { $0.id == record.id }
        let initialSaveError = store.errorMessage
        if savedLocally { store.saveDraft(nil) }
        if usesHealth {
            do {
                let finalMetrics = try await health.finish(at: endedAt)
                record.activeEnergyKcal = finalMetrics.activeEnergyKcal
                record.averageHeartRate = finalMetrics.averageHeartRate
                store.errorMessage = nil
                store.addRecord(record)
                savedLocally = savedLocally || store.history.contains { $0.id == record.id }
                if savedLocally { store.saveDraft(nil) }
            } catch {
                message = "Apple 健康保存未完成：\(error.localizedDescription) 已确认的组仍保留在本机训练中。"
            }
        }
        usesHealth = false
        isFinishing = false
        if savedLocally {
            finalize(record)
        } else {
            pendingRecord = record
            store.errorMessage = store.errorMessage ?? initialSaveError ?? "本地记录未能保存，请重试。"
            message = "尚未完成本地保存。训练仍保留，请重试保存后再开始新训练。"
        }
    }

    func retrySavingRecord() {
        guard let record = pendingRecord, !isFinishing else { return }
        store.errorMessage = nil
        store.addRecord(record)
        guard store.history.contains(where: { $0.id == record.id }) else { return }
        store.saveDraft(nil)
        pendingRecord = nil
        message = nil
        finalize(record)
    }

    private func finalize(_ record: WorkoutRecord) {
        completedRecord = record
        engine = nil
        pendingRecord = nil
        WKInterfaceDevice.current().play(.success)
    }

    /// Call only after the explicit reset confirmation and successful store clearing.
    func discardForReset() {
        guard !isStarting, !isFinishing else { return }
        stopMotion()
        health.discard()
        engine = nil
        pendingRecord = nil
        completedRecord = nil
        usesHealth = false
        message = nil
    }

    func tick() {
        now = Date()
        if engine?.phase == .resting, let end = engine?.restEndsAt, now >= end {
            engine?.skipRest(now: now)
            persistDraft()
            WKInterfaceDevice.current().play(.notification)
        }
        if engine?.phase == .active { persistDraft(throttled: true) }
    }

    func saveBeforeBackground() {
        // Without a running HK workout, watchOS may suspend the app when the wrist lowers.
        // Pause explicitly so a suspended estimator can never appear to be counting.
        if engine?.phase == .active && (!usesHealth || !health.isRunning) { pause() }
        persistDraft()
    }

    private func reconcileMotion() {
        guard engine?.phase == .active, let exercise = engine?.currentExercise,
              exercise.countingMode == .assisted else {
            stopMotion()
            return
        }
        guard motionExerciseID != exercise.id || !motion.isRunning else { return }
        motionExerciseID = exercise.id
        motion.start(profile: exercise.motionProfile)
        isAutoCounting = motion.isRunning
    }

    private func stopMotion() {
        motion.stop()
        isAutoCounting = false
        motionExerciseID = nil
    }

    private func persistDraft(throttled: Bool = false) {
        guard let engine, engine.phase != .finished else { return }
        let current = Date()
        if throttled && current.timeIntervalSince(lastDraftSave) < 1 { return }
        store.saveDraft(engine)
        lastDraftSave = current
    }
}
