<#
.SYNOPSIS
	编译警告数据库查询/管理工具（v2.0 增强版 - 编译警告闭环）
.DESCRIPTION
	查询和管理编译警告/错误数据库，支持：
	- 按关键词 / 平台搜索
	- 从编译输出文件自动解析并匹配警告
	- 【新】对比历史日志（-CompareWith）：高亮"新出现"的警告，旧警告静默或降权显示
	- 【新】未知警告自动入库（-AutoAdd）：编译出现数据库没覆盖的 warning/error 时，交互追加
	- 【新】项目警告快照（-ProjectDir）：编译后保存当前警告摘要到 <ProjectDir>/build/warnings_snapshot.json
	- 交互式添加 / 详情查看 / 统计摘要
.PARAMETER Search
	搜索关键词（按 code、message、id 模糊匹配）
.PARAMETER Platform
	按平台过滤（c51/armcc/gcc/esp-idf/linker）
.PARAMETER Parse
	编译输出文件路径，自动解析并匹配警告
.PARAMETER CompareWith
	与 -Parse 搭配：旧版编译日志路径。输出差异：只高亮新出现警告（旧警告静默/降权）
.PARAMETER AutoAdd
	与 -Parse 搭配：未匹配到数据库的 warning/error 行，交互追加到数据库
.PARAMETER ProjectDir
	项目路径：若指定，分析完成后在 <ProjectDir>/build/warnings_snapshot.json 写快照
.PARAMETER QuietDiff
	与 -CompareWith 搭配：已存在于旧日志的警告完全不显示（仅输出差异）
.PARAMETER Add
	交互式添加新警告
.PARAMETER List
	列出所有警告
.PARAMETER Detail
	查看指定 id 的警告详情
.EXAMPLE
	warning-db -Parse build.log
	warning-db -Parse build.log -CompareWith last_build.log -QuietDiff
	warning-db -Parse build.log -AutoAdd -ProjectDir D:\proj\voice_assistant
	warning-db -Search "未定义" -Platform c51
  version: 1.0.0
#>

param(
	[string]$Search,
	[string]$Platform,
	[string]$Parse,
	[switch]$Add,
	[switch]$List,
	[string]$Detail,

	# ===== v2.0 新增：编译警告闭环 =====
	[switch]$AutoAdd,
	[string]$CompareWith,
	[string]$ProjectDir,
	[switch]$QuietDiff
)

$DbPath = Join-Path $PSScriptRoot 'warning-db.json'

function Load-WarningDb {
	<# 加载 JSON 数据库 #>
	if (-not (Test-Path $DbPath)) {
		Write-Host "错误：找不到数据库文件 $DbPath" -ForegroundColor Red
		return @()
	}
	try {
		$json = Get-Content $DbPath -Raw -Encoding UTF8
		$data = $json | ConvertFrom-Json
		return $data
	}
	catch {
		Write-Host "错误：数据库文件解析失败 - $_" -ForegroundColor Red
		return @()
	}
}

function Save-WarningDb($db) {
	<# 保存数据库到 JSON 文件 #>
	try {
		$json = $db | ConvertTo-Json -Depth 10
		$utf8Bom = New-Object System.Text.UTF8Encoding($true)
		[System.IO.File]::WriteAllText($DbPath, $json, $utf8Bom)
		return $true
	}
	catch {
		Write-Host "错误：保存数据库失败 - $_" -ForegroundColor Red
		return $false
	}
}

function Get-SeverityColor($severity) {
	switch ($severity) {
		'critical' { return 'Red' }
		'high'     { return 'Magenta' }
		'medium'   { return 'Yellow' }
		'low'      { return 'Gray' }
		default    { return 'White' }
	}
}
function Get-SeverityText($severity) {
	switch ($severity) {
		'critical' { return '严重' }
		'high'     { return '高' }
		'medium'   { return '中' }
		'low'      { return '低' }
		default    { return '未知' }
	}
}
function Get-TypeColor($type) {
	if ($type -eq 'error') { return 'Red' } else { return 'Yellow' }
}

function Search-Warnings($db, $keyword, $platformFilter) {
	$results = @()
	foreach ($item in $db) {
		$matched = $true
		if ($keyword) {
			$kw = $keyword.ToLower()
			$inId = $item.id.ToLower().Contains($kw)
			$inCode = $item.code.ToLower().Contains($kw)
			$inMessage = $item.message.ToLower().Contains($kw)
			$matched = $inId -or $inCode -or $inMessage
		}
		if ($matched -and $platformFilter) {
			$matched = $item.platform -eq $platformFilter.ToLower()
		}
		if ($matched) { $results += $item }
	}
	return $results
}

function Show-WarningDetail($item) {
	$typeText = if ($item.type -eq 'error') { '错误' } else { '警告' }
	$typeColor = Get-TypeColor $item.type
	$sevColor = Get-SeverityColor $item.severity
	$sevText = Get-SeverityText $item.severity

	Write-Host ''
	Write-Host ('─' * 49) -ForegroundColor Gray
	Write-Host "  $($item.id) - $($item.code): $($item.message)" -ForegroundColor Cyan
	Write-Host ('─' * 49) -ForegroundColor Gray
	Write-Host "  平台：" -NoNewline; Write-Host $item.platform.ToUpper() -ForegroundColor Green
	Write-Host "  类型：" -NoNewline; Write-Host $typeText -ForegroundColor $typeColor
	Write-Host "  严重程度：" -NoNewline; Write-Host $sevText -ForegroundColor $sevColor
	Write-Host ''
	Write-Host "  常见原因：" -ForegroundColor White
	for ($i = 0; $i -lt $item.causes.Count; $i++) {
		Write-Host "    $($i+1). $($item.causes[$i])" -ForegroundColor Gray
	}
	Write-Host ''
	Write-Host "  解决方案：" -ForegroundColor White
	for ($i = 0; $i -lt $item.solutions.Count; $i++) {
		Write-Host "    $($i+1). $($item.solutions[$i])" -ForegroundColor Green
	}
	Write-Host ''
}

function Show-ResultList($results) {
	if ($results.Count -eq 0) {
		Write-Host "未找到匹配的警告。" -ForegroundColor Yellow
		return
	}
	Write-Host "找到 $($results.Count) 条匹配：" -ForegroundColor Green
	Write-Host ''
	for ($i = 0; $i -lt $results.Count; $i++) {
		$item = $results[$i]
		$typeText = if ($item.type -eq 'error') { 'error' } else { 'warn' }
		$typeColor = Get-TypeColor $item.type
		$sevColor = Get-SeverityColor $item.severity
		Write-Host "[" -NoNewline -ForegroundColor Gray
		Write-Host ($i + 1).ToString().PadLeft(2) -NoNewline -ForegroundColor White
		Write-Host "] " -NoNewline -ForegroundColor Gray
		Write-Host $item.id.PadRight(15) -NoNewline -ForegroundColor Cyan
		Write-Host "[" -NoNewline -ForegroundColor Gray
		Write-Host $typeText -NoNewline -ForegroundColor $typeColor
		Write-Host "]" -NoNewline -ForegroundColor Gray
		Write-Host ("  " + $item.platform.ToUpper()).PadRight(10) -NoNewline -ForegroundColor Green
		Write-Host $item.code -NoNewline -ForegroundColor $sevColor
		Write-Host ": $($item.message)" -ForegroundColor White
	}
	Write-Host ''
}

# ===============================================
# v2.0 新增：编译警告对比 + AutoAdd 核心函数
# ===============================================

function Get-CompileWarningsRaw($filePath) {
	<# 从编译日志中提取所有包含 warning/error 关键字的行（归一化，用于对比去重）
	   返回哈希表集合：{ Key="平台|类型|代码"（可空）, Line="原始行", Pattern="匹配模式" }
	#>
	if (-not (Test-Path $filePath)) { return @() }
	$lines = Get-Content $filePath -Encoding UTF8 -ErrorAction SilentlyContinue
	if (-not $lines) { return @() }

	# 常见编译器 warning/error 行正则：
	#   GCC/ESP-IDF: file.c:123:5: warning: xxx [-Wxxx]
	#   ARMCC:   "file.c", line 123: Warning:  #123-D: ...
	#   C51:     MAIN.C(45): warning C206: ...
	#   通用匹配：含有 warning / error （大小写不敏感）的行
	$genericRx = [regex]'(?i)\b(warning|error)\b'
	$raw = @()
	foreach ($line in $lines) {
		if ($line -match $genericRx) { $raw += $line.Trim() }
	}
	return $raw
}

function New-DiffKey($line) {
	<# 对一行编译警告生成"去重对比键"：
	   去掉路径前缀（只保留文件名）、行号、列号，保留核心错误码/消息关键字。
	   这样路径不同/行号不同但警告相同的条目会被判断为"同一个旧警告"。
	#>
	$s = $line
	# 去掉磁盘路径前缀，只保留 文件名(行号)
	$s = [regex]::Replace($s, '[A-Za-z]:\\[^\s"\'']*?([^\\\/]+\.(?:c|cpp|h|hpp|cxx|cc|S|s))', '$1')
	# 去掉 行号:列号 或 (行号)
	$s = [regex]::Replace($s, '[\(:]\d+(?::\d+)?[\):]', ':X:')
	# 去掉路径分隔符前的部分
	$s = [regex]::Replace($s, '[^\s]+[\\\/]([^\\\/\s]+\.(?:c|cpp|h|hpp|cxx|cc))', '$1')
	# 去掉连续空白
	$s = [regex]::Replace($s, '\s+', ' ').Trim().ToLower()
	return $s
}

function Parse-CompileOutput($db, $filePath) {
	<#
	  v2.0 重写：返回结构化对象 @{ Matches=@(...); Unmatched=@(raw_line); OldWarningKeys=@(diffkey); Summary=@{...} }
	  同时打印（兼容旧版）
	#>
	if (-not (Test-Path $filePath)) {
		Write-Host "错误：找不到文件 $filePath" -ForegroundColor Red
		return $null
	}

	$lines = Get-Content $filePath -Encoding UTF8
	$matchedEntries = @()      # 匹配上数据库的条目
	$matchedDbItemIds = @{}    # 去重用：数据库项id -> 次数
	$unmatchedLines = @()      # 未匹配上但含 warning/error 的原始行
	$processedKeys = @{}       # 已处理过的日志行（避免重复）

	$genericRx = [regex]'(?i)\b(warning|error)\b'

	foreach ($line in $lines) {
		# 跳过已经处理过的完全相同行
		if ($processedKeys.ContainsKey($line)) { continue }
		$processedKeys[$line] = $true

		$isMatched = $false
		foreach ($item in $db) {
			try {
				if ($line -match $item.pattern) {
					$matchedEntries += @{ Line = $line; Warning = $item }
					if (-not $matchedDbItemIds.ContainsKey($item.id)) {
						$matchedDbItemIds[$item.id] = 0
					}
					$matchedDbItemIds[$item.id]++
					$isMatched = $true
					break
				}
			} catch {}
		}

		# 未匹配，但含 warning/error -> 入 unmatched 列表（AutoAdd 用）
		if (-not $isMatched -and $line -match $genericRx) {
			$unmatchedLines += $line.Trim()
		}
	}

	# ==== 对比旧日志（如果指定 -CompareWith）====
	$oldKeys = @{}
	if ($CompareWith -and (Test-Path $CompareWith)) {
		$oldRaw = Get-CompileWarningsRaw $CompareWith
		foreach ($ol in $oldRaw) {
			$k = New-DiffKey $ol
			if (-not $oldKeys.ContainsKey($k)) { $oldKeys[$k] = 0 }
			$oldKeys[$k]++
		}
		Write-Host ''
		Write-Host '=========================================' -ForegroundColor Cyan
		Write-Host "  编译警告对比 (基准: $(Split-Path $CompareWith -Leaf))" -ForegroundColor Cyan
		Write-Host '=========================================' -ForegroundColor Cyan
	}

	Write-Host ''
	Write-Host '=========================================' -ForegroundColor Cyan
	Write-Host '  编译警告自动分析' -ForegroundColor Cyan
	Write-Host '=========================================' -ForegroundColor Cyan
	Write-Host "解析文件：$filePath" -ForegroundColor Gray
	Write-Host ''

	if ($matchedEntries.Count -eq 0 -and $unmatchedLines.Count -eq 0) {
		Write-Host '未发现 warning / error 行，干净。' -ForegroundColor Green
		return @{ Matches=@(); Unmatched=@(); OldKeys=$oldKeys; Summary=@{Error=0;Warning=0;New=0} }
	}

	$errors   = $matchedEntries | Where-Object { $_.Warning.type -eq 'error' }
	$warnings = $matchedEntries | Where-Object { $_.Warning.type -eq 'warning' }

	Write-Host "共找到：已知错误 $($errors.Count) 个，已知警告 $($warnings.Count) 个，未知条目 $($unmatchedLines.Count) 个" -ForegroundColor White
	Write-Host ''

	$newWarningCount = 0

	# ------- 打印已知匹配 -------
	$idx = 0
	foreach ($m in $matchedEntries) {
		$idx++
		$item = $m.Warning
		$typeText = if ($item.type -eq 'error') { '错误' } else { '警告' }
		$typeColor = Get-TypeColor $item.type
		$sevColor = Get-SeverityColor $item.severity

		# 判断是否为"新警告"（对比旧日志）
		$isNew = $false
		$tag = ''
		if ($oldKeys.Count -gt 0) {
			$dk = New-DiffKey $m.Line
			if (-not $oldKeys.ContainsKey($dk)) {
				$isNew = $true; $newWarningCount++
				$tag = ' [NEW]'
			}
		}

		# QuietDiff：老警告跳过显示
		if ($QuietDiff -and $oldKeys.Count -gt 0 -and -not $isNew) { continue }

		$headerColor = if ($isNew) { 'Red' } else { $typeColor }
		Write-Host "【$typeText $idx/$($matchedEntries.Count)$tag】" -ForegroundColor $headerColor
		Write-Host "  代码：" -NoNewline; Write-Host $item.code -ForegroundColor $sevColor
		Write-Host "  信息：" -NoNewline; Write-Host $m.Line.Trim() -ForegroundColor White
		Write-Host "  匹配：" -NoNewline
		Write-Host "$($item.id) [" -NoNewline -ForegroundColor Cyan
		Write-Host (Get-SeverityText $item.severity) -NoNewline -ForegroundColor $sevColor
		Write-Host "]" -ForegroundColor Cyan
		if ($item.solutions.Count -gt 0) {
			Write-Host "  建议：" -NoNewline; Write-Host $item.solutions[0] -ForegroundColor Green
		}
		Write-Host ''
	}

	# ------- 打印未匹配条目（AutoAdd 候选） -------
	if ($unmatchedLines.Count -gt 0) {
		Write-Host ''
		Write-Host ('─' * 50) -ForegroundColor Magenta
		Write-Host "  未匹配到数据库的 warning/error（共 $($unmatchedLines.Count) 条，候选 AutoAdd）" -ForegroundColor Magenta
		Write-Host ('─' * 50) -ForegroundColor Magenta

		# 判断是否新警告（对比旧日志）
		$newUnmatchedCount = 0
		for ($i = 0; $i -lt $unmatchedLines.Count; $i++) {
			$ul = $unmatchedLines[$i]
			$dk = New-DiffKey $ul
			$isNew = ($oldKeys.Count -gt 0) -and (-not $oldKeys.ContainsKey($dk))
			if ($isNew) { $newUnmatchedCount++ }
			if ($QuietDiff -and $oldKeys.Count -gt 0 -and -not $isNew) { continue }

			$prefix = if ($isNew) { "[NEW]" } else { "[old]" }
			$color  = if ($isNew) { 'Red'   } else { 'Gray' }
			Write-Host ("  {0,2}. {1} {2}" -f ($i + 1), $prefix, $ul) -ForegroundColor $color
		}
		Write-Host ''
		Write-Host "提示：加 -AutoAdd 参数可交互式将这些未匹配警告追加到数据库。" -ForegroundColor Gray
	}

	$summary = @{
		Error        = $errors.Count
		Warning      = $warnings.Count
		Unmatched    = $unmatchedLines.Count
		NewKnown     = $newWarningCount
		NewUnmatched = if ($oldKeys.Count -gt 0) { $newUnmatchedCount } else { 0 }
	}

	return @{
		Matches       = $matchedEntries
		Unmatched     = $unmatchedLines
		OldKeys       = $oldKeys
		Summary       = $summary
		MatchedItemId = $matchedDbItemIds
	}
}

function Invoke-AutoAddUnmatched($db, $unmatchedLines) {
	<# -AutoAdd：交互式将未匹配条目逐个追加到数据库 #>
	if (-not $unmatchedLines -or $unmatchedLines.Count -eq 0) { return $db }

	Write-Host ''
	Write-Host '=========================================' -ForegroundColor Cyan
	Write-Host "  AutoAdd：将 $($unmatchedLines.Count) 条未匹配警告入库" -ForegroundColor Cyan
	Write-Host "  （逐项确认，q 跳过 / a 全部跳过）" -ForegroundColor Cyan
	Write-Host '=========================================' -ForegroundColor Cyan
	Write-Host ''

	$addedCount = 0
	$skipAll = $false

	for ($i = 0; $i -lt $unmatchedLines.Count; $i++) {
		if ($skipAll) { break }
		$line = $unmatchedLines[$i]
		Write-Host ("[{0}/{1}] {2}" -f ($i + 1), $unmatchedLines.Count, $line) -ForegroundColor White

		$prompt = '  添加到数据库? (Y=是 / N=跳过 / q=之后全跳过)'
		Write-Host $prompt -ForegroundColor Yellow -NoNewline
		$choice = Read-Host ' '
		if ($choice -match '^[Qq]') { $skipAll = $true; continue }
		if ($choice -notmatch '^[Yy]') { continue }

		# 猜测平台 + 类型 + 代码
		$guessedPlatform = 'esp-idf'
		if ($line -match 'C\d{2,4}') { $guessedPlatform = 'c51' }
		elseif ($line -match 'error: \#\d+-D' -or $line -match '"[^"]+", line') { $guessedPlatform = 'armcc' }
		$guessedType = 'warning'
		if ($line -match '(?i)\berror\b') { $guessedType = 'error' }

		$guessedCode = ''
		if ($line -match '(?i)(?:warning|error)\s*[#:]*\s*([A-Z]?\d{2,5}(?:-[A-Z0-9]+)?)') {
			$guessedCode = $matches[1]
		}
		# GCC -Wxxx
		if (-not $guessedCode -and $line -match '\[-[Ww](\S+)\]') {
			$guessedCode = 'W_' + $matches[1]
		}

		Write-Host ''
		Write-Host "  默认填写（回车接受默认值 / 输入自定义）：" -ForegroundColor Gray
		$id = Read-Host "    ID (如 esp-idf-Wshift-negative-value)"
		if ([string]::IsNullOrWhiteSpace($id)) {
			$stamp = (Get-Date -Format 'HHmmss')
			$id = "$guessedPlatform-$guessedType-new_$stamp"
		}
		# 避免重复
		foreach ($it in $db) { if ($it.id -eq $id) { $id = $id + '_2' } }

		$p1 = Read-Host "    platform ($guessedPlatform)"
		$p2 = Read-Host "    type ($guessedType)"
		$p3 = Read-Host "    code ($($guessedCode ?? '?'))"
		$p4 = Read-Host "    message"
		$p5 = Read-Host "    pattern (正则匹配模式)"
		$p6 = Read-Host "    severity (critical/high/medium/low)  (medium)"

		$plat = if ([string]::IsNullOrWhiteSpace($p1)) { $guessedPlatform } else { $p1 }
		$typ  = if ([string]::IsNullOrWhiteSpace($p2)) { $guessedType    } else { $p2 }
		$cod  = if ([string]::IsNullOrWhiteSpace($p3)) { $guessedCode    } else { $p3 }
		$msg  = if ([string]::IsNullOrWhiteSpace($p4)) { ($line.Length -gt 80)? $line.Substring(0,80)+'...' : $line } else { $p4 }
		$pat  = if ([string]::IsNullOrWhiteSpace($p5)) { [regex]::Escape($cod) } else { $p5 }
		$sev  = if ([string]::IsNullOrWhiteSpace($p6)) { 'medium' } else { $p6 }

		$c1 = Read-Host '    常见原因 1 (可空)'
		$c2 = Read-Host '    常见原因 2 (可空, 回车结束)'
		$s1 = Read-Host '    解决方案 1'
		$s2 = Read-Host '    解决方案 2 (可空, 回车结束)'

		$causes = @(); if ($c1) { $causes += $c1 }; if ($c2) { $causes += $c2 }
		if ($causes.Count -eq 0) { $causes = @('TODO: 补充常见原因') }
		$solutions = @(); if ($s1) { $solutions += $s1 }; if ($s2) { $solutions += $s2 }
		if ($solutions.Count -eq 0) { $solutions = @('TODO: 补充解决方案') }

		$newItem = [PSCustomObject]@{
			id        = $id
			platform  = $plat
			type      = $typ
			code      = $cod
			message   = $msg
			pattern   = $pat
			causes    = $causes
			solutions = $solutions
			severity  = $sev
		}
		$db += $newItem
		$addedCount++
		Write-Host "  [OK] 已录入: $id" -ForegroundColor Green
		Write-Host ''
	}

	if ($addedCount -gt 0) {
		if (Save-WarningDb $db) {
			Write-Host "[OK] AutoAdd 完成：共新增 $addedCount 条记录，已保存到 $DbPath" -ForegroundColor Green
		}
	} else {
		Write-Host "[-] AutoAdd 未添加任何条目。" -ForegroundColor Gray
	}

	return $db
}

function Save-WarningSnapshot($resultStruct, $projectDir) {
	<# -ProjectDir：在 build/warnings_snapshot.json 写快照，下次 -CompareWith 可用 #>
	if (-not $projectDir) { return }
	if (-not (Test-Path $projectDir)) { return }
	$buildDir = Join-Path $projectDir 'build'
	if (-not (Test-Path $buildDir)) { New-Item -ItemType Directory -Path $buildDir -Force | Out-Null }

	$snapPath = Join-Path $buildDir 'warnings_snapshot.json'
	$summary = if ($resultStruct -and $resultStruct.Summary) {
		$resultStruct.Summary
	} else {
		@{ Error = 0; Warning = 0; Unmatched = 0 }
	}

	$ids = @{}
	if ($resultStruct -and $resultStruct.MatchedItemId) {
		foreach ($k in $resultStruct.MatchedItemId.Keys) { $ids[$k] = $resultStruct.MatchedItemId[$k] }
	}

	$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
	$snap = [PSCustomObject]@{
		timestamp       = $timestamp
		summary         = $summary
		matched_item_ids = $ids
	}
	try {
		$json = $snap | ConvertTo-Json -Depth 6
		$utf8Bom = New-Object System.Text.UTF8Encoding($true)
		[System.IO.File]::WriteAllText($snapPath, $json, $utf8Bom)
		Write-Host ""
		Write-Host "[快照] 已写入: $snapPath (下次对比可用 -CompareWith $snapPath)" -ForegroundColor Gray
	}
	catch {
		Write-Host "[!] 快照写入失败: $($_.Exception.Message)" -ForegroundColor Yellow
	}
}

function Add-Warning($db) {
	Write-Host ''
	Write-Host '=========================================' -ForegroundColor Cyan
	Write-Host '  添加新警告' -ForegroundColor Cyan
	Write-Host '=========================================' -ForegroundColor Cyan
	Write-Host ''

	$id = Read-Host '  输入唯一 ID（如 c51-c202）'
	if (-not $id) { Write-Host 'ID 不能为空。' -ForegroundColor Red; return $db }
	foreach ($item in $db) {
		if ($item.id -eq $id) { Write-Host "错误：ID '$id' 已存在。" -ForegroundColor Red; return $db }
	}

	$platform = Read-Host '  平台（c51/armcc/gcc/esp-idf/linker）'
	$type = Read-Host '  类型（error/warning）'
	$code = Read-Host '  错误/警告码（如 C202）'
	$message = Read-Host '  消息描述'
	$pattern = Read-Host '  正则匹配模式'
	$severity = Read-Host '  严重程度（critical/high/medium/low）'

	Write-Host ''
	Write-Host '  常见原因（每行一个，空行结束）：' -ForegroundColor White
	$causes = @()
	do { $c = Read-Host "    原因 $($causes.Count + 1)"; if ($c) { $causes += $c } } while ($c)

	Write-Host ''
	Write-Host '  解决方案（每行一个，空行结束）：' -ForegroundColor White
	$solutions = @()
	do { $s = Read-Host "    方案 $($solutions.Count + 1)"; if ($s) { $solutions += $s } } while ($s)

	$newItem = [PSCustomObject]@{
		id = $id; platform = $platform; type = $type; code = $code;
		message = $message; pattern = $pattern; causes = $causes;
		solutions = $solutions; severity = $severity
	}
	$db += $newItem
	if (Save-WarningDb $db) {
		Write-Host ''
		Write-Host "成功添加警告：$id" -ForegroundColor Green
	}
	return $db
}

function Show-Summary($db) {
	$platforms = @{}
	$types = @{ error = 0; warning = 0 }
	$severities = @{ critical = 0; high = 0; medium = 0; low = 0 }
	foreach ($item in $db) {
		if (-not $platforms.ContainsKey($item.platform)) { $platforms[$item.platform] = 0 }
		$platforms[$item.platform]++
		if ($types.ContainsKey($item.type)) { $types[$item.type]++ }
		if ($severities.ContainsKey($item.severity)) { $severities[$item.severity]++ }
	}

	Write-Host ''
	Write-Host '=========================================' -ForegroundColor Cyan
	Write-Host '  编译警告数据库 - 统计摘要' -ForegroundColor Cyan
	Write-Host '=========================================' -ForegroundColor Cyan
	Write-Host ''
	Write-Host "  总计：$($db.Count) 条记录" -ForegroundColor White
	Write-Host ''
	Write-Host '  按平台分布：' -ForegroundColor White
	foreach ($key in $platforms.Keys) {
		Write-Host "    $($key.PadRight(10)) : $($platforms[$key]) 条" -ForegroundColor Green
	}
	Write-Host ''
	Write-Host '  按类型分布：' -ForegroundColor White
	Write-Host "    error     : $($types['error']) 条" -ForegroundColor Red
	Write-Host "    warning   : $($types['warning']) 条" -ForegroundColor Yellow
	Write-Host ''
	Write-Host '  按严重程度分布：' -ForegroundColor White
	Write-Host "    critical  : $($severities['critical']) 条" -ForegroundColor Red
	Write-Host "    high      : $($severities['high']) 条" -ForegroundColor Magenta
	Write-Host "    medium    : $($severities['medium']) 条" -ForegroundColor Yellow
	Write-Host "    low       : $($severities['low']) 条" -ForegroundColor Gray
	Write-Host ''
}

function Interactive-Menu($db) {
	do {
		Write-Host ''
		Write-Host '=========================================' -ForegroundColor Cyan
		Write-Host '  编译警告数据库 v2.0' -ForegroundColor Cyan
		Write-Host '=========================================' -ForegroundColor Cyan
		Write-Host '  1. 搜索警告'
		Write-Host '  2. 按平台浏览'
		Write-Host '  3. 列出全部'
		Write-Host '  4. 解析编译输出'
		Write-Host '  5. 统计摘要'
		Write-Host '  6. 添加新警告'
		Write-Host '  0. 退出'
		Write-Host '=========================================' -ForegroundColor Cyan
		$choice = Read-Host '请选择'

		switch ($choice) {
			'1' {
				$kw = Read-Host '输入搜索关键词'
				$results = Search-Warnings $db $kw $null
				Write-Host ''
				Write-Host '=========================================' -ForegroundColor Cyan
				Write-Host '  编译警告数据库 - 搜索结果' -ForegroundColor Cyan
				Write-Host '=========================================' -ForegroundColor Cyan
				Write-Host "关键词：$kw" -ForegroundColor Gray
				Show-ResultList $results
				if ($results.Count -gt 0) {
					do {
						$sel = Read-Host '输入编号查看详情（q 返回）'
						if ($sel -eq 'q') { break }
						$num = 0
						if ([int]::TryParse($sel, [ref]$num) -and $num -ge 1 -and $num -le $results.Count) {
							Show-WarningDetail $results[$num - 1]
						}
					} while ($true)
				}
			}
			'2' {
				$plat = Read-Host '输入平台（c51/armcc/gcc/esp-idf/linker）'
				$results = Search-Warnings $db $null $plat
				Write-Host ''
				Write-Host '=========================================' -ForegroundColor Cyan
				Write-Host "  平台：$plat" -ForegroundColor Cyan
				Write-Host '=========================================' -ForegroundColor Cyan
				Show-ResultList $results
				if ($results.Count -gt 0) {
					do {
						$sel = Read-Host '输入编号查看详情（q 返回）'
						if ($sel -eq 'q') { break }
						$num = 0
						if ([int]::TryParse($sel, [ref]$num) -and $num -ge 1 -and $num -le $results.Count) {
							Show-WarningDetail $results[$num - 1]
						}
					} while ($true)
				}
			}
			'3' {
				Write-Host ''
				Write-Host '=========================================' -ForegroundColor Cyan
				Write-Host '  全部警告列表' -ForegroundColor Cyan
				Write-Host '=========================================' -ForegroundColor Cyan
				Show-ResultList $db
				if ($db.Count -gt 0) {
					do {
						$sel = Read-Host '输入编号查看详情（q 返回）'
						if ($sel -eq 'q') { break }
						$num = 0
						if ([int]::TryParse($sel, [ref]$num) -and $num -ge 1 -and $num -le $db.Count) {
							Show-WarningDetail $db[$num - 1]
						}
					} while ($true)
				}
			}
			'4' {
				$f = Read-Host '输入编译输出文件路径'
				if ($f) {
					$r = Parse-CompileOutput $db $f
					if ($r) { Save-WarningSnapshot $r $ProjectDir }
				}
			}
			'5' { Show-Summary $db }
			'6' { $db = Add-Warning $db }
			'0' { Write-Host ''; Write-Host '再见！' -ForegroundColor Green; break }
			default { Write-Host '无效选择，请重试。' -ForegroundColor Yellow }
		}
	} while ($choice -ne '0')
}

# ============================================================
# 主流程
# ============================================================
$db = Load-WarningDb
if ($db.Count -eq 0 -and -not $Add -and -not $Parse) {
	exit 1
}

if ($Detail) {
	$item = $db | Where-Object { $_.id -eq $Detail }
	if ($item) { Show-WarningDetail $item }
	else { Write-Host "错误：找不到 ID 为 '$Detail' 的警告。" -ForegroundColor Red; exit 1 }
}
elseif ($Search -or $Platform) {
	Write-Host ''
	Write-Host '=========================================' -ForegroundColor Cyan
	Write-Host '  编译警告数据库 - 搜索结果' -ForegroundColor Cyan
	Write-Host '=========================================' -ForegroundColor Cyan
	if ($Search)   { Write-Host "关键词：$Search"   -ForegroundColor Gray }
	if ($Platform) { Write-Host "平台：$Platform"   -ForegroundColor Gray }
	$results = Search-Warnings $db $Search $Platform
	Show-ResultList $results
	if ($results.Count -gt 0) {
		do {
			$sel = Read-Host '输入编号查看详情（q 退出）'
			if ($sel -eq 'q') { break }
			$num = 0
			if ([int]::TryParse($sel, [ref]$num) -and $num -ge 1 -and $num -le $results.Count) {
				Show-WarningDetail $results[$num - 1]
			}
		} while ($true)
	}
}
elseif ($Parse) {
	$result = Parse-CompileOutput $db $Parse
	# AutoAdd
	if ($AutoAdd -and $result) {
		$db = Invoke-AutoAddUnmatched $db $result.Unmatched
	}
	# 快照
	if ($ProjectDir) {
		Save-WarningSnapshot $result $ProjectDir
	}
}
elseif ($List) {
	Write-Host ''
	Write-Host '=========================================' -ForegroundColor Cyan
	Write-Host '  全部警告列表' -ForegroundColor Cyan
	Write-Host '=========================================' -ForegroundColor Cyan
	Show-ResultList $db
}
elseif ($Add) {
	$db = Add-Warning $db
}
else {
	Interactive-Menu $db
}
