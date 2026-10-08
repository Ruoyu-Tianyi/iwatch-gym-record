# 只有 Windows、iPhone 和 Apple Watch 时继续开发组迹

Windows 可以编辑源码、通过浏览器管理 GitHub 和 Apple 账号。GitHub Actions 的 macOS 云端机器负责 Xcode 编译。真机分发使用 TestFlight，需要付费 Apple Developer Program 会员。无需先购买 Mac。

项目仓库：[iwatch-gym-record](https://github.com/Ruoyu-Tianyi/iwatch-gym-record)。

## 现在先完成免费构建阶段

1. 源码上传后，打开仓库的 [Actions 构建页面](https://github.com/Ruoyu-Tianyi/iwatch-gym-record/actions/workflows/apple.yml)。首次 push 自动启动；以后也可点击 **Run workflow**。
2. 构建会选择 Xcode 26+，生成工程、运行核心与同步测试，并实际编译 iPhone / Watch App。
3. 点击一次运行查看每个步骤。页面底部的 `RepFlow-Apple-数字` artifact 包含构建日志、Xcode 结果和可用模拟器截图。Windows 浏览器即可下载。
4. 构建成功后再推进会员和 TestFlight 配置。模拟器输出验证代码与界面，无法直接安装到 iPhone / Apple Watch。

GitHub 的公开仓库使用标准 hosted runners 通常无需消耗私有仓库分钟数；私有仓库受账号套餐分钟数限制，macOS 用量按 GitHub 当前计费规则计算。超出额度时应先看 Actions 的账单提示，确认后再购买额度。工作流设有超时和并发取消，减少重复构建。

## 如果聊天连接无法上传新仓库

推送出现 `403` 时，在 [GitHub App 设置](https://github.com/settings/installations)找到与 ChatGPT / Codex 对应的连接，Configure → Repository access → 加入 `iwatch-gym-record`。授权刷新后可以继续由聊天助手上传。

如果该连接不提供写入能力，可在自己的 Windows 上登录 GitHub CLI，脚本使用你本人的授权完成上传：

1. 下载新版项目 ZIP 并解压。
2. 在解压得到的 `RepFlow` 文件夹打开 PowerShell。
3. 执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\continue-windows.ps1 -InstallTools
```

脚本安装官方 Git / GitHub CLI，打开浏览器登录；上传到空仓库后自动触发构建。若仓库已有源码，它只触发工作流，不覆盖远端文件。已有工具时可去掉 `-InstallTools`。下载脚本应先检查来源；本命令只为这一进程调整脚本执行策略。

## 注册会员并准备网页资料

在 [Apple Developer 注册入口](https://developer.apple.com/programs/enroll/)按你的国家／地区、个人或组织身份办理。可使用 Windows 浏览器和 iPhone 上的 Apple Developer App 完成 Apple 支持的注册流程；付费和身份核验需要你自己完成。价格以 Apple 当地页面为准。

会员激活后，通过网页完成：

1. 在 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) 注册 iPhone App ID，例如 `com.ruoyutianyi.RepFlow`。
2. 注册 Watch App ID `com.ruoyutianyi.RepFlow.watchkitapp`，为 Watch ID 启用 **HealthKit**。两个 ID 必须与你自己的实际注册结果一致。
3. 在 [App Store Connect](https://appstoreconnect.apple.com/)创建 iOS App，选择上述 iPhone Bundle ID；Watch App 随 iPhone 包提交。
4. 记录 Developer 的 **Team ID**。不要把它与 API 的 **Issuer ID** 混淆。
5. App Store Connect → Users and Access → Integrations → App Store Connect API 中，申请团队 API 访问并生成具有 **Admin** 权限的团队 API Key。此流程需要访问证书、描述文件和构建上传；普通只读密钥不适用。下载一次 `.p8`，保存在自己的安全位置，并记录 Key ID / Issuer ID。

## 配置一次无 Mac 签名流程

当前流水线把加密签名材料保存在**同一私有仓库的 `signing` 分支**，因此启用发布前请在仓库 Settings → General → Danger Zone 将仓库设为 Private。保持公开源码时，应另建私有签名仓库并调整实现；本版脚本会阻止在公开仓库生成签名材料。

在 Windows PowerShell 执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-testflight-windows.ps1
```

脚本询问网页获得的值和 `.p8` 路径，写入你自己的 GitHub 仓库设置。**不要把私钥、证书密码或登录密码粘贴到聊天、提交到代码或上传为公开文件。** match 加密密码要先保存到你的密码管理器；GitHub Secrets 无法读回原值。

| GitHub 设置 | 字段 | 用途 |
| --- | --- | --- |
| Actions Variables | `APPLE_TEAM_ID` | Developer Team ID |
| Actions Variables | `APP_BUNDLE_ID` | 自己注册的 iPhone ID；Watch ID 自动追加 `.watchkitapp` |
| Actions Variables | `APP_VERSION` | 商店版本，默认 `1.0.0` |
| Actions Secrets | `ASC_KEY_ID` / `ASC_ISSUER_ID` | API Key 的身份字段 |
| Actions Secrets | `ASC_API_KEY_P8` | `.p8` 完整内容 |
| Actions Secrets | `MATCH_PASSWORD` | 私有签名分支的加密密码 |

若 Actions 提示无法写 `signing` 分支，在 Settings → Actions → General 检查组织／仓库允许工作流使用所需写权限。`testflight.yml` 显式请求 `contents: write`，只通过手动 Run workflow 启动。对源代码与发布工作流的修改，应只授予可信开发者；能改工作流的人可能访问发布 Secrets。

## 一键生成并上传 TestFlight

打开 [Upload to TestFlight](https://github.com/Ruoyu-Tianyi/iwatch-gym-record/actions/workflows/testflight.yml)，点 **Run workflow**。

云端自动完成：检查配置和私有属性 → 更新两个 Bundle ID／Team／版本 → 初始化签名分支 → fastlane match 创建或复用 Apple Distribution 证书与两个 App Store 描述文件 → 加密保存签名材料 → 归档带 Watch 的 iPhone App → 上传 TestFlight。以后复用签名材料，避免每次重建证书。

该流程需要已注册的 App IDs、启用 HealthKit 的 Watch ID、存在的 App Store Connect App、有效 API 权限和会员。首轮签名尚需真实凭据验证；工作流成功上传也不等于 Apple 已完成处理或审核。

## 从 iPhone 安装到手表

1. 等待 App Store Connect → TestFlight 完成构建处理。
2. 在 App Store Connect 添加自己为内部测试用户，将已处理构建加入内部测试组。内部测试资格需要对应 App Store Connect 角色与 App 访问权；本人作为账号所有者可配置。
3. iPhone 安装 Apple 的 **TestFlight**，用测试账号接受邀请并安装组迹。
4. 确认 Watch 与 iPhone 配对正常，在 iPhone 的 Watch App 管理组迹安装；根据 TestFlight／当前 watchOS 提示安装对应 Watch 测试版本。
5. 先核对权限、组数保存、离线同步和手动计次，再按[真机验收表](DEVICE_TEST_PLAN.md)测量辅助计次误差。

TestFlight 构建通常有 90 天测试有效期；到期前用发布工作流上传新构建。外部测试按 Apple 要求进行 Beta App Review，正式商店上线还要按[上架教程](APP_STORE_RELEASE.md)准备元数据、隐私政策、截图和审核资料。

## 官方参考

- [GitHub hosted runners 与收费](https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions)
- [GitHub Actions artifacts](https://docs.github.com/en/actions/managing-workflow-runs/downloading-workflow-artifacts)
- [Apple Developer 注册](https://developer.apple.com/programs/enroll/)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [fastlane match](https://docs.fastlane.tools/actions/match/)
- [TestFlight 概览](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

更新日期：2026-10-08。签名与真机测试的状态以实际 CI 和设备记录为准。
