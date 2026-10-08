import SwiftUI
import RepFlowCore

struct PlanListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingPlan: TrainingPlan?
    @State private var showingGenerator = false
    @State private var planToDelete: TrainingPlan?
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                Button { showingGenerator = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles").font(.title2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("自动编排").font(.headline)
                            Text("按目标、器械和每周天数生成计划")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(PhoneTheme.card)
            }
            Section("我的计划") {
                if store.plans.isEmpty {
                    ContentUnavailableView {
                        Label("还没有计划", systemImage: "list.bullet.clipboard")
                    } description: {
                        Text("添加你熟悉的动作，安排组数和目标次数。")
                    } actions: {
                        Button("新建计划") { createPlan() }.buttonStyle(.bordered)
                    }
                    .listRowBackground(PhoneTheme.card)
                } else {
                    ForEach(store.plans) { plan in
                        NavigationLink { PlanDetailView(planID: plan.id) } label: { PlanRow(plan: plan) }
                            .listRowBackground(PhoneTheme.card)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    planToDelete = plan
                                    confirmingDelete = true
                                } label: { Label("删除", systemImage: "trash") }
                                Button { editingPlan = plan } label: { Label("编辑", systemImage: "pencil") }
                                    .tint(.blue)
                            }
                    }
                }
            }
            Section {
                Label("保存后会在配对设备连接可用时同步。Apple Watch 也可以独立选择计划、记录训练。", systemImage: "applewatch")
                    .font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PhoneTheme.background)
        .navigationTitle("计划")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { createPlan() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新建计划")
            }
        }
        .sheet(item: $editingPlan) { plan in PlanEditorView(plan: plan) }
        .sheet(isPresented: $showingGenerator) { PlanGeneratorView() }
        .confirmationDialog("删除这个计划？", isPresented: $confirmingDelete, titleVisibility: .visible, presenting: planToDelete) { plan in
            Button("删除「\(plan.name)」", role: .destructive) {
                store.errorMessage = nil
                store.deletePlan(id: plan.id)
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("删除会同步到配对设备。已经保存的训练记录会保留。")
        }
    }

    private func createPlan() {
        editingPlan = TrainingPlan(name: "我的训练", exercises: [])
    }
}

struct PlanDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let planID: UUID
    @State private var editingPlan: TrainingPlan?
    @State private var confirmingDelete = false

    private var plan: TrainingPlan? { store.plans.first { $0.id == planID } }

    var body: some View {
        Group {
            if let plan {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(plan.name).font(.system(.title, design: .rounded, weight: .bold))
                            Text("\(plan.exercises.count) 个动作 · \(plan.totalSets) 组")
                                .foregroundStyle(PhoneTheme.lime)
                            Label("在 Apple Watch 打开组迹，选择此计划开始训练。", systemImage: "applewatch")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }.listRowBackground(PhoneTheme.card)
                    Section("动作顺序") {
                        if plan.exercises.isEmpty {
                            Text("还没有动作。点右上角编辑来添加。")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                            ExerciseSummaryRow(exercise: exercise, index: index)
                        }
                    }.listRowBackground(PhoneTheme.card)
                    Section { AssistanceNotice() }.listRowBackground(Color.clear)
                    Section {
                        Button("删除计划", role: .destructive) { confirmingDelete = true }
                    }.listRowBackground(PhoneTheme.card)
                }
            } else {
                ContentUnavailableView("计划已删除", systemImage: "list.bullet.clipboard", description: Text("返回计划页创建新的训练安排。"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(PhoneTheme.background)
        .navigationTitle("计划详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let plan { Button("编辑") { editingPlan = plan } }
            }
        }
        .sheet(item: $editingPlan) { plan in PlanEditorView(plan: plan) }
        .confirmationDialog("删除这个计划？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除计划", role: .destructive) {
                store.errorMessage = nil
                store.deletePlan(id: planID)
                if store.errorMessage == nil { dismiss() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除会同步到配对设备，训练记录会保留。")
        }
    }
}

struct PlanEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrainingPlan
    @State private var editingExercise: ExercisePlan?
    @State private var showingLibrary = false
    @State private var confirmingDiscard = false
    @State private var saveError: String?
    private let original: TrainingPlan

    init(plan: TrainingPlan) {
        original = plan
        _draft = State(initialValue: plan)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.exercises.isEmpty
    }
    private var hasChanges: Bool { draft != original }

    var body: some View {
        NavigationStack {
            List {
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).font(.subheadline)
                    }.listRowBackground(PhoneTheme.card)
                }
                Section("计划名称") {
                    TextField("例如：胸背训练日", text: $draft.name)
                        .submitLabel(.done)
                }.listRowBackground(PhoneTheme.card)
                Section {
                    if draft.exercises.isEmpty {
                        Text("添加至少一个动作后即可保存。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, exercise in
                        Button { editingExercise = exercise } label: {
                            HStack {
                                ExerciseSummaryRow(exercise: exercise, index: index)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                    .onMove { draft.exercises.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.exercises.remove(atOffsets: $0) }
                    Button { showingLibrary = true } label: {
                        Label("添加动作", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("动作 · \(draft.totalSets) 组")
                        Spacer()
                        EditButton().font(.subheadline)
                    }
                } footer: {
                    Text("轻点动作编辑参数；使用编辑按钮调整动作顺序或删除。训练中的计划以开始时的版本为准。")
                }
                .listRowBackground(PhoneTheme.card)
                Section { AssistanceNotice() }.listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(PhoneTheme.background)
            .navigationTitle("编辑计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if hasChanges { confirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.errorMessage = nil
                        store.savePlan(draft)
                        if let error = store.errorMessage { saveError = error } else { dismiss() }
                    }.fontWeight(.semibold).disabled(!canSave)
                }
            }
            .sheet(item: $editingExercise) { exercise in
                ExerciseEditorView(exercise: exercise) { updated in
                    if let index = draft.exercises.firstIndex(where: { $0.id == updated.id }) {
                        draft.exercises[index] = updated
                    }
                }
            }
            .sheet(isPresented: $showingLibrary) {
                ExerciseLibraryView { draft.exercises.append($0) }
            }
            .confirmationDialog("放弃尚未保存的修改？", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
            .interactiveDismissDisabled(hasChanges)
        }
    }
}
