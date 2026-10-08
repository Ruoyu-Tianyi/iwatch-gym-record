import SwiftUI
import UIKit
import RepFlowCore

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exportFile: ExportFile?
    @State private var confirmingClear = false

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Apple Watch", systemImage: "applewatch")
                        .font(.title3.bold())
                    Text(store.syncStatus).font(.subheadline).foregroundStyle(.secondary)
                    Button { store.syncNow() } label: {
                        Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                    }.buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            } header: { Text("配对与同步") } footer: {
                Text("计划与记录保存在设备本地，并通过系统配对连接同步。离线时可在手表继续训练；重新连接后重试同步。无需注册账号。")
            }.listRowBackground(PhoneTheme.card)
            Section {
                NavigationLink { UsageGuideView() } label: {
                    Label("使用指南", systemImage: "questionmark.circle")
                }
                NavigationLink { PrivacyInfoView() } label: {
                    Label("隐私与健康权限", systemImage: "hand.raised")
                }
            }.listRowBackground(PhoneTheme.card)
            Section {
                Button {
                    do { exportFile = ExportFile(url: try store.exportURL()) }
                    catch { store.errorMessage = "导出失败：\(error.localizedDescription)" }
                } label: {
                    Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
                }
                LabeledContent("本机训练计划", value: "\(store.plans.count) 个")
                LabeledContent("本机训练记录", value: "\(store.history.count) 次")
            } header: { Text("数据") } footer: {
                Text("备份包含计划、训练记录，以及记录中已有的心率和活动能量。分享前请确认目标位置；本版本暂不支持从 JSON 导入。")
            }.listRowBackground(PhoneTheme.card)
            Section {
                Button("清除所有组迹数据", role: .destructive) { confirmingClear = true }
            } footer: {
                Text("清除范围包括本机和配对设备中此前保存的组迹计划与训练记录，不会删除 Apple 健康中的训练或已导出的文件。")
            }.listRowBackground(PhoneTheme.card)
            Section {
                LabeledContent("组迹 · RepFlow", value: appVersion)
                Text("让每一组都有记录。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.listRowBackground(PhoneTheme.card)
        }
        .scrollContentBackground(.hidden)
        .background(PhoneTheme.background)
        .navigationTitle("设置")
        .sheet(item: $exportFile) { item in
            ActivityShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("清除本机和配对设备的所有组迹数据？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清除所有组迹数据", role: .destructive) {
                store.errorMessage = nil
                store.clearAllData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。此前保存的计划、训练记录与本机未完成训练将被清除，并同步清除配对设备的计划与记录。Apple 健康中的训练和已经导出的文件会保留；请到对应 App 单独管理。建议先导出备份。")
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct UsageGuideView: View {
    var body: some View {
        List {
            Section("01 · 准备计划") {
                Text("在「计划」中编辑默认计划、创建新计划，或使用「自动编排」。可自由修改动作名称、顺序、组数、目标次数、重量和休息时间。")
                Text("常用动作包含卧推、宽距与窄距高位下拉、宽距与窄距坐姿划船、肩部训练和深蹲。")
            }
            Section("02 · 在手表开始") {
                Text("在 Apple Watch 打开组迹并选择计划。每组开始时手动启动计次，完成时先核对次数，再确认完成组。下一组和切换动作均由你操作。")
                Text("辅助计次只在当前组训练时使用运动传感器。可以随时修正次数；手动计次不依赖传感器或健康权限。")
                Text("组间休息结束会提醒你，但不会自动开始下一组。离开当前动作或提前结束时，请先确认需要保存的组。")
            }
            Section("03 · 回顾记录") {
                Text("在手表结束训练后，完成组会保存在本地，并同步到手机「记录」。可查看完成度、逐组次数、重量，以及已获取的运动数据。")
                Text("若记录未出现，确认 iPhone 与 Apple Watch 配对正常，在两台设备打开组迹，然后在设置点击「立即同步」。同步由系统调度，可能需要等待。")
            }
            Section("关于辅助计次") {
                AssistanceNotice()
                Text("首次使用建议先做少量标准动作并观察计次。动作不匹配或计次不稳定时，改用手动记录。卧推和高位下拉等动作的不同握法仍可能影响效果。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PhoneTheme.background)
        .navigationTitle("使用指南")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyInfoView: View {
    var body: some View {
        List {
            Section("设备本地保存") {
                Text("组迹无需账号，没有自建服务器、广告或分析 SDK。计划和训练记录保存在 App 本地，通过 Apple 的配对通信在你的 iPhone 与 Apple Watch 之间同步。")
                Text("手腕运动采样只用于当前训练的辅助计次，不保存原始运动采样。只有你确认完成的组会进入训练记录。")
            }
            Section("Apple 健康与运动权限") {
                Text("手表开始训练时可申请健康权限，读取当前训练中的心率和活动能量，并在你明确结束训练后保存力量训练。运动权限用于辅助计次。")
                Text("拒绝授权或数据不可用时，仍可手动记录组数和次数。没有读取到的心率和能量不会以估算值填充。")
                Text("可在 iPhone 的「健康」App 个人资料中的 App 权限入口，或系统设置的隐私与安全性入口管理健康权限；系统版本不同，入口名称可能略有差异。")
            }
            Section("同步、导出与删除") {
                Text("同步记录可能包含训练时获取的平均心率和活动能量，数据只通过系统连接发往你的配对设备。导出 JSON 时也会包含这些已有数据，由你选择保存或分享位置。")
                Text("删除计划、训练记录或清除全部数据会同步到配对设备。Apple 健康中的训练不会随之删除，已导出的副本也不受影响，需要自行在对应位置管理。")
                Text("本地数据是否进入设备系统备份由你的 Apple 系统设置管理。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PhoneTheme.background)
        .navigationTitle("隐私与健康权限")
        .navigationBarTitleDisplayMode(.inline)
    }
}
