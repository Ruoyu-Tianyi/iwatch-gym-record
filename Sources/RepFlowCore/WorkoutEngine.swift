import Foundation

public enum WorkoutPhase: String, Codable, CaseIterable, Identifiable, Sendable {
    case ready, active, resting, paused, finished
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ready: return "准备开始"
        case .active: return "正在训练"
        case .resting: return "组间休息"
        case .paused: return "已暂停"
        case .finished: return "训练结束"
        }
    }
}

/// Explicit transitions prevent a second tap from saving a set twice. An expired
/// rest timer permits `startSet`, but never starts a set or the sensors itself.
public struct WorkoutEngine: Identifiable, Codable, Equatable, Sendable {
    /// Stable from the first saved draft through completion and synchronization.
    public private(set) var id: UUID
    public private(set) var plan: TrainingPlan
    public private(set) var startedAt: Date
    public private(set) var phase: WorkoutPhase
    public private(set) var exerciseIndex: Int
    public private(set) var currentReps: Int
    public private(set) var sets: [CompletedSet]
    public private(set) var restEndsAt: Date?
    private var phaseBeforePause: WorkoutPhase?
    private var restRemainingAtPause: TimeInterval?
    private var finishedRecord: WorkoutRecord?

    public init(plan: TrainingPlan, now: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.plan = plan.normalized()
        self.startedAt = now
        self.phase = .ready
        self.exerciseIndex = 0
        self.currentReps = 0
        self.sets = []
        self.restEndsAt = nil
        self.phaseBeforePause = nil
        self.restRemainingAtPause = nil
        self.finishedRecord = nil
    }

    public var currentExercise: ExercisePlan? {
        guard plan.exercises.indices.contains(exerciseIndex) else { return nil }
        return plan.exercises[exerciseIndex]
    }
    public var completedSetsForCurrentExercise: Int {
        guard let exercise = currentExercise else { return 0 }
        return sets.filter { $0.exerciseID == exercise.id }.count
    }
    public var currentSetNumber: Int { completedSetsForCurrentExercise + 1 }
    public var completion: Double {
        guard plan.totalSets > 0 else { return 0 }
        // Extra sets of one exercise cannot stand in for skipped exercises.
        return min(max(Double(completedPlannedSets) / Double(plan.totalSets), 0), 1)
    }
    private var completedPlannedSets: Int {
        plan.exercises.reduce(0) { count, exercise in
            count + min(exercise.targetSets, sets.filter { $0.exerciseID == exercise.id }.count)
        }
    }
    public var canCompleteSet: Bool { phase == .active && currentExercise != nil && currentReps > 0 }
    public var isLastExercise: Bool { !plan.exercises.isEmpty && exerciseIndex == plan.exercises.count - 1 }

    public mutating func startSet(now: Date = Date()) {
        guard currentExercise != nil else { return }
        if phase == .resting, let end = restEndsAt, now >= end { phase = .ready }
        guard phase == .ready else { return }
        currentReps = 0
        restEndsAt = nil
        phase = .active
    }

    public mutating func setReps(_ value: Int) {
        guard phase == .active || (phase == .paused && phaseBeforePause == .active) else { return }
        currentReps = min(max(value, 0), 999)
    }

    public mutating func incrementRep() {
        guard phase == .active else { return }
        currentReps = min(currentReps + 1, 999)
    }

    public mutating func completeSet(now: Date = Date()) {
        guard canCompleteSet, let exercise = currentExercise else { return }
        sets.append(CompletedSet(exerciseID: exercise.id, exerciseName: exercise.name,
                                 reps: currentReps, weightKG: exercise.weightKG,
                                 completedAt: max(now, startedAt), assisted: exercise.countingMode == .assisted))
        currentReps = 0
        if exercise.restSeconds > 0 {
            restEndsAt = now.addingTimeInterval(TimeInterval(exercise.restSeconds))
            phase = .resting
        } else {
            restEndsAt = nil
            phase = .ready
        }
    }

    public mutating func skipRest(now: Date = Date()) {
        guard phase == .resting else { return }
        restEndsAt = nil
        phase = .ready
    }

    /// Advancing intentionally discards unconfirmed reps; callers should confirm
    /// the action when the current set contains reps. The final exercise is stable.
    public mutating func nextExercise(now: Date = Date()) {
        guard phase != .finished, exerciseIndex + 1 < plan.exercises.count else { return }
        exerciseIndex += 1
        currentReps = 0
        restEndsAt = nil
        restRemainingAtPause = nil
        if phase == .paused {
            phaseBeforePause = .ready
        } else {
            phase = .ready
            phaseBeforePause = nil
        }
    }

    public mutating func pause(now: Date = Date()) {
        guard phase != .paused && phase != .finished else { return }
        phaseBeforePause = phase
        if phase == .resting, let end = restEndsAt {
            restRemainingAtPause = max(0, end.timeIntervalSince(now))
        } else {
            restRemainingAtPause = nil
        }
        restEndsAt = nil
        phase = .paused
    }

    public mutating func resume(now: Date = Date()) {
        guard phase == .paused else { return }
        let previous = phaseBeforePause ?? .ready
        if previous == .resting {
            let remaining = restRemainingAtPause ?? 0
            phase = remaining > 0 ? .resting : .ready
            restEndsAt = remaining > 0 ? now.addingTimeInterval(remaining) : nil
        } else {
            phase = previous == .active && currentExercise != nil ? .active : .ready
        }
        phaseBeforePause = nil
        restRemainingAtPause = nil
    }

    /// Only confirmed sets are retained. Repeated calls return the same snapshot,
    /// including its UUID and metrics, so persistence and sync can deduplicate it.
    @discardableResult
    public mutating func finish(now: Date = Date(), activeEnergyKcal: Double? = nil,
                                averageHeartRate: Double? = nil) -> WorkoutRecord {
        if let finishedRecord { return finishedRecord }
        let record = WorkoutRecord(id: id, planID: plan.id, planName: plan.name,
                                   startedAt: startedAt, endedAt: max(now, startedAt), sets: sets,
                                   plannedSets: plan.totalSets, completedPlannedSets: completedPlannedSets,
                                   activeEnergyKcal: activeEnergyKcal,
                                   averageHeartRate: averageHeartRate)
        phase = .finished
        currentReps = 0
        restEndsAt = nil
        phaseBeforePause = nil
        restRemainingAtPause = nil
        finishedRecord = record
        return record
    }
    private enum CodingKeys: String, CodingKey {
        case id, plan, startedAt, phase, exerciseIndex, currentReps, sets, restEndsAt
        case phaseBeforePause, restRemainingAtPause, finishedRecord
    }

    /// Reject structurally inconsistent drafts rather than restoring an invisible
    /// exercise or allowing a corrupt counter to overflow. AppStore preserves the
    /// original draft and reports a recoverable error when this throws.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decode(TrainingPlan.self, forKey: .plan)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        phase = try c.decode(WorkoutPhase.self, forKey: .phase)
        exerciseIndex = try c.decode(Int.self, forKey: .exerciseIndex)
        currentReps = try c.decode(Int.self, forKey: .currentReps)
        sets = try c.decode([CompletedSet].self, forKey: .sets)
        restEndsAt = try c.decodeIfPresent(Date.self, forKey: .restEndsAt)
        phaseBeforePause = try c.decodeIfPresent(WorkoutPhase.self, forKey: .phaseBeforePause)
        restRemainingAtPause = try c.decodeIfPresent(TimeInterval.self, forKey: .restRemainingAtPause)
        finishedRecord = try c.decodeIfPresent(WorkoutRecord.self, forKey: .finishedRecord)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? finishedRecord?.id ?? UUID()

        func invalid(_ description: String) -> DecodingError {
            .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
        }
        guard startedAt.timeIntervalSinceReferenceDate.isFinite,
              restEndsAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
              (0...999).contains(currentReps),
              plan.exercises.isEmpty ? exerciseIndex == 0 : plan.exercises.indices.contains(exerciseIndex) else {
            throw invalid("Invalid draft date, exercise index, or repetition count")
        }
        let exerciseIDs = Set(plan.exercises.map(\.id))
        guard Set(sets.map(\.id)).count == sets.count,
              sets.allSatisfy({ exerciseIDs.contains($0.exerciseID) && $0.reps > 0 }) else {
            throw invalid("Draft contains duplicate sets or sets outside the plan")
        }
        if phase == .paused {
            guard let previous = phaseBeforePause, [.ready, .active, .resting].contains(previous),
                  restEndsAt == nil else { throw invalid("Invalid paused phase") }
            if previous == .resting {
                guard let remaining = restRemainingAtPause, remaining.isFinite, remaining >= 0 else {
                    throw invalid("Invalid paused rest timer")
                }
            } else if restRemainingAtPause != nil {
                throw invalid("Rest duration outside resting phase")
            }
        } else if phaseBeforePause != nil || restRemainingAtPause != nil {
            throw invalid("Unexpected pause state")
        }
        if phase == .resting {
            guard restEndsAt != nil else { throw invalid("Missing rest end date") }
        } else if restEndsAt != nil {
            throw invalid("Unexpected rest end date")
        }
        let holdsActiveSet = phase == .active || (phase == .paused && phaseBeforePause == .active)
        guard !holdsActiveSet || currentExercise != nil,
              holdsActiveSet || currentReps == 0 else { throw invalid("Invalid active set") }
        if phase == .finished {
            guard let record = finishedRecord, record.id == id, record.planID == plan.id,
                  record.sets == sets else { throw invalid("Invalid finished record") }
        } else if finishedRecord != nil {
            throw invalid("Unfinished draft contains a finished record")
        }
    }

}
