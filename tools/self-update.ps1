<#
.USAGE
自我更新升级工具 v2.0 - 系统维护与同步

用法示例：
  # 全量更新（tools + skills + memory + config）
  self-update -Mode all
  self-update -Mode all -DryRun

  # 单模块执行
  self-update -Mode tools -RemoteUrl https://github.com/user/tools.git
  self-update -Mode skills -DryRun
  self-update -Mode skills -AutoFix
  self-update -Mode memory -DryRun
  self-update -Mode config -DryRun
  self-update -Mode env -DryRun
  self-update -Mode device -Port COM8 -DryRun
  self-update -Mode projects -ProjectRoot <PROJECT_ROOT> -DryRun
  self-update -Mode projects -ProjectRoot <PROJECT_ROOT> -AutoCommit

  # 组合模式
  self-update -Mode env-device -DryRun

  # 触发方式（控制间隔检查）
  self-update -Mode all -Trigger session
  self-update -Mode all -Trigger git
  self-update -Mode all -Trigger error

  # 会话间隔（小时）
  self-update -Mode all -Trigger session -SessionIntervalHours 12

  # 静默模式 / 强制执行
  self-update -Mode all -Quiet
  self-update -Mode all -Force
  version: 2.1.0
#>
param(
	[string]$Mode = 'all',
	[ValidateSet('manual','session','error','git')]
	[string]$Trigger = 'manual',
	[string]$RemoteUrl = '',
	[switch]$DryRun,
	[int]$SessionIntervalHours = 24,
	[switch]$Quiet,
	[switch]$Force,
	[switch]$AutoFix,
	[string]$Port = '',
	[string]$ProjectRoot = '',
	[switch]$AutoCommit
)

# ==================== 常量 ====================
$SCRIPT:TOOLS_DIR = '$env:USERPROFILE\Tools'
$SCRIPT:SKILLS_SCAN_DIRS = @(
	'$env:USERPROFILE\.trae-cn\skills'
)
$SCRIPT:MEMORY_DIR = '$env:USERPROFILE\.trae-cn\memory'
$SCRIPT:STATE_FILE = Join-Path $SCRIPT:TOOLS_DIR '.self-update-state.json'
$SCRIPT:ARCHIVE_DIR = Join-Path $SCRIPT:MEMORY_DIR '.cleanup'
$SCRIPT:USER_PROFILE = Join-Path $SCRIPT:MEMORY_DIR 'user_profile.md'
$SCRIPT:SKILL_MIN_SIZE = 200
$SCRIPT:SKILL_MAX_SIZE = 50000
$SCRIPT:SESSION_RETAIN_DAYS = 30
$SCRIPT:DEFAULT_PROJECT_ROOT = '<PROJECT_ROOT>'
$SCRIPT:PROJECT_MAX_DEPTH = 5
$SCRIPT:TRIGGER_INTERVALS = @{
	session = @{ Hours = 24 }
	git     = @{ Hours = 1 }
	error   = @{ Hours = 1 }
}
$SCRIPT:MAX_STATE_RUNS = 20

# ==================== 基础工具函数 ====================

function Write-Status {
	param(
		[string]$Message,
		[string]$Type = 'Info'
	)
	if ($Quiet -and $Type -eq 'Info') { return }
	switch ($Type) {
		'Error'   { Write-Host "[X] $Message" -ForegroundColor Red }
		'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
		'Success' { Write-Host "[OK] $Message" -ForegroundColor Green }
		'Info'    { Write-Host "[*] $Message" -ForegroundColor Cyan }
		default   { Write-Host $Message }
	}
}

function Write-Section {
	param([string]$Title)
	Write-Host ""
	Write-Host ("=" * 60) -ForegroundColor DarkGray
	Write-Host " $Title" -ForegroundColor White
	Write-Host ("=" * 60) -ForegroundColor DarkGray
}

function Get-State {
	if (-not (Test-Path $SCRIPT:STATE_FILE)) {
		return @{
			last_session_run = ''
			last_error_run = ''
			last_git_run = ''
			runs = @()
		}
	}
	try {
		$raw = Get-Content -Raw -Path $SCRIPT:STATE_FILE -ErrorAction Stop
		$obj = $raw | ConvertFrom-Json -ErrorAction Stop
		$state = @{
			last_session_run = [string]$obj.last_session_run
			last_error_run = [string]$obj.last_error_run
			last_git_run = [string]$obj.last_git_run
			runs = @()
		}
		if ($obj.runs) {
			foreach ($r in $obj.runs) {
				$state.runs += ,@{
					time = [string]$r.time
					mode = [string]$r.mode
					trigger = [string]$r.trigger
					dry = [bool]$r.dry
					results = $r.results
				}
			}
		}
		return $state
	} catch {
		return @{
			last_session_run = ''
			last_error_run = ''
			last_git_run = ''
			runs = @()
		}
	}
}

function Save-State {
	param([hashtable]$State)
	try {
		if (-not (Test-Path $SCRIPT:TOOLS_DIR)) {
			New-Item -ItemType Directory -Path $SCRIPT:TOOLS_DIR -Force | Out-Null
		}
		# 只保留最近 N 条运行记录
		if ($State.runs.Count -gt $SCRIPT:MAX_STATE_RUNS) {
			$State.runs = $State.runs[-$SCRIPT:MAX_STATE_RUNS..-1]
		}
		$json = $State | ConvertTo-Json -Depth 6
		[System.IO.File]::WriteAllText($SCRIPT:STATE_FILE, $json, [System.Text.UTF8Encoding]::new($false))
	} catch {
		Write-Status "保存状态文件失败: $_" -Type Warning
	}
}

function Test-TriggerAllowed {
	param([hashtable]$State, [string]$TriggerType)
	if ($TriggerType -eq 'manual') { return $true }
	if ($Force) { return $true }
	$key = "last_$($TriggerType)_run"
	$last = $State[$key]
	if (-not $last) { return $true }
	try {
		$lastTime = [datetime]$last
	} catch { return $true }
	$cfg = $SCRIPT:TRIGGER_INTERVALS[$TriggerType]
	if (-not $cfg) { return $true }
	$elapsed = (Get-Date) - $lastTime
	if ($elapsed.TotalHours -lt $cfg.Hours) {
		return $false
	}
	return $true
}

# ==================== 模块 1: Update-Tools ====================

function Update-Tools {
	param(
		[string]$Url,
		[switch]$Dry
	)
	$report = @{ ok = $false; reason = ''; action = '' }
	if (-not (Test-Path $SCRIPT:TOOLS_DIR)) {
		$report.reason = 'tools_dir_missing'
		return $report
	}
	Push-Location $SCRIPT:TOOLS_DIR
	try {
		$isRepo = $false
		try {
			$null = git rev-parse --git-dir 2>$null
			if ($LASTEXITCODE -eq 0) { $isRepo = $true }
		} catch {}

		if (-not $isRepo) {
			if ($Url) {
				Write-Status "Tools 目录非 git 仓库，开始初始化 (remote: $Url)" -Type Info
				if ($Dry) {
					$report.action = 'dry_init'
					$report.ok = $true
					return $report
				}
				git init 2>&1 | Out-Null
				git remote add origin $Url 2>&1 | Out-Null
				git fetch origin 2>&1 | Out-Null
				$report.action = 'init_fetch'
				$report.ok = ($LASTEXITCODE -eq 0)
				if (-not $report.ok) { $report.reason = 'fetch_failed' }
				return $report
			} else {
				# 本机 Tools 无 git 同步（本地直改 + version-tools 登记闭环），视为跳过而非失败
				$report.ok = $true
				$report.action = 'no_git_sync'
				return $report
			}
		}
		# 已是仓库，检查工作区是否干净
		$status = git status --porcelain 2>$null
		if ($status) {
			$dirtyCount = @($status).Count
			if ($Dry) {
				$report.action = 'dry_auto_commit'
				$report.ok = $true
				return $report
			}
			if ($AutoFix) {
				# 自动提交并推送（Tools 版本登记落地远端），pre-commit 门禁会拦截问题文件
				Write-Status "Tools 工作区有 $dirtyCount 个未提交改动，自动提交并推送..." -Type Info
				git add -A 2>&1 | Out-Null
				$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
				git commit -m "chore(tools): 自动提交 $stamp" 2>&1 | Out-Null
				if ($LASTEXITCODE -ne 0) {
					Write-Status "自动提交被 pre-commit 门禁拦截，请手动处理（--no-verify 需说明原因）" -Type Warning
					$report.ok = $false
					$report.reason = 'auto_commit_blocked'
					return $report
				}
				git push 2>&1 | Out-Null
				$report.action = if ($LASTEXITCODE -eq 0) { 'auto_pushed' } else { 'auto_committed' }
				$report.ok = $true
				Write-Status "已提交并推送 Tools 变更（$stamp）" -Type Success
				return $report
			}
			Write-Status "Tools 工作区有 $dirtyCount 个未提交改动（建议 version-tools 登记后 git commit + push，或用 -AutoFix 自动提交）" -Type Warning
			$report.reason = 'dirty_worktree'
			$report.ok = $true
			$report.action = 'skipped_dirty'
			return $report
		}
		# 检查 remote
		$remote = git remote 2>$null
		if (-not $remote) {
			if ($Url) {
				if ($Dry) {
					$report.action = 'dry_remote_add'
					$report.ok = $true
					return $report
				}
				git remote add origin $Url 2>&1 | Out-Null
			} else {
				$report.reason = 'no_remote'
				$report.ok = $true
				return $report
			}
		}
		Write-Status "拉取 Tools 更新..." -Type Info
		if ($Dry) {
			$report.action = 'dry_pull'
			$report.ok = $true
			return $report
		}
		git pull 2>&1 | ForEach-Object { Write-Status $_ -Type Info }
		$report.action = 'pull'
		$report.ok = ($LASTEXITCODE -eq 0)
		if (-not $report.ok) { $report.reason = 'pull_failed' }
		return $report
	} finally {
		Pop-Location
	}
}

# ==================== 模块 2: Update-Skills ====================

function Update-Skills {
	param(
		[switch]$Dry,
		[switch]$AutoFix
	)
	$report = @{ ok = $true; total = 0; skipped = 0; fixed = 0; issues = @() }
	# 扫描所有 SKILL.md 文件
	$skillFiles = @()
	foreach ($scanDir in $SCRIPT:SKILLS_SCAN_DIRS) {
		if (Test-Path $scanDir) {
			$found = Get-ChildItem -Path $scanDir -Recurse -Filter 'SKILL.md' -File -ErrorAction SilentlyContinue
			if ($found) { $skillFiles += $found }
		}
	}
	$report.total = $skillFiles.Count
	Write-Status "发现 $($report.total) 个 SKILL.md 文件" -Type Info

	foreach ($file in $skillFiles) {
		# skip skill-audit itself (it documents hardcoded paths as examples)
		if ($file.Directory.Name -ieq 'skill-audit') { continue }
		$path = $file.FullName
		$size = $file.Length
		# 大小范围检查
		if ($size -lt $SCRIPT:SKILL_MIN_SIZE -or $size -gt $SCRIPT:SKILL_MAX_SIZE) {
			$report.skipped++
			$report.issues += "$($file.Name):size_out_of_range($size)"
			continue
		}
		$bytes = [System.IO.File]::ReadAllBytes($path)
		$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
		$text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
		$issues = @()
		$fixedThis = $false
		$newText = $text

		# BOM 检查仅适用于含中文 .ps1 脚本；SKILL.md 只要求 UTF-8（skill-audit 标准），无 BOM 合法
		# 检查硬编码路径
		$hardcoded = $false
		if ($text -match 'D:\\Keil_v5') {
			$hardcoded = $true
			if ($AutoFix -and -not $Dry) {
				$newText = $newText -replace 'D:\\Keil_v5', '<KEIL_ROOT>'
				$fixedThis = $true
			}
		}
		if ($text -match 'D:\\ESP32') {
			$hardcoded = $true
			if ($AutoFix -and -not $Dry) {
				$newText = $newText -replace 'D:\\ESP32', '<ESP_IDF_ROOT>'
				$fixedThis = $true
			}
		}
		if ($text -match 'C:\\Users\\[^\\\r\n]+(?=\\)') {
			$hardcoded = $true
			if ($AutoFix -and -not $Dry) {
				$newText = $newText -replace 'C:\\Users\\[^\\\r\n]+(?=\\)', '$env:USERPROFILE'
				$fixedThis = $true
			}
		}
		if ($hardcoded) { $issues += 'hardcoded_path' }

		# 检查 name / description 字段
		$hasName = ($text -match '(?m)^name:\s*(.+)$')
		$hasDesc = ($text -match '(?m)^description:\s*(.+)$')

		if (-not $hasName) {
			$issues += 'missing_name'
			if ($AutoFix -and -not $Dry) {
				$dirName = $file.Directory.Name
				$newText = Add-SkillField $newText 'name' $dirName
				$fixedThis = $true
			}
		}
		if (-not $hasDesc) {
			$issues += 'missing_description'
			if ($AutoFix -and -not $Dry) {
				$desc = Extract-SkillDescription $text
				if ($desc) {
					$newText = Add-SkillField $newText 'description' $desc
					$fixedThis = $true
				}
			}
		}

		if ($issues.Count -gt 0) {
			$report.issues += "$($file.Name):$($issues -join ',')"
		}
		if ($fixedThis) {
			$enc = [System.Text.UTF8Encoding]::new($true)
			[System.IO.File]::WriteAllText($path, $newText, $enc)
			$report.fixed++
			Write-Status "修复: $($file.Name) ($($issues -join ','))" -Type Success
		} elseif ($issues.Count -gt 0) {
			Write-Status "问题: $($file.Name) - $($issues -join ',')" -Type Warning
		}
	}
	$report.issues = ($report.issues -join '; ')
	return $report
}

function Invoke-SkillsHealth {
	$cs = Join-Path $SCRIPT:TOOLS_DIR 'check-skills.ps1'
	if (-not (Test-Path $cs)) { return @{ ok = $true; reason = 'check-skills 未部署' } }
	& $cs -Quiet 2>&1 | Out-Null
	if ($LASTEXITCODE -eq 1) {
		Write-Status '技能健康体检发现 P0/P1 问题，请运行 check-skills 查看详情' -Type Warning
		return @{ ok = $false; reason = 'skills_health_p01' }
	}
	if ($LASTEXITCODE -eq 2) { Write-Status '技能健康体检：仅 P2/P3 提示，可择期处理' -Type Info }
	elseif ($LASTEXITCODE -ne 0) { return @{ ok = $false; reason = "check_skills_exit_$LASTEXITCODE" } }
	return @{ ok = $true; reason = '' }
}
function Add-SkillField {
	param([string]$Content, [string]$Field, [string]$Value)
	# 已有 frontmatter，追加字段
	if ($Content -match '(?s)^(---\r?\n)(.*?)(\r?\n---)') {
		$front = $matches[2]
		$front += "`r`n${Field}: $Value"
		$rest = $Content.Substring($matches[0].Length)
		return $matches[1] + $front + $matches[3] + $rest
	}
	# 无 frontmatter，新建
	return "---`r`n${Field}: $Value`r`n---`r`n`r`n" + $Content
}

function Extract-SkillDescription {
	param([string]$Content)
	# .SYNOPSIS
	if ($Content -match '(?m)^\.SYNOPSIS\s*\r?\n\s*(.+)$') { return $matches[1].Trim() }
	# 第一个 Markdown 标题
	if ($Content -match '(?m)^#{1,3}\s+(.+)$') { return $matches[1].Trim() }
	# 第一段非空正文
	$lines = $Content -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^---' }
	if ($lines.Count -gt 0) { return $lines[0].Trim() }
	return 'Skill'
}

# ==================== 模块 3: Update-Memory ====================

function Update-Memory {
	param([switch]$Dry)
	$report = @{ ok = $true; archived = 0; duplicates = 0; cleaned = 0; errors = '' }
	if (-not (Test-Path $SCRIPT:MEMORY_DIR)) {
		$report.ok = $false
		$report.errors = 'memory_dir_missing'
		return $report
	}
	$projectsDir = Join-Path $SCRIPT:MEMORY_DIR 'projects'
	if (-not (Test-Path $projectsDir)) { return $report }

	$cutoff = (Get-Date).AddDays(-$SCRIPT:SESSION_RETAIN_DAYS)
	if (-not (Test-Path $SCRIPT:ARCHIVE_DIR)) {
		if (-not $Dry) {
			New-Item -ItemType Directory -Path $SCRIPT:ARCHIVE_DIR -Force | Out-Null
		}
	}

	# 归档过期 session 目录（目录名为 yyyyMMdd）
	$sessions = Get-ChildItem -Path $projectsDir -Recurse -Directory -Filter '20*' -ErrorAction SilentlyContinue
	foreach ($sess in $sessions) {
		$dirName = $sess.Name
		try {
			$dirDate = [datetime]::ParseExact($dirName, 'yyyyMMdd', $null)
		} catch { continue }
		if ($dirDate -lt $cutoff) {
			$relPath = $sess.FullName.Substring($projectsDir.Length).TrimStart('\')
			$archivePath = Join-Path $SCRIPT:ARCHIVE_DIR ($relPath -replace '[\\/]', '_')
			Write-Status "归档过期 session: $relPath" -Type Info
			if ($Dry) { continue }
			try {
				if (Test-Path $archivePath) { Remove-Item $archivePath -Recurse -Force }
				Move-Item -Path $sess.FullName -Destination $archivePath -Force
				$report.archived++
			} catch {
				$report.errors += "archive_fail:$relPath "
			}
		}
	}

	# 检测重复 topics.md（同项目目录下内容相同的文件）
	$projDirs = Get-ChildItem -Path $projectsDir -Directory -ErrorAction SilentlyContinue
	foreach ($pdir in $projDirs) {
		$topics = Get-ChildItem -Path $pdir.FullName -Recurse -Filter 'topics.md' -File -ErrorAction SilentlyContinue
		if ($topics.Count -le 1) { continue }
		$hashes = @{}
		foreach ($t in $topics) {
			try {
				$h = (Get-FileHash -Path $t.FullName -Algorithm MD5).Hash
				if ($hashes.ContainsKey($h)) {
					$report.duplicates++
					Write-Status "重复 topics.md: $($t.FullName)" -Type Warning
				} else {
					$hashes[$h] = $t.FullName
				}
			} catch {}
		}
	}

	# 清理空目录
	$empty = Get-ChildItem -Path $projectsDir -Recurse -Directory -ErrorAction SilentlyContinue |
		Where-Object { @(Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0 }
	foreach ($e in $empty) {
		if (-not $Dry) {
			try { Remove-Item -Path $e.FullName -Force; $report.cleaned++ } catch {}
		} else {
			$report.cleaned++
		}
	}

	# 沉淀后自动重建知识索引（memory 更新与索引保持同步）
	if (-not $Dry) {
		$kiScript = Join-Path $SCRIPT:TOOLS_DIR 'knowledge-index.ps1'
		if (Test-Path $kiScript) {
			& $kiScript -Index 2>&1 | Out-Null
			$report.knowledge_index = ($LASTEXITCODE -eq 0)
			Write-Status "知识索引已自动重建" -Type Success
		}
	}
	return $report
}

# ==================== 模块 4: Update-Config ====================

function Update-Config {
	param([switch]$Dry)
	$report = @{ ok = $true; synced = 0; issues = ''; fixed = 0 }
	$issues = @()

	# 检查 warning-db.json
	$warningDb = Join-Path $SCRIPT:TOOLS_DIR 'warning-db.json'
	if (-not (Test-Path $warningDb)) {
		$issues += 'missing_warning_db'
		Write-Status "warning-db.json 不存在" -Type Warning
	} else {
		$report.synced++
	}

	# 检查 Tools 脚本编码（无 BOM + 中文会被 PS5.1 按 GBK 读导致语法错误，Parser 检不出）
	$bomScript = Join-Path $SCRIPT:TOOLS_DIR 'check-bom.ps1'
	if (-not (Test-Path $bomScript)) {
		$issues += 'missing_check_bom'
		Write-Status "check-bom.ps1 不存在" -Type Warning
	} else {
		& $bomScript -Path $SCRIPT:TOOLS_DIR -Quiet
		if ($LASTEXITCODE -ne 0) {
			$issues += 'script_bom_issues'
			if ($AutoFix -and -not $Dry) {
				& $bomScript -Path $SCRIPT:TOOLS_DIR -Quiet -Fix
				if ($LASTEXITCODE -eq 0) { $report.fixed++ }
			}
			Write-Status "存在无 BOM + 中文的脚本，运行 check-bom.ps1 -Fix 修复" -Type Warning
		}
	}

	# 检查 .bat 包装器与 .ps1 一一对应（仅顶层目录）
	# 排除清单：dot-source 必需 / 被钩子内部调用等不适配 -File 调用的脚本，禁止 AutoFix 自动建 .bat
	$batExcludes = @('self-update', 'esp-idf-env', 'pre-commit-check')
	$ps1Files = Get-ChildItem -Path $SCRIPT:TOOLS_DIR -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
		Where-Object { ($_.Name -ne 'self-update.ps1') -and ($batExcludes -notcontains [System.IO.Path]::GetFileNameWithoutExtension($_.Name)) }
	$missingBat = 0
	foreach ($ps1 in $ps1Files) {
		$batName = [System.IO.Path]::GetFileNameWithoutExtension($ps1.Name) + '.bat'
		$batPath = Join-Path $SCRIPT:TOOLS_DIR $batName
		if (-not (Test-Path $batPath)) {
			$missingBat++
			if ($AutoFix -and -not $Dry) {
				$batContent = @"
@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
exit /b %ERRORLEVEL%
"@
				[System.IO.File]::WriteAllText($batPath, $batContent, [System.Text.UTF8Encoding]::new($false))
				$report.fixed++
			}
		}
	}
	if ($missingBat -gt 0) {
		$issues += "missing_bat_wrappers:$missingBat"
		Write-Status "缺少 $missingBat 个 .bat 包装器" -Type Warning
	}

	# 检查 board-config 目录
	$boardCfg = Join-Path $SCRIPT:TOOLS_DIR 'board-config'
	if (Test-Path $boardCfg) {
		$cfgs = Get-ChildItem -Path $boardCfg -Filter '*.ps1' -File -ErrorAction SilentlyContinue
		if ($cfgs) { $report.synced += $cfgs.Count }
	} else {
		$issues += 'missing_board_config'
	}

	# 检查工具脚本版本登记完整性（version-tools -Validate 门禁）
	$vtScript = Join-Path $SCRIPT:TOOLS_DIR 'version-tools.ps1'
	if (-not (Test-Path $vtScript)) {
		$issues += 'missing_version_tools'
		Write-Status "version-tools.ps1 不存在" -Type Warning
	} else {
		& $vtScript -Validate 2>&1 | Out-Null
		if ($LASTEXITCODE -ne 0) {
			$issues += 'tools_version_missing'
			if ($AutoFix -and -not $Dry) {
				& $vtScript -InitMissing 2>&1 | Out-Null
				if ($LASTEXITCODE -eq 0) { $report.fixed++ }
			}
			Write-Status "存在缺 version 行的工具脚本，运行 version-tools -InitMissing 修复" -Type Warning
		}

		# 版本时效检查：脚本已修改但未重新登记版本（防改完忘记 bump）
		$vtJson = Join-Path $SCRIPT:TOOLS_DIR 'tools_version.json'
		if (Test-Path $vtJson) {
			$reg = Get-Content $vtJson -Raw | ConvertFrom-Json
			$stale = @()
			foreach ($prop in $reg.PSObject.Properties) {
				$sp = Join-Path $SCRIPT:TOOLS_DIR $prop.Name
				if (-not (Test-Path $sp)) { continue }
				# 同格式字符串比较（yyyy-MM-dd HH:mm），避免分钟截断导致误报
				$curMod = (Get-Item $sp).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
				if ($curMod -gt $prop.Value.modified) { $stale += $prop.Name }
			}
			if ($stale.Count -gt 0) {
				$issues += "script_modified_no_bump:$($stale.Count)"
				Write-Status "有工具脚本已修改但未登记版本：$($stale -join ', ')" -Type Warning
			}
		}
	}

	# 检查 code-style-check 回归时效（脚本改动后必须验证基线，防漏检/误报）
	$cscPath = Join-Path $SCRIPT:TOOLS_DIR 'code-style-check.ps1'
	if (Test-Path $cscPath) {
		$stampPath = Join-Path $SCRIPT:TOOLS_DIR 'verify-code-style\.last_verified'
		if (-not (Test-Path $stampPath)) {
			$issues += 'verify_check_never_run'
			Write-Status "code-style-check.ps1 从未跑过 verify-check 回归，请先跑一遍基线" -Type Warning
		} else {
			try {
				$lastVerify = [datetime](Get-Content $stampPath -Raw)
				if ((Get-Item $cscPath).LastWriteTime -gt $lastVerify) {
					$issues += 'code_style_unverified'
					Write-Status "code-style-check.ps1 已改动但未回归：cd Tools\verify-code-style 跑 .\verify-check.ps1" -Type Warning
				}
			} catch {
				$issues += 'verify_stamp_invalid'
				Write-Status ".last_verified 时间戳无效，请重跑 verify-check.ps1" -Type Warning
			}
		}
	}

	if ($issues.Count -gt 0) { $report.issues = ($issues -join '; ') }
	return $report
}

# ==================== 模块 4.5: Update-Knowledge（skills + memory 仓自动提交） ====================

function Update-Knowledge {
	param([switch]$Dry)
	$report = @{ ok = $true; repos = @(); errors = '' }
	$targets = [ordered]@{
		'skills' = $SCRIPT:SKILLS_SCAN_DIRS[0]
		'memory' = $SCRIPT:MEMORY_DIR
	}
	foreach ($name in $targets.Keys) {
		$repo = $targets[$name]
		if (-not (Test-Path (Join-Path $repo '.git'))) { $report.errors += "${name}:no_repo "; continue }
		Push-Location $repo
		try {
			$st = git status --porcelain 2>$null
			if (-not $st) { $report.repos += "${name}:clean"; continue }
			if ($Dry) { $report.repos += "${name}:dry_commit"; continue }
			git add -A 2>&1 | Out-Null
			$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
			git commit -m "chore(knowledge): 自动提交 $stamp" 2>&1 | Out-Null
			if ($LASTEXITCODE -ne 0) { $report.errors += "${name}:commit_failed "; continue }
			git push 2>&1 | Out-Null
			if ($LASTEXITCODE -eq 0) {
				$report.repos += "${name}:pushed"
				Write-Status "已自动提交并推送 $name 仓（$stamp）" -Type Success
			} else {
				$report.repos += "${name}:committed"
				Write-Status "$name 仓已提交但推送失败（推送：git push 重试）" -Type Warning
			}
		} catch { $report.errors += "${name}:$_ " }
		finally { Pop-Location }
	}
	if ($report.errors) { $report.ok = $false; $report.reason = $report.errors.Trim() }
	return $report
}

# ==================== 模块 5: Update-Env ====================

function Update-Env {
	param([switch]$Dry)
	$report = @{ ok = $true; detected = 0; changed = 0; unchanged = 0 }
	$detected = [ordered]@{}

	# 系统构建号
	$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
	if ($osInfo -and $osInfo.BuildNumber) {
		$detected['windows_build'] = [string]$osInfo.BuildNumber
	}

	# Keil C51 版本
	$c51Path = 'D:\Keil_v5\C51\BIN\C51.exe'
	if (Test-Path $c51Path) {
		try {
			$ver = (Get-Item $c51Path).VersionInfo.FileVersion
			if ($ver) { $detected['keil_c51'] = $ver }
		} catch {}
	}

	# ESP-IDF 版本与路径
	try {
		$idfPath = $env:ESP_IDF_ROOT
		if (-not $idfPath) {
			$espIdfEnv = Join-Path $SCRIPT:TOOLS_DIR 'esp-idf-env.ps1'
			if (Test-Path $espIdfEnv) { . $espIdfEnv }
			$idfPath = $env:ESP_IDF_ROOT
		}
		if ($idfPath -and (Test-Path $idfPath)) {
			$detected['esp_idf_path'] = $idfPath
			$verFile = Join-Path $idfPath 'tools\cmake\version.cmake'
			if (Test-Path $verFile) {
				$vc = Get-Content $verFile -Raw -ErrorAction SilentlyContinue
				if ($vc -match 'IDF_VER\s+"([^"]+)"') { $detected['esp_idf'] = $matches[1] }
			}
		}
	} catch {}

	# Python 版本
	try {
		$py = & python --version 2>$null
		if ($py -match 'Python\s+([\d.]+)') { $detected['python'] = $matches[1] }
	} catch {}

	# uv 版本
	try {
		$uv = & uv --version 2>$null
		if ($uv -match 'uv\s+([\d.]+)') { $detected['uv'] = $matches[1] }
	} catch {}

	$report.detected = $detected.Count
	Write-Status "检测到 $($detected.Count) 项环境信息" -Type Info

	if (-not (Test-Path $SCRIPT:USER_PROFILE)) {
		$report.changed = $detected.Count
		Write-Status "user_profile.md 不存在，跳过对比" -Type Warning
		return $report
	}

	$content = [System.IO.File]::ReadAllText($SCRIPT:USER_PROFILE, [System.Text.UTF8Encoding]::new($false))
	$envSection = ''
	if ($content -match '(?ms)^## 环境状态.*?(?=^## |\z)') { $envSection = $matches[0] }

	# 每项的匹配与替换规则（只替换版本/路径/构建号，保留行内其余文字）
	$rules = [ordered]@{
		windows_build = @{ match = "\(Build\s+(\d+)\)";            replace = '(Build {0})' }
		keil_c51      = @{ match = 'Keil C51 编译器\*\*：V([\d.]+)';  replace = 'Keil C51 编译器**：V{0}' }
		esp_idf       = @{ match = 'ESP-IDF\*\*：v([\d.]+)';         replace = 'ESP-IDF**：v{0}' }
		esp_idf_path  = @{ match = '当前路径\s+([^\s。]+)';           replace = '当前路径 {0}' }
		python        = @{ match = 'Python\*\*：系统\s+([\d.]+)';     replace = 'Python**：系统 {0}' }
		uv            = @{ match = 'uv / uvx\*\*：([\d.]+)';          replace = 'uv / uvx**：{0}' }
	}

	$newContent = $content
	foreach ($key in $detected.Keys) {
		$val = $detected[$key]
		$rule = $rules[$key]
		if (-not $rule) { $report.unchanged++; continue }
		if ($envSection -match $rule.match) {
			$oldVal = $matches[1]
			if ($oldVal -eq $val) {
				$report.unchanged++
			} else {
				$report.changed++
				$repStr = [string]::Format($rule.replace, $val)
				$newContent = Replace-FirstEnvMatch $newContent $rule.match $repStr
				Write-Status "环境变化 [$key]: '$oldVal' -> '$val'" -Type Warning
			}
		} else {
			$report.changed++
			Write-Status "环境项 [$key] 未在记忆中找到 ('$val')" -Type Warning
		}
	}

	if (-not $Dry -and $report.changed -gt 0) {
		$date = Get-Date -Format 'yyyy-MM-dd'
		$newContent = $newContent -replace '(## 环境状态)（\d{4}-\d{2}-\d{2} 更新）', ('$1（' + $date + ' 更新）')
		Copy-Item -Path $SCRIPT:USER_PROFILE -Destination ($SCRIPT:USER_PROFILE + '.bak') -Force
		[System.IO.File]::WriteAllText($SCRIPT:USER_PROFILE, $newContent, [System.Text.UTF8Encoding]::new($false))
		Write-Status "已更新 user_profile.md 环境状态章节" -Type Success
	}
	return $report
}

function Replace-FirstEnvMatch {
	param([string]$Content, [string]$Pattern, [string]$Replacement)
	# 仅在"环境状态"章节内替换首次匹配
	if ($Content -match '(?ms)^(## 环境状态.*?)(?=^## |\z)') {
		$section = $matches[1]
		$before = $Content.Substring(0, $matches.Index)
		$after = $Content.Substring($matches.Index + $matches.Length)
		$newSection = [regex]::Replace($section, $Pattern, $Replacement, 1, [System.Text.RegularExpressions.RegexOptions]::Multiline)
		return $before + $newSection + $after
	}
	return $Content
}

# ==================== 模块 6: Update-Device ====================

function Update-Device {
	param(
		[string]$TargetPort,
		[switch]$Dry
	)
	$report = @{ ok = $true; detected = ''; changed = ''; unchanged = ''; skipped = '' }
	# 扫描串口
	$ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
	if ($ports.Count -eq 0) {
		$report.skipped = 'no_ports'
		Write-Status "未发现串口设备" -Type Warning
		return $report
	}
	Write-Status "发现串口: $($ports -join ', ')" -Type Info

	# 选择串口（优先 USB Serial / CP210x / CH340）
	$selected = $TargetPort
	if (-not $selected) {
		try {
			$pnpDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
				Where-Object { $_.Caption -match "\(COM\d+\)" }
			$priority = @('USB Serial', 'CP210', 'CH340', 'CH341')
			foreach ($pri in $priority) {
				$match = $pnpDevices | Where-Object { $_.Caption -match $pri } | Select-Object -First 1
				if ($match -and $match.Caption -match "\(COM(\d+)\)") {
					$selected = "COM$($matches[1])"
					break
				}
			}
		} catch {}
	}
	if (-not $selected) { $selected = $ports[0] }
	Write-Status "使用串口: $selected" -Type Info

	if ($Dry) {
		$report.detected = "dry_port=$selected"
		return $report
	}

	# 调用 esptool.py 读取芯片信息
	$esptool = 'esptool.py'
	try {
		$output = & $esptool --port $selected chip_id 2>&1 | Out-String
	} catch {
		$report.skipped = 'esptool_failed'
		Write-Status "esptool 调用失败: $_" -Type Warning
		return $report
	}

	$chipType = ''
	$mac = ''
	$flashSize = ''
	if ($output -match 'Chip is\s+(.+?)\s') { $chipType = $matches[1].Trim() }
	if ($output -match 'MAC:\s+([0-9a-fA-F:]+)') { $mac = $matches[1].Trim() }
	if ($output -match 'Flash size:\s+(.+)') { $flashSize = $matches[1].Trim() }

	if (-not $chipType) {
		$report.skipped = 'no_chip_info'
		Write-Status "未能读取芯片信息（可能非 ESP32 设备）" -Type Warning
		return $report
	}

	$report.detected = "chip=$chipType; mac=$mac; flash=$flashSize; port=$selected"
	Write-Status "芯片类型: $chipType" -Type Success
	Write-Status "MAC: $mac" -Type Success
	Write-Status "Flash: $flashSize" -Type Success
	Write-Status "串口: $selected" -Type Success
	Write-Status "（设备信息不自动写入记忆，需手动确认）" -Type Info
	return $report
}

# ==================== 模块 7: Update-Projects ====================

function Update-Projects {
	param(
		[string]$Root,
		[switch]$Dry,
		[switch]$AutoPush
	)
	$report = @{ ok = $true; scanned = 0; projects = 0; inited = 0; pulled = 0; committed = 0; pushed = 0; errors = '' }
	if (-not $Root) { $Root = $SCRIPT:DEFAULT_PROJECT_ROOT }
	if (-not (Test-Path $Root)) {
		$report.ok = $false
		$report.errors = 'root_missing'
		return $report
	}
	Write-Status "扫描项目根目录: $Root (最大深度 $($SCRIPT:PROJECT_MAX_DEPTH))" -Type Info

	$projects = Find-Projects -Root $Root -MaxDepth $SCRIPT:PROJECT_MAX_DEPTH
	$report.scanned = $projects.scanned
	$report.projects = $projects.list.Count
	Write-Status "扫描 $($report.scanned) 个目录，识别 $($report.projects) 个项目" -Type Info

	foreach ($proj in $projects.list) {
		Write-Status "处理项目: $($proj.Path) [$($proj.Type)]" -Type Info
		$result = Sync-ProjectGit -Path $proj.Path -Dry:$Dry -AutoPush:$AutoPush
		switch ($result.action) {
			'init'   { $report.inited++ }
			'pull'   { $report.pulled++ }
			'commit' { $report.committed++ }
			'push'   { $report.pushed++ }
		}
		if (-not $result.ok -and $result.error) {
			$report.errors += "$($proj.Path):$($result.error) "
		}
	}
	return $report
}

function Find-Projects {
	param([string]$Root, [int]$MaxDepth)
	$list = New-Object System.Collections.ArrayList
	$scanned = 0
	$stack = New-Object System.Collections.ArrayList
	$null = $stack.Add(@{ Path = $Root; Depth = 0 })
	while ($stack.Count -gt 0) {
		$item = $stack[$stack.Count - 1]
		$stack.RemoveAt($stack.Count - 1)
		if (-not (Test-Path $item.Path)) { continue }
		$scanned++
		$type = Test-ProjectType -Path $item.Path
		if ($type) {
			$null = $list.Add(@{ Path = $item.Path; Type = $type })
			continue  # 识别为项目后不再深入
		}
		if ($item.Depth -ge $MaxDepth) { continue }
		try {
			$subs = Get-ChildItem -Path $item.Path -Directory -ErrorAction SilentlyContinue
			foreach ($s in $subs) {
				# 跳过常见非项目目录
				if ($s.Name -match '^(build|node_modules|\.git|\.vscode|managed_components|\.cache|__pycache__)$') { continue }
				$null = $stack.Add(@{ Path = $s.FullName; Depth = $item.Depth + 1 })
			}
		} catch {}
	}
	return @{ scanned = $scanned; list = @($list) }
}

function Test-ProjectType {
	param([string]$Path)
	# ESP-IDF: CMakeLists.txt + sdkconfig
	if ((Test-Path (Join-Path $Path 'CMakeLists.txt')) -and (Test-Path (Join-Path $Path 'sdkconfig'))) {
		return 'esp-idf'
	}
	# Keil-ARM: .uvprojx
	if (Get-ChildItem -Path $Path -Filter '*.uvprojx' -File -ErrorAction SilentlyContinue) {
		return 'keil-arm'
	}
	# Keil-C51: .uvproj
	if (Get-ChildItem -Path $Path -Filter '*.uvproj' -File -ErrorAction SilentlyContinue) {
		return 'keil-c51'
	}
	# Makefile
	if (Test-Path (Join-Path $Path 'Makefile')) {
		return 'makefile'
	}
	return $null
}

function Sync-ProjectGit {
	param([string]$Path, [switch]$Dry, [switch]$AutoPush)
	$result = @{ ok = $true; action = ''; error = '' }
	Push-Location $Path
	try {
		$isRepo = $false
		try {
			$null = git rev-parse --git-dir 2>$null
			if ($LASTEXITCODE -eq 0) { $isRepo = $true }
		} catch {}

		if (-not $isRepo) {
			Write-Status "  非 git 仓库，初始化..." -Type Info
			if ($Dry) { $result.action = 'init'; return $result }
			git init 2>&1 | Out-Null
			# 创建 .gitignore
			$gitignorePath = Join-Path $Path '.gitignore'
			if (-not (Test-Path $gitignorePath)) {
				$gitignoreContent = @"
# 构建产物
build/
Listings/
Objects/
Output/
DebugConfig/
Debug/
*.o
*.obj
*.elf
*.bin
*.hex
*.map
*.bak
*.tmp

# Keil 临时文件
*.uvoptx
*.uvopt
*.scvd
*.db
*.dep
*.d
*.lst
*.htm
*.crf
*.iex
*.lnp
*.sct
*.ini
*.dbgconf
JLinkLog.txt

# ESP-IDF
managed_components/
dependencies.lock
sdkconfig.old
*.log

# IDE / 编辑器
.vscode/
.idea/
*.swp
*~

# 系统
Thumbs.db
.DS_Store
"@
				[System.IO.File]::WriteAllText($gitignorePath, $gitignoreContent, [System.Text.UTF8Encoding]::new($false))
			}
			git add . 2>&1 | Out-Null
			git commit -m 'init: 项目初始化' 2>&1 | Out-Null
			$result.action = 'init'
			return $result
		}

		# 已是仓库，检查 remote
		$remote = git remote 2>$null
		if (-not $remote) {
			Write-Status "  git 仓库无 remote" -Type Warning
			$result.action = 'no_remote'
			return $result
		}

		$status = git status --porcelain 2>$null
		if ($status -and $AutoPush) {
			Write-Status "  工作区有改动，提交..." -Type Info
			if (-not $Dry) {
				git add . 2>&1 | Out-Null
				$date = Get-Date -Format 'yyyy-MM-dd HH:mm'
				git commit -m "auto: 自动提交 $date" 2>&1 | Out-Null
				$result.action = 'commit'
				git push 2>&1 | Out-Null
				if ($LASTEXITCODE -eq 0) { $result.action = 'push' }
			}
			return $result
		}

		Write-Status "  拉取更新..." -Type Info
		if (-not $Dry) {
			git pull 2>&1 | Out-Null
		}
		$result.action = 'pull'
		return $result
	} catch {
		$result.ok = $false
		$result.error = $_.ToString()
		return $result
	} finally {
		Pop-Location
	}
}

# ==================== 主入口 ====================

function Invoke-SelfUpdate {
	Write-Host ""
	Write-Host "================================================" -ForegroundColor Cyan
	Write-Host "        自我更新升级工具 v2.0" -ForegroundColor White
	Write-Host "================================================" -ForegroundColor Cyan
	Write-Host "  模式: $Mode | 触发: $Trigger | DryRun: $([bool]$DryRun)" -ForegroundColor DarkGray
	Write-Host ""

	$state = Get-State

	# 检查触发间隔（非 manual 模式时）
	if ($Trigger -ne 'manual') {
		$allowed = Test-TriggerAllowed -State $state -TriggerType $Trigger
		if (-not $allowed) {
			Write-Status "触发间隔未满足 ($Trigger)，跳过执行。使用 -Force 强制执行。" -Type Warning
			return @{ ok = $false; reason = 'interval_not_met' }
		}
	}

	$results = @{}
	$modeRun = $false

	switch ($Mode) {
		'all' {
			$results.tools = Update-Tools -Url $RemoteUrl -Dry:$DryRun
			$results.skills = Update-Skills -Dry:$DryRun -AutoFix:$AutoFix; $results.skills_health = Invoke-SkillsHealth
			$results.memory = Update-Memory -Dry:$DryRun
			$results.config = Update-Config -Dry:$DryRun
			$modeRun = $true
		}
		'tools'    { $results.tools = Update-Tools -Url $RemoteUrl -Dry:$DryRun; $modeRun = $true }
		'skills'   { $results.skills = Update-Skills -Dry:$DryRun -AutoFix:$AutoFix; $results.skills_health = Invoke-SkillsHealth; $modeRun = $true }
		'memory'   { $results.memory = Update-Memory -Dry:$DryRun; $modeRun = $true }
		'config'   { $results.config = Update-Config -Dry:$DryRun; $modeRun = $true }
		'backup'   {
			$results.tools = Update-Tools -Url $RemoteUrl -Dry:$DryRun
			$results.knowledge = Update-Knowledge -Dry:$DryRun
			$modeRun = $true
		}
		'env'      { $results.env = Update-Env -Dry:$DryRun; $modeRun = $true }
		'device'   { $results.device = Update-Device -TargetPort $Port -Dry:$DryRun; $modeRun = $true }
		'projects' {
			$results.projects = Update-Projects -Root $ProjectRoot -Dry:$DryRun -AutoPush:$AutoCommit
			$modeRun = $true
		}
		'env-device' {
			$results.env = Update-Env -Dry:$DryRun
			$results.device = Update-Device -TargetPort $Port -Dry:$DryRun
			$modeRun = $true
		}
		default {
			Write-Status "未知模式: $Mode" -Type Error
			return @{ ok = $false; reason = 'unknown_mode' }
		}
	}

	if (-not $modeRun) {
		return @{ ok = $false; reason = 'no_mode' }
	}

	# 更新状态文件
	$runRecord = @{
		time = (Get-Date).ToString('o')
		mode = $Mode
		trigger = $Trigger
		dry = [bool]$DryRun
		results = $results
	}
	$state.runs += ,$runRecord
	switch ($Trigger) {
		'session' { $state.last_session_run = $runRecord.time }
		'error'   { $state.last_error_run = $runRecord.time }
		'git'     { $state.last_git_run = $runRecord.time }
	}
	Save-State -State $state

	# 输出执行汇总
	Write-Section '执行汇总'
	foreach ($key in $results.Keys) {
		$r = $results[$key]
		if ($r.ok) {
			Write-Status "[$key] 成功" -Type Success
		} else {
			Write-Status "[$key] 失败: $($r.reason)" -Type Error
		}
	}
	Write-Host ""
	return @{ ok = $true; reason = ''; results = $results }
}

# 执行
$result = Invoke-SelfUpdate
if (-not $result.ok -and $result.reason -ne 'interval_not_met') {
	exit 1
}
