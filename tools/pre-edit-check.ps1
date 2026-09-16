<#
.SYNOPSIS
	修改前预检工具 - 修改 .h 头文件前，强制做 impact-analyze + 自动创建 edit-safe 备份。
.DESCRIPTION
	工作流强制规则（防御性编程）：修改任何 .h/.hpp 头文件前，必须先运行本工具。
	本工具会：
	  1) 自动调用 impact-analyze 列出受影响文件清单（高/中/低影响）
	  2) 自动为被修改的 .h 和 所有 高/中 影响的 .c 文件调用 edit-safe 做备份
	  3) 输出 "必须同步检查" 的文件清单，供后续代码修改时逐项核对
	  4) 返回 exit code：发现高影响文件返回 1（提醒使用者注意），否则 0
.PARAMETER Header
	要修改的头文件名（如 audio_self_test.h），必填
.PARAMETER Symbol
	(可选) 要修改的具体符号（函数/宏/结构体名），若指定则额外做符号引用分析
.PARAMETER Path
	项目根目录（默认当前目录）
.PARAMETER SkipConfirm
	跳过"确认继续"的交互提示（非交互模式使用）
.EXAMPLE
	pre-edit-check audio_self_test.h
	在当前目录修改 audio_self_test.h 前预检

.EXAMPLE
	pre-edit-check -Header app_config.h -Symbol APP_AUDIO_ -Path D:\proj\voice_assistant
	修改 app_config.h 中的 APP_AUDIO_* 宏前预检，并显示符号引用位置

.EXAMPLE
	pre-edit-check es8311_driver.h -SkipConfirm
	非交互模式（不暂停）
  version: 1.0.0
#>

param(
	[Parameter(Position = 0, Mandatory = $true, HelpMessage = "要修改的头文件名（如 audio_self_test.h）")]
	[string]$Header,

	[Parameter(Position = 1)]
	[string]$Symbol = "",

	[Parameter(Position = 2)]
	[string]$Path = (Get-Location).Path,

	[switch]$SkipConfirm
)

$ErrorActionPreference = "Stop"

# 绝对路径
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
	Write-Host "[X] 项目目录不存在: $Path" -ForegroundColor Red
	exit 1
}
$projPath = (Resolve-Path -LiteralPath $Path).Path
$impactScript = Join-Path $PSScriptRoot "impact-analyze.ps1"
$editSafe = Join-Path $PSScriptRoot "edit-safe.ps1"

if (-not (Test-Path -LiteralPath $impactScript)) {
	Write-Host "[X] 找不到 impact-analyze.ps1（在 $PSScriptRoot）" -ForegroundColor Red
	exit 1
}

# 定位头文件绝对路径（防止 Header 写了相对路径）
$headerAbs = ""
$tryPaths = @(
	(Join-Path $projPath $Header),
	(Join-Path (Join-Path $projPath "main") $Header)
)
foreach ($tp in $tryPaths) {
	if (Test-Path -LiteralPath $tp -PathType Leaf) { $headerAbs = $tp; break }
}
if (-not $headerAbs) {
	# 递归搜索
	$found = Get-ChildItem -LiteralPath $projPath -Recurse -Filter $Header -File -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($found) { $headerAbs = $found.FullName }
}
if (-not $headerAbs) {
	Write-Host "[!] 在项目中找不到头文件: $Header" -ForegroundColor Yellow
	Write-Host "    将仍然执行影响分析（可能无结果）" -ForegroundColor Gray
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           修改前预检 / Pre-Edit Check            ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  目标头文件: $Header"
Write-Host "  项目目录:   $projPath"
if ($Symbol) { Write-Host "  目标符号:   $Symbol" }
Write-Host ""

# ========== Step 1: 运行 impact-analyze 并捕获输出 ==========
Write-Host "[1/4] 运行变更影响分析..." -ForegroundColor Cyan

$analysisParams = @{
	Path   = $projPath
	Header = $Header
	Detail = $false
}
if ($Symbol) { $analysisParams["Symbol"] = $Symbol }

& $impactScript @analysisParams

# ========== Step 2: 解析受影响文件清单（重新跑一遍拿结构化数据） ==========
Write-Host ""
Write-Host "[2/4] 提取高/中影响文件，准备自动备份..." -ForegroundColor Cyan

$sourceFiles = Get-ChildItem -LiteralPath $projPath -Recurse -Include *.c,*.cpp,*.cc,*.cxx -File -ErrorAction SilentlyContinue
$includePattern = '#include\s*"' + [regex]::Escape($Header) + '"'
$prefix = [System.IO.Path]::GetFileNameWithoutExtension($Header)
$symbolPattern = if ($Symbol) { '\b' + [regex]::Escape($Symbol) } else { '\b' + [regex]::Escape($prefix) + '_\w+' }

$highFiles = @()
$mediumFiles = @()
$lowFiles = @()

foreach ($file in $sourceFiles) {
	$lines = Get-Content $file.FullName -ErrorAction SilentlyContinue
	if (-not $lines) { continue }
	$hasInc = $false; $callCnt = 0
	foreach ($line in $lines) {
		if (-not $hasInc -and $line -match $includePattern) { $hasInc = $true }
		$callCnt += [regex]::Matches($line, $symbolPattern).Count
	}
	if ($hasInc) {
		if ($callCnt -ge 5) { $highFiles += $file.FullName }
		elseif ($callCnt -ge 1) { $mediumFiles += $file.FullName }
		else { $lowFiles += $file.FullName }
	}
}

Write-Host "  高影响 ($($highFiles.Count)): 调用 >=5 次，必须同步修改" -ForegroundColor Red
foreach ($f in $highFiles) { Write-Host "    !! $f" -ForegroundColor Red }
Write-Host "  中影响 ($($mediumFiles.Count)): 调用 1-4 次，可能需要修改" -ForegroundColor Yellow
foreach ($f in $mediumFiles) { Write-Host "    ?  $f" -ForegroundColor Yellow }
Write-Host "  低影响 ($($lowFiles.Count)): 仅 include 未调用" -ForegroundColor Gray
foreach ($f in $lowFiles) { Write-Host "    -  $f" -ForegroundColor Gray }

# ========== Step 3: 自动备份（.h 本身 + 高/中 影响的 .c） ==========
Write-Host ""
Write-Host "[3/4] 自动备份（头文件 + 高/中影响源文件）..." -ForegroundColor Cyan

$toBackup = @()
if ($headerAbs) { $toBackup += $headerAbs }
$toBackup += $highFiles
$toBackup += $mediumFiles
$toBackup = $toBackup | Select-Object -Unique  # 去重

if ($toBackup.Count -eq 0) {
	Write-Host "  [!] 没有找到任何可备份文件（未定位到头文件，且无引用）" -ForegroundColor Yellow
}
else {
	& $editSafe $toBackup
}

# ========== Step 4: 同步检查清单 ==========
Write-Host ""
Write-Host "[4/4] 修改完成后必须逐项核对:" -ForegroundColor Cyan
Write-Host "  ┌─────────────────────────────────────────────────"
$idx = 0
if ($headerAbs) {
	$idx++
	Write-Host "  │ $idx. 头文件本身: $Header => 是否已同步改对应 .c 的实现签名？"
}
foreach ($f in $highFiles) {
	$idx++
	$rel = $f.Replace($projPath, "").TrimStart("\")
	Write-Host "  │ $idx. [高] $rel => 函数参数/返回值/宏/结构体是否兼容？"
}
foreach ($f in $mediumFiles) {
	$idx++
	$rel = $f.Replace($projPath, "").TrimStart("\")
	Write-Host "  │ $idx. [中] $rel => 是否有调用受影响？"
}
Write-Host "  └─────────────────────────────────────────────────"
Write-Host ""
Write-Host "  快速重查命令: impact-analyze -Header $Header -Path $projPath -Detail" -ForegroundColor Gray

# ========== 交互确认（非 SkipConfirm 模式） ==========
if (-not $SkipConfirm -and -not [Console]::IsInputRedirected -and $Host.Name -notmatch 'NonInteractive') {
	Write-Host ""
	$confirm = Read-Host "以上文件已备份，确认继续修改? (Y=继续 / N=取消)"
	if ($confirm -notmatch '^[Yy]') {
		Write-Host "已取消。可执行: edit-safe -Restore <文件名> 恢复备份" -ForegroundColor Yellow
		exit 2
	}
}

# Exit code: 有高影响文件返回 1（提醒），否则 0
if ($highFiles.Count -gt 0) { exit 1 } else { exit 0 }
