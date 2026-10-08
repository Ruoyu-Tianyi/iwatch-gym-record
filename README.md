# 组迹 RepFlow

一款原生中文 Apple Watch 健身记录 App，配有 iPhone 计划管理和历史记录 App。训练时在手表查看当前动作、第几组和次数；使用腕部运动传感器辅助估计次数，再由你确认完成本组和切换动作。

**交付状态：可交给 Mac/Xcode 继续构建和发布的完整源码工程。2026-10-08 已通过 GitHub macOS 云端核心测试、两端无签名模拟器编译及模拟器预览流程；签名、真机验证及 TestFlight 尚未完成。辅助计次尚无真实训练准确率验证；不能把源码交付等同于已审核上架的 App。**

## 首版功能

- Apple Watch 可独立训练、编辑计划、查看记录；iPhone 便于编辑和排序动作、查看训练完成度。
- 大号次数显示、手动加减校正、手动确认组数与切换动作，休息倒计时及触感反馈。
- 实验性辅助计次覆盖卧推、宽距／窄距高位下拉、宽距／窄距坐姿划船、肩部动作和深蹲等动作轨迹。宽窄握距使用相同轨迹算法，不会自动识别握距或动作名称。
- 深蹲默认手动计次，用户可主动开启辅助计次；手腕固定在杠铃上时信号尤其容易失真。
- 编辑动作名称、目标组数／次数、重量、休息时间和计次方式；按目标、器械和训练天数生成规则模板计划。
- 经许可通过 HealthKit 记录力量训练、读取本次训练心率与活动能量；拒绝许可仍可手动记录。
- 本地 JSON 保存、配对 iPhone / Watch 同步、训练中断后恢复暂停草稿、iPhone 导出 JSON。没有账号、广告、后端或内购。

自动编排是固定规则模板，不是个性化 AI 教练。辅助计次不是医疗测量，也不承诺准确率。请在安全放下器械后操作手表，每组结束先核对次数。

## 在 Mac 上开始

只有 Windows、iPhone 和 Apple Watch 时，可使用已准备的 GitHub macOS 云端构建及 TestFlight 发布流程；具体步骤见 [Windows 云端开发与安装教程](docs/WINDOWS_CLOUD_GUIDE.md)。

最低运行系统是 iOS 17 和 watchOS 10。**运行系统下限与上传所需 SDK 是两件事**：截至 2026-10-07，Apple 官方要求 App Store Connect 上传使用 Xcode 26 或更新版本及相应 26 系列 SDK；发布当天应再次核对[官方要求](https://developer.apple.com/news/upcoming-requirements/)。

```bash
cd RepFlow
brew install xcodegen
./scripts/bootstrap-macos.sh
open RepFlow.xcodeproj
```

如果尚未安装 Xcode，请先从 Apple Developer 下载受支持的正式版，启动一次并安装 iOS/watchOS 平台。以上命令假定已安装 Homebrew；已有 XcodeGen 2.44.1 或更新版本时可跳过安装行。脚本使用 XcodeGen 从 `project.yml` 重新生成工程；工程文件也随源码交付。

在 Xcode 中：

1. 选中 `RepFlow` 工程，分别打开 `RepFlow`、`RepFlowWatch` target 的 **Signing & Capabilities**，选择自己的开发者 Team。
2. 在 `project.yml` 中把 `com.example.RepFlow` 及 `com.example.RepFlow.watchkitapp` 一起替换为自己的唯一标识，并同步修改 Watch 的 `WKCompanionAppBundleIdentifier`。重新执行引导脚本。不要只改 Xcode 界面后又用 XcodeGen 覆盖。
3. 用 `RepFlow` scheme 运行 iPhone App，用 `RepFlowWatch` scheme 运行 Watch App。真实传感器、心率、后台训练和跨设备同步必须在配对真机验证。

执行纯逻辑测试：

```bash
./scripts/test-core.sh
./scripts/test-sync.sh
```

第二个脚本使用测试替身验证真实存储与合并代码，不验证 Apple 的 WatchConnectivity 传输服务。

在已安装对应模拟器平台的 Mac 上检查两个 App 的编译：

```bash
xcodebuild -project RepFlow.xcodeproj -scheme RepFlow -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RepFlow.xcodeproj -scheme RepFlowWatch -configuration Debug -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

签名、设备安装和上架完整步骤见[苹果上架教程](docs/APP_STORE_RELEASE.md)。

## 交付目录

| 路径 | 内容 |
| --- | --- |
| `RepFlow.xcodeproj` / `project.yml` | 可打开的 Xcode 工程与可重复生成配置 |
| `PhoneApp/` | iPhone SwiftUI 界面 |
| `WatchApp/` | 手表界面、训练协调、CoreMotion、HealthKit |
| `Shared/` | 本地保存、配对设备同步 |
| `Sources/RepFlowCore/` | 共享数据模型、训练状态机、计次算法、模板编排 |
| `Tests/RepFlowCoreTests/` | 核心逻辑与合成信号测试 |
| `scripts/` / `.github/workflows/` | 本地引导、核心测试、Mac 编译检查 |

## 使用与发布文档

- [使用手册](docs/USER_GUIDE.md)：从建立计划到完成一场训练。
- [架构与已知限制](docs/ARCHITECTURE.md)：算法边界、HealthKit、数据和同步。
- [真机验收清单](docs/DEVICE_TEST_PLAN.md)：发布前逐项填写实测证据。
- [实际验证报告](docs/VERIFICATION.md)：本次交付已运行与尚未运行的检查。
- [苹果上架教程](docs/APP_STORE_RELEASE.md)：签名、归档、TestFlight、App Store Connect。
- [商店元数据与审核说明](docs/APP_STORE_METADATA.md)：可修改的中文文案与审核路径。
- [隐私政策模板](docs/PRIVACY_POLICY.md)：发布前替换运营主体、联系邮箱和公开 URL。

未完成的发布工作集中在真实 Apple 环境验收、传感器标定、开发者身份与商店资料。每次修改 SDK、第三方库或数据流，都应重新核对隐私申报及审核说明。

