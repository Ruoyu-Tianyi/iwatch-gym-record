import SwiftUI
import RepFlowCore

struct PlanGeneratorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var goal = TrainingGoal.hypertrophy
    @State private var equipment = TrainingEquipment.gym
    @State private var daysPerWeek = 3
    @State private var preview: [TrainingPlan] = []
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            List {
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.orange)
                        Text("尚未完成添加。再次点击添加可以继续，已保存的计划不会重复。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.listRowBackground(PhoneTheme.card)
                }
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.largeTitle).foregroundStyle(PhoneTheme.lime)
                        Text("安排下一周").font(.system(.title2, design: .rounded, weight: .bold))
                        Text("选择训练方向，生成一份可继续编辑的每周安排。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }.listRowBackground(PhoneTheme.card)
                Section("你的偏好") {
                    Picker("训练目标", selection: $goal) {
                        ForEach(TrainingGoal.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("可用器械", selection: $equipment) {
                        ForEach(TrainingEquipment.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("每周 \(daysPerWeek) 天", value: $daysPerWeek, in: 1...6)
                    Button {
                        preview = PlanGenerator.generate(goal: goal, equipment: equipment, daysPerWeek: daysPerWeek).map {
                            TrainingPlan(name: $0.name, exercises: $0.exercises.map(copyExercise))
                        }
                        saveError = nil
                    } label: {
                        Label(preview.isEmpty ? "生成预览" : "重新生成预览", systemImage: "arrow.clockwise")
                    }
                }.listRowBackground(PhoneTheme.card)
                if !preview.isEmpty {
                    ForEach(preview) { plan in
                        Section(plan.name) {
                            ForEach(plan.exercises) { ExerciseSummaryRow(exercise: $0) }
                        }.listRowBackground(PhoneTheme.card)
                    }
                    Section {
                        Button {
                            for plan in preview {
                                store.errorMessage = nil
                                store.savePlan(plan)
                                if let error = store.errorMessage {
                                    saveError = error
                                    return
                                }
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Label("添加全部 \(preview.count) 个计划", systemImage: "checkmark.circle.fill")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }.listRowBackground(PhoneTheme.card)
                }
                Section {
                    Text("编排使用本地规则模板，不是个体化教练建议。可在添加后修改动作、组数、次数与休息时间。根据经验与恢复情况安排训练日，重量由你自行填写。")
                        .font(.footnote).foregroundStyle(.secondary)
                    AssistanceNotice()
                }.listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(PhoneTheme.background)
            .navigationTitle("自动编排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .onChange(of: goal) { _, _ in preview = [] }
            .onChange(of: equipment) { _, _ in preview = [] }
            .onChange(of: daysPerWeek) { _, _ in preview = [] }
        }
    }
}
