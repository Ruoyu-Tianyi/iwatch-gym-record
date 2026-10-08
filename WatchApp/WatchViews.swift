import SwiftUI
import RepFlowCore

struct WatchHomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var coordinator: WorkoutCoordinator
    @State private var showWorkout = false
    @State private var showNewPlan = false

    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 3) {
                    Text("组迹").font(.system(.largeTitle, design: .rounded).bold()).foregroundStyle(Color.repLime)
                    Text("专注下一次发力").font(.footnote).foregroundStyle(.secondary)
                }
                WatchNoticeView()
                if let engine = coordinator.engine {
                    Button {
                        showWorkout = true
                    } label: {
                        Label(engine.phase == .paused ? "恢复训练" : "返回训练", systemImage: "figure.strengthtraining.traditional")
                    }.tint(.repLime)
                }
                Section("训练计划") {
                    ForEach(store.plans) { plan in
                        NavigationLink {
                            WatchPlanDetailView(planID: plan.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.name).font(.headline)
                                Text("\(plan.exercises.count) 个动作 · \(plan.totalSets) 组")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if store.plans.isEmpty { Text("创建一个计划，开始记录。").foregroundStyle(.secondary) }
                    Button { showNewPlan = true } label: { Label("新建计划", systemImage: "plus") }
                    NavigationLink { WatchGeneratorView() } label: { Label("生成训练计划", systemImage: "sparkles") }
                }
                NavigationLink { WatchHistoryView() } label: { Label("训练记录", systemImage: "clock.arrow.circlepath") }
                NavigationLink { WatchAboutView() } label: { Label("使用与数据", systemImage: "info.circle") }
            }
            .navigationTitle("组迹")
            .sheet(isPresented: $showNewPlan) {
                NavigationStack { WatchPlanEditorView(plan: TrainingPlan(name: "我的训练", exercises: [])) }
            }
            .sheet(isPresented: $showWorkout) {
                NavigationStack { WatchWorkoutView() }
            }
            .onChange(of: coordinator.engine != nil, initial: true) { _, active in
                if active { showWorkout = true }
            }
        }
    }
}

struct WatchNoticeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var coordinator: WorkoutCoordinator

    var body: some View {
        if let text = store.errorMessage ?? coordinator.message {
            VStack(alignment: .leading, spacing: 8) {
                Label("请留意", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                Text(text).font(.footnote)
                Button("知道了") {
                    store.errorMessage = nil
                    coordinator.message = nil
                }.font(.footnote)
            }.padding(8).background(Color.repSurface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct WatchPlanDetailView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var coordinator: WorkoutCoordinator
    let planID: UUID
    @State private var showEditor = false
    private var plan: TrainingPlan? { store.plans.first { $0.id == planID } }

    var body: some View {
        Group {
            if let plan {
                List {
                    Text(plan.name).font(.title3.bold())
                    Text("\(plan.totalSets) 组 · \(plan.exercises.count) 个动作").foregroundStyle(.secondary)
                    Section("开始训练") {
                        Button {
                            Task { await coordinator.start(plan: plan, withHealth: true) }
                        } label: {
                            Label(coordinator.isStarting ? "正在准备…" : "使用健康数据开始", systemImage: "heart.fill")
                        }.disabled(startDisabled(plan))
                        Text("将请求心率、活动能量与体能训练权限。授权后在 Apple 健康保存力量训练。")
                            .font(.caption2).foregroundStyle(.secondary)
                        Button("仅记录组数与次数") {
                            Task { await coordinator.start(plan: plan, withHealth: false) }
                        }.disabled(startDisabled(plan))
                        Text("不使用健康数据时，离开前台会暂停当前组的计次。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(plan.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name).font(.headline)
                            Text("\(exercise.targetSets) 组 × \(exercise.targetReps) 次")
                                .font(.footnote).foregroundStyle(Color.repLime)
                            Text(exercise.countingMode == .assisted ? "腕部自动估计 · 需核对" : "手动计次")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if coordinator.engine != nil {
                        Text("请先结束正在进行的训练。").font(.footnote).foregroundStyle(.orange)
                    }
                    Button("编辑计划") { showEditor = true }
                }
                .sheet(isPresented: $showEditor) { NavigationStack { WatchPlanEditorView(plan: plan) } }
            } else {
                ContentUnavailableView("计划已删除", systemImage: "list.bullet")
            }
        }.navigationTitle("训练计划")
    }

    private func startDisabled(_ plan: TrainingPlan) -> Bool {
        plan.exercises.isEmpty || coordinator.isStarting || coordinator.engine != nil || coordinator.isFinishing
    }
}

struct WatchWorkoutView: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var confirmFinish = false
    @State private var confirmNext = false
    @State private var confirmPause = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WatchNoticeView()
                if coordinator.pendingRecord != nil {
                    Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle).foregroundStyle(.orange)
                    Text("本地保存尚未完成").font(.headline)
                    Text("训练仍保留在当前页面。请释放设备存储空间后重试。").font(.footnote)
                    Button("重试保存") { coordinator.retrySavingRecord() }.tint(.repLime)
                } else if let engine = coordinator.engine {
                    if coordinator.isFinishing {
                        ProgressView("正在保存训练…")
                        Text("已完成的组优先保存在本机。").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        sessionContent(engine)
                    }
                } else if let record = coordinator.completedRecord {
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(Color.repLime)
                    Text("训练已完成").font(.headline)
                    Text("\(record.sets.count) 组 · \(record.totalReps) 次").font(.title3.bold())
                    Text("计划完成度 \(Int(record.completion * 100))%").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("查看详情") { WatchRecordView(record: record) }
                    Button("完成") { dismiss() }.tint(.repLime)
                } else {
                    Text("当前没有进行中的训练")
                    Button("返回") { dismiss() }
                }
            }.padding(.horizontal, 6)
        }
        .navigationTitle(coordinator.engine?.phase == .paused ? "已暂停" : "训练")
        .interactiveDismissDisabled(coordinator.isFinishing)
        .confirmationDialog("结束本次训练？", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("保存并结束") { Task { await coordinator.finish() } }
            Button("继续训练", role: .cancel) {}
        } message: {
            Text("已确认的组会保存。当前组未确认的 \(coordinator.engine?.currentReps ?? 0) 次不会计入记录；需要保留请先完成本组。")
        }
        .confirmationDialog("切换到下个动作？", isPresented: $confirmNext, titleVisibility: .visible) {
            Button("切换动作", role: .destructive) { coordinator.nextExercise() }
            Button("返回本组", role: .cancel) {}
        } message: { Text("当前组尚未确认的次数将被舍弃，已完成的组会保留。") }
        .confirmationDialog("暂停训练？", isPresented: $confirmPause, titleVisibility: .visible) {
            Button("暂停") { coordinator.pause() }
            Button("继续训练", role: .cancel) {}
        } message: { Text("会保留当前次数，并暂停自动估计。") }
    }

    @ViewBuilder
    private func sessionContent(_ engine: WorkoutEngine) -> some View {
        if let exercise = engine.currentExercise {
            VStack(spacing: 6) {
                Text(exercise.name).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Text("第 \(engine.currentSetNumber) 组 / \(exercise.targetSets) · 目标 \(exercise.targetReps) 次")
                    .font(.caption2).foregroundStyle(.secondary)
                if engine.phase == .active {
                    HStack(spacing: 6) {
                        Button { coordinator.adjustReps(by: -1) } label: {
                            Image(systemName: "minus").font(.title3.bold()).frame(width: 38, height: 38)
                                .background(Color.repSurface, in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel("减少一次").disabled(engine.currentReps == 0)
                        repCount(engine)
                        Button { coordinator.adjustReps(by: 1) } label: {
                            Image(systemName: "plus").font(.title3.bold()).frame(width: 38, height: 38)
                                .background(Color.repSurface, in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel("增加一次")
                    }
                    Button("完成第 \(engine.currentSetNumber) 组") { coordinator.completeSet() }
                        .tint(.repLime).disabled(!engine.canCompleteSet)
                } else if engine.phase == .resting {
                    Text("休息").font(.caption).foregroundStyle(.secondary)
                    Text(restText).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                        .accessibilityLabel("休息剩余 \(coordinator.remainingRest) 秒")
                    Button("跳过休息") { coordinator.skipRest() }
                    Text("休息结束后，手动开始下一组").font(.caption2).foregroundStyle(.secondary)
                } else if engine.phase == .paused {
                    repCount(engine)
                    Button("继续训练") { coordinator.resume() }.tint(.repLime)
                    Label("计次已暂停", systemImage: "pause.fill").font(.caption)
                } else if engine.phase == .ready {
                    repCount(engine)
                    Button(engine.completedSetsForCurrentExercise >= exercise.targetSets ? "再加一组" : "开始第 \(engine.currentSetNumber) 组") {
                        coordinator.startSet()
                    }.tint(.repLime)
                }
            }
            if engine.completedSetsForCurrentExercise >= exercise.targetSets {
                Label("本动作目标已完成", systemImage: "checkmark.circle").font(.caption).foregroundStyle(Color.repLime)
            }
            if engine.phase == .active && exercise.countingMode == .assisted {
                Label(coordinator.isAutoCounting ? "自动估计中" : "自动估计不可用", systemImage: coordinator.isAutoCounting ? "waveform.path" : "hand.tap")
                    .font(.caption).foregroundStyle(coordinator.isAutoCounting ? Color.repLime : Color.orange)
                Text(coordinator.isAutoCounting ? "实验功能：可能漏计或多计，请用 + / − 核对。" : "请使用 + / − 手动记录本组次数。")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if engine.phase == .ready && exercise.countingMode == .assisted {
                Text("开始后才估计次数。抬手操作和调整器械可能误计，完成组前请核对。").font(.caption2).foregroundStyle(.secondary)
            } else if engine.phase == .active {
                Text("使用 + / − 记录本组次数").font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text("动作 \(engine.exerciseIndex + 1)/\(engine.plan.exercises.count)")
                Spacer()
                Text("已完成 \(engine.completedSetsForCurrentExercise)/\(exercise.targetSets) 组")
            }.font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: engine.completion).tint(.repLime)
            if exercise.weightKG > 0 { Text("训练重量 \(exercise.weightKG.formatted()) kg").font(.caption2).foregroundStyle(.secondary) }
            if coordinator.usesHealth { WatchHealthMetricsView(service: coordinator.health) }
            if engine.phase != .paused {
                Button { confirmPause = true } label: { Label("暂停", systemImage: "pause") }
                if !engine.isLastExercise {
                    Button("下个动作") {
                        if engine.phase == .active { confirmNext = true }
                        else { coordinator.nextExercise() }
                    }
                }
            }
            Button("结束训练", role: .destructive) { confirmFinish = true }.padding(.top, 4)
        }
    }

    private func repCount(_ engine: WorkoutEngine) -> some View {
        Text("\(engine.currentReps)")
            .font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
            .minimumScaleFactor(0.6).lineLimit(1).frame(maxWidth: .infinity)
            .contentTransition(.numericText()).foregroundStyle(engine.phase == .paused ? Color.secondary : Color.repLime)
            .accessibilityLabel("本组 \(engine.currentReps) 次")
    }

    private var restText: String {
        String(format: "%02d:%02d", coordinator.remainingRest / 60, coordinator.remainingRest % 60)
    }
}

struct WatchHealthMetricsView: View {
    @ObservedObject var service: HealthWorkoutService
    var body: some View {
        HStack(spacing: 10) {
            Label(service.heartRate.map { "\(Int($0.rounded()))" } ?? "—", systemImage: "heart.fill")
                .foregroundStyle(.pink).accessibilityLabel("心率 " + (service.heartRate.map { "\(Int($0.rounded())) 次每分钟" } ?? "暂无数据"))
            Text(service.activeEnergyKcal.map { "\(Int($0.rounded())) 千卡" } ?? "— 千卡")
                .foregroundStyle(.secondary)
        }.font(.caption2).monospacedDigit()
    }
}

struct WatchHistoryView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            if store.history.isEmpty {
                Text("还没有训练记录。完成一组并结束训练后，会显示在这里。").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(store.history.sorted { $0.startedAt > $1.startedAt }) { record in
                NavigationLink { WatchRecordView(record: record) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.planName).font(.headline)
                        Text(record.startedAt, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                        Text("\(record.sets.count) 组 · \(record.totalReps) 次").font(.caption).foregroundStyle(Color.repLime)
                    }
                }
            }
        }.navigationTitle("训练记录")
    }
}

struct WatchRecordView: View {
    let record: WorkoutRecord
    var body: some View {
        List {
            Text(record.planName).font(.headline)
            Text(record.startedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
            Text("\(record.sets.count) 组 · \(record.totalReps) 次").font(.title3.bold()).foregroundStyle(Color.repLime)
            Text("目标 \(record.plannedSets) 组 · 完成 \(Int(record.completion * 100))%")
            Text("时长 \(max(0, Int(record.endedAt.timeIntervalSince(record.startedAt) / 60))) 分钟")
            if let energy = record.activeEnergyKcal { Text("活动能量 \(Int(energy.rounded())) 千卡") }
            if let heartRate = record.averageHeartRate { Text("平均心率 \(Int(heartRate.rounded())) 次/分") }
            ForEach(Array(record.sets.enumerated()), id: \.element.id) { index, set in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(index + 1). \(set.exerciseName)").font(.headline)
                    Text("\(set.reps) 次" + (set.weightKG > 0 ? " · \(set.weightKG.formatted()) kg" : ""))
                        .font(.footnote).foregroundStyle(Color.repLime)
                    Text(set.assisted ? "辅助计次 · 已确认" : "手动计次").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("训练详情")
    }
}

struct WatchAboutView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var coordinator: WorkoutCoordinator
    @State private var confirmClear = false
    var body: some View {
        List {
            Text("腕部自动估计").font(.headline)
            Text("支持卧推、宽窄距下拉、宽窄距划船、肩部动作等轨迹。算法尚未经过实测验证，不保证识别每一次动作，也不会自动识别动作名称。")
                .font(.footnote)
            Text("深蹲默认手动：手腕固定在杠铃上可能难以捕捉动作。可编辑计划后尝试辅助计次。")
                .font(.footnote).foregroundStyle(.secondary)
            Text("每组需手动开始与完成；切换动作前确认本组。摇晃手腕、借力、变更佩戴位置都可能影响计数。")
                .font(.footnote)
            Text("数据与同步").font(.headline)
            Text("计划和记录保存在设备，通过配对的 iPhone 同步。原始运动数据不会保存或上传。同步无需账户。")
                .font(.footnote)
            Text(store.syncStatus).font(.caption2).foregroundStyle(.secondary)
            Button("重新同步") { store.syncNow() }
            Text("仅作为健身记录工具，不提供医疗建议。健康权限可在系统设置中管理；删除组迹中的记录不会删除 Apple 健康中的训练。")
                .font(.caption2).foregroundStyle(.secondary)
            WatchNoticeView()
            Button("清除所有组迹数据", role: .destructive) { confirmClear = true }
                .disabled(coordinator.isStarting || coordinator.isFinishing)
            if coordinator.engine != nil {
                Text("清除数据也会放弃当前尚未保存的训练。").font(.caption2).foregroundStyle(.orange)
            }
        }
        .navigationTitle("使用与数据")
        .confirmationDialog("清除所有组迹数据？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除全部并放弃当前训练", role: .destructive) {
                store.errorMessage = nil
                store.clearAllData()
                if store.errorMessage == nil { coordinator.discardForReset() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除本机计划、记录和草稿，同步删除配对设备中的组迹数据，并放弃当前未保存的训练。尚未结束的健康训练也会丢弃；Apple 健康中既有记录及此前导出的文件会保留。操作不可撤销，如需备份请先在 iPhone 设置中导出。")
        }
    }
}
