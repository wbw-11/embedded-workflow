<#
.SYNOPSIS
    嵌入式项目代码统计工具

.DESCRIPTION
    统计嵌入式项目的代码行数、文件数、模块分布、注释率等指标。
    支持 ESP-IDF、Keil ARM、Keil C51、通用 C 等项目类型自动识别。
    自动识别 C/C++/Python 注释，去除空行和注释行后统计有效代码行数。

.PARAMETER Path
    项目目录路径，默认为当前目录。

.PARAMETER Detail
    显示每个文件的详细统计信息（每个文件一行）。

.PARAMETER Top
    显示最大文件 Top N，默认为 5。

.EXAMPLE
    .\project-stats.ps1
    统计当前目录下的项目

.EXAMPLE
    .\project-stats.ps1 -Path D:\MyProject
    统计指定目录下的项目

.EXAMPLE
    .\project-stats.ps1 -Detail
    显示每个文件的详细统计

.EXAMPLE
    .\project-stats.ps1 -Top 10
    显示 Top 10 最大文件

.NOTES
    作者：TRAE Embedded Assistant
    创建日期：2026-07-26
    编码：UTF-8 with BOM
  version: 1.0.0
#>

param(
    [Parameter(Position = 0, HelpMessage = "项目目录路径")]
    [string]$Path = (Get-Location).Path,

    [switch]$Detail,

    [int]$Top = 5
)

# ============================================================
# 全局配置
# ============================================================

# 设置控制台编码为 UTF-8（确保中文正确显示）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 排除的目录（编译输出、版本控制、IDE 配置等）
$script:ExcludeDirs = @(
    'build', '.git', '.svn', '.vscode', '.idea',
    'dependencies', '__pycache__', 'node_modules', '.settings',
    'Debug', 'Release', 'Listings', 'Objects', 'Output',
    'DebugConfig', 'Records', '.ccache', 'managed_components'
)

# 代码文件扩展名
$script:CodeExtensions = @('.c', '.h', '.cpp', '.hpp', '.cc', '.cxx', '.s', '.asm', '.py')

# 文档文件扩展名
$script:DocExtensions = @('.md', '.txt', '.rst')

# CMake 文件名
$script:CmakeFile = 'CMakeLists.txt'

# 统计显示顺序的扩展名列表
$script:DisplayOrder = @('.c', '.h', '.cpp', '.hpp', '.cc', '.s', '.asm', '.py', '.md', '.txt', 'CMakeLists.txt')

# ============================================================
# 函数：识别项目类型
# ============================================================
function Get-ProjectType {
    param([string]$ProjectPath)

    if (-not (Test-Path $ProjectPath)) {
        return @{ Type = '未知'; Detail = '路径不存在' }
    }

    # 检查 ESP-IDF 项目（CMakeLists.txt 包含 idf_component_register）
    $cmakeFiles = Get-ChildItem -Path $ProjectPath -Filter $script:CmakeFile -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-FileExcluded -FilePath $_.FullName) }

    foreach ($cmake in $cmakeFiles) {
        try {
            $content = [System.IO.File]::ReadAllText($cmake.FullName)
            if ($content -match 'idf_component_register') {
                return @{ Type = 'ESP-IDF'; Detail = 'idf_component_register' }
            }
        } catch { }
    }

    # 检查 Keil ARM 项目
    $uvprojxFiles = @(Get-ChildItem -Path $ProjectPath -Filter "*.uvprojx" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-FileExcluded -FilePath $_.FullName) })
    if ($uvprojxFiles.Count -gt 0) {
        return @{ Type = 'Keil ARM'; Detail = $uvprojxFiles[0].Name }
    }

    # 检查 Keil C51 项目
    $uvprojFiles = @(Get-ChildItem -Path $ProjectPath -Filter "*.uvproj" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-FileExcluded -FilePath $_.FullName) })
    if ($uvprojFiles.Count -gt 0) {
        return @{ Type = 'Keil C51'; Detail = $uvprojFiles[0].Name }
    }

    # 检查通用 C 项目
    $cFiles = @(Get-ChildItem -Path $ProjectPath -Recurse -File -Include *.c, *.h -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-FileExcluded -FilePath $_.FullName) })
    if ($cFiles.Count -gt 0) {
        return @{ Type = '通用 C'; Detail = '*.c/*.h' }
    }

    return @{ Type = '未知'; Detail = '未识别的项目类型' }
}

# ============================================================
# 函数：判断行类型（空行/注释行/代码行）
# ============================================================
function Get-LineType {
    param(
        [string]$Line,
        [string]$Extension,
        [ref]$InBlockComment
    )

    # 空行：仅包含空白字符
    if ([string]::IsNullOrWhiteSpace($Line)) {
        return 'blank'
    }

    $trimmed = $Line.Trim()

    # 非代码文件类型 - 视为代码行
    $codeExts = @('.c', '.h', '.cpp', '.hpp', '.cc', '.cxx', '.s', '.asm', '.py', '.cmake')
    if ($Extension -notin $codeExts) {
        return 'code'
    }

    # Python/CMake 注释：以 # 开头
    if ($Extension -in @('.py', '.cmake')) {
        if ($trimmed.StartsWith('#')) { return 'comment' }
        return 'code'
    }

    # C/C++/汇编 注释处理
    # 情况 1：处于块注释中
    if ($InBlockComment.Value) {
        if ($trimmed -match '\*/') {
            # 块注释结束
            $InBlockComment.Value = $false
            # 检查 */ 后面是否还有代码
            $after = $trimmed -replace '^.*?\*/', ''
            if ([string]::IsNullOrWhiteSpace($after)) {
                return 'comment'
            }
            return 'code'
        }
        return 'comment'
    }

    # 情况 2：单行注释 //
    if ($trimmed.StartsWith('//')) {
        return 'comment'
    }

    # 情况 3：块注释开始 /*
    if ($trimmed.StartsWith('/*')) {
        # 检查是否同行结束 /* ... */
        if ($trimmed -match '\*/') {
            $after = $trimmed -replace '^/\*.*?\*/', ''
            if ([string]::IsNullOrWhiteSpace($after)) {
                return 'comment'
            }
            return 'code'
        }
        # 块注释未结束，进入块注释状态
        $InBlockComment.Value = $true
        return 'comment'
    }

    # 情况 4：多行注释续行（* 开头）
    if ($trimmed.StartsWith('*')) {
        return 'comment'
    }

    # 其他情况：代码行
    return 'code'
}

# ============================================================
# 函数：统计单个文件的代码行数
# ============================================================
function Get-CodeStats {
    param([string]$FilePath)

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $fileName = [System.IO.Path]::GetFileName($FilePath)

    # CMakeLists.txt 特殊处理
    if ($fileName -eq $script:CmakeFile) {
        $ext = '.cmake'
    }

    # 读取文件内容（使用 .NET 方法提高性能）
    $lines = @()
    try {
        $lines = [System.IO.File]::ReadAllLines($FilePath)
    } catch {
        $fileItem = Get-Item $FilePath -ErrorAction SilentlyContinue
        $size = if ($fileItem) { $fileItem.Length } else { 0 }
        return @{ Code = 0; Comment = 0; Blank = 0; Total = 0; Size = $size }
    }

    if ($null -eq $lines -or $lines.Count -eq 0) {
        $fileItem = Get-Item $FilePath -ErrorAction SilentlyContinue
        $size = if ($fileItem) { $fileItem.Length } else { 0 }
        return @{ Code = 0; Comment = 0; Blank = 0; Total = 0; Size = $size }
    }

    $code = 0
    $comment = 0
    $blank = 0
    $inBlockComment = $false

    foreach ($line in $lines) {
        $type = Get-LineType -Line $line -Extension $ext -InBlockComment ([ref]$inBlockComment)
        switch ($type) {
            'blank'   { $blank++ }
            'comment' { $comment++ }
            'code'    { $code++ }
        }
    }

    $fileSize = (Get-Item $FilePath -ErrorAction SilentlyContinue).Length

    return @{
        Code    = $code
        Comment = $comment
        Blank   = $blank
        Total   = $lines.Count
        Size    = $fileSize
    }
}

# ============================================================
# 函数：判断文件是否应被排除
# ============================================================
function Test-FileExcluded {
    param([string]$FilePath)

    foreach ($dir in $script:ExcludeDirs) {
        if ($FilePath -match "\\$dir\\") {
            return $true
        }
    }
    return $false
}

# ============================================================
# 函数：格式化字节数
# ============================================================
function Format-Size {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

# ============================================================
# 函数：绘制进度条
# ============================================================
function Get-ProgressBar {
    param([double]$Percent, [int]$Width = 10)

    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }

    $filled = [int]([math]::Round($Percent / 100 * $Width))
    if ($filled -gt $Width) { $filled = $Width }
    $empty = $Width - $filled
    return ('█' * $filled) + ('░' * $empty)
}

# ============================================================
# 函数：格式化输出统计结果
# ============================================================
function Format-Stats {
    param(
        [hashtable]$ProjectInfo,
        [array]$FileStats,
        [hashtable]$ExtensionStats,
        [hashtable]$TotalStats,
        [bool]$ShowDetail,
        [int]$TopCount
    )

    $separator = '========================================='

    Write-Host ''
    Write-Host $separator -ForegroundColor Cyan
    Write-Host '  项目统计报告' -ForegroundColor Cyan
    Write-Host $separator -ForegroundColor Cyan

    Write-Host ("项目类型：{0} ({1})" -f $ProjectInfo.Type, $ProjectInfo.Detail) -ForegroundColor Yellow
    Write-Host ("项目路径：{0}" -f $ProjectInfo.Path) -ForegroundColor Yellow
    Write-Host ''

    # ---------- 文件统计 ----------
    Write-Host '【文件统计】' -ForegroundColor Green

    $totalFiles = 0
    $totalLines = 0

    # 按预定义顺序显示
    foreach ($key in $script:DisplayOrder) {
        if ($ExtensionStats.ContainsKey($key)) {
            $stat = $ExtensionStats[$key]
            $label = if ($key -eq 'CMakeLists.txt') { 'CMakeLists' } else { "$key 文件" }
            Write-Host ("  {0,-12} : {1,4} 个  {2,8:N0} 行" -f $label, $stat.Count, $stat.Lines) -ForegroundColor White
            $totalFiles += $stat.Count
            $totalLines += $stat.Lines
        }
    }

    # 显示其他扩展名
    $otherKeys = $ExtensionStats.Keys | Where-Object { $_ -notin $script:DisplayOrder }
    foreach ($key in $otherKeys) {
        $stat = $ExtensionStats[$key]
        Write-Host ("  {0,-12} : {1,4} 个  {2,8:N0} 行" -f "$key 文件", $stat.Count, $stat.Lines) -ForegroundColor DarkGray
        $totalFiles += $stat.Count
        $totalLines += $stat.Lines
    }

    Write-Host ("  {0}" -f ('─' * 35)) -ForegroundColor DarkGray
    Write-Host ("  {0,-12} : {1,4} 个  {2,8:N0} 行" -f '合计', $totalFiles, $totalLines) -ForegroundColor Cyan
    Write-Host ''

    # ---------- 代码质量 ----------
    Write-Host '【代码质量】' -ForegroundColor Green

    $totalAll = $TotalStats.Code + $TotalStats.Comment + $TotalStats.Blank
    if ($totalAll -gt 0) {
        $codePct = $TotalStats.Code / $totalAll * 100
        $commentPct = $TotalStats.Comment / $totalAll * 100
        $blankPct = $TotalStats.Blank / $totalAll * 100
    } else {
        $codePct = $commentPct = $blankPct = 0
    }

    Write-Host ("  代码行     : {0,6:N0} 行 ({1,5:N1}%)" -f $TotalStats.Code, $codePct) -ForegroundColor White
    Write-Host ("  注释行     : {0,6:N0} 行 ({1,5:N1}%)" -f $TotalStats.Comment, $commentPct) -ForegroundColor White
    Write-Host ("  空行       : {0,6:N0} 行 ({1,5:N1}%)" -f $TotalStats.Blank, $blankPct) -ForegroundColor White
    $bar = Get-ProgressBar -Percent $commentPct -Width 10
    Write-Host ("  注释率     : {0} {1:N1}%" -f $bar, $commentPct) -ForegroundColor Magenta
    Write-Host ''

    # ---------- 模块分布 ----------
    Write-Host '【模块分布】' -ForegroundColor Green

    $moduleStats = @{}
    foreach ($f in $FileStats) {
        $relPath = $f.RelativePath
        $parts = ($relPath -split '[\\/]') | Where-Object { $_ -ne '' }
        if ($parts.Count -ge 2) {
            if ($parts[0] -eq 'components' -and $parts.Count -ge 3) {
                $module = "$($parts[0])/$($parts[1])"
            } else {
                $module = $parts[0]
            }
        } else {
            $module = '根目录'
        }
        if (-not $moduleStats.ContainsKey($module)) {
            $moduleStats[$module] = 0
        }
        $moduleStats[$module] += $f.Stats.Total
    }

    $sortedModules = $moduleStats.GetEnumerator() | Sort-Object Value -Descending
    $moduleTotal = ($sortedModules | Measure-Object -Property Value -Sum).Sum

    $shown = 0
    $otherLines = 0
    $otherCount = 0
    foreach ($m in $sortedModules) {
        if ($shown -lt 3) {
            $pct = if ($moduleTotal -gt 0) { $m.Value / $moduleTotal * 100 } else { 0 }
            Write-Host ("  {0,-15} : {1,6:N0} 行 ({2,5:N1}%)" -f ($m.Key + '/'), $m.Value, $pct) -ForegroundColor White
            $shown++
        } else {
            $otherLines += $m.Value
            $otherCount++
        }
    }
    if ($otherCount -gt 0) {
        $pct = if ($moduleTotal -gt 0) { $otherLines / $moduleTotal * 100 } else { 0 }
        Write-Host ("  {0,-15} : {1,6:N0} 行 ({2,5:N1}%)" -f '其他', $otherLines, $pct) -ForegroundColor DarkGray
    }
    Write-Host ''

    # ---------- Top N 最大文件 ----------
    Write-Host ("【Top {0} 最大文件】" -f $TopCount) -ForegroundColor Green

    $topFiles = $FileStats |
        Where-Object { $_.Stats.Total -gt 0 } |
        Sort-Object { $_.Stats.Total } -Descending |
        Select-Object -First $TopCount

    $idx = 1
    foreach ($f in $topFiles) {
        $relPath = $f.RelativePath
        if ($relPath.Length -gt 35) {
            $relPath = '...' + $relPath.Substring($relPath.Length - 32)
        }
        Write-Host ("  {0}. {1,-35} : {2,5:N0} 行" -f $idx, $relPath, $f.Stats.Total) -ForegroundColor White
        $idx++
    }
    Write-Host ''

    # ---------- 项目体积 ----------
    Write-Host '【项目体积】' -ForegroundColor Green
    Write-Host ("  总大小     : {0}" -f (Format-Size -Bytes $TotalStats.Size)) -ForegroundColor Cyan
    Write-Host ("  文件数     : {0:N0}" -f $totalFiles) -ForegroundColor Cyan
    Write-Host ''

    # ---------- 详细统计 ----------
    if ($ShowDetail) {
        Write-Host '【详细统计】' -ForegroundColor Green
        Write-Host ("  {0,-45} {1,8} {2,8} {3,8} {4,8}" -f '文件', '代码', '注释', '空行', '总计') -ForegroundColor Yellow
        Write-Host ("  {0}" -f ('─' * 82)) -ForegroundColor DarkGray
        foreach ($f in ($FileStats | Sort-Object RelativePath)) {
            $relPath = $f.RelativePath
            if ($relPath.Length -gt 43) {
                $relPath = '...' + $relPath.Substring($relPath.Length - 40)
            }
            Write-Host ("  {0,-45} {1,8:N0} {2,8:N0} {3,8:N0} {4,8:N0}" -f $relPath, $f.Stats.Code, $f.Stats.Comment, $f.Stats.Blank, $f.Stats.Total) -ForegroundColor White
        }
        Write-Host ''
    }

    Write-Host $separator -ForegroundColor Cyan
    Write-Host ''
}

# ============================================================
# 主流程
# ============================================================

# 参数校验
if ($Top -lt 1) { $Top = 5 }

# 解析路径
$resolvedPath = (Resolve-Path $Path -ErrorAction SilentlyContinue).Path
if (-not $resolvedPath) {
    Write-Host "错误：路径不存在 - $Path" -ForegroundColor Red
    exit 1
}
$Path = $resolvedPath

Write-Host "正在分析项目：$Path" -ForegroundColor Yellow

# 识别项目类型
$projType = Get-ProjectType -ProjectPath $Path
Write-Host ("识别到项目类型：{0}" -f $projType.Type) -ForegroundColor Green

# 收集所有目标文件
$allFiles = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { -not (Test-FileExcluded -FilePath $_.FullName) }

$targetExtensions = $script:CodeExtensions + $script:DocExtensions
$targetFiles = @($allFiles | Where-Object {
    $ext = $_.Extension.ToLower()
    $name = $_.Name
    ($ext -in $targetExtensions) -or ($name -eq $script:CmakeFile)
})

if ($targetFiles.Count -eq 0) {
    Write-Host '未找到可统计的文件。' -ForegroundColor Red
    exit 0
}

$totalCount = $targetFiles.Count
Write-Host ("找到 {0:N0} 个待统计文件..." -f $totalCount) -ForegroundColor Yellow

# 逐文件统计
$fileStats = @()
$extStats = @{}
$totalCode = 0
$totalComment = 0
$totalBlank = 0
$totalSize = 0

$i = 0
foreach ($file in $targetFiles) {
    $i++
    Write-Progress -Activity "统计代码中" -Status "[$i/$totalCount] $($file.Name)" -PercentComplete ($i / $totalCount * 100)

    $stats = Get-CodeStats -FilePath $file.FullName

    $relPath = $file.FullName.Substring($Path.Length).TrimStart('\', '/')

    $fileStats += [PSCustomObject]@{
        RelativePath = $relPath
        Stats        = $stats
    }

    # 按扩展名分类
    $extKey = $file.Extension.ToLower()
    if ($file.Name -eq $script:CmakeFile) {
        $extKey = 'CMakeLists.txt'
    }
    if (-not $extStats.ContainsKey($extKey)) {
        $extStats[$extKey] = @{ Count = 0; Lines = 0 }
    }
    $extStats[$extKey].Count++
    $extStats[$extKey].Lines += $stats.Total

    $totalCode += $stats.Code
    $totalComment += $stats.Comment
    $totalBlank += $stats.Blank
    $totalSize += $stats.Size
}
Write-Progress -Activity "统计代码中" -Completed

# 汇总统计
$totalStats = @{
    Code    = $totalCode
    Comment = $totalComment
    Blank   = $totalBlank
    Size    = $totalSize
}

$projectInfo = @{
    Type   = $projType.Type
    Detail = $projType.Detail
    Path   = $Path
}

# 格式化输出
Format-Stats `
    -ProjectInfo $projectInfo `
    -FileStats $fileStats `
    -ExtensionStats $extStats `
    -TotalStats $totalStats `
    -ShowDetail $Detail `
    -TopCount $Top
