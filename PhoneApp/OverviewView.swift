import SwiftUI
import RepFlowCore

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: PhoneTab

    private var thisWeek: [WorkoutRecord] {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return store.history.filter { interval.contains($0.startedAt) }
    }

    private var latest: WorkoutRecord? {
        store.history.max { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("这一周").font(.title3.bold())
                        Spacer()
                        Text(Date(), format: .dateTime.month().day())
                            .font(.subheadline).foregroundStyle(PhoneTheme.muted)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        MetricTile(value: "\(thisWeek.count)", title: "次训练", symbol: "figure.strengthtraining.traditional")
                        MetricTile(value: "\(thisWeek.reduce(0) { $0 + $1.sets.count })", title: "已完成组", symbol: "checkmark.circle")
                        MetricTile(value: "\(thisWeek.reduce(0) { $0 + $1.totalReps })", title: "累计次数", symbol: "repeat")
                    }
                }
                nextPlan
                if let latest {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("最近一次").font(.title3.bold())
                        NavigationLink {
                            RecordDetailView(recordID: latest.id)
                        } label: {
                            TrainingCard { RecordSummary(record: latest) }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    TrainingCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("第一组，从今天开始", systemImage: "flag.checkered")
                                .font(.headline).foregroundStyle(PhoneTheme.lime)
                            Text("在 Apple Watch 打开「组迹」，选择计划并开始训练。结束后，你的训练记录会显示在这里。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                AssistanceNotice()
            }
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(PhoneTheme.background)
        .navigationTitle("组迹")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { selection = .settings } label: {
                    Image(systemName: "applewatch")
                }
                .accessibilityLabel("查看手表同步状态")
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("专注动作。\n记数交给组迹。")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("手表记录每一组，手机安排下一练。")
                .font(.subheadline).foregroundStyle(PhoneTheme.muted)
            Label(store.syncStatus, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(PhoneTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private var nextPlan: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("你的训练计划").font(.title3.bold())
                Spacer()
                Button("全部") { selection = .plans }.font(.subheadline)
            }
            if let plan = store.plans.first {
                NavigationLink {
                    PlanDetailView(planID: plan.id)
                } label: {
                    TrainingCard {
                        VStack(alignment: .leading, spacing: 16) {
                            PlanRow(plan: plan)
                            Divider()
                            Text(plan.exercises.prefix(3).map(\.name).joined(separator: "  ·  "))
                                .font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Label("在手表上开始训练", systemImage: "applewatch")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline).foregroundStyle(PhoneTheme.lime)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                TrainingCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("还没有训练计划").font(.headline)
                        Text("自己安排动作，或根据目标和器械生成每周安排。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("创建第一个计划") { selection = .plans }
                            .buttonStyle(.borderedProminent).foregroundStyle(PhoneTheme.background)
                    }
                }
            }
        }
    }
}
