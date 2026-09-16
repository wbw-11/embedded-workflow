<#
.SYNOPSIS
embedded-workflow 一键部署：部署 skills + tools 加入 PATH + 首次验证
.DESCRIPTION
clone 本仓库后在根目录运行，自动完成：
  1. 复制 skills/ 到 TRAE 技能目录（.trae-cn\skills），自动发现
  2. 将 tools/ 加入用户 PATH（脚本名即命令名）
  3. 运行首次验证（tool-guide / version-tools -Validate / check-bom）
说明：
  - 脚本自定位（$PSScriptRoot），任意路径 clone 均可运行，零硬编码
  - 重复执行安全（幂等）：skills 已有同名目录则跳过，PATH 已有则不重复加
.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\install.ps1
  version: 1.0.0
#>
[CmdletBinding()]
param(
    [switch]$NoPath,   # 跳过 PATH 修改（仅部署 skills + 验证）
    [switch]$Force     # 覆盖已存在的同名 skill 目录（默认跳过）
)

$ErrorActionPreference = 'Stop'
$repo_root = $PSScriptRoot
$skills_src = Join-Path $repo_root 'skills'
$tools_src  = Join-Path $repo_root 'tools'
$trae_home  = Join-Path $env:USERPROFILE '.trae-cn'
$skills_dst = Join-Path $trae_home 'skills'

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "    [!!] $msg" -ForegroundColor Yellow }

# ---------- 0. 环境检查 ----------
Write-Step '环境检查'
if (-not (Test-Path $skills_src)) { throw "未找到 skills 目录: $skills_src（请在仓库根目录运行本脚本）" }
if (-not (Test-Path $tools_src))  { throw "未找到 tools 目录: $tools_src" }
$ps_major = $PSVersionTable.PSVersion.Major
if ($ps_major -lt 5) { throw "需要 PowerShell 5.1+，当前 $($PSVersionTable.PSVersion)" }
Write-OK "PowerShell $($PSVersionTable.PSVersion)"
Write-OK "仓库: $repo_root"

# ---------- 1. 部署 skills ----------
Write-Step "部署 skills → $skills_dst"
if (-not (Test-Path $skills_dst)) { New-Item -ItemType Directory -Path $skills_dst -Force | Out-Null }

$deployed = 0; $skipped = 0
Get-ChildItem -Path $skills_src -Directory | ForEach-Object {
    $dst_skill = Join-Path $skills_dst $_.Name
    if (Test-Path $dst_skill) {
        if ($Force) {
            Remove-Item $dst_skill -Recurse -Force
            Copy-Item $_.FullName $dst_skill -Recurse -Force
            $deployed++
        } else {
            $skipped++
        }
    } else {
        Copy-Item $_.FullName $dst_skill -Recurse -Force
        $deployed++
    }
}
$skill_count = (Get-ChildItem $skills_dst -Directory).Count
Write-OK "已部署 $deployed 个技能，跳过 $skipped 个（同名，用 -Force 覆盖），当前技能目录共 $skill_count 个"
Write-Warn '提示：若 TRAE 正在运行，重启后技能才会被自动发现'

# ---------- 2. 加入用户 PATH ----------
if ($NoPath) {
    Write-Warn '已跳过 PATH 修改（-NoPath），工具请手动使用 tools\ 全路径调用'
} else {
    Write-Step '将 tools/ 加入用户 PATH'
    $user_path = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($user_path -split ';' | Where-Object { $_ -eq $tools_src }) {
        Write-OK "PATH 已包含 $tools_src"
    } else {
        [Environment]::SetEnvironmentVariable('Path', "$user_path;$tools_src", 'User')
        Write-OK "已追加（当前终端需重启后才生效）: $tools_src"
    }
}

# ---------- 3. 首次验证 ----------
Write-Step '首次验证'
$verify_cmds = @(
    @{ Name = 'tool-guide';            Args = @() },
    @{ Name = 'version-tools';         Args = @('-Validate') },
    @{ Name = 'check-bom';             Args = @('-Quiet') }
)
$fail = 0
foreach ($cmd in $verify_cmds) {
    $script = Join-Path $tools_src ($cmd.Name + '.ps1')
    # 子进程方式调用：脚本内 exit 码经 $LASTEXITCODE 可靠传递（& 变量调用会丢失）
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script @($cmd.Args) 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "$($cmd.Name) $($cmd.Args -join ' ') → PASS"
    } else {
        Write-Warn "$($cmd.Name) $($cmd.Args -join ' ') → 失败(exit $LASTEXITCODE)"
        $fail++
    }
}

# ---------- 4. 总结 ----------
Write-Host "`n========== 部署完成 ==========" -ForegroundColor Cyan
Write-Host "  skills : $skill_count 个 → $skills_dst"
Write-Host "  tools  : $tools_src" -NoNewline
if ($NoPath) { Write-Host "（未加 PATH）" } else { Write-Host "（已加 PATH，重开终端生效）" }
Write-Host "  验证   : " -NoNewline
if ($fail -eq 0) { Write-Host "3/3 PASS，部署成功" -ForegroundColor Green }
else             { Write-Host "$fail/3 未通过，见上方提示" -ForegroundColor Yellow }
Write-Host "  下一步 : 打开 TRAE（重启），对 AI 说「帮我开新项目」，即走四步准备流程"
Write-Host "============================" -ForegroundColor Cyan

exit $fail
