# 在 Windows 启动组迹云端构建

你的仓库已经创建：[Ruoyu-Tianyi/iwatch-gym-record](https://github.com/Ruoyu-Tianyi/iwatch-gym-record)。源码与自动化流程已于 2026-10-08 上传，首次 macOS 云端构建全部通过。下面的脚本可用于后续手动触发构建。

## 第一次操作

1. 完整解压 ZIP，进入里面的 `RepFlow` 文件夹。
2. 在文件资源管理器地址栏输入 `powershell`，回车。
3. 粘贴执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\continue-windows.ps1 -InstallTools
```

按提示安装官方 Git / GitHub CLI，在弹出的浏览器中登录你自己的 GitHub 账号。脚本会将源码上传到空仓库，启动 macOS 云端编译，并打开构建网页。

如果安装完工具后仍提示找不到 `git` 或 `gh`，关闭 PowerShell，重新打开，再执行同一命令。没有 `winget` 时，从 [Git 官网](https://git-scm.com/download/win) 和 [GitHub CLI 官网](https://cli.github.com/)安装，然后去掉命令中的 `-InstallTools`。

## 查看运行结果

打开 [Actions 构建页面](https://github.com/Ruoyu-Tianyi/iwatch-gym-record/actions/workflows/apple.yml)，点击一次运行。绿色表示本次流程通过；失败时进入红色步骤查看具体日志。

页面底部的 `RepFlow-Apple-数字` 下载包提供构建日志、Xcode 结果及可用模拟器截图。可把失败步骤的日志发回聊天继续修复。现有源码仓库再次运行上述脚本会触发构建，不会用旧 ZIP 覆盖仓库。

如果上传提示缺少 workflow scope：

```powershell
gh auth refresh --hostname github.com --scopes workflow
```

按浏览器提示补充权限，再运行上传脚本。上传中断时可以重跑；脚本不会使用 force push。

## 安装到 iPhone 和 Apple Watch

当前没有付费 Apple Developer 会员，可以先完成云端编译与截图检查。通过 TestFlight 安装到真机时，需要你自行注册并激活会员；购买和身份核验无法由源码脚本代办。

会员激活后，本包提供 `setup-testflight-windows.ps1` 和手动触发的 `Upload to TestFlight` 工作流。它们使用云端签名，避免要求你在 Mac 上手工导出证书。一次性网页配置、Secrets 设置、手机与手表安装步骤见[完整 Windows 教程](docs/WINDOWS_CLOUD_GUIDE.md)。

签名配置前需将仓库设为 Private。不要把 `.p8`、证书密码或其他凭据上传到聊天或源码。当前已通过实际 macOS 云端构建，尚未执行 TestFlight 上传，脚本、工作流配置及源码验证结果见[验证记录](docs/VERIFICATION.md)。

