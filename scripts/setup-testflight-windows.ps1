param([string]$Repository = "Ruoyu-Tianyi/iwatch-gym-record")
$ErrorActionPreference = "Stop"
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw "仓库格式应为 owner/repo。" }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "请先运行 continue-windows.ps1 安装并登录 GitHub CLI。" }
$repoJson = & gh repo view $Repository --json isPrivate
if ($LASTEXITCODE -ne 0) { throw "无法访问仓库。" }
if (-not ($repoJson | ConvertFrom-Json).isPrivate) { throw "请先在仓库 Settings > General > Danger Zone 改为 Private。签名材料使用私有仓库。" }

Write-Host "请先完成付费 Apple Developer 注册，注册两个 App ID，并创建 App Store Connect App 和 Admin 团队 API Key。"
Write-Host "凭据只会发送到你自己的 GitHub Actions Secrets，请不要在聊天中提供它们。"
$team = Read-Host "Apple Developer Team ID（10 位）"
$bundle = Read-Host "已注册的 iPhone Bundle ID（例如 com.ruoyutianyi.RepFlow）"
$keyId = Read-Host "App Store Connect Key ID"
$issuerId = Read-Host "App Store Connect Issuer ID"
$keyPath = (Read-Host "已下载的 AuthKey_xxx.p8 文件完整路径").Trim('"')
if ($team -notmatch '^[A-Z0-9]{10}$') { throw "Team ID 格式错误。" }
if ($bundle -notmatch '^[A-Za-z0-9]+(\.[A-Za-z0-9-]+){2,}$' -or $bundle.StartsWith("com.example.")) { throw "请输入自己已注册的 Bundle ID。" }
if ($keyId -notmatch '^[A-Za-z0-9]+$' -or $issuerId -notmatch '^[A-Fa-f0-9-]{36}$') { throw "API Key ID / Issuer ID 格式错误。" }
if (-not (Test-Path $keyPath -PathType Leaf)) { throw "找不到 .p8 文件。" }
$privateKey = Get-Content -Raw -LiteralPath $keyPath
if ($privateKey -notmatch '-----BEGIN PRIVATE KEY-----') { throw "文件不是 App Store Connect 私钥。" }
$securePassword = Read-Host "match 签名库加密密码（至少 20 字符；先保存到你的密码管理器）" -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    if ($passwordText.Length -lt 20) { throw "请使用至少 20 字符的签名库加密密码。" }
    foreach ($item in @(
        @{ Name = "APPLE_TEAM_ID"; Value = $team },
        @{ Name = "APP_BUNDLE_ID"; Value = $bundle },
        @{ Name = "APP_VERSION"; Value = "1.0.0" }
    )) {
        & gh variable set $item.Name --repo $Repository --body $item.Value
        if ($LASTEXITCODE -ne 0) { throw "保存变量 $($item.Name) 失败。" }
    }
    foreach ($item in @(
        @{ Name = "ASC_KEY_ID"; Value = $keyId },
        @{ Name = "ASC_ISSUER_ID"; Value = $issuerId },
        @{ Name = "ASC_API_KEY_P8"; Value = $privateKey },
        @{ Name = "MATCH_PASSWORD"; Value = $passwordText }
    )) {
        $item.Value | & gh secret set $item.Name --repo $Repository
        if ($LASTEXITCODE -ne 0) { throw "保存 Secret $($item.Name) 失败。" }
    }
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    $passwordText = $null
    $privateKey = $null
}
Write-Host "配置完成。接下来在浏览器手动点击 Upload to TestFlight > Run workflow。"
Start-Process "https://github.com/$Repository/actions/workflows/testflight.yml"
