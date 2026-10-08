import Foundation

/// Transparent, deterministic templates; this does not adapt to health data,
/// prescribe training load, or perform medical/AI recommendations.
public enum PlanGenerator {
    public static func generate(goal: TrainingGoal, equipment: TrainingEquipment,
                                daysPerWeek: Int) -> [TrainingPlan] {
        let days = min(max(daysPerWeek, 1), 6)
        let split: [SessionKind]
        switch days {
        case 1: split = [.fullBody]
        case 2: split = [.upper, .lower]
        case 3: split = [.push, .pull, .lower]
        case 4: split = [.upper, .lower, .upper, .lower]
        case 5: split = [.push, .pull, .lower, .upper, .lower]
        default: split = [.push, .pull, .lower, .push, .pull, .lower]
        }
        let sets = goal == .strength ? 4 : 3
        let reps = goal == .strength ? 6 : (goal == .hypertrophy ? 12 : 10)
        let rest = goal == .strength ? 150 : (goal == .hypertrophy ? 75 : 90)
        let goalIndex = TrainingGoal.allCases.firstIndex(of: goal) ?? 0
        let equipmentIndex = TrainingEquipment.allCases.firstIndex(of: equipment) ?? 0
        let base = 10000 + goalIndex * 100000 + equipmentIndex * 10000 + days * 1000
        return split.enumerated().map { index, kind in
            let exercises = selections(for: kind, equipment: equipment, alternate: index >= 3)
                .enumerated().map { exerciseIndex, choice in
                    ExercisePlan(id: stableID(base + index * 100 + exerciseIndex + 1),
                                 name: choice.name, targetSets: sets, targetReps: reps,
                                 restSeconds: rest, weightKG: 0, countingMode: choice.mode,
                                 motionProfile: choice.profile)
                }
            return TrainingPlan(id: stableID(base + index * 100),
                                name: "第 \(index + 1) 天 · \(kind.title)", exercises: exercises,
                                updatedAt: Date(timeIntervalSince1970: 0))
        }
    }

    private enum SessionKind {
        case fullBody, upper, push, pull, lower
        var title: String {
            switch self {
            case .fullBody: return "全身基础"
            case .upper: return "上肢训练"
            case .push: return "胸肩推举"
            case .pull: return "背部拉力"
            case .lower: return "下肢训练"
            }
        }
    }
    private struct Choice {
        var name: String
        var profile: MotionProfile
        var mode: CountingMode
        init(_ name: String, _ profile: MotionProfile = .generic, _ mode: CountingMode = .assisted) {
            self.name = name
            self.profile = profile
            self.mode = mode
        }
    }
    private static func selections(for kind: SessionKind, equipment: TrainingEquipment,
                                   alternate: Bool) -> [Choice] {
        let push: [Choice]
        let pull: [Choice]
        let lower: [Choice]
        switch equipment {
        case .gym:
            push = [Choice("杠铃卧推", .benchPress), Choice("上斜哑铃卧推", .benchPress),
                    Choice("坐姿哑铃肩推"), Choice("哑铃侧平举", .lateralRaise)]
            pull = [Choice(alternate ? "窄距高位下拉" : "宽距高位下拉", .latPulldown),
                    Choice(alternate ? "宽距坐姿划船" : "窄距坐姿划船", .seatedRow),
                    Choice("哑铃弯举", .curl)]
            lower = [Choice("杠铃深蹲", .squat, .manual), Choice("坐姿腿举", .generic, .manual),
                     Choice("罗马尼亚硬拉", .generic, .manual), Choice("站姿提踵", .generic, .manual)]
        case .dumbbells:
            push = [Choice("哑铃地板卧推", .benchPress), Choice("站姿哑铃肩推"),
                    Choice("哑铃侧平举", .lateralRaise)]
            pull = [Choice("双臂俯身哑铃划船", .seatedRow), Choice("俯身哑铃反向飞鸟", .lateralRaise),
                    Choice("哑铃弯举", .curl)]
            lower = [Choice("高脚杯深蹲", .squat, .manual), Choice("哑铃罗马尼亚硬拉", .generic, .manual),
                     Choice("哑铃分腿蹲（双侧合计）", .generic, .manual)]
        case .bodyweight:
            // Wrists often remain stationary in these movements, so manual is the safe default.
            push = [Choice("俯卧撑", .generic, .manual), Choice("跪姿俯卧撑", .generic, .manual),
                    Choice("徒手肩胛俯卧撑", .generic, .manual)]
            pull = [Choice("俯卧 W 抬臂", .generic, .manual), Choice("俯卧反向飞鸟", .generic, .manual),
                    Choice("俯卧 Y 抬臂", .generic, .manual)]
            lower = [Choice("自重深蹲", .squat, .manual), Choice("臀桥", .generic, .manual),
                     Choice("后撤箭步蹲（双侧合计）", .generic, .manual)]
        }
        switch kind {
        case .fullBody: return [push[0], pull[0], lower[0], push.last!, pull.last!]
        case .upper: return [push[0], pull[0], push[1], pull[1], push.last!]
        case .push: return push
        case .pull: return pull
        case .lower: return lower
        }
    }
}
