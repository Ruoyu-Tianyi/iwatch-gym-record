import Foundation
import XCTest
@testable import RepFlowCore

final class ModelsAndPlannerTests: XCTestCase {
    func testExerciseNormalizationBoundsAndInvalidWeights() throws {
        let exercise = ExercisePlan(name: "  \n ", targetSets: -5, targetReps: 0,
                                    restSeconds: -4, weightKG: .nan)
        XCTAssertEqual(exercise.name, "新动作")
        XCTAssertEqual(exercise.targetSets, 1)
        XCTAssertEqual(exercise.targetReps, 1)
        XCTAssertEqual(exercise.restSeconds, 0)
        XCTAssertEqual(exercise.weightKG, 0)
        var edited = ExercisePlan(name: "测试")
        edited.name = "  卧推 \n"
        edited.targetSets = Int.max
        edited.targetReps = Int.max
        edited.restSeconds = Int.max
        edited.weightKG = 2000
        let normalized = edited.normalized()
        XCTAssertEqual(normalized.name, "卧推")
        XCTAssertEqual(normalized.targetSets, 30)
        XCTAssertEqual(normalized.targetReps, 200)
        XCTAssertEqual(normalized.restSeconds, 1800)
        XCTAssertEqual(normalized.weightKG, 1000)
        // Persisted drafts are validated again when decoded, even after direct editor mutations.
        let decoded = try JSONDecoder().decode(ExercisePlan.self, from: JSONEncoder().encode(edited))
        XCTAssertEqual(decoded, normalized)
    }

    func testPlanRepairsDuplicateExerciseIdentityAndNormalizesTotals() {
        var exercise = ExercisePlan(name: "卧推")
        exercise.targetSets = -1
        let plan = TrainingPlan(name: "  训练  ", exercises: [exercise, exercise])
        XCTAssertEqual(plan.name, "训练")
        XCTAssertEqual(plan.totalSets, 2)
        XCTAssertNotEqual(plan.exercises[0].id, plan.exercises[1].id)
        XCTAssertEqual(plan.exercises[0].id, exercise.id)
    }

    func testStarterPlansStableAndContainPriorityMovements() throws {
        let plans = TrainingPlan.starterPlans
        XCTAssertEqual(plans, TrainingPlan.starterPlans)
        XCTAssertEqual(Set(plans.map(\.id)).count, plans.count)
        let exercises = plans.flatMap(\.exercises)
        for name in ["杠铃卧推", "宽距高位下拉", "窄距高位下拉", "宽距坐姿划船", "窄距坐姿划船", "坐姿哑铃肩推", "杠铃深蹲"] {
            XCTAssertTrue(exercises.contains { $0.name == name }, name)
        }
        XCTAssertTrue(exercises.filter { $0.motionProfile == .squat }.allSatisfy { $0.countingMode == .manual })
        XCTAssertEqual(exercises.first { $0.name == "宽距高位下拉" }?.motionProfile,
                       exercises.first { $0.name == "窄距高位下拉" }?.motionProfile)
        XCTAssertEqual(plans, try JSONDecoder().decode([TrainingPlan].self, from: JSONEncoder().encode(plans)))
    }

    func testGeneratorAllCombinationsDeterministicAndWithinRequestedEquipment() {
        for goal in TrainingGoal.allCases {
            for equipment in TrainingEquipment.allCases {
                for days in 1...6 {
                    let plans = PlanGenerator.generate(goal: goal, equipment: equipment, daysPerWeek: days)
                    XCTAssertEqual(plans.count, days)
                    XCTAssertEqual(plans, PlanGenerator.generate(goal: goal, equipment: equipment, daysPerWeek: days))
                    XCTAssertEqual(Set(plans.map(\.id)).count, days)
                    let exercises = plans.flatMap(\.exercises)
                    XCTAssertEqual(Set(exercises.map(\.id)).count, exercises.count)
                    XCTAssertTrue(exercises.allSatisfy { $0.weightKG == 0 })
                    XCTAssertTrue(exercises.allSatisfy { $0.targetSets > 0 && $0.targetReps > 0 && $0.restSeconds > 0 })
                    XCTAssertTrue(exercises.filter { $0.motionProfile == .squat }.allSatisfy { $0.countingMode == .manual })
                    if equipment != .gym {
                        XCTAssertFalse(exercises.contains { $0.name.contains("杠铃") || $0.name.contains("高位下拉") || $0.name.contains("坐姿划船") })
                    }
                    if equipment == .bodyweight {
                        XCTAssertTrue(exercises.allSatisfy { $0.countingMode == .manual && !$0.name.contains("哑铃") })
                    }
                }
            }
        }
    }

    func testGeneratorClampsDaysAndChangesGoals() {
        XCTAssertEqual(PlanGenerator.generate(goal: .balanced, equipment: .gym, daysPerWeek: -1).count, 1)
        XCTAssertEqual(PlanGenerator.generate(goal: .balanced, equipment: .gym, daysPerWeek: 99).count, 6)
        let strength = PlanGenerator.generate(goal: .strength, equipment: .gym, daysPerWeek: 3)[0].exercises[0]
        let hypertrophy = PlanGenerator.generate(goal: .hypertrophy, equipment: .gym, daysPerWeek: 3)[0].exercises[0]
        XCTAssertLessThan(strength.targetReps, hypertrophy.targetReps)
        XCTAssertGreaterThan(strength.restSeconds, hypertrophy.restSeconds)
        let sixDays = PlanGenerator.generate(goal: .balanced, equipment: .gym, daysPerWeek: 6).flatMap(\.exercises)
        for name in ["宽距高位下拉", "窄距高位下拉", "宽距坐姿划船", "窄距坐姿划船"] {
            XCTAssertTrue(sixDays.contains { $0.name == name })
        }
    }

    func testRecordDeduplicatesSetsSanitizesMetricsAndClampsCompletion() throws {
        let set = CompletedSet(exerciseID: UUID(), exerciseName: "卧推", reps: 10, weightKG: 40)
        let record = WorkoutRecord(planID: UUID(), planName: "胸", sets: [set, set], plannedSets: 1,
                                   activeEnergyKcal: .nan, averageHeartRate: -2)
        XCTAssertEqual(record.sets.count, 1)
        XCTAssertEqual(record.totalReps, 10)
        XCTAssertEqual(record.completion, 1)
        XCTAssertNil(record.activeEnergyKcal)
        XCTAssertNil(record.averageHeartRate)
        let overflow = WorkoutRecord(planID: UUID(), planName: "胸", sets: [set], plannedSets: 0)
        XCTAssertEqual(overflow.completion, 0)
        XCTAssertEqual(record, try JSONDecoder().decode(WorkoutRecord.self, from: JSONEncoder().encode(record)))
    }

    func testLegacyRecordsDecodeWithoutPerExerciseCompletion() throws {
        let set = CompletedSet(exerciseID: UUID(), exerciseName: "卧推", reps: 10)
        let record = WorkoutRecord(planID: UUID(), planName: "胸", sets: [set], plannedSets: 2)
        let decoded = try JSONDecoder().decode(WorkoutRecord.self, from: JSONEncoder().encode(record))
        XCTAssertNil(decoded.completedPlannedSets)
        XCTAssertEqual(decoded.completion, 0.5)
    }
}
