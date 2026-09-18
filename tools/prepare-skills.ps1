<#
.SYNOPSIS
skills 发布过滤：按白名单核对/同步仓库 skills 目录，防止混入非嵌入式流程技能
.DESCRIPTION
仓库 skills/ 只允许 skills-whitelist.json 列出的嵌入式开发流程技能。
用法（在仓库根目录）：
  .\tools\prepare-skills.ps1 -Check     # 核对仓库 skills 与白名单是否一致（发布前必跑）
  .\tools\prepare-skills.ps1 -Sync      # 从本机 ~\.trae-cn\skills 按白名单同步到仓库（-Force 覆盖同名）
  .\tools\prepare-skills.ps1 -Init      # 从当前仓库 skills 目录生成/更新白名单（新增技能后跑一次）
说明：
  - Check 发现白名单外技能 → 列出并退出码 1（阻止发布）
  - Sync 只复制白名单内的技能，天然排除 cangjie 蒸馏 / 平台技能 / 通用工具
  - 白名单文件：tools\skills-whitelist.json（纯 JSON，维护时只增删技能名）
  version: 1.0.0
#>
[CmdletBinding()]
param(
    [switch]$Check,     # 核对仓库 skills 与白名单（不写文件）
    [switch]$Sync,      # 从本机技能目录按白名单同步到仓库 skills\
    [switch]$Init,      # 用仓库当前 skills\ 目录重建白名单（新增技能后使用）
    [switch]$Force      # Sync 时覆盖仓库已存在技能
)

$ErrorActionPreference = 'Stop'
$repo_root = Split-Path $PSScriptRoot -Parent
$skills_dir = Join-Path $repo_root 'skills'
$wl_file    = Join-Path $repo_root 'tools\skills-whitelist.json'
$local_skills = Join-Path $env:USERPROFILE '.trae-cn\skills'

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-OK($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "    [!!] $m" -ForegroundColor Yellow }

if (-not (Test-Path $skills_dir)) { throw "未找到 skills 目录: $skills_dir" }
if (-not (Test-Path $wl_file))    { throw "未找到白名单: $wl_file" }

$wl = (Get-Content $wl_file -Raw | ConvertFrom-Json).skills
$wl_set = @{}; foreach ($s in $wl) { $wl_set[$s] = $true }

# ---------- -Check ----------
if ($Check) {
    Write-Step "核对仓库 skills 与白名单（白名单 $($wl.Count) 个）"
    $present = @(Get-ChildItem $skills_dir -Directory | Select-Object -ExpandProperty Name)
    $outside = @($present | Where-Object { -not $wl_set.ContainsKey($_) })
    $missing = @($wl | Where-Object { $_ -notin $present })

    if ($outside.Count -eq 0 -and $missing.Count -eq 0) {
        Write-OK "一致：仓库 skills 共 $($present.Count) 个，全部在白名单内"
        Write-OK "可以发布"
        exit 0
    }
    if ($outside.Count -gt 0) {
        Write-Warn "发现 $($outside.Count) 个白名单外技能（混入风险）："
        $outside | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    }
    if ($missing.Count -gt 0) {
        Write-Warn "$($missing.Count) 个白名单技能仓库缺失："
        $missing | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    }
    Write-Warn "处理：白名单外技能请删除；缺失技能请 -Sync 拉取；然后重跑 -Check"
    exit 1
}

# ---------- -Init ----------
if ($Init) {
    Write-Step "从仓库 skills\ 重建白名单"
    $names = @(Get-ChildItem $skills_dir -Directory | Select-Object -ExpandProperty Name | Sort-Object)
    $obj = [ordered]@{ skills = $names }
    $json = $obj | ConvertTo-Json
    [IO.File]::WriteAllText($wl_file, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-OK "白名单已重建：$($names.Count) 个技能 -> tools\skills-whitelist.json"
    Write-Warn "确认白名单剔除了非嵌入式流程技能后再提交"
    exit 0
}

# ---------- -Sync ----------
if ($Sync) {
    Write-Step "从本机技能目录按白名单同步到仓库 skills\"
    if (-not (Test-Path $local_skills)) { throw "本机技能目录不存在: $local_skills" }

    $added = 0; $skipped = 0; $missing_local = @()
    foreach ($s in $wl) {
        $src = Join-Path $local_skills $s
        $dst = Join-Path $skills_dir $s
        if (-not (Test-Path $src)) {
            $missing_local += $s
            continue
        }
        if (Test-Path $dst) {
            if ($Force) {
                Remove-Item $dst -Recurse -Force
                Copy-Item $src $dst -Recurse -Force
                $added++
                Write-OK "已覆盖: $s"
            } else {
                $skipped++
            }
        } else {
            Copy-Item $src $dst -Recurse -Force
            $added++
            Write-OK "已新增: $s"
        }
    }
    Write-OK "新增/覆盖 $added 个，跳过 $skipped 个（同名，用 -Force 覆盖）"
    if ($missing_local.Count -gt 0) {
        Write-Warn "本机缺失 $($missing_local.Count) 个白名单技能：$($missing_local -join ', ')"
    }
    Write-Warn "提示：-Sync 只同步白名单；若本机有非白名单技能要剔除，请从仓库 skills\ 手动删除"
    exit 0
}

Write-Host "用法：-Check | -Sync | -Init（见脚本头注释）" -ForegroundColor Yellow
exit 1