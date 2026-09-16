<#
.SYNOPSIS
Tools 发布工程工具：版本登记 / 变更记录 / 缺失检测（单一真实源=脚本内嵌 version 行）
.DESCRIPTION
统一管理 $env:USERPROFILE\Tools\*.ps1 的版本：
  - script 内 version: x.y.z 行为唯一版本源（位于脚本首帮助注释块末尾）
  - tools_version.json 为聚合索引（-Register 生成），供 tool-guide 展示
  - changelog.md 记录每次变更
用法：
  version-tools                      # 列表（等同 -List）
  version-tools -InitMissing         # 给缺少 version 行的脚本注入 version: 1.0.0
  version-tools -Register            # 重建 tools_version.json
  version-tools -Bump -Name check-skills.ps1 -How minor -Message "新增 reference 关联检查"
  version-tools -Validate            # 检测缺失版本脚本（返回码 1=有缺失）
  version-tools -SelfTest            # 冒烟自检
.EXAMPLE
version-tools -Bump -Name dev-flow.ps1 -How patch -Message "修正 -Include 扩展名匹配"
  version: 1.3.0
#>
param(
	[switch]$InitMissing,       # 给无版本脚本注入 version: 1.0.0
	[switch]$Register,          # 重建 tools_version.json
	[switch]$Validate,          # 检测缺失
	[switch]$SelfTest,          # 冒烟
	[string]$Bump = '',         # 逗号分隔: Name=xxx.ps1,How=patch|minor|major,Message=说明 或直接用 -Name/-How/-Message
	[string]$Name = '',
	[ValidateSet('patch', 'minor', 'major')]
	[string]$How = 'patch',
	[string]$Message = '',
	[switch]$Log               # 查看 changelog 最近变更记录
)

# ==================== 常量 ====================
$SCRIPT:TOOLS = if ($SelfTest) { Join-Path $env:TEMP 'version-tools_selftest' } else { '$env:USERPROFILE\Tools' }
$SCRIPT:VERSION_FILE = Join-Path $SCRIPT:TOOLS 'tools_version.json'
$SCRIPT:CHANGELOG = Join-Path $SCRIPT:TOOLS 'changelog.md'

function Test-VerLine {
	param([string]$Line)
	return ($Line -match '^\s*version:\s*(\d+)\.(\d+)\.(\d+)\s*$')
}

function Get-ScriptVersion {
	param([string]$Path)
	# 首个 <# #> 注释块内找 version 行
	$lines = [System.IO.File]::ReadAllLines($Path)
	for ($i = 0; $i -lt [Math]::Min($lines.Count, 50); $i++) {
		if (Test-VerLine $lines[$i]) {
			if ($lines[$i] -match '^\s*version:\s*(.+?)\s*$') { return $matches[1] }
		}
	}
	return $null
}

function Set-ScriptVersion {
	param([string]$Path, [string]$NewVersion)
	$bytes = [System.IO.File]::ReadAllBytes($Path)
	$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
	$text = [System.IO.File]::ReadAllText($Path)
	$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
	$lines = [System.IO.File]::ReadAllLines($Path)
	$idx = -1
	for ($i = 0; $i -lt [Math]::Min($lines.Count, 50); $i++) {
		if (Test-VerLine $lines[$i]) { $idx = $i; break }
	}
	if ($idx -lt 0) { return $false }
	$oldVer = ''
	if ($lines[$idx] -match '^\s*(version:)\s*(\S+)\s*$') { $oldVer = $matches[2] }
	$lines[$idx] = "  version: $NewVersion"
	$enc = New-Object System.Text.UTF8Encoding($hasBom)
	[System.IO.File]::WriteAllText($Path, (($lines -join $nl) + $nl), $enc)
	return $oldVer
}

function Get-ToolScripts {
	Get-ChildItem $SCRIPT:TOOLS -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Where-Object {
		$_.Name -notin @('version-tools.ps1') -and $_.FullName -notmatch '\\lib\\'
	} | Sort-Object Name
}

# ==================== InitMissing ====================
function Invoke-InitMissing {
	$fixed = 0
	foreach ($f in Get-ToolScripts) {
		if (-not (Get-ScriptVersion $f.FullName)) {
			# 在首个 <# #> 块结束前插入 version 行
			$bytes = [System.IO.File]::ReadAllBytes($f.FullName)
			$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
			$text = [System.IO.File]::ReadAllText($f.FullName)
			$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
			$lines = [System.IO.File]::ReadAllLines($f.FullName)
			$endIdx = -1
			for ($i = 0; $i -lt [Math]::Min($lines.Count, 60); $i++) {
				if ($lines[$i].Trim() -eq '#>') { $endIdx = $i; break }
			}
			if ($endIdx -lt 0) { Write-Host "  [SKIP] $($f.Name) 无注释块头部，跳过"; continue }
			$newLines = @(); $newLines += $lines[0..($endIdx-1)]; $newLines += '  version: 1.0.0'; $newLines += $lines[$endIdx..($lines.Count-1)]
			$enc = New-Object System.Text.UTF8Encoding($hasBom)
			[System.IO.File]::WriteAllText($f.FullName, (($newLines -join $nl) + $nl), $enc)
			Write-Host "  [注入] $($f.Name) -> 1.0.0"
			$fixed++
		}
	}
	Write-Host "[OK] InitMissing 完成，注入 $fixed 个脚本"
	Invoke-Register | Out-Null
}

# ==================== Register ====================
function Invoke-Register {
	$map = [ordered]@{}
	foreach ($f in Get-ToolScripts) {
		$ver = Get-ScriptVersion $f.FullName
		$map[$f.Name] = @{
			version  = if ($ver) { $ver } else { 'N/A' }
			modified = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
			size     = $f.Length
		}
	}
	$json = $map | ConvertTo-Json -Depth 3
	$enc = New-Object System.Text.UTF8Encoding($true)
	[System.IO.File]::WriteAllText($SCRIPT:VERSION_FILE, $json, $enc)
	Write-Host "[OK] tools_version.json 已重建（$($map.Count) 个脚本）"
	return $map.Count
}

# ==================== Bump ====================
function Bump-Version {
	param([string]$File, [string]$How, [string]$Msg)
	$target = Join-Path $SCRIPT:TOOLS $File
	if (-not (Test-Path $target)) { Write-Host "[X] 不存在: $File"; return 1 }
	$cur = Get-ScriptVersion $target
	if (-not $cur) { Write-Host "[X] $File 无 version 行（先跑 -InitMissing）"; return 1 }
	$parts = $cur -split '\.'
	if ($parts.Count -ne 3) { Write-Host "[X] 版本格式异常: $cur"; return 1 }
	$maj = [int]$parts[0]; $min = [int]$parts[1]; $pat = [int]$parts[2]
	switch ($How) {
		'major' { $maj++; $min = 0; $pat = 0 }
		'minor' { $min++; $pat = 0 }
		default { $pat++ }
	}
	$newVer = "$maj.$min.$pat"
	$oldVer = Set-ScriptVersion -Path $target -NewVersion $newVer
	if (-not $oldVer) { Write-Host "[X] 写入失败"; return 1 }
	# 追加 changelog
	$today = (Get-Date).ToString('yyyy-MM-dd')
	$entry = "### $today`t$File`t$cur -> $newVer`t$How"
	if ($Msg) { $entry += "`t$Msg" }
	if (-not (Test-Path $SCRIPT:CHANGELOG)) {
		"# Tools Changelog`r`n`r`n$entry`r`n" | Out-File -FilePath $SCRIPT:CHANGELOG -Encoding UTF8
	} else {
		$curText = [System.IO.File]::ReadAllText($SCRIPT:CHANGELOG)
		if (-not $curText.EndsWith("`n")) { [System.IO.File]::AppendAllText($SCRIPT:CHANGELOG, "`r`n") }
		[System.IO.File]::AppendAllText($SCRIPT:CHANGELOG, "$entry`r`n")
	}
	Write-Host "[OK] ${File}: $cur -> $newVer$($(if($Msg){"（$Msg）"}else{''}))"
	Invoke-Register | Out-Null
	return 0
}

# ==================== Validate ====================
function Invoke-Validate {
	$missing = @()
	foreach ($f in Get-ToolScripts) { if (-not (Get-ScriptVersion $f.FullName)) { $missing += $f.Name } }
	if ($missing.Count -eq 0) { Write-Host '[OK] 全部脚本已带 version'; return 0 }
	Write-Host "[!] $($missing.Count) 个脚本缺 version：$($missing -join ', ')" -ForegroundColor Yellow
	return 1
}

# ==================== List ====================
function Invoke-List {
	$json = if (Test-Path $SCRIPT:VERSION_FILE) { Get-Content $SCRIPT:VERSION_FILE -Raw | ConvertFrom-Json } else { $null }
	if (-not $json) { Write-Host '[i] tools_version.json 不存在，请先 -Register'; return }
	Write-Host ""
	Write-Host ('{0,-32} {1,10} {2,12}' -f '脚本', '版本', '修改日期')
	Write-Host ('=' * 60)
	foreach ($prop in $json.PSObject.Properties) {
		Write-Host ('{0,-32} {1,10} {2,12}' -f $prop.Name, $prop.Value.version, $prop.Value.modified)
	}
	# 工具自身（不登记在 json，单独显示）
	$selfPath = Join-Path $SCRIPT:TOOLS 'version-tools.ps1'
	if (Test-Path $selfPath) {
		$selfVer = Get-ScriptVersion $selfPath
		if ($selfVer) {
			$selfMod = (Get-Item $selfPath).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
			Write-Host ('{0,-32} {1,10} {2,12}' -f 'version-tools.ps1 (自身)', $selfVer, $selfMod)
		}
	}
}

# ==================== SelfTest ====================
function Invoke-SelfTest {
	Write-Host '===== version-tools 冒烟自检 =====' -ForegroundColor Cyan
	if (Test-Path $SCRIPT:TOOLS) { Remove-Item $SCRIPT:TOOLS -Recurse -Force }
	New-Item -ItemType Directory -Path $SCRIPT:TOOLS -Force | Out-Null
	$encB = New-Object System.Text.UTF8Encoding($true)
	# 造 2 个假脚本：一个带版本，一个不带
	[System.IO.File]::WriteAllText((Join-Path $SCRIPT:TOOLS 'alpha.ps1'), "<#`n.SYNOPSIS`nTest A`n  version: 1.2.3`n#>", $encB)
	[System.IO.File]::WriteAllText((Join-Path $SCRIPT:TOOLS 'beta.ps1'), "<#`n.SYNOPSIS`nTest B`n#>", $encB)
	try {
		$vA = Get-ScriptVersion (Join-Path $SCRIPT:TOOLS 'alpha.ps1')
		$ok1 = ($vA -eq '1.2.3')
		$vB = Get-ScriptVersion (Join-Path $SCRIPT:TOOLS 'beta.ps1')
		$ok2 = ($null -eq $vB)
		Invoke-InitMissing | Out-Null
		$vB2 = Get-ScriptVersion (Join-Path $SCRIPT:TOOLS 'beta.ps1')
		$ok3 = ($vB2 -eq '1.0.0')
		Invoke-Register | Out-Null
		$json = Get-Content (Join-Path $SCRIPT:TOOLS 'tools_version.json') -Raw | ConvertFrom-Json
		$ok4 = ($json.'alpha.ps1'.version -eq '1.2.3' -and $json.'beta.ps1'.version -eq '1.0.0')
		$old = Get-ScriptVersion (Join-Path $SCRIPT:TOOLS 'alpha.ps1')
		$new = (Split-Bump (Get-ScriptVersion (Join-Path $SCRIPT:TOOLS 'alpha.ps1')) 'minor')
		Set-ScriptVersion (Join-Path $SCRIPT:TOOLS 'alpha.ps1') $new | Out-Null
		$ok5 = ((Get-ScriptVersion (Join-Path $SCRIPT:TOOLS 'alpha.ps1')) -eq '1.3.0')
		Write-Host ("  版本读取: {0} [{1}]" -f $vA, $(if($ok1){'PASS'}else{'FAIL'}))
		Write-Host ("  缺失检测: {0} [{1}]" -f $(if($null -eq $vB){'OK'}else{'FAIL'}), $(if($ok2){'PASS'}else{'FAIL'}))
		Write-Host ("  InitMissing注入: {0} [{1}]" -f $vB2, $(if($ok3){'PASS'}else{'FAIL'}))
		Write-Host ("  Register聚合: {0} [{1}]" -f "alpha=$($json.'alpha.ps1'.version)", $(if($ok4){'PASS'}else{'FAIL'}))
		Write-Host ("  版本bump(minor): {0} -> {1} [{2}]" -f $old, $new, $(if($ok5){'PASS'}else{'FAIL'}))
		if ($ok1 -and $ok2 -and $ok3 -and $ok4 -and $ok5) { Write-Host '[PASS] 自检通过' -ForegroundColor Green; return 0 }
		Write-Host '[FAIL] 自检未通过' -ForegroundColor Red
		return 1
	} finally { Remove-Item $SCRIPT:TOOLS -Recurse -Force -ErrorAction SilentlyContinue }
}

function Split-Bump {
	param([string]$Cur, [string]$How)
	$p = $Cur -split '\.'
	$maj = [int]$p[0]; $min = [int]$p[1]; $pat = [int]$p[2]
	switch ($How) { 'major' { return "$($maj+1).0.0" } 'minor' { return "$maj.$($min+1).0" } default { return "$maj.$min.$($pat+1)" } }
}

# ==================== Changelog 查看 ====================
function Show-Changelog {
	param([int]$Count = 10)
	if (-not (Test-Path $SCRIPT:CHANGELOG)) { Write-Host '[i] changelog.md 不存在'; return }
	$entries = Get-Content $SCRIPT:CHANGELOG | Where-Object { $_ -match '^### ' }
	$total = $entries.Count
	Write-Host "=== Tools Changelog（最近 $([Math]::Min($Count, $total)) / 共 $total 条）===" -ForegroundColor Cyan
	$entries | Select-Object -Last $Count | ForEach-Object { Write-Host $_ }
	Write-Host ''
	Write-Host "完整记录：$($SCRIPT:CHANGELOG)" -ForegroundColor Gray
}

# ==================== 入口 ====================
if ($SelfTest) { exit (Invoke-SelfTest) }
if ($InitMissing) { Invoke-InitMissing; exit 0 }
if ($Register) { exit (Invoke-Register) }
if ($Validate) { exit (Invoke-Validate) }
if ($Log) { Show-Changelog; exit 0 }
if ($Bump) {
	# 解析 -Bump "Name=xxx.ps1,How=minor,Message=..."
	foreach ($kv in ($Bump -split ',')) { if ($kv -match '^([^=]+)=(.*)$') { switch ($matches[1].Trim()) { 'Name' { $Name = $matches[2].Trim() } 'How' { $How = $matches[2].Trim() } 'Message' { $Message = $matches[2].Trim() } } } }
}
if ($Name) { exit (Bump-Version -File $Name -How $How -Msg $Message) }
Invoke-List
