<#
.SYNOPSIS
    项目收尾工具 - 清理备份、归档日志、检查 git、生成总结模板。

.DESCRIPTION
    在项目收尾时自动执行以下任务：
      1. 清理 .bak 备份文件（在用户确认后删除）
      2. 归档串口日志文件（serial_log_*.txt 等）到项目目录下的 logs/ 子目录
      3. 输出本次工作的改动总结模板（提示用户填入 memory）
      4. 检查 git status（如果项目用了 git）
      5. 检查待办事项（未关闭 todo / 未烧录验证）

.EXAMPLE
    .\project-finalize.ps1
    在当前目录执行项目收尾。

.EXAMPLE
    .\project-finalize.ps1 -Path "D:\MyProject"
    指定项目目录执行收尾。

.EXAMPLE
    .\project-finalize.ps1 -Path "D:\MyProject" -DryRun
    预演模式，只显示要做什么，不实际执行。

.EXAMPLE
    .\project-finalize.ps1 -Path "D:\MyProject" -Force
    跳过所有确认，直接执行。
  version: 1.0.0
#>

param(
    [Parameter(Position = 0, HelpMessage = "项目目录路径（默认当前目录）")]
    [string]$Path = (Get-Location).Path,

    [switch]$DryRun,

    [switch]$Force
)

# ============================================
# 函数：查找 .bak 备份文件
# ============================================
function Find-BackupFiles {
    param([string]$ProjectPath)

    $bakFiles = Get-ChildItem -Path $ProjectPath -Recurse -Filter "*.bak" -File -ErrorAction SilentlyContinue
    return $bakFiles
}

# ============================================
# 函数：查找日志文件（serial_log_*.txt 等）
# ============================================
function Find-LogFiles {
    param([string]$ProjectPath)

    $logPatterns = @("serial_log_*.txt", "*.log")
    $logFiles = @()
    foreach ($pattern in $logPatterns) {
        $logFiles += Get-ChildItem -Path $ProjectPath -Filter $pattern -File -ErrorAction SilentlyContinue
    }
    # 去重，避免同一文件被多个 pattern 命中
    return $logFiles | Sort-Object FullName -Unique
}

# ============================================
# 函数：归档日志到 logs/ 子目录
# ============================================
function Archive-Logs {
    param(
        [string]$ProjectPath,
        [array]$LogFiles,
        [bool]$IsDryRun
    )

    $logsDir = Join-Path $ProjectPath "logs"
    if (-not (Test-Path $logsDir)) {
        if ($IsDryRun) {
            Write-Host "  [DryRun] 将创建目录: $logsDir" -ForegroundColor Yellow
        }
        else {
            New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
        }
    }

    foreach ($log in $LogFiles) {
        $destPath = Join-Path $logsDir $log.Name
        if ($IsDryRun) {
            Write-Host "  [DryRun] 将移动: $($log.FullName) -> $destPath" -ForegroundColor Yellow
        }
        else {
            Move-Item -Path $log.FullName -Destination $destPath -Force
        }
    }
}

# ============================================
# 函数：检查 git status
# ============================================
function Invoke-GitCheck {
    param([string]$ProjectPath)

    $gitDir = Join-Path $ProjectPath ".git"
    if (-not (Test-Path $gitDir)) {
        Write-Host "  当前项目未使用 git 版本控制" -ForegroundColor Gray
        return
    }

    Push-Location $ProjectPath
    try {
        # 当前分支
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
        if ($branch) {
            Write-Host "  当前分支: $branch" -ForegroundColor Cyan
        }

        # git status 摘要
        $statusOutput = git status --porcelain 2>$null
        if ($statusOutput) {
            $modified  = @($statusOutput | Where-Object { $_ -match "^ M" }).Count
            $added     = @($statusOutput | Where-Object { $_ -match "^A"  }).Count
            $untracked = @($statusOutput | Where-Object { $_ -match "^\?\?" }).Count

            Write-Host "  修改文件: $modified 个"
            Write-Host "  新增文件: $added 个"
            Write-Host "  未跟踪: $untracked 个"
            Write-Host ""
            Write-Host "  建议: git add . && git commit -m `"...`"" -ForegroundColor Green
        }
        else {
            Write-Host "  工作区干净，无未提交改动" -ForegroundColor Green
        }
    }
    finally {
        Pop-Location
    }
}

# ============================================
# 函数：生成改动总结模板
# ============================================
function Generate-SummaryTemplate {
    $today = Get-Date -Format "yyyy-MM-dd"
    $template = @"
请将以下内容填入 project_memory.md：

### [$today] [模块名] [功能描述]
- 改动文件：xxx.c, xxx.h
- 改动内容：xxx
- 验证结果：xxx
- 注意事项：xxx
"@
    Write-Host $template
}

# ============================================
# 主流程
# ============================================
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  项目收尾工具" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "项目路径：$Path" -ForegroundColor Yellow
Write-Host ""

# 校验路径
if (-not (Test-Path -Path $Path -PathType Container)) {
    Write-Host "错误：项目路径不存在或不是目录: $Path" -ForegroundColor Red
    exit 1
}

# DryRun 提示
if ($DryRun) {
    Write-Host "【DryRun 模式】只显示要做什么，不实际执行" -ForegroundColor Magenta
    Write-Host ""
}

# 【1/6】扫描 .bak 备份文件
Write-Host "【1/6】扫描 .bak 备份文件" -ForegroundColor Cyan
$bakFiles = Find-BackupFiles -ProjectPath $Path
if ($bakFiles -and $bakFiles.Count -gt 0) {
    Write-Host "  发现 $($bakFiles.Count) 个 .bak 文件：" -ForegroundColor Yellow
    foreach ($f in $bakFiles) {
        Write-Host "    $($f.Name)"
    }

    $shouldDelete = $false
    if ($Force) {
        $shouldDelete = $true
    }
    elseif (-not $DryRun) {
        $reply = Read-Host "  确认删除？(Y/N)"
        if ($reply -match "^[Yy]$") {
            $shouldDelete = $true
        }
    }

    if ($shouldDelete -and -not $DryRun) {
        foreach ($f in $bakFiles) {
            Remove-Item -Path $f.FullName -Force
        }
        Write-Host "  已删除 $($bakFiles.Count) 个 .bak 文件" -ForegroundColor Green
    }
    elseif ($DryRun) {
        Write-Host "  [DryRun] 将删除以上 $($bakFiles.Count) 个文件" -ForegroundColor Yellow
    }
    else {
        Write-Host "  已跳过删除" -ForegroundColor Gray
    }
}
else {
    Write-Host "  未发现 .bak 文件" -ForegroundColor Gray
}
Write-Host ""

# 【2/6】扫描日志文件
Write-Host "【2/6】扫描日志文件" -ForegroundColor Cyan
$logFiles = Find-LogFiles -ProjectPath $Path
if ($logFiles -and $logFiles.Count -gt 0) {
    Write-Host "  发现 $($logFiles.Count) 个日志文件：" -ForegroundColor Yellow
    foreach ($f in $logFiles) {
        Write-Host "    $($f.Name)"
    }
    Write-Host "  归档到 logs/ 目录" -ForegroundColor Cyan
    Archive-Logs -ProjectPath $Path -LogFiles $logFiles -IsDryRun $DryRun
    if (-not $DryRun) {
        Write-Host "  归档完成" -ForegroundColor Green
    }
}
else {
    Write-Host "  未发现日志文件" -ForegroundColor Gray
}
Write-Host ""

# 【3/6】检查 git status
Write-Host "【3/6】检查 git status" -ForegroundColor Cyan
Invoke-GitCheck -ProjectPath $Path
Write-Host ""

# 【4/6】生成改动总结模板
Write-Host "【4/6】生成改动总结模板" -ForegroundColor Cyan
Generate-SummaryTemplate
Write-Host ""

# 【5/6】检查待办事项
Write-Host "【5/6】检查待办事项" -ForegroundColor Cyan
Write-Host "  - 是否有未关闭的 todo？（提示用户）" -ForegroundColor Yellow
Write-Host "  - 是否有未烧录验证的代码？（提示用户）" -ForegroundColor Yellow
Write-Host ""

# 【6/6】更新知识索引
Write-Host "【6/6】更新知识索引" -ForegroundColor Cyan
$kiScript = Join-Path $PSScriptRoot 'knowledge-index.ps1'
if (Test-Path $kiScript) {
    try {
        & $kiScript -Index
        Write-Host "  知识索引已更新" -ForegroundColor Green
    } catch {
        Write-Host "  知识索引更新失败: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "  knowledge-index.ps1 不存在，跳过" -ForegroundColor Gray
}
Write-Host ""

Write-Host "=========================================" -ForegroundColor Green
Write-Host "  收尾完成！" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
