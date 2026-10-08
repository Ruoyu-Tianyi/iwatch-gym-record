# 商店元数据与审核说明模板

适用于组迹首版。提交前根据真实构建、设备实测和最终功能修改，替换所有 `【…】` 占位符。名称可用性和长度以 App Store Connect 校验为准。不得把本模板视为已完成审核资料。

## 简体中文商店信息

| 字段 | 建议内容 |
| --- | --- |
| 名称 | 组迹 RepFlow |
| 副标题 | 手腕辅助计次，记录每组训练 |
| 主要类别 | 健康健美 / Health & Fitness |
| 关键词 | 健身,力量训练,组数,计次,训练计划,卧推,下拉,划船,深蹲,手表 |
| 支持 URL | `【真实公开 HTTPS 支持页】` |
| 隐私政策 URL | `【真实公开 HTTPS 隐私页】` |
| 版权 | `2026 【真实权利人】` |

### 推广文本

抬腕看清做到第几组。用 Apple Watch 记录动作与次数，手动确认每组；用 iPhone 轻松编排训练计划。实验性辅助计次支持腕部运动估算，每组均可校正。

### 描述

训练到一半，忘了自己做到第几组？组迹把当前动作、组数和次数放在你的手腕上，让每组训练都有记录。

【在手表上完成训练】
Apple Watch 可独立使用。选择计划，开始本组，核对次数后确认完成，再由你切换下一个动作。组间休息倒计时和触感提示，让训练节奏更清楚。

【按自己的训练方式记录】
手动加减次数随时可用。实验性辅助计次使用手腕运动传感器估算次数，提供卧推、高位下拉、坐姿划船、肩部动作等轨迹。宽窄握距可分别命名和编排。深蹲默认手动计次，也可自行尝试辅助模式。

辅助计次尚未经过真实训练准确率验证；动作速度、器械、佩戴方式和手腕活动幅度都会影响结果。请在每组确认前核对、校正次数，必要时使用手动计次。组迹不自动识别动作名称、握距或动作标准程度。

【提前安排，训练后回看】
自定义动作名称、组数、目标次数、重量和休息时间；根据目标、器械和每周训练天数生成规则模板。iPhone 配套 App 支持方便编辑和排序、查看训练详情与计划完成度，并通过配对连接同步至手表。

【可选健康记录】
经你授权，使用 Apple Watch 的健康能力记录力量训练，显示本次心率和活动能量。拒绝健康权限也能手动记录组数与次数。

【数据由你掌握】
无需账号，没有广告。计划与记录保存在设备本地，通过配对 iPhone 与 Apple Watch 同步；可主动导出 JSON。开发者不通过服务器接收你的训练或健康数据。

需要 iOS 17 或更新版本、watchOS 10 或更新版本。核心训练功能在 Apple Watch 上使用，iPhone 用于管理计划与查看记录。计划模板不提供医疗建议或个体化训练处方；操作手表前请安全放下器械。

### 首版更新说明

首次发布：独立 Apple Watch 训练记录、可校正的实验性辅助计次、手动组数确认、休息提示、iPhone 计划管理与历史、配对同步和可选健康记录。

## 截图规划

| 顺序 | 实际界面 | 可用标题 | 拍摄要求 |
| --- | --- | --- | --- |
| 1 | Watch 训练中 | 这一组，做到第几次 | 展示真实次数与 `−` / `+` 按钮 |
| 2 | Watch 组间休息 | 每完成一组，由你确认 | 展示组序号和休息状态 |
| 3 | iPhone 计划编辑 | 你的动作，你来安排 | 使用卧推、宽窄下拉／划船等样例 |
| 4 | iPhone 自动编排预览 | 先有计划，再开始训练 | 标注规则模板，避免个性化 AI 宣称 |
| 5 | iPhone 训练详情 | 每组记录，都能回看 | 使用已明确标为测试的非个人数据 |

辅助计次截图附近保留「实验性腕部估算，可手动校正」说明。宣传稿和截图中的统计必须能在 App 中重现；不填写编造的准确率或真实用户数。

## 审核联系信息

- 姓名：`【可联系的真实姓名】`
- 电话：`【含国家／地区码】`
- 邮箱：`【审核期间有人查看的邮箱】`
- 登录要求：无账号，无登录，无订阅或内购。
- 特殊硬件：需要 Apple Watch 才能执行核心训练与真实运动采样，iPhone 配套 App 用于计划／历史管理。

## 审核说明（中文）

本 App 是独立可运行的 Apple Watch 力量训练记录工具，附带 iPhone 配套 App。没有账号、广告、分析 SDK、服务器或付费解锁。请使用 Apple Watch 检查核心训练功能。

测试路径：

1. 在 iPhone「计划」查看预置计划，或新建包含 1 个动作、1 组、目标 5 次的测试计划，计次方式选择手动；等待它同步到配对 Watch。也可直接在 Watch 创建计划。
2. 在 Watch 打开计划，选择「仅记录组数与次数」。点击「开始第 1 组」，通过 `+` 增加至 5 次，点击完成本组，再确认结束。
3. Watch 和 iPhone「记录」可查看这次训练。iPhone「设置」可手动发起同步及导出 JSON。
4. HealthKit 为可选路径：在 Watch 选择「使用健康数据开始」，系统请求读取心率、活动能量，以及写入训练与活动能量的相关授权。拒绝授权仍可使用本地手动记录。仅用户明确结束时尝试保存健康训练。
5. 辅助计次为实验性腕部加速度估算，需要真实 Apple Watch 运动输入，不能在模拟器中验证计次表现。App 显示其限制并提供加减校正；它不识别动作质量、不宣称医疗用途或计次准确率。

数据仅保存在本地并同步于配对设备，不发送到开发者服务器。删除组迹记录不会删除 Apple 健康 App 中的训练；用户可在健康 App 单独管理。iPhone「清除所有组迹数据」会同时传播配对设备的历史清除操作，操作前提供确认。

验证设备／系统：`【填入实际设备型号、系统版本】`。
TestFlight 验证版本：`【版本与 build】`。
如需说明视频：`【公开可访问的真实操作视频 URL；未提供则删去此行】`。

## Review notes (English)

RepFlow is an independently usable Apple Watch strength-workout logger with an iPhone companion for plan editing and history. No account, subscription, in-app purchase, advertising, analytics SDK, or developer-operated backend is used.

To test the core flow, open or create a plan on Apple Watch, choose the local logging option ("仅记录组数与次数"), start a set, adjust repetitions using the plus/minus controls, confirm the set, and finish the workout. A completed record appears locally and is synchronized with the paired iPhone when the system delivers the update. Plans can also be created directly on the watch.

The optional HealthKit path ("使用健康数据开始") requests heart-rate and active-energy read access, and workout and active-energy write access. Permission denial does not block manual logging. Workout saving is attempted only after the user explicitly finishes. Deleting app records does not delete workouts already saved in Apple Health.

Assisted repetition counting is an experimental wrist-acceleration estimate that requires a physical Apple Watch. It has no validated real-world accuracy claim. Users can correct every count manually. The app does not identify exercise form or provide medical measurements. Automatic plan generation uses fixed rule templates, not individualized medical advice.

Please see the actual tested device and build details above. No demo credentials are required.

## 提交前内容核查

- 删除或替换所有占位符，核对两种语言是否与真实构建一致。
- 将「尚未经过真实训练准确率验证」只在有完整测量证据后改为准确的实测表述，不能因为完成一次体验测试就删掉限制。
- 确认 App Privacy、隐私政策、权限说明与二进制中的所有 SDK 一致。
- 不宣称医疗器械、疾病检测、必然减脂、自动判断动作标准或无需确认的精准计数。
- 确认支持和隐私链接可公开访问，截图展示的是审核构建真正具备的界面。
