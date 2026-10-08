# 组迹交付验证记录

验证日期：2026-10-07。交付为原生 iOS / watchOS 源码、已生成的 Xcode 工程、图标及发布文档。以下结果区分实际运行的检查和仍需 Apple 环境完成的验收。

## 本次实际运行

环境：Debian 13、x86_64 Linux、Swift 6.0.3（项目使用 Swift 5 语言模式），XcodeGen 2.44.1。

| 检查 | 结果 | 可以证明的范围 |
| --- | --- | --- |
| `./scripts/test-core.sh` | 37 项 XCTest 全部通过，0 失败 | 数据模型、计划编排、训练状态机及合成信号计次 |
| `./scripts/test-sync.sh` | 20 项检查通过 | 实际 AppStore 的磁盘保存与合并逻辑；Combine 与配对传输使用测试替身 |
| `xcodegen generate --spec project.yml` | 成功生成 `RepFlow.xcodeproj` | 项目配置可被真实 XcodeGen 解析并生成工程 |
| `python3 scripts/validate-project.py` | 32 项检查通过 | 两端标识关联、Watch 嵌入、权限用途、独立运行标记、版本设置、共享 scheme、隐私资源与不透明 1024 图标 |
| 20 个应用／核心 Swift 源文件的 `swiftc -frontend -parse` | 全部通过 | Swift 语法正确；不能替代 Apple SDK 类型检查 |
| 4 个 Shell 脚本的 `bash -n` | 全部通过 | Shell 语法正确 |

核心测试的原始输出见 [core-tests.txt](verification/core-tests.txt)，存储同步输出见 [sync-tests.txt](verification/sync-tests.txt)。Swift 工具末尾可能另行显示「0 tests」的 Swift Testing runner；本项目使用 XCTest，其汇总明确为 37 tests、0 failures。

核心检查包括重复点击防重复记组、手动次数修正、休息结束不自动开始计次、暂停／恢复保留状态、额外组数不能替代漏掉的其他动作、固定训练 ID 防止草稿恢复后重复归档，以及损坏草稿拒绝恢复。

计次算法的 14 项测试输入是人工构造的安静、噪声、周期、冲击、采样中断和异常时间戳信号。这些结果验证算法边界，**不代表卧推、下拉、划船或深蹲的真实计次准确率**。

存储检查包括离线双端编辑、墓碑防删除数据复活、记录去重、健康指标补齐、损坏文件恢复、保存失败不假成功、清除屏障和清除后不重新播种默认计划。测试替身不会执行真正的蓝牙、系统后台调度或 WatchConnectivity 传输。

## 仍需完成的发布验收

当前环境没有 macOS、Xcode、Apple SDK、配对设备或用户开发者签名身份，以下项目未执行：

- iPhone 和 Apple Watch 原生编译、运行与屏幕布局检查。
- HealthKit / CoreMotion 权限、实际心率与活动能量、写入健康、熄屏后台及系统中断行为。
- 真正的 WatchConnectivity 离线队列、重新配对和大历史记录传输。
- 不同手腕、握距、器械、节奏和重量下的计次误差测量与参数标定。
- Archive、签名、Validate App、TestFlight、App Store 审核和发布。

CI 配置已提供，但尚未成功推送并触发远端 CI，因此不能把已配置的流程当作已经通过的 Apple 构建。可以在 Mac 执行 `./scripts/build-apple.sh`，或在 Windows 按[云端教程](WINDOWS_CLOUD_GUIDE.md)上传并启动 GitHub macOS 构建，再按[真机验收清单](DEVICE_TEST_PLAN.md)记录设备证据。发布流程见[苹果上架教程](APP_STORE_RELEASE.md)。

## Windows 自动化补充验证

补充日期：2026-10-08。增加了 Windows 一键上传／构建入口、云端截图与日志、私有签名分支及手动触发的 TestFlight 发布流程。

| 检查 | 实际结果 |
| --- | --- |
| 两个 `.ps1` 的 PowerShell 7.4.19 parser | 通过；脚本为 UTF-8 BOM 编码，兼容 Windows PowerShell 5.1 的中文读取 |
| 实际 PowerShell 脚本的两条防护路径，GitHub／浏览器命令使用替身 | 已有仓库只触发工作流且不修改 Git；公开仓库在索取凭据／写 Secrets 前阻止签名设置 |
| `Fastfile` 与 `Gemfile` 的 Ruby 3.3.8 `-c` | 语法检查通过；fastlane 固定版本为 2.240.1 |
| 发布配置脚本 | 替换两个 Bundle ID、companion ID、Team 和版本的隔离副本检查通过 |
| Shell、工作流 YAML、Markdown 链接与工程资源 | 检查通过，工程资源仍为 32 项 |

本次没有运行 Windows 的真实工具安装／浏览器登录、GitHub macOS 原生编译、Apple 签名或 TestFlight 上传。PowerShell 防护路径检查不会连接 GitHub。用户选择在本地操作，源码、脚本和操作说明已打包；从 [WINDOWS_START_HERE.md](../WINDOWS_START_HERE.md) 开始。

## 首版行为边界

- 自动计次是可修正的腕部周期估计，不自动识别当前动作、握距或组边界。深蹲默认手动，也可主动试用辅助计次。
- 每组开始、完成组、切换动作和结束训练均需用户操作；当前未确认组不会写入最终记录。
- 无健康训练会话时，离开前台会暂停当前组；后台休息提醒不保证实时，重新进入后按时间更新。
- 进程重启后恢复本地进度为暂停状态，继续记录不会补造中断期间的次数或健康数据，也不会恢复旧 HealthKit 会话。
- 自动编排采用规则模板；没有个体训练处方、自动负重进阶或医学判断。
- JSON 导出可用于留存和人工恢复参考，本版没有导入界面。设备时钟明显不一致可能影响基于时间的编辑合并。

完成上述 Apple 环境验证后，应更新本记录和验收表，再以实测结果决定辅助计次是否对外开放。
