import Foundation
import XCTest
@testable import RepFlowCore

final class WorkoutEngineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func plan(rest: Int = 60, targetSets: Int = 2) -> TrainingPlan {
        TrainingPlan(name: "胸背", exercises: [
            ExercisePlan(name: "卧推", targetSets: targetSets, restSeconds: rest,
                         weightKG: 40, countingMode: .assisted, motionProfile: .benchPress),
            ExercisePlan(name: "窄距坐姿划船", targetSets: targetSets, restSeconds: rest,
                         weightKG: 30, countingMode: .manual, motionProfile: .seatedRow)
        ], updatedAt: start)
    }

    func testExplicitStartAndManualCorrection() {
        var engine = WorkoutEngine(plan: plan(), now: start)
        engine.incrementRep()
        engine.setReps(8)
        engine.completeSet(now: start)
        XCTAssertEqual(engine.currentReps, 0)
        XCTAssertTrue(engine.sets.isEmpty)
        engine.startSet(now: start)
        engine.incrementRep()
        engine.setReps(8)
        XCTAssertTrue(engine.canCompleteSet)
        engine.setReps(-2)
        XCTAssertEqual(engine.currentReps, 0)
        XCTAssertFalse(engine.canCompleteSet)
        engine.setReps(10)
        engine.completeSet(now: start.addingTimeInterval(25))
        XCTAssertEqual(engine.sets.count, 1)
        XCTAssertEqual(engine.sets[0].reps, 10)
        XCTAssertEqual(engine.sets[0].weightKG, 40)
        XCTAssertTrue(engine.sets[0].assisted)
        XCTAssertEqual(engine.currentReps, 0)
        XCTAssertEqual(engine.currentSetNumber, 2)
        XCTAssertEqual(engine.phase, .resting)
    }

    func testCompletingAgainCannotDuplicateSet() {
        var engine = WorkoutEngine(plan: plan(), now: start)
        engine.startSet(now: start)
        engine.setReps(10)
        engine.completeSet(now: start)
        engine.completeSet(now: start)
        engine.setReps(12)
        engine.completeSet(now: start)
        XCTAssertEqual(engine.sets.count, 1)
        XCTAssertEqual(engine.currentReps, 0)
    }

    func testRestExpiryStillRequiresExplicitStart() {
        var engine = WorkoutEngine(plan: plan(), now: start)
        engine.startSet(now: start)
        engine.setReps(10)
        engine.completeSet(now: start)
        engine.startSet(now: start.addingTimeInterval(59))
        XCTAssertEqual(engine.phase, .resting)
        engine.incrementRep()
        XCTAssertEqual(engine.currentReps, 0)
        engine.startSet(now: start.addingTimeInterval(60))
        XCTAssertEqual(engine.phase, .active)
        XCTAssertEqual(engine.currentReps, 0)
    }

    func testSkipRestAndZeroRestLeaveReady() {
        var engine = WorkoutEngine(plan: plan(), now: start)
        engine.startSet(now: start)
        engine.setReps(1)
        engine.completeSet(now: start)
        engine.skipRest(now: start.addingTimeInterval(1))
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertNil(engine.restEndsAt)
        engine.incrementRep()
        XCTAssertEqual(engine.currentReps, 0)
        var noRest = WorkoutEngine(plan: plan(rest: 0), now: start)
        noRest.startSet(now: start)
        noRest.setReps(1)
        noRest.completeSet(now: start)
        XCTAssertEqual(noRest.phase, .ready)
        noRest.completeSet(now: start)
        XCTAssertEqual(noRest.sets.count, 1)
    }

    func testPauseResumeActivePreservesCorrectedRepsButBlocksSensorUpdates() {
        var engine = WorkoutEngine(plan: plan(), now: start)
        engine.startSet(now: start)
        engine.setReps(5)
        engine.pause(now: start.addingTimeInterval(2))
        engine.incrementRep()
        engine.completeSet(now: start)
        XCTAssertEqual(engine.currentReps, 5)
        XCTAssertFalse(engine.canCompleteSet)
        engine.setReps(4)
        engine.pause(now: start.addingTimeInterval(3))
        engine.resume(now: start.addingTimeInterval(10))
        XCTAssertEqual(engine.phase, .active)
        XCTAssertEqual(engine.currentReps, 4)
        engine.completeSet(now: start.addingTimeInterval(20))
        XCTAssertEqual(engine.sets.first?.reps, 4)
    }

    func testPauseRestFreezesRemainingTime() {
        var engine = WorkoutEngine(plan: plan(), now: start)
        engine.startSet(now: start)
        engine.setReps(10)
        engine.completeSet(now: start)
        engine.pause(now: start.addingTimeInterval(20))
        XCTAssertNil(engine.restEndsAt)
        engine.pause(now: start.addingTimeInterval(30))
        engine.resume(now: start.addingTimeInterval(100))
        XCTAssertEqual(engine.phase, .resting)
        XCTAssertEqual(engine.restEndsAt, start.addingTimeInterval(140))
        engine.startSet(now: start.addingTimeInterval(139))
        XCTAssertEqual(engine.phase, .resting)
        engine.startSet(now: start.addingTimeInterval(140))
        XCTAssertEqual(engine.phase, .active)
    }

    func testPausingExpiredRestResumesReady() {
        var engine = WorkoutEngine(plan: plan(), now: start)
        engine.startSet(now: start)
        engine.setReps(1)
        engine.completeSet(now: start)
        engine.pause(now: start.addingTimeInterval(80))
        engine.resume(now: start.addingTimeInterval(200))
        XCTAssertEqual(engine.phase, .ready)
    }

    func testNextExerciseExplicitAndCannotOverrun() {
        var engine = WorkoutEngine(plan: plan(rest: 0, targetSets: 1), now: start)
        engine.startSet(now: start)
        engine.setReps(10)
        engine.completeSet(now: start)
        XCTAssertEqual(engine.exerciseIndex, 0)
        engine.startSet(now: start)
        engine.setReps(7)
        engine.nextExercise(now: start)
        XCTAssertEqual(engine.exerciseIndex, 1)
        XCTAssertEqual(engine.currentReps, 0)
        XCTAssertEqual(engine.sets.count, 1)
        XCTAssertTrue(engine.isLastExercise)
        engine.nextExercise(now: start)
        XCTAssertEqual(engine.exerciseIndex, 1)
        XCTAssertEqual(engine.currentSetNumber, 1)
    }

    func testNextExerciseDuringPauseStaysPausedAndResumesReady() {
        var engine = WorkoutEngine(plan: plan(), now: start)
        engine.startSet(now: start)
        engine.setReps(7)
        engine.pause(now: start)
        engine.nextExercise(now: start)
        XCTAssertEqual(engine.phase, .paused)
        XCTAssertEqual(engine.currentReps, 0)
        engine.resume(now: start)
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertEqual(engine.exerciseIndex, 1)
    }

    func testFinishIdempotentAndDiscardsUnconfirmedReps() throws {
        var engine = WorkoutEngine(plan: plan(rest: 0), now: start)
        engine.startSet(now: start)
        engine.setReps(12)
        engine.completeSet(now: start.addingTimeInterval(30))
        engine.startSet(now: start.addingTimeInterval(31))
        engine.setReps(6)
        let record = engine.finish(now: start.addingTimeInterval(45), activeEnergyKcal: 12,
                                   averageHeartRate: 110)
        XCTAssertEqual(record.totalReps, 12)
        XCTAssertEqual(record.sets.count, 1)
        XCTAssertEqual(record.completion, 0.25)
        XCTAssertEqual(record.activeEnergyKcal, 12)
        XCTAssertEqual(record.averageHeartRate, 110)
        XCTAssertEqual(engine.phase, .finished)
        XCTAssertEqual(engine.currentReps, 0)
        engine.nextExercise(now: start)
        engine.startSet(now: start)
        engine.incrementRep()
        engine.pause(now: start)
        engine.resume(now: start)
        XCTAssertEqual(engine.exerciseIndex, 0)
        XCTAssertEqual(engine.finish(now: start.addingTimeInterval(100), activeEnergyKcal: 90), record)
        var restored = try JSONDecoder().decode(WorkoutEngine.self, from: JSONEncoder().encode(engine))
        XCTAssertEqual(restored.finish(now: start.addingTimeInterval(200)), record)
    }

    func testExtraSetsDoNotReplaceSkippedExerciseInCompletion() {
        var engine = WorkoutEngine(plan: plan(rest: 0, targetSets: 1), now: start)
        for _ in 0..<3 {
            engine.startSet(now: start)
            engine.setReps(10)
            engine.completeSet(now: start)
        }
        XCTAssertEqual(engine.completion, 0.5)
        let record = engine.finish(now: start)
        XCTAssertEqual(record.totalReps, 30)
        XCTAssertEqual(record.completion, 0.5)
        XCTAssertEqual(record.completedPlannedSets, 1)
    }

    func testEmptyPlanCanFinishButCannotStart() {
        var engine = WorkoutEngine(plan: TrainingPlan(name: "空计划"), now: start)
        engine.startSet(now: start)
        engine.incrementRep()
        engine.completeSet(now: start)
        engine.nextExercise(now: start)
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertNil(engine.currentExercise)
        XCTAssertFalse(engine.isLastExercise)
        XCTAssertEqual(engine.completion, 0)
        let record = engine.finish(now: start.addingTimeInterval(-10), activeEnergyKcal: -.infinity,
                                   averageHeartRate: -1)
        XCTAssertEqual(record.endedAt, start)
        XCTAssertEqual(record.plannedSets, 0)
        XCTAssertNil(record.activeEnergyKcal)
        XCTAssertNil(record.averageHeartRate)
        XCTAssertEqual(record.completion, 0)
    }

    func testPausedDraftRoundTripCanResume() throws {
        var engine = WorkoutEngine(plan: plan(), now: start)
        engine.startSet(now: start)
        engine.setReps(8)
        engine.pause(now: start)
        var restored = try JSONDecoder().decode(WorkoutEngine.self, from: JSONEncoder().encode(engine))
        XCTAssertEqual(restored, engine)
        restored.resume(now: start.addingTimeInterval(20))
        XCTAssertEqual(restored.phase, .active)
        XCTAssertEqual(restored.currentReps, 8)
    }
}

extension WorkoutEngineTests {
    func testFinishedRecordUsesIDPersistedBeforeFinish() throws {
        var engine = WorkoutEngine(plan: plan(rest: 0), now: start)
        engine.startSet(now: start)
        engine.setReps(8)
        engine.completeSet(now: start)
        let draftData = try JSONEncoder().encode(engine)
        let saved = engine.finish(now: start.addingTimeInterval(30))
        var restoredDraft = try JSONDecoder().decode(WorkoutEngine.self, from: draftData)
        XCTAssertEqual(restoredDraft.id, saved.id)
        let replayed = restoredDraft.finish(now: start.addingTimeInterval(40))
        XCTAssertEqual(replayed.id, saved.id, "A crash before deleting the draft must retain a deduplicable session ID")
        XCTAssertEqual(replayed.sets, saved.sets)
    }

    func testInvalidDraftIndexCounterAndPhaseAreRejected() throws {
        var engine = WorkoutEngine(plan: plan(), now: start)
        engine.startSet(now: start)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(engine)) as? [String: Any])
        for change: [String: Any] in [
            ["exerciseIndex": -1], ["exerciseIndex": 500],
            ["currentReps": Int.max], ["currentReps": -1],
            ["phase": "resting"], ["phase": "paused"], ["phase": "finished"]
        ] {
            let changed = original.merging(change) { _, replacement in replacement }
            let data = try JSONSerialization.data(withJSONObject: changed)
            XCTAssertThrowsError(try JSONDecoder().decode(WorkoutEngine.self, from: data))
        }
    }

    func testAllValidTransitionSnapshotsDecode() throws {
        var engine = WorkoutEngine(plan: plan(), now: start)
        func check(_ engine: WorkoutEngine) throws {
            XCTAssertEqual(engine, try JSONDecoder().decode(WorkoutEngine.self, from: JSONEncoder().encode(engine)))
        }
        try check(engine)
        engine.pause(now: start)
        try check(engine)
        engine.resume(now: start)
        engine.startSet(now: start)
        engine.setReps(5)
        try check(engine)
        engine.pause(now: start)
        try check(engine)
        engine.resume(now: start)
        engine.completeSet(now: start)
        try check(engine)
        engine.pause(now: start.addingTimeInterval(10))
        try check(engine)
        engine.resume(now: start.addingTimeInterval(20))
        try check(engine)
        engine.finish(now: start.addingTimeInterval(30))
        try check(engine)
    }
}
