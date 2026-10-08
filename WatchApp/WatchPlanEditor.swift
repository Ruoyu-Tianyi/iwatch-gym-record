import SwiftUI
import RepFlowCore

struct WatchPlanEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var plan: TrainingPlan
    @State private var confirmDelete = false

    init(plan: TrainingPlan) { _plan = State(initialValue: plan) }

    var body: some View {
        Form {
            WatchNoticeView()
            Section("计划名称") { TextField("训练名称", text: $plan.name) }
            Section("动作顺序") {
                ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                    NavigationLink {
                        WatchExerciseEditorView(exercise: exercise, onSave: { edited in
                            if let position = plan.exercises.firstIndex(where: { $0.id == edited.id }) {
                                plan.exercises[position] = edited
                            }
                        }, onDelete: {
                            plan.exercises.removeAll { $0.id == exercise.id }
                        })
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(exercise.name)")
                            Text("\(exercise.targetSets) 组 × \(exercise.targetReps) 次").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if index > 0 {
                        Button("上移“\(exercise.name)”") {
                            plan.exercises.swapAt(index, index - 1)
                        }.font(.caption2)
                    }
                }
                NavigationLink {
                    WatchAddExerciseView { exercise in plan.exercises.append(exercise) }
                } label: { Label("添加动作", systemImage: "plus") }
            }
            Text("修改将在保存计划后生效。正在进行的训练使用开始时的计划。").font(.caption2).foregroundStyle(.secondary)
            Button("保存计划") {
                plan.name = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
                plan.updatedAt = Date()
                store.errorMessage = nil
                store.savePlan(plan)
                if store.errorMessage == nil { dismiss() }
            }.tint(.repLime).disabled(plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plan.exercises.isEmpty)
            if store.plans.contains(where: { $0.id == plan.id }) {
                Button("删除计划", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("编辑计划")
        .confirmationDialog("删除这个计划？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除计划", role: .destructive) {
                store.errorMessage = nil
                store.deletePlan(id: plan.id)
                if store.errorMessage == nil { dismiss() }
            }
        } message: { Text("已保存的训练记录仍会保留。此删除会同步至配对设备。") }
    }
}

struct WatchExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exercise: ExercisePlan
    @State private var confirmDelete = false
    let onSave: (ExercisePlan) -> Void
    let onDelete: () -> Void

    init(exercise: ExercisePlan, onSave: @escaping (ExercisePlan) -> Void, onDelete: @escaping () -> Void) {
        _exercise = State(initialValue: exercise)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        Form {
            Section("动作名称") { TextField("动作名称", text: $exercise.name) }
            WatchNumberAdjuster(title: "目标组数", value: "\(exercise.targetSets) 组", minus: {
                exercise.targetSets = max(1, exercise.targetSets - 1)
            }, plus: { exercise.targetSets = min(30, exercise.targetSets + 1) })
            WatchNumberAdjuster(title: "每组次数", value: "\(exercise.targetReps) 次", minus: {
                exercise.targetReps = max(1, exercise.targetReps - 1)
            }, plus: { exercise.targetReps = min(200, exercise.targetReps + 1) })
            WatchNumberAdjuster(title: "组间休息", value: "\(exercise.restSeconds) 秒", minus: {
                exercise.restSeconds = max(0, exercise.restSeconds - 15)
            }, plus: { exercise.restSeconds = min(900, exercise.restSeconds + 15) })
            WatchNumberAdjuster(title: "训练重量", value: "\(exercise.weightKG.formatted()) kg", minus: {
                exercise.weightKG = max(0, exercise.weightKG - 2.5)
            }, plus: { exercise.weightKG = min(500, exercise.weightKG + 2.5) })
            Text("重量 0 表示未设置。重量仅用于记录，不是建议负重。").font(.caption2).foregroundStyle(.secondary)
            Picker("计次方式", selection: $exercise.countingMode) {
                Text("手动").tag(CountingMode.manual)
                Text("辅助估计（实验）").tag(CountingMode.assisted)
            }
            Picker("动作轨迹", selection: $exercise.motionProfile) {
                ForEach(MotionProfile.allCases) { profile in Text(profile.title).tag(profile) }
            }
            if exercise.countingMode == .assisted {
                Text("腕部估计未经过实测验证。宽窄距可使用相同轨迹，但不同器械、姿势会影响准确度。深蹲手腕固定时建议手动。").font(.caption2).foregroundStyle(.orange)
            }
            Button("保存动作") {
                exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(exercise)
                dismiss()
            }.tint(.repLime).disabled(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("删除动作", role: .destructive) { confirmDelete = true }
        }
        .navigationTitle("编辑动作")
        .confirmationDialog("从计划中删除动作？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除动作", role: .destructive) { onDelete(); dismiss() }
        } message: { Text("返回后还需保存计划，才会同步到设备。") }
    }
}

private struct WatchNumberAdjuster: View {
    let title: String
    let value: String
    let minus: () -> Void
    let plus: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(Color.repLime).monospacedDigit()
            HStack(spacing: 12) {
                Button(action: minus) { Image(systemName: "minus").frame(maxWidth: .infinity) }
                    .accessibilityLabel("减少" + title)
                Button(action: plus) { Image(systemName: "plus").frame(maxWidth: .infinity) }
                    .accessibilityLabel("增加" + title)
            }.buttonStyle(.bordered)
        }.padding(.vertical, 4)
    }
}

struct WatchAddExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ExercisePlan) -> Void
    private let templates: [(String, MotionProfile, CountingMode)] = [
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
        ("自定义动作", .generic, .manual)
    ]
    var body: some View {
        List {
            Text("添加后可修改名称、组数和次数。").font(.caption2).foregroundStyle(.secondary)
            ForEach(templates.indices, id: \.self) { index in
                let template = templates[index]
                Button(template.0) {
                    onSelect(ExercisePlan(name: template.0, targetSets: 3, targetReps: 10,
                                          restSeconds: 90, weightKG: 0, countingMode: template.2,
                                          motionProfile: template.1))
                    dismiss()
                }
            }
        }.navigationTitle("添加动作")
    }
}

struct WatchGeneratorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var goal: TrainingGoal = .balanced
    @State private var equipment: TrainingEquipment = .gym
    @State private var days = 3
    @State private var addedCount = 0
    @State private var generated = false
    @State private var pendingPlans: [TrainingPlan]?

    private var preview: [TrainingPlan] {
        PlanGenerator.generate(goal: goal, equipment: equipment, daysPerWeek: days)
    }

    var body: some View {
        Form {
            WatchNoticeView()
            if generated {
                Label("已添加 \(addedCount) 个计划", systemImage: "checkmark.circle.fill").foregroundStyle(Color.repLime)
                Button("返回") { dismiss() }
            } else {
                Picker("训练目标", selection: $goal) {
                    ForEach(TrainingGoal.allCases) { Text($0.title).tag($0) }
                }.disabled(addedCount > 0)
                Picker("可用器械", selection: $equipment) {
                    ForEach(TrainingEquipment.allCases) { Text($0.title).tag($0) }
                }.disabled(addedCount > 0)
                Picker("每周天数", selection: $days) {
                    ForEach(1...6, id: \.self) { Text("\($0) 天").tag($0) }
                }.disabled(addedCount > 0)
                Section("计划预览") {
                    ForEach(preview) { plan in
                        VStack(alignment: .leading) {
                            Text(plan.name).font(.headline)
                            Text("\(plan.exercises.count) 个动作 · \(plan.totalSets) 组").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("根据固定规则生成计划，可逐项编辑。请按经验调整动作和负重，计划不读取健康数据，也不提供医学或个性化训练建议。")
                    .font(.caption2).foregroundStyle(.secondary)
                Button(addedCount > 0 ? "重试添加剩余计划" : "添加 \(days) 天计划") { addPlans() }.tint(.repLime)
                if addedCount > 0 { Text("已添加 \(addedCount) 个，重试只补齐剩余计划。").font(.caption2) }
            }
        }
        .navigationTitle("生成计划")
        .onChange(of: goal) { _, _ in pendingPlans = nil }
        .onChange(of: equipment) { _, _ in pendingPlans = nil }
        .onChange(of: days) { _, _ in pendingPlans = nil }
    }

    private func addPlans() {
        if pendingPlans == nil {
            // Freeze a batch once. Retrying a partially written batch preserves all IDs.
            pendingPlans = preview.map { template in
                var copy = template
                copy.id = UUID()
                copy.updatedAt = Date()
                for index in copy.exercises.indices { copy.exercises[index].id = UUID() }
                return copy
            }
        }
        guard let batch = pendingPlans else { return }
        store.errorMessage = nil
        for plan in batch {
            if !store.plans.contains(where: { $0.id == plan.id }) { store.savePlan(plan) }
            addedCount = batch.filter { candidate in store.plans.contains { $0.id == candidate.id } }.count
            if store.errorMessage != nil { return }
        }
        generated = addedCount == batch.count
    }
}
