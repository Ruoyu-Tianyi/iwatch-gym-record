import SwiftUI
import RepFlowCore

enum PhoneTheme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.095)
    static let card = Color(red: 0.075, green: 0.105, blue: 0.155)
    static let lime = Color(red: 0.79, green: 0.96, blue: 0.34)
    static let muted = Color(red: 0.64, green: 0.70, blue: 0.77)
    static let assistNote = "辅助计次通过手腕运动估算，尚未经过真实训练准确率验证。握法、佩戴位置与动作幅度会影响结果；请在每组结束前校正次数。深蹲默认手动计次。"
}

struct TrainingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PhoneTheme.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct MetricTile: View {
    let value: String
    let title: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(PhoneTheme.lime)
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title).font(.caption).foregroundStyle(PhoneTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PhoneTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

struct PlanRow: View {
    let plan: TrainingPlan

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "dumbbell.fill")
                .font(.title3)
                .foregroundStyle(PhoneTheme.lime)
                .frame(width: 46, height: 46)
                .background(PhoneTheme.lime.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.name).font(.headline).foregroundStyle(.primary)
                Text("\(plan.exercises.count) 个动作 · \(plan.totalSets) 组")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

struct ExerciseSummaryRow: View {
    let exercise: ExercisePlan
    var index: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let index {
                Text(String(format: "%02d", index + 1))
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(PhoneTheme.lime)
                    .frame(minWidth: 25)
                    .padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name).font(.headline).foregroundStyle(.primary)
                Text("\(exercise.targetSets) 组 × \(exercise.targetReps) 次 · \(weightText(exercise.weightKG)) · 休息 \(exercise.restSeconds) 秒")
                    .font(.subheadline).foregroundStyle(.secondary)
                if exercise.countingMode == .assisted {
                    Label("辅助计次 · 实验功能", systemImage: "waveform.path")
                        .font(.caption).foregroundStyle(PhoneTheme.lime)
                } else {
                    Label("手动计次", systemImage: "hand.tap")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

func weightText(_ weight: Double) -> String {
    if weight <= 0 { return "自重 / 未填重量" }
    return "\(weight.formatted(.number.precision(.fractionLength(0...1)))) kg"
}

func durationText(_ record: WorkoutRecord) -> String {
    let seconds = max(0, Int(record.endedAt.timeIntervalSince(record.startedAt)))
    if seconds < 60 { return "\(seconds) 秒" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes) 分钟" }
    return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
}

struct AssistanceNotice: View {
    var body: some View {
        Label {
            Text(PhoneTheme.assistNote).font(.footnote)
        } icon: {
            Image(systemName: "waveform.path")
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
