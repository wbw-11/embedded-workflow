<#
.SYNOPSIS
技能拆分助手：按行区间从 SKILL.md 拆出同目录 reference.md
.DESCRIPTION
用法：
  split-skill -Name gh-cli -Range "317-2016" -RefTitle "命令速查大全" -RefNote "gh release/issue/pr 等全部子命令"
   - 将 SKILL.md 第 317-2016 行移到同目录 reference.md
   - SKILL.md 保留其余行，在第一个区间处插入桥接指引（指向 reference.md）
   - 自动校验行数守恒（kept + moved == total），不守恒则拒绝写入
   - 保留原 BOM 与换行符
参数：
  -Name        技能目录名（在 .trae-cn\skills 下）
  -Range       行区间列表，分号分隔，如 "183-239;345-589;604-661"（1-based 含端）
  -RefTitle    reference.md 标题用词（默认"详细参考"）
  -RefNote     桥接说明里补充移出内容描述（默认空）
  -Dry         只预览不写文件
.EXAMPLE
split-skill -Name embedded-dev-rules -Range "183-239;345-589;604-661" -Dry
split-skill -Name keil-auto-flash -Range "502-590" -RefTitle "辅助脚本与示例" -RefNote "芯片表/内存统计/日志判断"
  version: 1.0.0
#>
param(
	[string]$Name = '',
	[string]$Range = '',
	[string]$RefTitle = '详细参考',
	[string]$RefNote = '',
	[switch]$Dry
)

# ==================== 解析区间 ====================
function Parse-Ranges {
	param([string]$RangeText, [int]$Total)
	$list = @()
	$parts = $RangeText -split ';'
	foreach ($p in $parts) {
		$p = $p.Trim()
		if ($p -notmatch '^(\d+)-(\d+)$') {
			Write-Host "[X] 区间格式错误: '$p'（应为 A-B）" -ForegroundColor Red
			exit 1
		}
		$a = [int]$matches[1]; $b = [int]$matches[2]
		if ($a -lt 1 -or $b -lt $a -or $b -gt $Total) {
			Write-Host "[X] 区间越界: $a-$b（文件共 $Total 行）" -ForegroundColor Red
			exit 1
		}
		$list += @{ start = $a; end = $b }
	}
	# 排序 + 重叠检查
	$sorted = $list | Sort-Object { $_.start }
	$prev = 0
	foreach ($r in $sorted) {
		if ($r.start -le $prev) {
			Write-Host "[X] 区间重叠或未升序: $($r.start)-$($r.end)" -ForegroundColor Red
			exit 1
		}
		$prev = $r.end
	}
	return ,$sorted
}

# ==================== 定位技能文件 ====================
$skillRoot = @(
	"$env:USERPROFILE\.trae-cn\skills",
	"$env:USERPROFILE\.qoderworkcn\skills"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Name -or -not $Range) { Write-Host '[X] 必填 -Name 与 -Range' -ForegroundColor Red; exit 1 }
$dir = Join-Path $skillRoot $Name
$src = Join-Path $dir 'SKILL.md'
if (-not (Test-Path $src)) { Write-Host "[X] 未找到 $src" -ForegroundColor Red; exit 1 }

$bytes = [System.IO.File]::ReadAllBytes($src)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$text = [System.IO.File]::ReadAllText($src)
$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$all = [System.IO.File]::ReadAllLines($src)
$total = $all.Count
if ($total -lt 30) { Write-Host "[X] 文件仅 $total 行，无需拆分" -ForegroundColor Yellow; exit 2 }

# 防重复拆分：已有 reference.md 且 SKILL.md 已含 reference.md 指引
$refPath = Join-Path $dir 'reference.md'
if ((Test-Path $refPath) -and $text.Contains('reference.md')) {
	Write-Host "[X] 该技能已拆分（reference.md 已存在且 SKILL.md 已有引用），如需重拆请先删除 reference.md" -ForegroundColor Yellow
	exit 2
}

$ranges = @(Parse-Ranges $Range $total)
$moved = 0
foreach ($r in $ranges) { $moved += ($r.end - $r.start + 1) }
$kept = $total - $moved

# ==================== 构造 reference.md 内容 ====================
$refHead = @(
	"# $Name - $RefTitle",
	'',
	"> 本文件为 $Name 技能的 $RefTitle（自 SKILL.md 拆分）。SKILL.md 保留核心工作流，需要详细信息时打开本文件。",
	'',
	'---',
	''
)
$refContent = @()
$refContent += $refHead
foreach ($r in $ranges) {
	$refContent += $all[($r.start-1)..($r.end-1)]
}

# ==================== 构造新 SKILL.md 内容 ====================
$keep = @()
$bridge = @(
	'',
	'## 详细参考',
	'',
	"> 以下完整内容维护在 **同目录 reference.md**：$RefNote",
	'> 主文件保留核心工作流，需要详情时打开 reference.md。',
	'',
	'---',
	''
)
$cursor = 0
$i = 0
foreach ($r in $ranges) {
	if ($r.start - 1 -gt $cursor) {
		$keep += $all[$cursor..($r.start-2)]   # 区间前保留段
	}
	if ($i -eq 0) { $keep += $bridge }        # 第一个区间处插入桥接
	$cursor = $r.end                          # 跳过区间
	$i++
}
if ($cursor -le $total - 1) { $keep += $all[$cursor..($total-1)] }  # 尾部保留段

# ==================== 行数守恒校验 ====================
if (($keep.Count - $bridge.Count + $moved) -ne $total) {
	Write-Host "[X] 行数守恒校验失败 keep=$($keep.Count) bridge=$($bridge.Count) moved=$moved total=$total" -ForegroundColor Red
	exit 1
}

# ==================== 输出预览 / 写入 ====================
Write-Host "技能:      $Name" -ForegroundColor Cyan
Write-Host "原行数:    $total" -ForegroundColor Cyan
Write-Host "移出区间:  $($ranges | ForEach-Object { "$($_.start)-$($_.end)" })" -ForegroundColor Cyan
Write-Host "新 SKILL:  $($keep.Count) 行" -ForegroundColor Cyan
Write-Host "reference: $($refContent.Count) 行" -ForegroundColor Cyan
if ($Dry) { Write-Host '[Dry] 预览结束，未写入任何文件' -ForegroundColor Yellow; exit 0 }

$enc = New-Object System.Text.UTF8Encoding($hasBom)
[System.IO.File]::WriteAllText($src, (($keep -join $nl) + $nl), $enc)
[System.IO.File]::WriteAllText($refPath, (($refContent -join $nl) + $nl), $enc)
Write-Host "[OK] 已写入 SKILL.md（$($keep.Count) 行）与 reference.md（$($refContent.Count) 行）" -ForegroundColor Green
exit 0
