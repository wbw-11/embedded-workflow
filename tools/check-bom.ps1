<#
.SYNOPSIS
	Tools 脚本编码自检工具 - 检测"无 BOM + 含中文"的 .ps1 文件
.DESCRIPTION
	PowerShell 5.1 按系统 ANSI(GBK) 读取无 BOM 的 UTF-8 文件，中文注释的字节序列会吞掉引号，
	导致脚本运行时语法错误（Parser API 检查不出来，必须实际运行才能发现）。
	本工具全量扫描 .ps1/.psm1，找出这类隐患文件，并支持自动修复（加 BOM + 备份）。
.USAGE
	.\check-bom.ps1              # 扫描脚本所在目录（默认 Tools），只报告不修复
	.\check-bom.ps1 -Fix         # 扫描并自动加 BOM（修复前备份到 bom_fix_backup_<时间戳>）
	.\check-bom.ps1 -Path D:\xxx # 扫描指定目录
	.\check-bom.ps1 -Quiet       # 静默模式（供 self-update 调用，只输出问题）
	退出码: 0 = 干净（或修复完成）, 1 = 存在隐患未修复
  version: 1.0.0
#>
param(
	[string]$Path = '',
	[switch]$Fix,
	[switch]$Quiet
)

if (-not $Path) {
	$Path = $PSScriptRoot
}

if (-not (Test-Path $Path)) {
	Write-Host "[X] 目录不存在: $Path" -ForegroundColor Red
	exit 2
}

# 严格 UTF-8 解码器（非法字节抛异常，用于区分 UTF-8 和其他编码）
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)

$dangerous = @()   # 无 BOM + UTF-8 + 含中文（高危，PS5.1 会乱码）
$unknown = @()     # 无 BOM + 非 UTF-8（可能是 GBK 存量文件，需人工判断）
$scanned = 0

$files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
	Where-Object {
		$_.Extension -in '.ps1', '.psm1' -and
		$_.FullName -notmatch 'bom_fix_backup'
	}

foreach ($f in $files) {
	$scanned++
	$bytes = [System.IO.File]::ReadAllBytes($f.FullName)
	$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

	if ($hasBom) { continue }

	# 跳过空文件/过短文件（无内容可判断）
	if ($bytes.Length -lt 2) { continue }

	try {
		$text = $strictUtf8.GetString($bytes)
		$isUtf8 = $true
	} catch {
		$isUtf8 = $false
	}

	if ($isUtf8) {
		if ($text -match '[\u4e00-\u9fff]') {
			$dangerous += $f.FullName
		}
	} else {
		$unknown += $f.FullName
	}
}

if (-not $Quiet) {
	Write-Host "扫描目录: $Path" -ForegroundColor Cyan
	Write-Host "共扫描 $scanned 个 .ps1/.psm1 文件" -ForegroundColor Cyan
}

if ($dangerous.Count -eq 0 -and $unknown.Count -eq 0) {
	if (-not $Quiet) {
		Write-Host "[OK] 全部脚本编码正常（UTF-8 带 BOM 或无中文）" -ForegroundColor Green
	}
	exit 0
}

if (-not $Quiet) {
	Write-Host ""
}
foreach ($p in $dangerous) {
	Write-Host ("[!] 无BOM+中文: {0}" -f $p) -ForegroundColor Yellow
}
foreach ($p in $unknown) {
	Write-Host ("[?] 非UTF-8: {0}" -f $p) -ForegroundColor Magenta
}

if ($Fix) {
	$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
	$backupDir = Join-Path $Path "bom_fix_backup_$stamp"
	$fixedCount = 0

	foreach ($p in $dangerous) {
		# 只修危险类（无 BOM + UTF-8 + 中文），非 UTF-8 文件不动（避免损坏 GBK 存量文件）
		if (-not (Test-Path $backupDir)) {
			New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
		}
		Copy-Item -Path $p -Destination (Join-Path $backupDir (Split-Path $p -Leaf)) -Force
		$data = [System.IO.File]::ReadAllBytes($p)
		[System.IO.File]::WriteAllBytes($p, ([byte[]](0xEF, 0xBB, 0xBF) + $data))
		$fixedCount++
		Write-Host ("[OK] 已加 BOM: {0}" -f $p) -ForegroundColor Green
	}

	if ($unknown.Count -gt 0) {
		Write-Host "[!] 非 UTF-8 文件未自动处理，请人工检查确认编码" -ForegroundColor Yellow
	}
	if ($fixedCount -gt 0) {
		if (-not $Quiet) {
			Write-Host ("备份目录: {0}" -f $backupDir) -ForegroundColor Cyan
		}
		exit 0
	}
}

# 未修复或还有未处理项
exit 1
