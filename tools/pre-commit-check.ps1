<#
.SYNOPSIS
	Git pre-commit 检查器 - 由 install-precommit 安装的钩子调用
.DESCRIPTION
	在仓库根目录运行（install-precommit 生成的钩子负责 cd），对暂存文件执行：
	1. 暂存 .ps1：无 BOM + 含中文 → 阻止提交（PowerShell 5.1 会读坏）
	2. 暂存 .c/.h：code-style-check 溢出+防御专项，退出码 3（P0 致命）→ 阻止提交
	退出码: 0 = 放行, 1 = 存在必须修复的问题（阻止提交）
.NOTES
	本脚本由 Tools\install-precommit.ps1 安装的 .git/hooks/pre-commit 调用，不直接手工运行
  version: 1.0.0
#>

$ErrorActionPreference = 'SilentlyContinue'

$repoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) {
	Write-Host '[X] pre-commit-check: 不是 git 仓库' -ForegroundColor Red
	exit 1
}
Set-Location $repoRoot

$staged = & git diff --cached --name-only --diff-filter=ACM 2>$null
$cFiles = @($staged | Where-Object { $_ -match '\.(c|h)$' })
$psFiles = @($staged | Where-Object { $_ -match '\.ps1$' })

if ($cFiles.Count -eq 0 -and $psFiles.Count -eq 0) {
	exit 0
}

$blocked = $false

# ---------- 1. 暂存 .ps1 编码检查 ----------
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
foreach ($f in $psFiles) {
	$full = Join-Path $repoRoot $f
	$bytes = [System.IO.File]::ReadAllBytes($full)
	$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
	if ($hasBom -or $bytes.Length -lt 2) { continue }
	try {
		$text = $strictUtf8.GetString($bytes)
		if ($text -match '[\u4e00-\u9fff]') {
			Write-Host "" -ForegroundColor Yellow
			Write-Host '[X] pre-commit 阻止: 以下 .ps1 无 UTF-8 BOM 且含中文' -ForegroundColor Red
			Write-Host "    $f" -ForegroundColor Red
			Write-Host '    修复: 运行 check-bom -Fix（或对文件加 UTF-8 BOM）后重新提交' -ForegroundColor Yellow
			$blocked = $true
		}
	} catch {}
}

# ---------- 2. 暂存 .c/.h 代码专项检查 ----------
if ($cFiles.Count -gt 0) {
	$checker = Join-Path $PSScriptRoot 'code-style-check.ps1'
	$maxCode = 0
	foreach ($f in $cFiles) {
		$full = Join-Path $repoRoot $f
		Write-Host "[*] pre-commit 检查: $f" -ForegroundColor Cyan
		& powershell -NoProfile -ExecutionPolicy Bypass -File $checker -Path $full -Checks "overflow,defensive" 2>&1 | ForEach-Object { Write-Host $_ }
		$code = $LASTEXITCODE
		if ($code -gt $maxCode) { $maxCode = $code }
	}
	if ($maxCode -eq 3) {
		Write-Host "" -ForegroundColor Yellow
		Write-Host '[X] 存在 P0 致命溢出隐患，提交已被阻止' -ForegroundColor Red
		Write-Host '    保留修改：先 commit 其他文件，或用 git commit --no-verify 强制提交' -ForegroundColor Yellow
		$blocked = $true
	} elseif ($maxCode -ge 1) {
		Write-Host '[!] 存在 P1/规范级问题（警告，不阻止），建议提交后纳入审查修复' -ForegroundColor Yellow
	}
}

if ($blocked) {
	exit 1
}
exit 0
