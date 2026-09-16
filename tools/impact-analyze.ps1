<#
.SYNOPSIS
    变更影响分析工具 - 分析 C/C++ 头文件变更对项目的影响范围。

.DESCRIPTION
    当修改 .h 头文件后，自动分析项目中所有引用该头文件的 .c/.cpp 文件，
    并搜索头文件中的函数声明/宏定义/结构体在项目中的所有使用位置，
    输出受影响文件清单，按影响程度（高/中/低）排序。
    自动识别项目类型（ESP-IDF / Keil ARM / Keil C51 / 通用 C）。

    影响程度判断规则：
      - 高：调用该头文件中的函数/宏 5 次以上（必须同步修改）
      - 中：调用 1-4 次（可能需要修改）
      - 低：仅包含头文件但未使用其中的符号

.EXAMPLE
    .\impact-analyze.ps1 -Header uart.h
    分析当前项目中 uart.h 头文件的变更影响。

.EXAMPLE
    .\impact-analyze.ps1 -Path "D:\MyProject" -Header uart.h -Symbol uart_init
    分析指定项目中 uart.h 头文件和 uart_init 符号的变更影响。

.EXAMPLE
    .\impact-analyze.ps1 -Path . -Header uart.h -Symbol uart_init -Detail
    显示详细的分析结果（不截断符号引用列表）。

.EXAMPLE
    .\impact-analyze.ps1 -Symbol gpio_read
    仅分析指定符号在当前项目中的所有引用位置。
  version: 1.0.0
#>

param(
    [Parameter(Position = 0, HelpMessage = "项目目录路径（默认当前目录）")]
    [string]$Path = (Get-Location).Path,

    [Parameter(Position = 1, HelpMessage = "要分析的头文件名（如 uart.h）")]
    [string]$Header = "",

    [Parameter(Position = 2, HelpMessage = "要分析的符号名（如 uart_init）")]
    [string]$Symbol = "",

    [switch]$Detail
)

# ============================================
# 函数：识别项目类型
# ============================================
function Get-ProjectType {
    param([string]$ProjectPath)

    # 检查 ESP-IDF 项目标志：sdkconfig 文件
    $sdkconfig = Join-Path $ProjectPath "sdkconfig"
    if (Test-Path $sdkconfig) {
        return "ESP-IDF"
    }

    # 检查 ESP-IDF 项目标志：CMakeLists.txt 包含 idf_component_register
    $cmakeFile = Join-Path $ProjectPath "CMakeLists.txt"
    if (Test-Path $cmakeFile) {
        $cmakeContent = Get-Content $cmakeFile -Raw -ErrorAction SilentlyContinue
        if ($cmakeContent -match "idf_component_register" -or $cmakeContent -match "ESPIDF|esp-idf") {
            return "ESP-IDF"
        }
    }

    # 检查 ESP-IDF 项目标志：components 目录
    $componentsDir = Join-Path $ProjectPath "components"
    if (Test-Path $componentsDir) {
        return "ESP-IDF"
    }

    # 检查 Keil ARM 项目：*.uvprojx 文件
    $uvprojxFiles = Get-ChildItem -Path $ProjectPath -Filter "*.uvprojx" -Recurse -File -ErrorAction SilentlyContinue
    if ($uvprojxFiles -and $uvprojxFiles.Count -gt 0) {
        return "Keil ARM"
    }

    # 检查 Keil C51 项目：*.uv2 文件
    $uv2Files = Get-ChildItem -Path $ProjectPath -Filter "*.uv2" -Recurse -File -ErrorAction SilentlyContinue
    if ($uv2Files -and $uv2Files.Count -gt 0) {
        return "Keil C51"
    }

    return "通用 C"
}

# ============================================
# 函数：查找 #include "xxx.h" 的所有文件
# ============================================
function Find-HeaderReferences {
    param(
        [string]$ProjectPath,
        [string]$HeaderName
    )

    $results = @()

    # 扫描所有 .c/.cpp 源文件
    $sourceFiles = Get-ChildItem -Path $ProjectPath -Recurse -Include *.c,*.cpp,*.cc,*.cxx -File -ErrorAction SilentlyContinue

    # 构造 #include "xxx.h" 匹配模式
    $includePattern = '#include\s*"' + [regex]::Escape($HeaderName) + '"'

    # 提取头文件名前缀作为符号前缀（如 uart.h -> uart_）
    $prefix = [System.IO.Path]::GetFileNameWithoutExtension($HeaderName)
    $symbolPattern = '\b' + [regex]::Escape($prefix) + '_\w+'

    foreach ($file in $sourceFiles) {
        $lines = Get-Content $file.FullName -ErrorAction SilentlyContinue
        if (-not $lines) { continue }

        $hasInclude = $false
        $callCount = 0

        foreach ($line in $lines) {
            if (-not $hasInclude -and $line -match $includePattern) {
                $hasInclude = $true
            }
            # 统计该文件中调用头文件相关符号的次数
            $symbolMatches = [regex]::Matches($line, $symbolPattern)
            $callCount += $symbolMatches.Count
        }

        if ($hasInclude) {
            $results += [PSCustomObject]@{
                File      = $file.FullName
                FileName  = $file.Name
                CallCount = $callCount
            }
        }
    }

    return $results
}

# ============================================
# 函数：查找符号在项目中的所有使用位置
# ============================================
function Find-SymbolReferences {
    param(
        [string]$ProjectPath,
        [string]$SymbolName
    )

    $results = @()

    # 扫描所有 .c/.cpp/.h 源文件
    $sourceFiles = Get-ChildItem -Path $ProjectPath -Recurse -Include *.c,*.cpp,*.cc,*.cxx,*.h,*.hpp -File -ErrorAction SilentlyContinue

    # 使用单词边界匹配符号，避免误匹配
    $pattern = '\b' + [regex]::Escape($SymbolName) + '\b'

    foreach ($file in $sourceFiles) {
        $lines = Get-Content $file.FullName -ErrorAction SilentlyContinue
        if (-not $lines) { continue }

        $lineNumber = 0
        foreach ($line in $lines) {
            $lineNumber++
            if ($line -match $pattern) {
                $trimmed = $line.Trim()
                $results += [PSCustomObject]@{
                    File       = $file.FullName
                    FileName   = $file.Name
                    LineNumber = $lineNumber
                    Content    = $trimmed
                }
            }
        }
    }

    return $results
}

# ============================================
# 函数：综合分析，按影响程度排序
# ============================================
function Analyze-Impact {
    param(
        [string]$ProjectPath,
        [string]$HeaderName,
        [string]$SymbolName,
        [bool]$ShowDetail
    )

    # 识别项目类型
    $projectType = Get-ProjectType -ProjectPath $ProjectPath

    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "  变更影响分析报告" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "项目类型：$projectType"
    $target = if ($HeaderName) { $HeaderName } else { $SymbolName }
    Write-Host "分析目标：$target"
    Write-Host ""

    # 计算总步骤数
    $totalSteps = 0
    if ($HeaderName)  { $totalSteps++ }
    if ($SymbolName)  { $totalSteps++ }

    if ($totalSteps -eq 0) {
        Write-Host "错误：请至少指定 -Header 或 -Symbol 参数" -ForegroundColor Red
        Write-Host "用法：.\impact-analyze.ps1 -Header uart.h [-Symbol uart_init] [-Path .] [-Detail]" -ForegroundColor Yellow
        return
    }

    $currentStep = 0
    $highCount = 0
    $mediumCount = 0
    $lowCount = 0

    # 【步骤1】头文件引用分析
    if ($HeaderName) {
        $currentStep++
        Write-Host "【$currentStep/$totalSteps】头文件引用分析（#include `"$HeaderName`"）" -ForegroundColor Cyan

        # 提取头文件名前缀作为符号前缀（如 uart.h -> uart_）
        $headerPrefix = [System.IO.Path]::GetFileNameWithoutExtension($HeaderName)

        $headerRefs = Find-HeaderReferences -ProjectPath $ProjectPath -HeaderName $HeaderName

        Write-Host "  受影响文件：$($headerRefs.Count) 个"
        Write-Host "  ─────────────────────────────"

        if ($headerRefs.Count -eq 0) {
            Write-Host "  未找到引用该头文件的源文件" -ForegroundColor Gray
        }
        else {
            # 按影响程度排序：高 > 中 > 低（按调用次数降序）
            $sorted = $headerRefs | Sort-Object { $_.CallCount } -Descending

            foreach ($ref in $sorted) {
                $level = ""
                $color = "White"
                if ($ref.CallCount -ge 5) {
                    $level = "[高]"
                    $color = "Red"
                    $highCount++
                }
                elseif ($ref.CallCount -ge 1) {
                    $level = "[中]"
                    $color = "Yellow"
                    $mediumCount++
                }
                else {
                    $level = "[低]"
                    $color = "Gray"
                    $lowCount++
                }
                # 文件名右填充到 20 字符（中文宽度问题忽略，保持对齐美观）
                $fileName = $ref.FileName.PadRight(20)
                Write-Host "  $level $fileName ($($ref.CallCount) 处调用 ${headerPrefix}_* 函数)" -ForegroundColor $color
            }
        }
        Write-Host ""
    }

    # 【步骤2】符号引用分析
    if ($SymbolName) {
        $currentStep++
        Write-Host "【$currentStep/$totalSteps】符号引用分析" -ForegroundColor Cyan
        Write-Host "  分析符号：$SymbolName"
        Write-Host "  ─────────────────────────────"

        $symbolRefs = Find-SymbolReferences -ProjectPath $ProjectPath -SymbolName $SymbolName

        if ($symbolRefs.Count -eq 0) {
            Write-Host "  未找到符号引用" -ForegroundColor Gray
        }
        else {
            # 默认最多显示 20 条，-Detail 显示全部
            $displayCount = if ($ShowDetail) { $symbolRefs.Count } else { [Math]::Min(20, $symbolRefs.Count) }

            for ($i = 0; $i -lt $displayCount; $i++) {
                $ref = $symbolRefs[$i]
                # 文件名:行号 左填充对齐
                $location = "$($ref.FileName):$($ref.LineNumber)".PadRight(15)
                Write-Host "  $location : $($ref.Content)"
            }

            if (-not $ShowDetail -and $symbolRefs.Count -gt 20) {
                Write-Host "  ... 还有 $($symbolRefs.Count - 20) 处引用（使用 -Detail 查看全部）" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    # 影响评估
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host "  影响评估" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host "  高影响：$highCount 个文件（必须同步修改）" -ForegroundColor Red
    Write-Host "  中影响：$mediumCount 个文件（可能需要修改）" -ForegroundColor Yellow
    Write-Host "  低影响：$lowCount 个文件" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  建议："
    Write-Host "  1. 检查高影响文件中的函数调用，确保参数和返回值兼容"
    Write-Host "  2. 如果修改了结构体，检查所有初始化代码"
    Write-Host "  3. 如果修改了宏定义，检查所有使用该宏的代码"
    Write-Host "  4. 编译验证后，逐个验证每个文件的功能"
    Write-Host ""
}

# ============================================
# 主流程
# ============================================
$ErrorActionPreference = "Stop"

# 校验项目路径
if (-not (Test-Path -Path $Path -PathType Container)) {
    Write-Host "错误：项目路径不存在或不是目录: $Path" -ForegroundColor Red
    exit 1
}

# 解析为绝对路径
$resolvedPath = (Resolve-Path -Path $Path).Path

# 执行综合分析
Analyze-Impact -ProjectPath $resolvedPath -HeaderName $Header -SymbolName $Symbol -ShowDetail $Detail.IsPresent
