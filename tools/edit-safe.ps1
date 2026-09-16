<#
.SYNOPSIS
	安全文件编辑包装器 - 修改文件前自动创建时间戳备份。
.DESCRIPTION
	修改任何源码文件前先调用本脚本，自动创建 .bak_YYYYMMDD_HHMMSS 备份。
	如果文件已经有 .bak，会根据当前时间生成新的带时间戳后缀，不覆盖旧备份。
	支持批量处理多个文件。
.PARAMETER Files
	要编辑的文件路径列表（可用逗号分隔，或 pipeline 输入）
.PARAMETER Restore
	从最新时间戳备份恢复（删除当前文件，重命名最新 .bak_* 为原文件名）
.PARAMETER List
	列出指定文件的所有现有备份（按时间倒序）
.EXAMPLE
	edit-safe main.c
	为 main.c 创建备份，返回备份路径（之后可放心改 main.c）

.EXAMPLE
	edit-safe -Files main.c,app_config.h,audio_self_test.h
	批量创建多文件备份

.EXAMPLE
	edit-safe -Restore main.c
	从最新时间戳备份恢复 main.c

.EXAMPLE
	edit-safe -List main.c
	查看 main.c 的所有现有备份
  version: 1.0.0
#>

param(
	[Parameter(Position = 0, ValueFromRemainingArguments = $true, ValueFromPipeline = $true)]
	[string[]]$Files,

	[switch]$Restore,
	[switch]$List
)

$ErrorActionPreference = "Stop"

function Get-TimeStampSuffix {
	<# 返回当前时间的紧凑后缀，如 20260801_170530 #>
	return (Get-Date -Format "yyyyMMdd_HHmmss")
}

function New-SafeBackup {
	param([string]$FilePath)

	if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
		Write-Host "[!] 文件不存在，跳过备份: $FilePath" -ForegroundColor Yellow
		return $null
	}

	$absPath = (Resolve-Path -LiteralPath $FilePath).Path
	$dir = Split-Path $absPath -Parent
	$name = Split-Path $absPath -Leaf
	$suffix = Get-TimeStampSuffix
	$backupPath = Join-Path $dir "$name.bak_$suffix"

	$tries = 0
	while ((Test-Path -LiteralPath $backupPath) -and $tries -lt 10) {
		$tries++
		Start-Sleep -Milliseconds 150
		$suffix = Get-TimeStampSuffix
		$backupPath = Join-Path $dir "$name.bak_$suffix"
	}

	try {
		Copy-Item -LiteralPath $absPath -Destination $backupPath -Force
		$size = (Get-Item -LiteralPath $backupPath).Length
		Write-Host "[OK] 备份已创建: $backupPath ($size bytes)" -ForegroundColor Green
		return $backupPath
	}
	catch {
		Write-Host "[X] 备份失败: $($_.Exception.Message)" -ForegroundColor Red
		return $null
	}
}

function Restore-LatestBackup {
	param([string]$FilePath)

	if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
		Write-Host "[!] 目标文件不存在，无法恢复: $FilePath" -ForegroundColor Yellow
		return
	}

	$absPath = (Resolve-Path -LiteralPath $FilePath).Path
	$dir = Split-Path $absPath -Parent
	$name = Split-Path $absPath -Leaf
	$pattern = "$name.bak_*"

	$backups = Get-ChildItem -LiteralPath $dir -Filter $pattern -File -ErrorAction SilentlyContinue |
		Sort-Object LastWriteTime -Descending

	if (-not $backups -or $backups.Count -eq 0) {
		Write-Host "[!] 没有找到任何备份 ($pattern)" -ForegroundColor Yellow
		return
	}

	$latest = $backups[0]
	Write-Host "[*] 最新备份: $($latest.Name) ($($latest.LastWriteTime))" -ForegroundColor Cyan
	$confirm = Read-Host "确认恢复当前文件 $name 到此备份？(Y/N)"
	if ($confirm -notmatch '^[Yy]') {
		Write-Host "已取消恢复。" -ForegroundColor Gray
		return
	}

	try {
		# 先备份当前文件（避免误删）
		$rollback = Join-Path $dir "$name.pre_restore_$(Get-TimeStampSuffix)"
		Copy-Item -LiteralPath $absPath -Destination $rollback
		Remove-Item -LiteralPath $absPath -Force
		Rename-Item -LiteralPath $latest.FullName -NewName $name
		Write-Host "[OK] 已从备份恢复: $name" -ForegroundColor Green
		Write-Host "    恢复前的原文件保存在: $rollback（如不需要可手动删除）" -ForegroundColor Gray
	}
	catch {
		Write-Host "[X] 恢复失败: $($_.Exception.Message)" -ForegroundColor Red
	}
}

function List-Backups {
	param([string]$FilePath)

	if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
		# 即使文件被删了，也尝试列目录里的备份
		$dir = Split-Path (Resolve-Path (Split-Path $FilePath -Parent)).Path -Parent
		$name = Split-Path $FilePath -Leaf
	}
	else {
		$absPath = (Resolve-Path -LiteralPath $FilePath).Path
		$dir = Split-Path $absPath -Parent
		$name = Split-Path $absPath -Leaf
	}

	$pattern = "$name.bak_*"
	$backups = Get-ChildItem -LiteralPath $dir -Filter $pattern -File -ErrorAction SilentlyContinue |
		Sort-Object LastWriteTime -Descending

	if (-not $backups -or $backups.Count -eq 0) {
		Write-Host "[-] $name 没有任何备份" -ForegroundColor Gray
		return
	}

	Write-Host "=== $name 的备份列表（共 $($backups.Count) 个，时间倒序）===" -ForegroundColor Cyan
	for ($i = 0; $i -lt $backups.Count; $i++) {
		$b = $backups[$i]
		$marker = if ($i -eq 0) { " [最新]" } else { "" }
		Write-Host ("  {0,2}. {1,-26} {2,8} bytes   {3}{4}" -f
			($i + 1), $b.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"),
			$b.Length, $b.Name, $marker)
	}
}

# ============== 主流程 ==============

if ($Restore) {
	if (-not $Files -or $Files.Count -eq 0) {
		Write-Host "[X] -Restore 需要指定要恢复的文件路径" -ForegroundColor Red
		exit 1
	}
	foreach ($f in $Files) { Restore-LatestBackup $f }
	exit 0
}

if ($List) {
	if (-not $Files -or $Files.Count -eq 0) {
		Write-Host "[X] -List 需要指定要查看的文件路径" -ForegroundColor Red
		exit 1
	}
	foreach ($f in $Files) { List-Backups $f }
	exit 0
}

# 默认：备份模式
if (-not $Files -or $Files.Count -eq 0) {
	Write-Host "[X] 未指定任何文件。" -ForegroundColor Red
	Write-Host "用法: edit-safe <file1> [file2 ...]  或  edit-safe -List <file>  或  edit-safe -Restore <file>" -ForegroundColor Yellow
	exit 1
}

$count = 0
foreach ($f in $Files) {
	$b = New-SafeBackup $f
	if ($b) { $count++ }
}

Write-Host ""
Write-Host "[完成] 共备份 $count / $($Files.Count) 个文件" -ForegroundColor Green
