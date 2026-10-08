import Foundation
import RepFlowCore

@main
struct StoreHarness {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RepFlowStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), "FAIL: \(message)")
            checks += 1
        }

        let dirA = root.appendingPathComponent("A")
        let dirB = root.appendingPathComponent("B")
        let a = AppStore(directory: dirA)
        let transportA = ConnectivityService.instances.last!
        let b = AppStore(directory: dirB)
        let transportB = ConnectivityService.instances.last!
        expect(a.plans.count == 3 && b.plans.count == 3, "first install seeds deterministic plans")
        var edited = a.plans[0]
        edited.name = "自定义宽距下拉"
        a.savePlan(edited)
        let oldPlanPacket = transportA.reliable[0]
        transportB.onReceive?(oldPlanPacket)
        expect(b.plans.first { $0.id == edited.id }?.name == edited.name, "paired plan edits merge")
        let reloaded = AppStore(directory: dirA)
        expect(reloaded.plans.first { $0.id == edited.id }?.name == edited.name, "edits survive process reload")
        b.deletePlan(id: edited.id)
        transportA.onReceive?(transportB.reliable[0])
        transportA.onReceive?(oldPlanPacket)
        transportB.onReceive?(oldPlanPacket)
        expect(!a.plans.contains { $0.id == edited.id } && !b.plans.contains { $0.id == edited.id }, "deletion tombstones defeat delayed snapshots")

        let time = Date().addingTimeInterval(-10)
        let completed = CompletedSet(exerciseID: UUID(), exerciseName: "卧推", reps: 10, completedAt: time)
        let record = WorkoutRecord(planID: UUID(), planName: "胸背", startedAt: time.addingTimeInterval(-120), endedAt: time,
                                   sets: [completed], plannedSets: 3)
        a.addRecord(record)
        let recordPacket = transportA.reliable[0]
        transportB.onReceive?(recordPacket)
        transportB.onReceive?(recordPacket)
        expect(b.history.filter { $0.id == record.id }.count == 1, "record replay is idempotent")
        var enriched = record
        enriched.activeEnergyKcal = 32
        a.addRecord(enriched)
        transportB.onReceive?(transportA.reliable[0])
        expect(b.history.first?.activeEnergyKcal == 32 && b.history.count == 1, "same-ID health enrichment replaces without duplication")
        b.deleteRecord(id: record.id)
        transportA.onReceive?(transportB.reliable[0])
        transportA.onReceive?(recordPacket)
        a.addRecord(enriched)
        expect(a.history.isEmpty, "deleted record cannot resurrect from replay or late metric completion")

        var engine = WorkoutEngine(plan: a.plans[0])
        engine.startSet()
        engine.setReps(7)
        a.saveDraft(engine)
        let restored = a.loadDraft()
        expect(restored?.phase == .paused && restored?.currentReps == 7, "interrupted active draft restores paused with reps")
        engine.completeSet()
        let finalRecord = engine.finish()
        a.addRecord(finalRecord)
        expect(a.loadDraft() == nil, "a committed workout never restores its stale draft")

        let exported = try a.exportURL()
        expect(FileManager.default.fileExists(atPath: exported.path), "export produces a file")
        let archived = dirA.appendingPathComponent("unreadable-test-store.json")
        try Data("old-sensitive-file".utf8).write(to: archived)
        let outbox = dirA.appendingPathComponent("SyncOutbox")
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        try Data("old-transfer".utf8).write(to: outbox.appendingPathComponent("pending.json"))
        a.clearAllData()
        let resetPacket = transportA.reliable[0]
        transportB.onReceive?(resetPacket)
        transportB.onReceive?(oldPlanPacket)
        transportB.onReceive?(recordPacket)
        expect(a.plans.isEmpty && a.history.isEmpty && b.plans.isEmpty && b.history.isEmpty, "clear barrier rejects all delayed pre-clear data")
        expect(!FileManager.default.fileExists(atPath: archived.path) && !FileManager.default.fileExists(atPath: outbox.path)
               && !FileManager.default.fileExists(atPath: exported.path), "clear removes archives, outbox and local export files")
        let emptyReload = AppStore(directory: dirA)
        expect(emptyReload.plans.isEmpty, "clear never reseeds sample plans on restart")
        try Data("broken-json".utf8).write(to: dirB.appendingPathComponent("store.json"))
        let resetRecovery = AppStore(directory: dirB)
        expect(resetRecovery.plans.isEmpty && resetRecovery.history.isEmpty, "post-reset backup cannot resurrect pre-reset data")
        let afterReset = TrainingPlan(name: "新的训练", exercises: [ExercisePlan(name: "卧推")])
        a.savePlan(afterReset)
        transportB.onReceive?(transportA.reliable[0])
        expect(b.plans.contains { $0.id == afterReset.id }, "new edits after clear remain syncable")

        let damagedDir = root.appendingPathComponent("Damaged")
        try FileManager.default.createDirectory(at: damagedDir, withIntermediateDirectories: true)
        let original = Data("intentionally-invalid".utf8)
        let damagedURL = damagedDir.appendingPathComponent("store.json")
        try original.write(to: damagedURL)
        let damaged = AppStore(directory: damagedDir)
        damaged.savePlan(afterReset)
        expect(damaged.plans.isEmpty && damaged.errorMessage != nil, "unrecoverable storage blocks writes and default seeding")
        let preserved = try Data(contentsOf: damagedURL)
        expect(preserved == original, "damaged primary bytes stay untouched")
        let rawExport = try damaged.exportURL()
        let exportedBytes = try Data(contentsOf: rawExport)
        expect(exportedBytes == original, "recovery export keeps the exact original bytes")
        damaged.clearAllData()
        damaged.savePlan(afterReset)
        expect(damaged.plans.count == 1, "explicit clear unblocks damaged storage")

        let blockedDir = root.appendingPathComponent("WriteFailure")
        let blocked = AppStore(directory: blockedDir)
        let plansBefore = blocked.plans
        let stateURL = blockedDir.appendingPathComponent("store.json")
        try FileManager.default.removeItem(at: stateURL)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)
        blocked.savePlan(afterReset)
        expect(blocked.plans == plansBefore && blocked.errorMessage != nil, "failed persistence does not report an in-memory save")

        print("PASS: \(checks) store persistence/sync checks (test transport; real WCSession requires paired Apple devices).")
    }
}
