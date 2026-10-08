import Foundation

public enum CountingMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case manual, assisted
    public var id: String { rawValue }
    public var title: String { self == .manual ? "手动计次" : "辅助计次（实验）" }
}

public enum MotionProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case benchPress, latPulldown, seatedRow, curl, lateralRaise, squat, generic
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .benchPress: return "卧推"
        case .latPulldown: return "高位下拉"
        case .seatedRow: return "坐姿划船"
        case .curl: return "弯举"
        case .lateralRaise: return "侧平举"
        case .squat: return "深蹲"
        case .generic: return "其他动作"
        }
    }
    /// All profiles are experimental wrist-motion estimates, never exercise classifiers.
    public var supportsAssisted: Bool { true }
}

public enum TrainingGoal: String, CaseIterable, Codable, Identifiable, Sendable {
    case balanced, strength, hypertrophy
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .balanced: return "均衡训练"
        case .strength: return "力量提升"
        case .hypertrophy: return "增肌训练"
        }
    }
}

public enum TrainingEquipment: String, CaseIterable, Codable, Identifiable, Sendable {
    case bodyweight, dumbbells, gym
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .bodyweight: return "自重训练"
        case .dumbbells: return "哑铃"
        case .gym: return "健身房器械"
        }
    }
}

internal func cleanName(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : String(trimmed.prefix(100))
}

internal func finiteClamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
}

internal func finiteMetric(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
}

internal func stableID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "FAD30000-0000-4000-8000-%012llX", Int64(value)))!
}

public struct ExercisePlan: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var targetSets: Int
    public var targetReps: Int
    public var restSeconds: Int
    public var weightKG: Double
    public var countingMode: CountingMode
    public var motionProfile: MotionProfile

    public init(id: UUID = UUID(), name: String = "新动作", targetSets: Int = 3,
                targetReps: Int = 10, restSeconds: Int = 90, weightKG: Double = 0,
                countingMode: CountingMode = .manual, motionProfile: MotionProfile = .generic) {
        self.id = id
        self.name = cleanName(name, fallback: "新动作")
        self.targetSets = min(max(targetSets, 1), 30)
        self.targetReps = min(max(targetReps, 1), 200)
        self.restSeconds = min(max(restSeconds, 0), 1800)
        self.weightKG = finiteClamp(weightKG, 0...1000)
        self.countingMode = countingMode
        self.motionProfile = motionProfile
    }

    public func normalized() -> ExercisePlan {
        ExercisePlan(id: id, name: name, targetSets: targetSets, targetReps: targetReps,
                     restSeconds: restSeconds, weightKG: weightKG,
                     countingMode: countingMode, motionProfile: motionProfile)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, targetSets, targetReps, restSeconds, weightKG, countingMode, motionProfile
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  name: try c.decode(String.self, forKey: .name),
                  targetSets: try c.decodeIfPresent(Int.self, forKey: .targetSets) ?? 3,
                  targetReps: try c.decodeIfPresent(Int.self, forKey: .targetReps) ?? 10,
                  restSeconds: try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 90,
                  weightKG: try c.decodeIfPresent(Double.self, forKey: .weightKG) ?? 0,
                  countingMode: try c.decodeIfPresent(CountingMode.self, forKey: .countingMode) ?? .manual,
                  motionProfile: try c.decodeIfPresent(MotionProfile.self, forKey: .motionProfile) ?? .generic)
    }

    /// Shared catalog. Narrow and wide grips intentionally share the same motion model.
    public static var templates: [ExercisePlan] {
        let values: [(String, MotionProfile, CountingMode)] = [
            ("杠铃卧推", .benchPress, .assisted),
            ("上斜哑铃卧推", .benchPress, .assisted),
            ("宽距高位下拉", .latPulldown, .assisted),
            ("窄距高位下拉", .latPulldown, .assisted),
            ("宽距坐姿划船", .seatedRow, .assisted),
            ("窄距坐姿划船", .seatedRow, .assisted),
            ("坐姿哑铃肩推", .generic, .assisted),
            ("哑铃侧平举", .lateralRaise, .assisted),
            ("哑铃弯举", .curl, .assisted),
            ("杠铃深蹲", .squat, .manual),
            ("高脚杯深蹲", .squat, .manual),
            ("自重深蹲", .squat, .manual)
        ]
        return values.enumerated().map { index, value in
            ExercisePlan(id: stableID(100 + index), name: value.0,
                         countingMode: value.2, motionProfile: value.1)
        }
    }
}

public struct TrainingPlan: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var exercises: [ExercisePlan]
    public var updatedAt: Date
    public var totalSets: Int { exercises.reduce(0) { $0 + min(max($1.targetSets, 1), 30) } }

    public init(id: UUID = UUID(), name: String = "新训练计划", exercises: [ExercisePlan] = [],
                updatedAt: Date = Date()) {
        self.id = id
        self.name = cleanName(name, fallback: "新训练计划")
        self.exercises = exercises.map { $0.normalized() }
        self.updatedAt = updatedAt
        // An exercise ID identifies one position in a plan, including repeated names.
        var seen: Set<UUID> = []
        for index in self.exercises.indices {
            if !seen.insert(self.exercises[index].id).inserted {
                self.exercises[index].id = UUID()
                seen.insert(self.exercises[index].id)
            }
        }
    }

    public func normalized() -> TrainingPlan {
        TrainingPlan(id: id, name: name, exercises: exercises, updatedAt: updatedAt)
    }

    private enum CodingKeys: String, CodingKey { case id, name, exercises, updatedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  name: try c.decode(String.self, forKey: .name),
                  exercises: try c.decode([ExercisePlan].self, forKey: .exercises),
                  updatedAt: try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0))
    }

    public static var starterPlans: [TrainingPlan] {
        let catalog = ExercisePlan.templates
        let epoch = Date(timeIntervalSince1970: 0)
        return [
            TrainingPlan(id: stableID(1), name: "胸肩 · 推的力量",
                         exercises: [catalog[0], catalog[1], catalog[6], catalog[7]], updatedAt: epoch),
            TrainingPlan(id: stableID(2), name: "背部 · 宽窄交替",
                         exercises: [catalog[2], catalog[3], catalog[4], catalog[5]], updatedAt: epoch),
            TrainingPlan(id: stableID(3), name: "下肢 · 深蹲基础",
                         exercises: [catalog[9], catalog[10], catalog[11]], updatedAt: epoch)
        ]
    }
}

public struct CompletedSet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var exerciseID: UUID
    public var exerciseName: String
    public var reps: Int
    public var weightKG: Double
    public var completedAt: Date
    public var assisted: Bool

    public init(id: UUID = UUID(), exerciseID: UUID, exerciseName: String,
                reps: Int, weightKG: Double = 0, completedAt: Date = Date(), assisted: Bool = false) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = cleanName(exerciseName, fallback: "动作")
        self.reps = min(max(reps, 0), 999)
        self.weightKG = finiteClamp(weightKG, 0...1000)
        self.completedAt = completedAt
        self.assisted = assisted
    }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseID, exerciseName, reps, weightKG, completedAt, assisted
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  exerciseID: try c.decode(UUID.self, forKey: .exerciseID),
                  exerciseName: try c.decode(String.self, forKey: .exerciseName),
                  reps: try c.decode(Int.self, forKey: .reps),
                  weightKG: try c.decodeIfPresent(Double.self, forKey: .weightKG) ?? 0,
                  completedAt: try c.decode(Date.self, forKey: .completedAt),
                  assisted: try c.decodeIfPresent(Bool.self, forKey: .assisted) ?? false)
    }
}

public struct WorkoutRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var planID: UUID
    public var planName: String
    public var startedAt: Date
    public var endedAt: Date
    public var sets: [CompletedSet]
    public var plannedSets: Int
    /// Capped sum per exercise. Missing on older exports, which use raw set count.
    public var completedPlannedSets: Int?
    public var activeEnergyKcal: Double?
    public var averageHeartRate: Double?

    public var completion: Double {
        guard plannedSets > 0 else { return 0 }
        return min(max(Double(completedPlannedSets ?? sets.count) / Double(plannedSets), 0), 1)
    }
    public var totalReps: Int { sets.reduce(0) { $0 + min(max($1.reps, 0), 999) } }

    public init(id: UUID = UUID(), planID: UUID, planName: String,
                startedAt: Date = Date(), endedAt: Date = Date(), sets: [CompletedSet] = [],
                plannedSets: Int = 0, completedPlannedSets: Int? = nil, activeEnergyKcal: Double? = nil, averageHeartRate: Double? = nil) {
        self.id = id
        self.planID = planID
        self.planName = cleanName(planName, fallback: "训练")
        self.startedAt = startedAt
        self.endedAt = max(startedAt, endedAt)
        var seen: Set<UUID> = []
        self.sets = sets.filter { seen.insert($0.id).inserted }
        self.plannedSets = max(plannedSets, 0)
        self.completedPlannedSets = completedPlannedSets.map { min(max($0, 0), max(plannedSets, 0)) }
        self.activeEnergyKcal = finiteMetric(activeEnergyKcal)
        self.averageHeartRate = finiteMetric(averageHeartRate)
    }

    private enum CodingKeys: String, CodingKey {
        case id, planID, planName, startedAt, endedAt, sets, plannedSets, completedPlannedSets, activeEnergyKcal, averageHeartRate
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  planID: try c.decode(UUID.self, forKey: .planID),
                  planName: try c.decode(String.self, forKey: .planName),
                  startedAt: try c.decode(Date.self, forKey: .startedAt),
                  endedAt: try c.decode(Date.self, forKey: .endedAt),
                  sets: try c.decode([CompletedSet].self, forKey: .sets),
                  plannedSets: try c.decode(Int.self, forKey: .plannedSets),
                  completedPlannedSets: try c.decodeIfPresent(Int.self, forKey: .completedPlannedSets),
                  activeEnergyKcal: try c.decodeIfPresent(Double.self, forKey: .activeEnergyKcal),
                  averageHeartRate: try c.decodeIfPresent(Double.self, forKey: .averageHeartRate))
    }
}
