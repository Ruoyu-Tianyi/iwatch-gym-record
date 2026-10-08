import SwiftUI
import RepFlowCore

struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExercisePlan
    @State private var confirmingDiscard = false
    private let original: ExercisePlan
    let onSave: (ExercisePlan) -> Void

    init(exercise: ExercisePlan, onSave: @escaping (ExercisePlan) -> Void) {
        original = exercise
        _draft = State(initialValue: exercise)
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.weightKG.isFinite && draft.weightKG >= 0 && draft.weightKG <= 1000
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("动作名称") {
                    TextField("例如：宽距高位下拉", text: $draft.name)
                        .submitLabel(.done)
                }
                Section {
                    Stepper("目标组数：\(draft.targetSets) 组", value: $draft.targetSets, in: 1...30)
                    Stepper("每组次数：\(draft.targetReps) 次", value: $draft.targetReps, in: 1...200)
                    HStack {
                        Text("重量（kg）")
                        Spacer()
                        TextField("0", value: $draft.weightKG, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 70, maxWidth: 130)
                            .accessibilityLabel("重量，千克；零表示自重或未填写")
                    }
                    Stepper("组间休息：\(draft.restSeconds) 秒", value: $draft.restSeconds, in: 0...1800, step: 15)
                } header: {
                    Text("训练目标")
                } footer: {
                    Text("重量为每组记录值，0 表示自重或未填写。记录哑铃时请固定使用单只或总重口径。目标次数不会自动结束一组，完成组由你确认。")
                }
                Section {
                    Picker("计次方式", selection: $draft.countingMode) {
                        ForEach(CountingMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Picker("动作模型", selection: $draft.motionProfile) {
                        ForEach(MotionProfile.allCases) { profile in Text(profile.title).tag(profile) }
                    }
                    if draft.countingMode == .assisted {
                        Label("实验功能：每组结束前核对并修正次数。", systemImage: "waveform.path")
                            .font(.subheadline).foregroundStyle(PhoneTheme.lime)
                    }
                    if draft.motionProfile == .squat {
                        Text("深蹲时手腕可能相对固定，尤其是杠铃深蹲。推荐手动计次；辅助模式仅供尝试。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("手表计次") } footer: { Text("宽距与窄距动作共用相应动作模型，名称可自行区分。") }
                Section { AssistanceNotice() }
            }
            .scrollContentBackground(.hidden)
            .background(PhoneTheme.background)
            .navigationTitle("编辑动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if draft != original { confirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(draft)
                        dismiss()
                    }.fontWeight(.semibold).disabled(!canSave)
                }
            }
            .confirmationDialog("放弃这个动作的修改？", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
            .interactiveDismissDisabled(draft != original)
        }
    }
}

struct ExerciseLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let onAdd: (ExercisePlan) -> Void

    private var templates: [ExercisePlan] {
        ExercisePlan.templates.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onAdd(ExercisePlan(name: "自定义动作", countingMode: .manual, motionProfile: .generic))
                        dismiss()
                    } label: {
                        Label("添加自定义动作", systemImage: "plus.circle")
                    }
                }
                Section("常用动作") {
                    ForEach(templates) { exercise in
                        Button {
                            onAdd(copyExercise(exercise))
                            dismiss()
                        } label: {
                            HStack {
                                ExerciseSummaryRow(exercise: exercise)
                                Spacer(minLength: 4)
                                Image(systemName: "plus.circle.fill").foregroundStyle(PhoneTheme.lime)
                            }
                        }.buttonStyle(.plain)
                    }
                    if templates.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PhoneTheme.background)
            .searchable(text: $search, prompt: "搜索卧推、下拉、划船…")
            .navigationTitle("添加动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

func copyExercise(_ source: ExercisePlan) -> ExercisePlan {
    ExercisePlan(name: source.name, targetSets: source.targetSets, targetReps: source.targetReps,
                 restSeconds: source.restSeconds, weightKG: source.weightKG,
                 countingMode: source.countingMode, motionProfile: source.motionProfile)
}
