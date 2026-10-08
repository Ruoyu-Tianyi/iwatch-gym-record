import SwiftUI
import RepFlowCore

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var recordToDelete: WorkoutRecord?
    @State private var confirmingDelete = false

    private var records: [WorkoutRecord] {
        store.history.filter { record in
            search.isEmpty || record.planName.localizedCaseInsensitiveContains(search)
                || record.sets.contains { $0.exerciseName.localizedCaseInsensitiveContains(search) }
        }.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        List {
            if store.history.isEmpty {
                ContentUnavailableView {
                    Label("还没有训练记录", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("在 Apple Watch 完成并结束一次训练后，记录会自动同步到这里。")
                } actions: {
                    Button("尝试同步") { store.syncNow() }.buttonStyle(.bordered)
                }.listRowBackground(Color.clear)
            } else if records.isEmpty {
                ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
            } else {
                Section {
                    HStack {
                        Text("\(records.count) 次训练")
                        Spacer()
                        Text("\(records.reduce(0) { $0 + $1.sets.count }) 组")
                            .foregroundStyle(PhoneTheme.lime)
                    }.font(.subheadline)
                }.listRowBackground(PhoneTheme.card)
                Section {
                    ForEach(records) { record in
                        NavigationLink { RecordDetailView(recordID: record.id) } label: {
                            RecordSummary(record: record).padding(.vertical, 6)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                recordToDelete = record
                                confirmingDelete = true
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }.listRowBackground(PhoneTheme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PhoneTheme.background)
        .searchable(text: $search, prompt: "搜索计划或动作")
        .navigationTitle("训练记录")
        .refreshable { store.syncNow() }
        .confirmationDialog("删除这次训练记录？", isPresented: $confirmingDelete, titleVisibility: .visible, presenting: recordToDelete) { record in
            Button("删除记录", role: .destructive) {
                store.errorMessage = nil
                store.deleteRecord(id: record.id)
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("删除会同步到配对设备，Apple 健康中的训练不会被删除。")
        }
    }
}

struct RecordSummary: View {
    let record: WorkoutRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.planName).font(.headline).foregroundStyle(.primary)
                    Text(record.startedAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text(record.completion, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(PhoneTheme.lime)
                    .accessibilityLabel("计划完成度 \(Int(record.completion * 100)) 百分比")
            }
            ProgressView(value: record.completion)
                .tint(PhoneTheme.lime)
                .accessibilityLabel("计划完成度")
            Text("\(record.sets.count) 组 · \(record.totalReps) 次 · \(durationText(record))")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ExerciseSetGroup: Identifiable {
    let id: UUID
    let name: String
    var sets: [CompletedSet]
}

struct RecordDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID
    @State private var confirmingDelete = false

    private var record: WorkoutRecord? { store.history.first { $0.id == recordID } }

    var body: some View {
        Group {
            if let record {
                List {
                    Section {
                        RecordSummary(record: record).padding(.vertical, 8)
                        LabeledContent("开始", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("结束", value: record.endedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("计划组数", value: "\(record.plannedSets) 组")
                        LabeledContent("已记录组数", value: "\(record.sets.count) 组")
                    }.listRowBackground(PhoneTheme.card)
                    if record.activeEnergyKcal != nil || record.averageHeartRate != nil {
                        Section {
                            if let energy = record.activeEnergyKcal {
                                LabeledContent("活动能量", value: "\(energy.formatted(.number.precision(.fractionLength(0)))) 千卡")
                            }
                            if let heartRate = record.averageHeartRate {
                                LabeledContent("平均心率", value: "\(heartRate.formatted(.number.precision(.fractionLength(0)))) 次/分钟")
                            }
                        } header: { Text("手表运动数据") } footer: {
                            Text("由 Apple Watch 训练期间提供。只展示已获取的数据。")
                        }.listRowBackground(PhoneTheme.card)
                    }
                    if record.sets.isEmpty {
                        Section {
                            ContentUnavailableView("没有已确认的组", systemImage: "checkmark.circle", description: Text("这次训练没有保存完成组。计次需要在手表上确认完成组后才会计入记录。"))
                        }.listRowBackground(PhoneTheme.card)
                    } else {
                        ForEach(groupedSets(record)) { group in
                            Section(group.name) {
                                ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, set in
                                    SetDetailRow(set: set, number: index + 1)
                                }
                            }.listRowBackground(PhoneTheme.card)
                        }
                    }
                    Section {
                        Text("完成度按各动作已确认的目标组数计算，上限为 100%；额外组不会替代其他动作未完成的组。次数包含训练时的手动修正。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.listRowBackground(Color.clear)
                }
            } else {
                ContentUnavailableView("记录已删除", systemImage: "clock", description: Text("返回记录页查看其他训练。"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(PhoneTheme.background)
        .navigationTitle("训练详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if record != nil {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Image(systemName: "trash")
                    }.accessibilityLabel("删除训练记录")
                }
            }
        }
        .confirmationDialog("删除这次训练记录？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) {
                store.errorMessage = nil
                store.deleteRecord(id: recordID)
                if store.errorMessage == nil { dismiss() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除会同步到配对设备，Apple 健康中的训练不会被删除。")
        }
    }

    private func groupedSets(_ record: WorkoutRecord) -> [ExerciseSetGroup] {
        var groups: [ExerciseSetGroup] = []
        for set in record.sets {
            if let index = groups.firstIndex(where: { $0.id == set.exerciseID }) {
                groups[index].sets.append(set)
            } else {
                groups.append(ExerciseSetGroup(id: set.exerciseID, name: set.exerciseName, sets: [set]))
            }
        }
        return groups
    }
}

private struct SetDetailRow: View {
    let set: CompletedSet
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("第 \(number) 组").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(set.reps) 次").font(.headline).monospacedDigit()
            }
            HStack {
                Text(weightText(set.weightKG))
                Spacer()
                Text(set.assisted ? "辅助计次" : "手动计次")
            }.font(.caption).foregroundStyle(.secondary)
            Text(set.completedAt, format: .dateTime.hour().minute())
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
