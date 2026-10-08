# 组迹：从源码到 Apple App Store

更新日期：2026-10-07。对象：带 iPhone 配套 App、可独立运行的 Apple Watch 原生 App。本文提供实际操作路径；**源码交付不包含开发者身份、证书、已签名安装包、TestFlight 验收或审核通过结果**。已经运行的检查见 [VERIFICATION.md](VERIFICATION.md)，待完成项见[真机验收表](DEVICE_TEST_PLAN.md)。

## 1. 准备 Mac 与开发者身份

需要可运行当前正式版 Xcode 的 Mac，以及用于实测的 iPhone 和 Apple Watch。最低运行版本为 iOS 17 / watchOS 10，实测还应覆盖发布时的当前系统。App Store 发布需要 Apple Developer Program 会员；加入时以 Apple 显示的本地价格、主体及身份要求为准。

截至本次核验，Apple [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/) 明确：自 **2026-04-28** 起，上传到 App Store Connect 的 App 必须使用 **Xcode 26 或更新版本**和 iOS / watchOS 等相应 **26 系列或更新 SDK** 构建。这不要求把 App 的最低运行系统改成 26。发布当天重新打开官方页面核对，不能照搬过期博客中的工具版本。

1. 安装满足当前上传要求的 Xcode 正式版，启动并接受许可，安装 iOS、watchOS 平台和需要的模拟器。
2. 在 Xcode → Settings → Accounts 登录 Apple ID，确认能看到有权限的 Team。
3. 连接、信任并配对 iPhone / Watch，根据设备系统提示启用 Developer Mode；在 Xcode 的 Devices and Simulators 中确认可用。
4. 安装 Homebrew 和 XcodeGen（项目引导脚本会检查相应工具）。

```bash
xcode-select -p
xcodebuild -version
swift --version
```

如果 `xcode-select` 指向 Command Line Tools，应切换为实际 Xcode 路径；示例路径需与你机器一致：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 2. 生成工程并确认可编译

```bash
cd RepFlow
brew install xcodegen
./scripts/bootstrap-macos.sh
./scripts/test-core.sh
./scripts/test-sync.sh
open RepFlow.xcodeproj
```

已安装符合要求的 XcodeGen 时可跳过安装行。`project.yml` 是工程配置的源文件。改动构建设置、target、Info.plist 路径等配置时，要同步维护它，否则下次 XcodeGen 会覆盖仅在 Xcode 界面中的修改。`test-sync.sh` 使用系统框架与传输的测试替身，验证的是存储和合并逻辑，不是 Apple 跨设备投递服务。

先检查两端模拟器编译，再上真机：

```bash
xcodebuild -project RepFlow.xcodeproj -scheme RepFlow -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RepFlow.xcodeproj -scheme RepFlowWatch -configuration Debug -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

模拟器能验证界面、导航和一部分逻辑，不能验证真实手腕动作、心率、活动能量、耗电或后台持续训练。若编译失败，先修复平台编译错误，再继续签名与分发。

## 3. 设置两端 Bundle ID、Team 与能力

示例标识不可直接发布。替换时保持这三个值匹配：

| 位置 | 当前示例 | 自己的示例 |
| --- | --- | --- |
| iPhone target Bundle ID | `com.example.RepFlow` | `com.yourcompany.RepFlow` |
| Watch target Bundle ID | `com.example.RepFlow.watchkitapp` | `com.yourcompany.RepFlow.watchkitapp` |
| Watch Info.plist `WKCompanionAppBundleIdentifier` | `com.example.RepFlow` | 与 iPhone Bundle ID 完全相同 |

在 `project.yml` 和项目所用 plist 中替换后重新生成工程。`com.yourcompany` 也只是文档示例，应使用你有权使用且在开发者账号中唯一的标识。两端 Team 必须一致。

项目使用现代单 target Watch App，不需要另建传统 WatchKit Extension。Watch 配置包括：

- `WKApplication = YES`。
- `WKRunsIndependentlyOfCompanionApp = YES`，表示能独立运行，不代表必须另建一个商店产品。
- `WKCompanionAppBundleIdentifier` 指向 iPhone App。
- HealthKit entitlement 与 Capability，仅在实际使用健康 API 的 Watch target 开启。
- Watch 的 `WKBackgroundModes` 包含 `workout-processing`。
- 健康读取、健康写入、运动访问的中文用途说明，分别对应 `NSHealthShareUsageDescription`、`NSHealthUpdateUsageDescription`、`NSMotionUsageDescription`。

分别选择两个 target → Signing & Capabilities → 勾选 Automatically manage signing → 选择 Team。第一次 Xcode 可能创建相应 App ID 与开发描述文件。若使用手工签名，需为两个 Bundle ID 分别生成支持正确 entitlement 的描述文件。

检查 HealthKit 能力在开发者后台与签名描述文件中一致。不要无故开启 Clinical Health Records、后台健康数据投递或 App Groups；本项目不依赖这些能力。WatchConnectivity 不要求建设服务器或共用 App Group。

**常见签名故障：**

| 提示／现象 | 排查方法 |
| --- | --- |
| Bundle identifier unavailable | 换成自己唯一的完整 Bundle ID，并一起更新 companion 配置 |
| Provisioning profile doesn't include HealthKit | 检查 Watch App ID 能力，重新生成／下载描述文件 |
| Watch companion mismatch | 比对 Watch 的 companion 标识与最终 iOS Bundle ID，检查大小写 |
| Watch 设备不可选择 | 检查系统/Xcode 兼容、配对、Developer Mode 和平台组件安装 |
| 免费 Team 无法使用需要的能力 | 使用具备相应能力的付费开发者 Team，核对 Apple 账号限制 |

## 4. 真机安装并完成验收

用 `RepFlow` scheme 安装至 iPhone，再用 `RepFlowWatch` scheme 运行至配对 Watch。然后验证 Watch 可在 iPhone 不在身边时直接启动、建计划和训练。安装与初次配对仍受 Apple 设备设置流程约束。

完整填写 [DEVICE_TEST_PLAN.md](DEVICE_TEST_PLAN.md)。首版至少放行以下行为：

- 正常结束仅生成一条本地记录，确认过的组数、次数和重量正确。
- 拒绝健康权限仍可手动训练；权限部分允许或无心率时不崩溃、不显示伪造的零值。
- 完成组、休息、暂停、恢复、切换动作、结束和异常退出后的草稿符合说明。
- 两端离线编辑、重新连接、删除记录和清空数据的结果可解释且没有意外复活。
- 卧推、宽窄下拉、宽窄划船、肩部训练和深蹲均做真实计数对照；误差明显的动作使用手动默认或收窄辅助功能范围。
- 熄屏、抬腕、低电量、长休息、来电等真实场景不丢失已确认组。

此处不能以单元测试代替实测。未获得真实误差证据时，商店和 App 内必须保留「实验性腕部估算、每组核对校正」说明；如果效果不足以完成所宣称功能，应先改为手动默认并修复后再送审。

## 5. 准备公开支持页与隐私政策

把 [PRIVACY_POLICY.md](PRIVACY_POLICY.md) 中的占位符替换成真实运营主体、生效日期、联系邮箱和公开网页 URL，并发布到你控制的 HTTPS 页面。这个仓库里的 Markdown 文件不是自动存在的公网网页。

支持页至少包含：App 名称、设备要求、常见问题、联系方式、隐私政策链接。无需让用户登录即可访问。通过未登录浏览器检查链接可用。

App 内的隐私说明必须与公开政策一致。如果上架版本增加 URL，检查能正常打开；如果计划添加崩溃 SDK、分析 SDK、服务器、云同步或付费功能，先更新政策与 App Privacy 申报，不能继续照搬当前「无数据收集」结论。

根据 Apple [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)，仅在设备上处理而不向开发者／合作方服务器发送的数据不属于其定义中的收集。本版无服务器与第三方 SDK，HealthKit 和配对设备同步不会向开发者交付数据，因此 **Data Not Collected 是供最终核查的候选答案**。请逐项检查最终二进制与 SDK，而不是仅凭本教程勾选。用户主动分享导出文件的实际接收方也应在隐私政策中解释。

`PrivacyInfo.xcprivacy` 与商店隐私标签不是同一件事。确认两个 target 的归档中包含需要的隐私清单，Required Reason API 的 reason 与真实调用一致。若加入 SDK，按 Apple 规则合并其清单并审核，不能为消除警告随便填写理由代码。

## 6. 创建 App Store Connect 记录

在 [App Store Connect](https://appstoreconnect.apple.com/) → My Apps → `+` → New App：

1. 平台选择 iOS，主语言选择简体中文，名称可用时填写「组迹 RepFlow」。SKU 使用内部唯一值，例如 `repflow-ios-001`。
2. Bundle ID 选择自己的 **iPhone App 标识**，不是 Watch 的 `.watchkitapp` 标识。
3. 该 iOS App 记录包括随包分发的 Watch App；不需要因为 Watch 独立运行再建一个重复产品。按[添加 watchOS 信息](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-watchos-app-information/)填写 Apple Watch 区域。
4. 类别可选 Health & Fitness / 健康健美；年龄分级、医疗器械状态、内容权利等问卷按最终实际功能填写，不在没有依据时自行宣称器械认证或最低年龄等级。
5. 填写支持 URL、隐私政策 URL、联系信息；逐项提交 App Privacy。
6. 设置价格与可售地区。本版无内购；免费或付费由实际商业计划决定，付费时完成对应协议、税务和银行信息。

面向欧盟分发，按 [DSA trader 要求](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)完成交易者状态与所需联系资料。面向中国大陆，核对 App Information 中的合规字段及适用的 ICP 备案要求；Apple 指出部分 App 需要备案且元数据应与备案资料一致。不要自行推断「无后端」必然免除要求。参考[App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)和后台提示。

## 7. 图标、截图与商店文案

项目包含图标资源，但应确认你拥有最终品牌、图形和名称的使用权；在 Xcode 的 AppIcon 资源目录与归档校验中检查所有所需尺寸。

使用真实运行的 App 截图。iPhone + Watch 产品应分别提供 Apple 要求的 iPhone 与 Apple Watch 截图；具体尺寸和必需设备组以[截图规格](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)及当前后台校验为准。不要把网页概念稿或模拟数据画面包装成已经真机验证的功能证据。

建议截图顺序：

1. Watch 训练页：当前动作、组序号、次数、加减校正。
2. Watch 组间休息和手动开始下一组。
3. iPhone 计划编辑：宽窄变式、组次与重量。
4. iPhone 自动编排预览。
5. iPhone 训练详情与完成度。

截图避免真实个人健康记录，使用可解释的测试记录。文案可从 [APP_STORE_METADATA.md](APP_STORE_METADATA.md)复制后按成品修改。辅助计次说明要明显，不能在主标题承诺精准而把限制藏在审核备注中。

## 8. 归档、校验与上传

确认版本号和构建号；同一次发布包的 iOS 与 Watch 版本保持一致，每次重新上传递增构建号。在 `project.yml` 中更新设置并重新生成，避免两处不一致。

Xcode 中选择 **RepFlow scheme**，目标选择 **Any iOS Device / generic iOS device**，Configuration 使用 Release，然后 Product → Archive。它应归档 iPhone App 及嵌入的 Watch App。不要把模拟器构建当作可提交归档。

命令行等价示例（签名已在本机配置）：

```bash
xcodebuild -project RepFlow.xcodeproj -scheme RepFlow -configuration Release -destination 'generic/platform=iOS' -archivePath build/RepFlow.xcarchive archive
```

在 Organizer 中选择归档 → Validate App。核对错误／警告，特别是嵌入 Watch、Bundle ID、版本号、图标、隐私目的说明、隐私清单和签名能力。通过后用 Distribute App → App Store Connect → Upload 上传。处理完成后才会在后台显示可选构建。

出口合规根据代码实际使用的加密回答。本版未实现自有加密，但使用系统安全能力，不能笼统理解为「无网络就不存在加密」。按[出口合规指南](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)确认是否属于豁免；只有符合条件才填写对应 `ITSAppUsesNonExemptEncryption` 值，新增加密库后重新评估。

## 9. TestFlight

先创建内部测试组并分发已处理构建；外部测试按 Apple 当前要求填写 Beta App Review 信息并等待所需审核。参考 [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)。

重点让测试者用自己的真实手表和真实器械记录误差，并使用「实际次数／显示次数／修正后次数」记录表反馈。TestFlight 不能只由开发者在一台模拟器点通。

在新的安装状态测试权限；从上一构建升级测试计划、历史和草稿保留。检查 Watch 独立使用、配对同步、HealthKit 保存与清除语义。完成修复后递增 build，再跑受影响项。

## 10. 提交审核与上线

1. 创建 App Store 版本，选择已完成 TestFlight 验证的构建。
2. 填写所有元数据、截图、隐私与合规内容。
3. 在 Review Information 填写真实联系信息。不需要登录账号，注明核心训练入口在 Watch；附清晰操作步骤和实验性计次限制，可参考文案模板。
4. 选择合适发布方式。首次发布建议审核通过后手动发布，便于最后检查公开支持页和资料。
5. Add for Review / Submit for Review。后台按钮名称可能调整，按当前界面完成。

审核关注功能完整、权限用途、真实截图、HealthKit 适当使用及准确性宣称。Apple [审核指南 5.1.3](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research)限制健康／健身数据的广告和数据挖掘使用；本版不提供这些用途。不要编写无法证明的计次准确率、医学结论或自动识别能力。

被拒时逐条回应实际问题，提交说明或新构建，不要仅反复提交同一问题版本。获批并发布后，用普通 App Store 下载路径再次验证安装、Watch 安装与公开资料。

## 11. 发布完成的交接证据

维护一份发布记录，至少包括：Git commit、版本与 build、Xcode/SDK 版本、两个 Bundle ID、测试设备与系统、真机验收表、TestFlight 构建、公开支持／隐私 URL、审核结果和上线 URL。不要记录证书私钥、App Store Connect API 密钥或用户健康数据。

如果只有源码和核心测试结果，而缺少平台构建或真机证据，状态应写为「待 Mac 构建／待真机验收」，不应写为「可直接上架」或「已发布」。

## 官方参考（2026-10-07 核验）

- [上传版本与 SDK 要求](https://developer.apple.com/news/upcoming-requirements/)
- [Apple Developer 账号与会员](https://developer.apple.com/support/compare-memberships/)
- [独立 watchOS App](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps)
- [配置 HealthKit](https://developer.apple.com/documentation/healthkit/setting-up-healthkit)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) / [管理 App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [新建 App 记录](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/) / [watchOS 元数据](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-watchos-app-information/)
- [截图规格](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)
- [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [出口加密申报](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/)
- [欧盟 DSA](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) / [地区及 App 信息字段](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
