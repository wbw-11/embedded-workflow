<#
.SYNOPSIS
	项目清理工具
.DESCRIPTION
	安全清理项目中间文件，清理前要求用户确认
.EXAMPLE
	keil-clean              # 自动检测项目类型并清理
	keil-clean -ESP32       # 清理 ESP-IDF 项目
	keil-clean -All         # 清理所有类型文件
	keil-clean -Force       # 跳过确认直接清理
  version: 1.0.0
#>

param([switch]$ESP32, [switch]$All, [switch]$Force)

$keilExtensions = @('.bak', '.ddk', '.edk', '.lst', '.lnp', '.mpf', '.mpj',
'.obj', '.omf', '.plg', '.rpt', '.tmp', '.__i', '._ia',
'.crf', '.o', '.d', '.axf', '.tra', '.dep', '.iex',
'.htm', '.sct', '.map', '.sbr', '.m51')

$keilFiles = @('JLinkLog.txt')
$keilGuiPatterns = @('*.uvgui.*')

$esp32CleanItems = @('build', 'sdkconfig.old', 'managed_components', '.cache')

$isEsp32 = $false
$isKeil = $false

if (Test-Path 'CMakeLists.txt') {
	$cmakeContent = Get-Content 'CMakeLists.txt' -Raw -ErrorAction SilentlyContinue
	if ($cmakeContent -match 'idf_component_register') { $isEsp32 = $true }
}

if (Get-ChildItem -Filter '*.uvprojx' -ErrorAction SilentlyContinue) { $isKeil = $true }
if (Get-ChildItem -Filter '*.uvproj' -ErrorAction SilentlyContinue) { $isKeil = $true }

if ($All) { $isEsp32 = $true; $isKeil = $true }
if ($ESP32) { $isEsp32 = $true }

if (-not $isEsp32 -and -not $isKeil) { $isKeil = $true }

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  项目清理工具 v2.0' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

$totalFiles = 0
$totalDirs = 0

if ($isKeil) {
	foreach ($ext in $keilExtensions) {
		$files = Get-ChildItem -Filter "*$ext" -Recurse -ErrorAction SilentlyContinue
		$totalFiles += $files.Count
	}
	foreach ($name in $keilFiles) {
		$files = Get-ChildItem -Filter $name -Recurse -ErrorAction SilentlyContinue
		$totalFiles += $files.Count
	}
	foreach ($pattern in $keilGuiPatterns) {
		$files = Get-ChildItem -Filter $pattern -Recurse -ErrorAction SilentlyContinue
		$totalFiles += $files.Count
	}
}

if ($isEsp32) {
	foreach ($item in $esp32CleanItems) {
		if (Test-Path $item) {
			$totalDirs++
		}
	}
}

Write-Host "即将清理:" -ForegroundColor Yellow
if ($isKeil) { Write-Host "  - $totalFiles 个 Keil 中间文件" -ForegroundColor Yellow }
if ($isEsp32) { Write-Host "  - $totalDirs 个 ESP-IDF 目录 (build, .cache 等)" -ForegroundColor Yellow }
Write-Host ''

if (-not $Force) {
	$confirm = Read-Host '确认清理？(Y/N)'
	if ($confirm -notmatch '^[Yy]') {
		Write-Host '[!] 用户取消清理' -ForegroundColor Yellow
		exit 0
	}
}

if ($isKeil) {
	Write-Host '[Keil] 清理中间文件...' -ForegroundColor Yellow
	$cleanedCount = 0
	foreach ($ext in $keilExtensions) {
		$files = Get-ChildItem -Filter "*$ext" -Recurse -ErrorAction SilentlyContinue
		foreach ($f in $files) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue; $cleanedCount++ }
	}
	foreach ($name in $keilFiles) {
		$files = Get-ChildItem -Filter $name -Recurse -ErrorAction SilentlyContinue
		foreach ($f in $files) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue; $cleanedCount++ }
	}
	foreach ($pattern in $keilGuiPatterns) {
		$files = Get-ChildItem -Filter $pattern -Recurse -ErrorAction SilentlyContinue
		foreach ($f in $files) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue; $cleanedCount++ }
	}
	Write-Host "  [OK] 清理 $cleanedCount 个文件" -ForegroundColor Green
}

if ($isEsp32) {
	Write-Host ''
	Write-Host '[ESP-IDF] 清理构建目录...' -ForegroundColor Yellow
	$cleanedCount = 0
	foreach ($item in $esp32CleanItems) {
		if (Test-Path $item) {
			Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue
			if (-not (Test-Path $item)) { $cleanedCount++ }
		}
	}
}

Write-Host '[OK] 清理完成' -ForegroundColor Green
