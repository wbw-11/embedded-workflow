<#
.SYNOPSIS
	一键验证工具 - 代码完成后强制运行
.DESCRIPTION
	整合规范检查、头文件联动、编译验证 3 个步骤。
	未通过不得交付用户。对应 project_memory.md 的"代码完成后强制审查规则"。
.NOTE
	文件操作工具选择：常规读写用内置 Read/Edit/Grep 工具；
	MCP_Filesystem 仅供 integrated_code_mode 内 JavaScript 调用，不用于常规文件操作。

.USAGE
	auto-verify -Path <文件或目录>
	auto-verify -Path main.c
	auto-verify -Path . -SkipCompile
	auto-verify -Path uart.h -Steps style,impact
	auto-verify -Path . -Json report.json
  version: 1.0.0
#>

param(
	[Parameter(Mandatory = $true)]
	[string]$Path,

	[string]$Steps = 'all',

	[switch]$SkipCompile,

	[string]$Json = '',

	[switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$TOOLS_DIR = $PSScriptRoot

# ==================== 工具函数 ====================

function Write-Status {
	param([string]$Message, [string]$Type = 'Info')
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
	if ($Quiet) { return }
	Write-Host ""
	Write-Host ("=" * 60) -ForegroundColor DarkGray
	Write-Host " $Title" -ForegroundColor White
	Write-Host ("=" * 60) -ForegroundColor DarkGray
}

# 解析 Steps 参数（仅支持 style/impact/compile/all）
$stepList = @()
foreach ($s in $Steps -split ',') {
	$t = $s.Trim().ToLower()
	if ('style', 'impact', 'compile', 'all' -contains $t) {
		$stepList += $t
	}
}
if ($stepList.Count -eq 0) { $stepList = @('all') }
if ($SkipCompile) {
	$stepList = @($stepList | Where-Object { $_ -ne 'compile' -and $_ -ne 'all' })
	if ($stepList.Count -eq 0) { $stepList = @('style', 'impact') }
}
if ($stepList -contains 'all') {
	$stepList = @('style', 'impact', 'compile')
	if ($SkipCompile) { $stepList = @('style', 'impact') }
}

# 解析 Path
if (-not (Test-Path $Path)) {
	Write-Status "路径不存在: $Path" -Type Error
	exit 1
}
$fullPath = (Resolve-Path $Path).Path
$isFile = Test-Path $fullPath -PathType Leaf
$targetDir = if ($isFile) { Split-Path $fullPath -Parent } else { $fullPath }
$targetFile = if ($isFile) { $fullPath } else { '' }
$ext = if ($isFile) { [System.IO.Path]::GetExtension($fullPath).ToLower() } else { '' }

# 结果汇总
$result = @{
	path = $fullPath
	steps_run = @()
	steps_passed = @()
	steps_failed = @()
	steps_skipped = @()
	details = @{}
}

Write-Section "auto-verify 一键验证"
Write-Status "目标: $fullPath" -Type Info
Write-Status "步骤: $($stepList -join ', ')" -Type Info

# ==================== 步骤 1/3: 规范检查 ====================

if ($stepList -contains 'style') {
	Write-Section "步骤 1/3: 规范检查 (code-style-check)"
	$result.steps_run += 'style'
	$styleJson = if ($Json) { Join-Path $targetDir '.auto-verify-style.json' } else { '' }
	try {
		$styleScript = Join-Path $TOOLS_DIR 'code-style-check.ps1'
		if ($styleJson -and $Quiet) {
			& $styleScript -Path $fullPath -Checks all -Json $styleJson -Quiet
		} elseif ($styleJson) {
			& $styleScript -Path $fullPath -Checks all -Json $styleJson
		} elseif ($Quiet) {
			& $styleScript -Path $fullPath -Checks all -Quiet
		} else {
			& $styleScript -Path $fullPath -Checks all
		}
		$styleExit = $LASTEXITCODE
		if ($styleExit -eq 0) {
			Write-Status "规范检查通过" -Type Success
			$result.steps_passed += 'style'
		} else {
			Write-Status "规范检查发现问题（退出码 $styleExit）" -Type Warning
			$result.steps_failed += 'style'
		}
		$result.details.style = @{ exit_code = $styleExit; json = $styleJson }
	} catch {
		Write-Status "规范检查执行失败: $_" -Type Error
		$result.steps_failed += 'style'
		$result.details.style = @{ error = "$_" }
	}
}

# ==================== 步骤 2/3: 头文件联动 ====================

if ($stepList -contains 'impact') {
	Write-Section "步骤 2/3: 头文件联动 (impact-analyze)"
	$result.steps_run += 'impact'
	if ($isFile -and $ext -eq '.h') {
		$headerName = [System.IO.Path]::GetFileName($targetFile)
		try {
			& (Join-Path $TOOLS_DIR 'impact-analyze.ps1') -Path $targetDir -Header $headerName
			$impactExit = $LASTEXITCODE
			if ($impactExit -eq 0) {
				Write-Status "头文件影响分析完成" -Type Success
				$result.steps_passed += 'impact'
			} else {
				$result.steps_failed += 'impact'
			}
			$result.details.impact = @{ header = $headerName; exit_code = $impactExit }
		} catch {
			Write-Status "影响分析失败: $_" -Type Error
			$result.steps_failed += 'impact'
		}
	} else {
		Write-Status "非 .h 文件，跳过头文件联动分析" -Type Info
		$result.steps_skipped += 'impact'
	}
}

# ==================== 步骤 3/3: 编译验证 ====================

if ($stepList -contains 'compile') {
	Write-Section "步骤 3/3: 编译验证 (build-all)"
	$result.steps_run += 'compile'
	# 查找项目根目录（含 sdkconfig 或 .uvprojx 的目录）
	$projectRoot = $targetDir
	$searchDir = $targetDir
	for ($i = 0; $i -lt 5; $i++) {
		if ((Test-Path (Join-Path $searchDir 'sdkconfig')) -or
			(Get-ChildItem -Path $searchDir -Filter '*.uvprojx' -File -ErrorAction SilentlyContinue) -or
			(Get-ChildItem -Path $searchDir -Filter '*.uvproj' -File -ErrorAction SilentlyContinue)) {
			$projectRoot = $searchDir
			break
		}
		$parent = Split-Path $searchDir -Parent
		if (-not $parent -or $parent -eq $searchDir) { break }
		$searchDir = $parent
	}
	try {
		& (Join-Path $TOOLS_DIR 'build-all.ps1') -ProjectDir $projectRoot
		$buildExit = $LASTEXITCODE
		if ($buildExit -eq 0) {
			Write-Status "编译验证通过" -Type Success
			$result.steps_passed += 'compile'
		} else {
			Write-Status "编译失败（退出码 $buildExit）" -Type Error
			$result.steps_failed += 'compile'
		}
		$result.details.compile = @{ project_root = $projectRoot; exit_code = $buildExit }
	} catch {
		Write-Status "编译执行异常: $_" -Type Error
		$result.steps_failed += 'compile'
		$result.details.compile = @{ error = "$_" }
	}
}

# ==================== 汇总 ====================

Write-Section "验证汇总"
$totalRun = $result.steps_run.Count
$totalPass = $result.steps_passed.Count
$totalFail = $result.steps_failed.Count
$totalSkip = $result.steps_skipped.Count

Write-Status "执行: $totalRun | 通过: $totalPass | 失败: $totalFail | 跳过: $totalSkip" -Type Info

if ($totalFail -gt 0) {
	Write-Status "失败步骤: $($result.steps_failed -join ', ')" -Type Error
	Write-Status "验证未通过，不得交付用户" -Type Error
} else {
	Write-Status "全部步骤通过，可交付用户" -Type Success
}

# JSON 报告
if ($Json) {
	try {
		$jsonObj = @{
			path = $result.path
			timestamp = (Get-Date).ToString('o')
			steps_run = $result.steps_run
			steps_passed = $result.steps_passed
			steps_failed = $result.steps_failed
			steps_skipped = $result.steps_skipped
			details = $result.details
			overall_pass = ($totalFail -eq 0)
		}
		$jsonStr = $jsonObj | ConvertTo-Json -Depth 5
		[System.IO.File]::WriteAllText($Json, $jsonStr, [System.Text.UTF8Encoding]::new($true))
		Write-Status "JSON 报告已写入: $Json" -Type Info
	} catch {
		Write-Status "JSON 报告写入失败: $_" -Type Warning
	}
}

# 退出码
if ($totalFail -gt 0) { exit 1 } else { exit 0 }
