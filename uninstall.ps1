<#
.SYNOPSIS
embedded-workflow 一键卸载：删除已部署技能 + 移除 PATH + 清理清单
.DESCRIPTION
与 install.ps1 配套的精准卸载：
  1. 删除本仓库 install.ps1 部署过的技能目录（只删清单中记录的，不碰用户原有技能）
  2. 从用户 PATH 移除 tools 目录
  3. 删除部署清单与记录目录
安全设计：
  - 清单缺失时拒绝盲删（提示先跑 install.ps1），-Scan 可改为按同名扫描删除（有风险）
  - install 时跳过未覆盖的同名技能（skipped）不会被删
.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -Scan   # 清单缺失时按同名扫描（谨慎）
  version: 1.0.0
#>
[CmdletBinding()]
param(
    [switch]$Scan,      # 清单缺失时按「仓库同名技能」扫描删除（可能误删用户自建同名技能）
    [switch]$Force      # 删除前不询问
)

$ErrorActionPreference = 'Stop'
$repo_root = $PSScriptRoot
$skills_src = Join-Path $repo_root 'skills'
$tools_src  = Join-Path $repo_root 'tools'
$trae_home  = Join-Path $env:USERPROFILE '.trae-cn'
$skills_dst = Join-Path $trae_home 'skills'
$record_dir = Join-Path $trae_home 'embedded-workflow'
$record_file = Join-Path $record_dir 'install.json'

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "    [!!] $msg" -ForegroundColor Yellow }

# ---------- 0. 加载清单 ----------
Write-Step '读取部署清单'
$record = $null
if (Test-Path $record_file) {
    try { $record = Get-Content $record_file -Raw | ConvertFrom-Json } catch { $record = $null }
}

if ($record) {
    Write-OK "清单: $($record.installed_at) @ $($record.repo_root)"
    $skip_list = @($record.skills_deployed) + @($record.skills_overwritten)  # 需删除的技能名
} else {
    Write-Warn "清单不存在: $record_file"
    if ($Scan) {
        Write-Warn '按 -Scan 模式：扫描仓库同名技能目录删除（可能误删用户自建同名技能）'
        $skip_list = @(Get-ChildItem $skills_src -Directory | ForEach-Object { $_.Name })
    } else {
        throw '无清单不卸载（安全策略）。若确实要删同名技能，请用 -Scan（有误删风险）'
    }
}

# ---------- 1. 删除技能 ----------
Write-Step '删除已部署技能'
$removed = 0
foreach ($name in $skip_list) {
    $dst = Join-Path $skills_dst $name
    if (Test-Path $dst) {
        Remove-Item $dst -Recurse -Force
        $removed++
        Write-OK "已删除技能: $name"
    } else {
        Write-Warn "技能已不存在（跳过）: $name"
    }
}
Write-OK "共删除 $removed 个技能目录"

# ---------- 2. 移除 PATH ----------
Write-Step '从用户 PATH 移除 tools'
$user_path = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($record -and -not $record.path_added) {
    Write-OK 'install 时未加过 PATH（跳过）'
} else {
    $new_path = @($user_path -split ';' | Where-Object { $_ -and ($_ -ne $tools_src) }) -join ';'
    if ($new_path -eq $user_path) {
        Write-OK "PATH 不含 $tools_src（无需处理）"
    } else {
        [Environment]::SetEnvironmentVariable('Path', $new_path, 'User')
        Write-OK "已移除（当前终端需重启后生效）: $tools_src"
    }
}

# ---------- 3. 清理清单 ----------
Write-Step '清理部署记录'
if (Test-Path $record_dir) {
    Remove-Item $record_dir -Recurse -Force
    Write-OK "已删除记录目录: $record_dir"
} else {
    Write-OK '记录目录不存在（无需清理）'
}

# ---------- 4. 总结 ----------
Write-Host "`n========== 卸载完成 ==========" -ForegroundColor Cyan
Write-Host "  已删除技能 : $removed 个"
Write-Host "  PATH       : 已还原（重开终端生效）"
Write-Host "  残留       : 无（如需彻底删除仓库文件夹，直接删除本目录即可）"
Write-Host "============================" -ForegroundColor Cyan

exit 0
