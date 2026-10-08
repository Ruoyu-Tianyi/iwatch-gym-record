import Combine
import Foundation
import RepFlowCore

/// The file and wire schemas deliberately share the same merge representation.
/// Missing items in an incoming snapshot never imply deletion.
private struct StoreSnapshot: Codable {
    var schemaVersion = 1
    var plans: [TrainingPlan] = []
    var history: [WorkoutRecord] = []
    var planTombstones: [String: Date] = [:]
    var recordTombstones: [String: Date] = [:]
    var recordUpdatedAt: [String: Date] = [:]
    var resetBefore: Date?
}

private struct DraftSnapshot: Codable {
    var schemaVersion = 1
    var engine: WorkoutEngine
}

private enum StoreFailure: LocalizedError {
    case unsupportedVersion
    case unavailable
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "数据格式版本较新，请先更新两台设备上的组迹。"
        case .unavailable: return "本地数据暂时不可写。请先导出原始文件，再在设置中明确清除数据以重置。"
        case .invalidData: return "训练数据包含无效数值，未覆盖本机数据。"
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var plans: [TrainingPlan] = []
    @Published var history: [WorkoutRecord] = []
    @Published var errorMessage: String?
    @Published var syncStatus = "数据保存在本机"

    private var planTombstones: [String: Date] = [:]
    private var recordTombstones: [String: Date] = [:]
    private var recordUpdatedAt: [String: Date] = [:]
    private var resetBefore: Date?
    private var storageBlocked = false
    private var draftBlocked = false
    private let directory: URL
    private let connectivity: ConnectivityService
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var stateURL: URL { directory.appendingPathComponent("store.json") }
    private var backupURL: URL { directory.appendingPathComponent("store.previous.json") }
    private var markerURL: URL { directory.appendingPathComponent("initialized") }
    private var draftURL: URL { directory.appendingPathComponent("draft.json") }

    /// A custom directory is useful for isolated persistence/merge verification.
    init(directory customDirectory: URL? = nil) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        directory = customDirectory ?? root.appendingPathComponent("RepFlow", isDirectory: true)
        connectivity = ConnectivityService(outboxURL: directory.appendingPathComponent("SyncOutbox", isDirectory: true))
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try loadStore()
        } catch {
            storageBlocked = true
            errorMessage = "本地数据读取失败，原文件已保留。请先导出备份，再在设置中清除重置。\n\(error.localizedDescription)"
        }

        connectivity.onReceive = { [weak self] data in self?.receive(data) }
        connectivity.onStatus = { [weak self] status in self?.syncStatus = status }
        connectivity.onActivated = { [weak self] in self?.syncNow() }
        connectivity.start()
    }

    func savePlan(_ plan: TrainingPlan) {
        guard canWrite() else { return }
        var saved = plan
        let previous = plans.first(where: { $0.id == saved.id })?.updatedAt
        saved.updatedAt = nextRevision(after: [previous, planTombstones[saved.id.uuidString], resetBefore])
        guard valid(saved) else {
            errorMessage = "请检查动作名称、组数、次数、重量和休息时间。"
            return
        }
        var state = snapshot()
        state.plans.removeAll { $0.id == saved.id }
        state.plans.append(saved)
        state.planTombstones.removeValue(forKey: saved.id.uuidString)
        guard commit(state) else { return }
        var delta = StoreSnapshot()
        delta.plans = [saved]
        delta.resetBefore = resetBefore
        publish(reliable: delta)
    }

    func deletePlan(id: UUID) {
        guard canWrite() else { return }
        var state = snapshot()
        let revision = nextRevision(after: [state.plans.first(where: { $0.id == id })?.updatedAt, state.planTombstones[id.uuidString], resetBefore])
        state.plans.removeAll { $0.id == id }
        state.planTombstones[id.uuidString] = revision
        guard commit(state) else { return }
        var delta = StoreSnapshot()
        delta.planTombstones[id.uuidString] = revision
        delta.resetBefore = resetBefore
        publish(reliable: delta)
    }

    func addRecord(_ record: WorkoutRecord) {
        guard canWrite(), valid(record) else {
            if !storageBlocked { errorMessage = StoreFailure.invalidData.localizedDescription }
            return
        }
        // A late HealthKit completion must never resurrect a deleted workout.
        guard recordTombstones[record.id.uuidString] == nil,
              resetBefore.map({ record.endedAt > $0 }) ?? true else { return }
        var state = snapshot()
        var saved = record
        if let existing = state.history.first(where: { $0.id == record.id }) {
            if saved.activeEnergyKcal == nil { saved.activeEnergyKcal = existing.activeEnergyKcal }
            if saved.averageHeartRate == nil { saved.averageHeartRate = existing.averageHeartRate }
            if saved == existing { return }
        }
        state.history.removeAll { $0.id == saved.id }
        state.history.append(saved)
        let revision = nextRevision(after: [state.recordUpdatedAt[saved.id.uuidString]])
        state.recordUpdatedAt[saved.id.uuidString] = revision
        guard commit(state) else { return }
        var delta = StoreSnapshot()
        delta.history = [saved]
        delta.recordUpdatedAt[saved.id.uuidString] = revision
        delta.resetBefore = resetBefore
        publish(reliable: delta)
    }

    func deleteRecord(id: UUID) {
        guard canWrite() else { return }
        var state = snapshot()
        state.history.removeAll { $0.id == id }
        state.recordUpdatedAt.removeValue(forKey: id.uuidString)
        let revision = nextRevision(after: [state.recordTombstones[id.uuidString], resetBefore])
        state.recordTombstones[id.uuidString] = revision
        guard commit(state) else { return }
        var delta = StoreSnapshot()
        delta.recordTombstones[id.uuidString] = revision
        delta.resetBefore = resetBefore
        publish(reliable: delta)
    }

    /// The caller presents confirmation. HealthKit has its own deletion controls.
    func clearAllData() {
        let previousBlock = storageBlocked
        var didCommitReset = false
        defer {
            // A cleanup failure must not leave paired devices unaware of a reset
            // which was already committed on this device.
            if didCommitReset { publish(reliable: snapshot()) }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var state = StoreSnapshot()
            state.resetBefore = nextRevision(after: plans.map { Optional($0.updatedAt) } + [resetBefore])
            storageBlocked = false
            guard commit(state) else {
                storageBlocked = previousBlock
                return
            }
            didCommitReset = true
            try connectivity.cancelPendingTransfers()
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where file.lastPathComponent == "draft.json" || file.lastPathComponent.hasPrefix("unreadable-") {
                try FileManager.default.removeItem(at: file)
            }
            for file in try FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: nil)
                where file.lastPathComponent.hasPrefix("RepFlow-") && file.pathExtension == "json" {
                try FileManager.default.removeItem(at: file)
            }
            draftBlocked = false
            errorMessage = nil
        } catch {
            errorMessage = "清除未完全完成：\(error.localizedDescription)"
        }
    }

    func syncNow() {
        guard !storageBlocked else {
            syncStatus = "本地数据需要恢复，暂不接收或发送同步"
            return
        }
        publish(reliable: snapshot())
    }

    func saveDraft(_ engine: WorkoutEngine?) {
        guard canWrite() else { return }
        do {
            guard let engine else {
                if FileManager.default.fileExists(atPath: draftURL.path) {
                    try FileManager.default.removeItem(at: draftURL)
                }
                draftBlocked = false
                return
            }
            guard !draftBlocked else { throw StoreFailure.unavailable }
            try encoder.encode(DraftSnapshot(engine: engine)).write(to: draftURL, options: .atomic)
        } catch {
            errorMessage = "训练草稿保存失败：\(error.localizedDescription)"
        }
    }

    func loadDraft() -> WorkoutEngine? {
        guard FileManager.default.fileExists(atPath: draftURL.path) else { return nil }
        do {
            let saved = try decoder.decode(DraftSnapshot.self, from: Data(contentsOf: draftURL))
            guard saved.schemaVersion == 1 else { throw StoreFailure.unsupportedVersion }
            var engine = saved.engine
            if history.contains(where: { $0.id == engine.id }) {
                // A process interruption between committing the final record and
                // deleting its draft must never restore the completed session.
                try? FileManager.default.removeItem(at: draftURL)
                return nil
            }
            guard engine.phase != .finished else { return nil }
            if engine.phase != .paused { engine.pause() }
            // Loading is passive: the coordinator must explicitly resume sensors.
            return engine
        } catch {
            draftBlocked = true
            errorMessage = "训练草稿无法读取，原文件已保留。可在设置清除数据后重新开始。\n\(error.localizedDescription)"
            return nil
        }
    }

    func exportURL() throws -> URL {
        let filename = "RepFlow-\(UUID().uuidString).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        if storageBlocked && FileManager.default.fileExists(atPath: stateURL.path) {
            // Recovery export preserves the original bytes, including damaged JSON.
            try Data(contentsOf: stateURL).write(to: url, options: .atomic)
        } else {
            let exportEncoder = JSONEncoder()
            exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            exportEncoder.dateEncodingStrategy = .iso8601
            try exportEncoder.encode(snapshot()).write(to: url, options: .atomic)
        }
        return url
    }

    private func canWrite() -> Bool {
        guard !storageBlocked else {
            errorMessage = StoreFailure.unavailable.localizedDescription
            return false
        }
        return true
    }

    private func snapshot() -> StoreSnapshot {
        StoreSnapshot(plans: plans, history: history, planTombstones: planTombstones,
                      recordTombstones: recordTombstones, recordUpdatedAt: recordUpdatedAt, resetBefore: resetBefore)
    }

    private func apply(_ state: StoreSnapshot) {
        plans = state.plans.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }
        history = state.history.sorted {
            $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt > $1.startedAt
        }
        planTombstones = state.planTombstones
        recordTombstones = state.recordTombstones
        recordUpdatedAt = state.recordUpdatedAt
        resetBefore = state.resetBefore
    }

    /// Persist before publishing any UI mutation; a full disk must not appear saved.
    @discardableResult
    private func commit(_ state: StoreSnapshot) -> Bool {
        do {
            let data = try encoder.encode(state)
            if let reset = state.resetBefore, resetBefore.map({ reset > $0 }) ?? true {
                // Persist a reset-safe backup first. A later damaged primary must
                // not bring back data the user explicitly cleared on either device.
                try data.write(to: backupURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: stateURL.path) {
                try Data(contentsOf: stateURL).write(to: backupURL, options: .atomic)
            }
            try data.write(to: stateURL, options: .atomic)
            apply(state)
            if !FileManager.default.fileExists(atPath: markerURL.path) {
                try Data("RepFlow local schema 1".utf8).write(to: markerURL, options: .atomic)
            }
            return true
        } catch {
            errorMessage = "数据保存失败，请检查设备存储空间后重试。\n\(error.localizedDescription)"
            return false
        }
    }

    private func loadStore() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: stateURL.path) {
            do {
                apply(try decodeStore(Data(contentsOf: stateURL)))
                return
            } catch {
                if let failure = error as? StoreFailure, case .unsupportedVersion = failure { throw error }
                guard manager.fileExists(atPath: backupURL.path),
                      let backup = try? decodeStore(Data(contentsOf: backupURL)) else { throw error }
                try archiveUnreadableFile(stateURL)
                try encoder.encode(backup).write(to: stateURL, options: .atomic)
                apply(backup)
                errorMessage = "已从上一次保存恢复数据，最近一次修改可能丢失。无法读取的原文件已单独保留。"
                return
            }
        }
        if manager.fileExists(atPath: backupURL.path) {
            let backup = try decodeStore(Data(contentsOf: backupURL))
            try encoder.encode(backup).write(to: stateURL, options: .atomic)
            apply(backup)
            errorMessage = "主数据文件缺失，已从上一次保存恢复。请核对最近的训练。"
            return
        }
        guard !manager.fileExists(atPath: markerURL.path) else { throw StoreFailure.unavailable }
        var seeded = StoreSnapshot()
        seeded.plans = TrainingPlan.starterPlans.map { plan in
            var plan = plan
            // A second device's first install must never replace an edited plan.
            plan.updatedAt = Date(timeIntervalSince1970: 0)
            return plan
        }
        guard commit(seeded) else { throw StoreFailure.unavailable }
    }

    private func archiveUnreadableFile(_ url: URL) throws {
        let archived = directory.appendingPathComponent("unreadable-\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: url, to: archived)
    }

    private func decodeStore(_ data: Data) throws -> StoreSnapshot {
        let state = try decoder.decode(StoreSnapshot.self, from: data)
        guard state.schemaVersion == 1 else { throw StoreFailure.unsupportedVersion }
        guard state.plans.allSatisfy(valid), state.history.allSatisfy(valid),
              state.plans.count == Set(state.plans.map(\.id)).count,
              state.history.count == Set(state.history.map(\.id)).count else { throw StoreFailure.invalidData }
        return state
    }

    private func publish(reliable: StoreSnapshot) {
        do {
            var context = snapshot()
            var contextData = try encoder.encode(context)
            if contextData.count > ConnectivityService.contextLimit {
                context.history = []
                context.recordUpdatedAt = [:]
                contextData = try encoder.encode(context)
            }
            if contextData.count > ConnectivityService.contextLimit {
                // Large snapshots use a durable file. Context still propagates the
                // reset barrier promptly; partial snapshots are merge-safe.
                context = StoreSnapshot()
                context.resetBefore = resetBefore
                contextData = try encoder.encode(context)
            }
            connectivity.publish(context: contextData, reliable: [try encoder.encode(reliable)])
        } catch {
            syncStatus = "同步数据编码失败，本机数据仍然保留"
        }
    }

    private func receive(_ data: Data) {
        guard !storageBlocked else {
            syncStatus = "本地数据需要恢复，未覆盖原文件"
            return
        }
        do {
            let incoming = try decodeStore(data)
            var merged = snapshot()
            if let remoteReset = incoming.resetBefore,
               merged.resetBefore.map({ remoteReset > $0 }) ?? true {
                merged.resetBefore = remoteReset
            }
            for (id, date) in incoming.planTombstones where merged.planTombstones[id].map({ date > $0 }) ?? true {
                merged.planTombstones[id] = date
            }
            for (id, date) in incoming.recordTombstones where merged.recordTombstones[id].map({ date > $0 }) ?? true {
                merged.recordTombstones[id] = date
            }

            var plansByID = Dictionary(uniqueKeysWithValues: merged.plans.map { ($0.id, $0) })
            for plan in incoming.plans {
                if let previous = plansByID[plan.id] {
                    if plan.updatedAt > previous.updatedAt || (plan.updatedAt == previous.updatedAt && deterministicWinner(plan, over: previous)) {
                        plansByID[plan.id] = plan
                    }
                } else { plansByID[plan.id] = plan }
            }
            merged.plans = plansByID.values.filter { plan in
                let notDeleted = merged.planTombstones[plan.id.uuidString].map { plan.updatedAt > $0 } ?? true
                let notReset = merged.resetBefore.map { plan.updatedAt > $0 } ?? true
                return notDeleted && notReset
            }

            var recordsByID = Dictionary(uniqueKeysWithValues: merged.history.map { ($0.id, $0) })
            for record in incoming.history {
                let key = record.id.uuidString
                let incomingRevision = incoming.recordUpdatedAt[key] ?? record.endedAt
                if let previous = recordsByID[record.id] {
                    let localRevision = merged.recordUpdatedAt[key] ?? previous.endedAt
                    if incomingRevision > localRevision || (incomingRevision == localRevision && deterministicWinner(record, over: previous)) {
                        recordsByID[record.id] = record
                        merged.recordUpdatedAt[key] = incomingRevision
                    }
                } else {
                    recordsByID[record.id] = record
                    merged.recordUpdatedAt[key] = incomingRevision
                }
            }
            merged.history = recordsByID.values.filter { record in
                merged.recordTombstones[record.id.uuidString] == nil && (merged.resetBefore.map { record.endedAt > $0 } ?? true)
            }
            let liveRecordIDs = Set(merged.history.map { $0.id.uuidString })
            merged.recordUpdatedAt = merged.recordUpdatedAt.filter { liveRecordIDs.contains($0.key) }
            // Stable order avoids repeated disk writes for equivalent snapshots.
            merged.plans.sort { $0.id.uuidString < $1.id.uuidString }
            merged.history.sort { $0.id.uuidString < $1.id.uuidString }
            var current = snapshot()
            current.plans.sort { $0.id.uuidString < $1.id.uuidString }
            current.history.sort { $0.id.uuidString < $1.id.uuidString }
            if try encoder.encode(merged) != encoder.encode(current) {
                guard commit(merged) else { return }
            }
            syncStatus = "已接收配对设备数据"
        } catch {
            syncStatus = "收到的数据未合并，请更新两台设备后重试"
            errorMessage = "配对同步失败：\(error.localizedDescription)"
        }
    }

    private func deterministicWinner<T: Encodable>(_ incoming: T, over existing: T) -> Bool {
        guard let lhs = try? encoder.encode(incoming), let rhs = try? encoder.encode(existing) else { return false }
        return rhs.lexicographicallyPrecedes(lhs)
    }

    private func nextRevision(after previous: [Date?]) -> Date {
        let latest = previous.compactMap { $0 }.max() ?? .distantPast
        return max(Date(), latest.addingTimeInterval(0.001))
    }

    private func valid(_ plan: TrainingPlan) -> Bool {
        !plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        plan.updatedAt.timeIntervalSince1970.isFinite &&
        !plan.exercises.isEmpty && Set(plan.exercises.map(\.id)).count == plan.exercises.count &&
        plan.exercises.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.targetSets > 0 && $0.targetReps > 0 && $0.restSeconds >= 0 &&
            $0.weightKG.isFinite && $0.weightKG >= 0
        }
    }

    private func valid(_ record: WorkoutRecord) -> Bool {
        record.startedAt.timeIntervalSince1970.isFinite && record.endedAt.timeIntervalSince1970.isFinite &&
        record.endedAt >= record.startedAt && record.plannedSets >= 0 &&
        (record.activeEnergyKcal.map { $0.isFinite && $0 >= 0 } ?? true) &&
        (record.averageHeartRate.map { $0.isFinite && $0 > 0 } ?? true) &&
        Set(record.sets.map(\.id)).count == record.sets.count &&
        record.sets.allSatisfy { $0.reps >= 0 && $0.weightKG.isFinite && $0.weightKG >= 0 && $0.completedAt.timeIntervalSince1970.isFinite }
    }
}
