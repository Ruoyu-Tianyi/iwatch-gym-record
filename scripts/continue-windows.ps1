param(
    [string]$Repository = "Ruoyu-Tianyi/iwatch-gym-record",
    [switch]$InstallTools
)
$ErrorActionPreference = "Stop"
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw "仓库格式应为 owner/repo。" }
Set-Location (Split-Path $PSScriptRoot -Parent)

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program 执行失败。请查看上方错误。" }
}
if ($InstallTools) {
    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        throw "缺少 winget。请从 git-scm.com 和 cli.github.com 安装 Git 与 GitHub CLI 后重新运行。"
    }
    if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
        Invoke-Checked -Program "winget" -Arguments @("install", "--id", "Git.Git", "-e", "--source", "winget")
    }
    if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
        Invoke-Checked -Program "winget" -Arguments @("install", "--id", "GitHub.cli", "-e", "--source", "winget")
    }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
}
foreach ($tool in @("git", "gh")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "缺少 $tool。请重新运行脚本并加 -InstallTools，或从官方安装 Git 与 GitHub CLI。"
    }
}
& gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-Checked -Program "gh" -Arguments @("auth", "login", "--hostname", "github.com", "--web", "--git-protocol", "https", "--scopes", "repo,workflow")
}
$repoJson = & gh repo view $Repository --json isEmpty,isPrivate,url
if ($LASTEXITCODE -ne 0) { throw "无法访问仓库。请确认登录了有写入权限的 GitHub 账号。" }
$repo = $repoJson | ConvertFrom-Json
if ($repo.isEmpty) {
    if (-not (Test-Path ".git")) {
        Invoke-Checked -Program "git" -Arguments @("init", "-b", "main")
    }
    $userJson = & gh api user
    if ($LASTEXITCODE -ne 0) { throw "无法读取 GitHub 账号。" }
    $user = $userJson | ConvertFrom-Json
    Invoke-Checked -Program "git" -Arguments @("config", "user.name", $user.login)
    Invoke-Checked -Program "git" -Arguments @("config", "user.email", "$($user.id)+$($user.login)@users.noreply.github.com")
    Invoke-Checked -Program "git" -Arguments @("config", "credential.https://github.com.helper", "!gh auth git-credential")
    Invoke-Checked -Program "git" -Arguments @("add", ".")
    foreach ($script in Get-ChildItem "scripts" -Filter "*.sh") {
        Invoke-Checked -Program "git" -Arguments @("update-index", "--chmod=+x", "--", "scripts/$($script.Name)")
    }
    & git diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        Invoke-Checked -Program "git" -Arguments @("commit", "-m", "Deliver RepFlow apps and cloud build automation")
    } elseif ($LASTEXITCODE -ne 0) { throw "无法检查源码提交。" }
    $remotes = & git remote
    if ($remotes -contains "origin") {
        Invoke-Checked -Program "git" -Arguments @("remote", "set-url", "origin", "https://github.com/$Repository.git")
    } else {
        Invoke-Checked -Program "git" -Arguments @("remote", "add", "origin", "https://github.com/$Repository.git")
    }
    Invoke-Checked -Program "git" -Arguments @("push", "-u", "origin", "HEAD:main")
    Write-Host "源码已上传，push 会自动启动 macOS 构建。"
} else {
    # Existing repositories are never replaced by the downloaded source package.
    Invoke-Checked -Program "gh" -Arguments @("workflow", "run", "apple.yml", "--repo", $Repository)
    Write-Host "已启动现有源码的 macOS 云端构建。"
}
$url = "https://github.com/$Repository/actions/workflows/apple.yml"
Write-Host "构建结果、截图与日志：$url"
Start-Process $url
