<#
.SYNOPSIS
  Tool usage guide - help choose the right tool
.DESCRIPTION
  When multiple tools have overlapping functions, this guide helps choose the best one
.EXAMPLE
  tool-guide                    # show all tool categories
  tool-guide -Category Flash    # show flash tools only
  tool-guide -Tool build-all    # show specific tool details
  version: 1.1.1
#>

param(
  [string]$Category,
  [string]$Tool
)

# 加载 tools_version.json 版本映射（{脚本名.ps1 -> version}）
$script:ToolVersions = @{}
$vtJsonPath = Join-Path $PSScriptRoot 'tools_version.json'
if (Test-Path $vtJsonPath) {
  try {
    $vt = Get-Content $vtJsonPath -Raw | ConvertFrom-Json
    foreach ($prop in $vt.PSObject.Properties) { $script:ToolVersions[$prop.Name] = $prop.Value.version }
  } catch {}
}

function Get-ToolVersionText {
  param([string]$ToolName)
  $key = "$ToolName.ps1"
  if ($script:ToolVersions.ContainsKey($key)) { return " v$($script:ToolVersions[$key])" }
  return ''
}

$catNames = @{
  ChipDetect = "芯片检测"
  ProjectInit = "项目初始化"
  BuildFlash = "构建与烧录"
  Debug = "调试与监控"
  Hardware = "硬件设计"
  CodeQuality = "代码质量"
  ProjectManage = "项目管理"
  SkillMaintain = "技能维护"
}

$toolCategories = [ordered]@{
  ChipDetect = @(
    [PSCustomObject]@{
      Name = "detect-chip"
      Primary = $true
      Description = "检测连接的芯片型号"
      Skill = "hardware-detection"
    }
  )
  ProjectInit = @(
    [PSCustomObject]@{
      Name = "switch-board"
      Primary = $true
      Description = "切换/查看当前板子配置"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "new-board-config"
      Primary = $false
      Description = "创建新板子配置"
      Skill = "project-init"
    }
    [PSCustomObject]@{
      Name = "preflight"
      Primary = $false
      Description = "开工预检（工程声明×工具链×硬件三查，判断能否直接开工）"
      Skill = $null
    }
  )
  BuildFlash = @(
    [PSCustomObject]@{
      Name = "build-all"
      Primary = $true
      Description = "通用构建（自动识别芯片类型）"
      Skill = $null
    }

    [PSCustomObject]@{
      Name = "dev-flow"
      Primary = $false
      Description = "开发闭环流水线（编译→时间戳→版本→烧录→核验→归档）"
      Skill = "keil-auto-flash"
    }
    [PSCustomObject]@{
      Name = "safe-flash"
      Primary = $true
      Description = "安全烧录（芯片类型验证）"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "esp-burn"
      Primary = $false
      Description = "ESP32 专用构建烧录"
      Skill = "esp-idf-build"
    }
    [PSCustomObject]@{
      Name = "keil-clean"
      Primary = $false
      Description = "清理 Keil 临时文件"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "esp-erase-flash"
      Primary = $false
      Description = "擦除 ESP32 Flash"
      Skill = $null
    }
  )
  Debug = @(
    [PSCustomObject]@{
      Name = "debug-board"
      Primary = $true
      Description = "通用调试入口"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "debug-esp32"
      Primary = $false
      Description = "ESP32 专用调试"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "esp-monitor"
      Primary = $false
      Description = "ESP32 专用串口监控"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "serial-debug"
      Primary = $false
      Description = "通用串口调试"
      Skill = "serial-debug"
    }
  )
  Hardware = @(
    [PSCustomObject]@{
      Name = "pin-check"
      Primary = $true
      Description = "引脚分配和冲突检测"
      Skill = "peripheral-driver-template"
    }
  )
  CodeQuality = @(
    [PSCustomObject]@{
      Name = "project-stats"
      Primary = $false
      Description = "项目统计（代码行数等）"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "warning-db"
      Primary = $false
      Description = "编译警告数据库"
      Skill = "embedded-code-review"
    }
    [PSCustomObject]@{
      Name = "impact-analyze"
      Primary = $false
      Description = "变更影响分析"
      Skill = $null
    }
  )
  ProjectManage = @(
    [PSCustomObject]@{
      Name = "project-finalize"
      Primary = $true
      Description = "项目收尾清理"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "knowledge-index"
      Primary = $false
      Description = "跨项目知识索引"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "watch-board"
      Primary = $false
      Description = "板子连接监控"
      Skill = $null
    }
  )
  SkillMaintain = @(
    [PSCustomObject]@{
      Name = "check-skills"
      Primary = $true
      Description = "技能库健康体检（行数/编码/version/代码块/reference 关联）"
      Skill = "skill-audit"
    }
    [PSCustomObject]@{
      Name = "split-skill"
      Primary = $false
      Description = "技能拆分助手（SKILL.md -> reference.md）"
      Skill = "skill-audit"
    }
    [PSCustomObject]@{
      Name = "check-bom"
      Primary = $false
      Description = "PowerShell 脚本 BOM 检查与修复"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "version-tools"
      Primary = $false
      Description = "工具版本登记/变更记录/缺失检测（-Bump 递增并自动入 changelog）"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "self-update"
      Primary = $false
      Description = "工具箱/技能/记忆/环境自我体检（config 含版本门禁+时效检查）"
      Skill = $null
    }
    [PSCustomObject]@{
      Name = "install-precommit"
      Primary = $false
      Description = "安装 git pre-commit 提交门禁"
      Skill = "embedded-dev-rules"
    }
  )
}

function Show-Category {
  param([string]$CatKey)

  if (-not $toolCategories.Contains($CatKey)) {
    Write-Host "[!] Unknown category: $CatKey" -ForegroundColor Yellow
    return
  }

  $catName = $catNames[$CatKey]
  $tools = $toolCategories[$CatKey]
  Write-Host ""
  Write-Host "【$catName】" -ForegroundColor Cyan

  foreach ($tool in $tools) {
    $primaryTag = if ($tool.Primary) { " [推荐]" } else { "" }
    $verTag = Get-ToolVersionText $tool.Name
    $skillTag = if ($tool.Skill) { " (Skill: $($tool.Skill))" } else { "" }
    Write-Host "  $($tool.Name)" -ForegroundColor Green -NoNewline
    Write-Host $verTag -ForegroundColor DarkCyan -NoNewline
    Write-Host $primaryTag -ForegroundColor Yellow -NoNewline
    Write-Host ": $($tool.Description)$skillTag" -ForegroundColor Gray
  }
}

function Show-ToolDetail {
  param([string]$ToolName)

  foreach ($catKey in $toolCategories.Keys) {
    foreach ($tool in $toolCategories[$catKey]) {
      if ($tool.Name -eq $ToolName) {
        $catName = $catNames[$catKey]
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  工具: $($tool.Name)" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  分类: $catName"
        $verTag = Get-ToolVersionText $tool.Name
        if ($verTag) { Write-Host "  版本: $($verTag.Trim())" }
        Write-Host "  描述: $($tool.Description)"
        Write-Host "  推荐: $(if ($tool.Primary) { "是" } else { "否" })"
        if ($tool.Skill) {
          Write-Host "  关联 Skill: $($tool.Skill)"
        }
        Write-Host "========================================"
        return
      }
    }
  }

  Write-Host "[!] Tool not found: $ToolName" -ForegroundColor Yellow
}

try {
  if ($Tool) {
    Show-ToolDetail -ToolName $Tool
  } elseif ($Category) {
    $catKey = $null
    foreach ($key in $catNames.Keys) {
      if ($catNames[$key] -eq $Category -or $key -eq $Category) {
        $catKey = $key
        break
      }
    }
    if ($catKey) {
      Show-Category -CatKey $catKey
    } else {
      Write-Host "[!] Unknown category: $Category" -ForegroundColor Yellow
    }
  } else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  工具使用指南" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    foreach ($catKey in $toolCategories.Keys) {
      Show-Category -CatKey $catKey
    }

    Write-Host ""
    Write-Host "使用方式:" -ForegroundColor Yellow
    Write-Host "  tool-guide                    # 显示所有工具" -ForegroundColor Gray
    Write-Host "  tool-guide -Category Flash    # 按分类查看" -ForegroundColor Gray
    Write-Host "  tool-guide -Tool build-all    # 查看工具详情" -ForegroundColor Gray
    Write-Host ""
  }
} catch {
  Write-Host "[X] Execution failed: $($_.Exception.Message)" -ForegroundColor Red
}
