<#
.SYNOPSIS
技能库健康体检工具：行数/编码/frontmatter(version)/代码块成对/reference 关联 一键扫描
.DESCRIPTION
扫描技能 SKILL.md，检查：
  P0：空文件 / 行数 <30（空壳）
  P1：编码损坏 / 代码块不配对 / 行数 >1000
  P2：frontmatter 缺 version / reference.md 存在但 SKILL.md 无引用指引
  P3：行数 500-1000（建议拆分，仅提示）
输出报告与退出码：0=干净，1=有 P0/P1，2=仅 P2/P3
.EXAMPLE
check-skills                       # 全部技能体检
check-skills -Path C:\Users\xx\.trae-cn\skills\gh-cli   # 单个技能
check-skills -Quiet                # 只输出问题概要
  version: 1.0.0
#>
param(
	[string]$Path = '',
	[switch]$Quiet
)

function Test-Utf8 {
	param([byte[]]$Bytes)
	try {
		$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
		$null = $utf8.GetString($Bytes)
		return $true
	} catch { return $false }
}

# ==================== 确定扫描根 ====================
$skillRoot = $Path
if (-not $skillRoot) {
	$skillRoot = @(
		"$env:USERPROFILE\.trae-cn\skills",
		"$env:USERPROFILE\.qoderworkcn\skills"
	) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $skillRoot -or -not (Test-Path $skillRoot)) {
	Write-Host '[X] 未找到技能目录' -ForegroundColor Red
	exit 1
}
if (-not $Quiet) { Write-Host "扫描目录: $skillRoot" -ForegroundColor Cyan }

# SKILL.md：技能根目录下一层子目录（插件技能结构不同，默认不递归）
$files = Get-ChildItem $skillRoot -Depth 1 -Filter 'SKILL.md' -File -ErrorAction SilentlyContinue

$p0 = @(); $p1 = @(); $p2 = @(); $p3 = @()
foreach ($f in $files) {
	$name = $f.Directory.Name
	$full = $f.FullName
	$bytes = [System.IO.File]::ReadAllBytes($full)
	$text = [System.IO.File]::ReadAllText($full)
	$lines = $text -split "`r?`n"
	$lineCount = $lines.Count
	$probs = @()

	# P0: 空文件 / 空壳
	if ($bytes.Length -eq 0) { $p0 += "${name}:空文件"; continue }
	if ($lineCount -lt 30) { $p0 += "${name}:仅${lineCount}行(空壳)"; continue }

	# P1: 编码
	if (-not (Test-Utf8 $bytes)) { $probs += '编码非UTF-8' }

	# P1: 代码块成对
	$codeMarks = ([regex]::Matches($text, '(?m)^```')).Count
	if ($codeMarks % 2 -ne 0) { $probs += "代码块不配对($codeMarks)" }

	# frontmatter 顶层字段
	$fm = @()
	foreach ($l in $lines) {
		if ($l -eq '---' -and $fm.Count -gt 0) { break }
		$fm += $l
	}
	$fmText = $fm -join "`n"

	# P2: version
	if ($fmText -notmatch '(?m)^version:\s*\S') { $probs += 'frontmatter缺version' }

	# name/description（重要，破损即报入 P1）
	if ($fmText -notmatch '(?m)^name:\s*\S') { $probs += 'frontmatter缺name' }
	if ($fmText -notmatch '(?m)^description:\s*\S') { $probs += 'frontmatter缺description' }

	# P2: reference 关联（存在 reference.md 则 SKILL.md 须含指引）
	$refFile = Join-Path $f.Directory.FullName 'reference.md'
	if ((Test-Path $refFile) -and -not $text.Contains('reference.md')) {
		$probs += '有reference.md但SKILL.md无引用'
	}

	# 行数分级
	if ($lineCount -gt 1000) { $probs += "${lineCount}行(>1000,建议拆分)" }
	elseif ($lineCount -gt 500) { $p3 += "${name}:${lineCount}行(500-1000,可拆分)" }

	if ($probs.Count -gt 0) { $p1 += "${name}:  $($probs -join ', ')" }
}

# ==================== 输出报告 ====================
if (-not $Quiet) {
	Write-Host "`n========== 体检报告（共 $($files.Count) 个技能） ==========" -ForegroundColor White
	Write-Host "`n[P0] 无法使用 ($($p0.Count))" -ForegroundColor Red
	if ($p0.Count -eq 0) { Write-Host '  无' } else { $p0 | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red } }
	Write-Host "`n[P1] 编码/代码块/超长损坏 ($($p1.Count))" -ForegroundColor Yellow
	if ($p1.Count -eq 0) { Write-Host '  无' } else { $p1 | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow } }
	Write-Host "`n[P2] 维护隐患 ($($p2.Count))" -ForegroundColor Gray
	if ($p2.Count -eq 0) { Write-Host '  无' } else { $p2 | ForEach-Object { Write-Host "  - $_" } }
	Write-Host "`n[P3] 建议优化 ($($p3.Count))" -ForegroundColor Gray
	if ($p3.Count -eq 0) { Write-Host '  无' } else { $p3 | ForEach-Object { Write-Host "  - $_" } }
}
if ($p0.Count + $p1.Count -gt 0) { Write-Host "[结果] 有 P0/P1 问题，需处理" -ForegroundColor Red; exit 1 }
if ($p0.Count + $p1.Count -eq 0 -and $p2.Count -eq 0) { if (-not $Quiet) { Write-Host "[结果] 全部健康" -ForegroundColor Green }; exit 0 }
if (-not $Quiet) { Write-Host "[结果] 仅 P2/P3 提示" -ForegroundColor Yellow }
exit 2
