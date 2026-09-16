<#
.SYNOPSIS
开工预检（可选步骤）：工程声明 × 工具链清单 × 硬件证据 三查比对，输出能否直接开工
.DESCRIPTION
新项目 / 老项目开工前运行，自动判断本机工具链是否覆盖工程需求，避免用错版本。
  1. 工程声明：读 .uvprojx 的 <Device>/<PackID>、sdkconfig 的 IDF target
  2. 工具链清单：Keil UV4 + 已装 DFP（ARM\PACK 扫描）、ESP-IDF 框架版本（候选路径+存在性）
  3. 硬件证据（-Board）：调用 detect-chip 实测芯片，与声明比对
结论：OK 可直接开工 / [!] 缺版本（列出差距）/ [X] 无法识别（缺资料需人工）
.EXAMPLE
preflight                          # 预检当前目录
preflight -ProjectDir D:\proj\gd32 # 预检指定工程
preflight -ProjectDir D:\proj -Board   # 含硬件实测（需板子在线）
  version: 1.0.3
#>
param(
	[string]$ProjectDir = (Get-Location),
	[switch]$Board,       # 含硬件实测（detect-chip，需板子在线）
	[switch]$FixAuto    # 缺 DFP 时自动调 Keil Pack Installer 安装
)

$ErrorActionPreference = 'Continue'
$SCRIPT:TOOLS = $PSScriptRoot
$commonPs1 = Join-Path $PSScriptRoot 'lib\common.ps1'
if (Test-Path $commonPs1) { . $commonPs1 }

function Write-Hr {
	param([string]$Title)
	Write-Host ''
	Write-Host ('=' * 60) -ForegroundColor White
	Write-Host "  $Title" -ForegroundColor White
	Write-Host ('=' * 60) -ForegroundColor White
}

# ============================================================
# 1. 工程声明
# ============================================================
function Get-ProjDeclare {
	param([string]$Path)
	$result = @{ Type = 'Unknown'; Chip = ''; PackID = ''; IdfTarget = '' }
	if (-not (Test-Path $Path)) { return $result }

	# ESP-IDF
	$sdkconfig = Join-Path $Path 'sdkconfig'
	if (Test-Path $sdkconfig) {
		$result.Type = 'ESP-IDF'
		$t = Get-Content $sdkconfig -Raw -ErrorAction SilentlyContinue
		$m = [regex]::Match($t, 'CONFIG_IDF_TARGET="?([^"\r\n]+)"?')
		if ($m.Success) { $result.IdfTarget = $m.Value -replace 'CONFIG_IDF_TARGET="?', '' -replace '"$', '' }
		return $result
	}

	# Keil ARM / C51（根目录 + 两级递归）
	$uvprojx = Get-ChildItem -Path $Path -Filter '*.uvprojx' -File -ErrorAction SilentlyContinue
	if (-not $uvprojx) { $uvprojx = Get-ChildItem -Path $Path -Filter '*.uvprojx' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue }
	if ($uvprojx) {
		$result.Type = 'Keil ARM'
		$xml = Get-Content $uvprojx[0].FullName -Raw -ErrorAction SilentlyContinue
		$m1 = [regex]::Match($xml, '<Device>(.*?)</Device>')
		$m2 = [regex]::Match($xml, '<PackID>(.*?)</PackID>')
		if ($m1.Success) { $result.Chip = $m1.Groups[1].Value }
		if ($m2.Success) { $result.PackID = $m2.Groups[1].Value }
		return $result
	}
	$uvproj = Get-ChildItem -Path $Path -Filter '*.uvproj' -File -ErrorAction SilentlyContinue
	if (-not $uvproj) { $uvproj = Get-ChildItem -Path $Path -Filter '*.uvproj' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue }
	if ($uvproj) {
		$result.Type = 'Keil C51'
		$xml = Get-Content $uvproj[0].FullName -Raw -ErrorAction SilentlyContinue
		$m1 = [regex]::Match($xml, '<Device>(.*?)</Device>')
		if ($m1.Success) { $result.Chip = $m1.Groups[1].Value }
		return $result
	}
	return $result
}

# ============================================================
# 2. 工具链清单
# ============================================================
function Get-ToolchainList {
	$result = @{ Uv4 = ''; C51 = ''; DfpList = @(); EspIdfList = @() }
	$uv4 = Find-KeilUv4
	$result.Uv4 = $uv4
	if ($uv4) {
		# UV4.exe 在 <Keil根>\UV4\ → 反推根目录
		$keilRoot = Split-Path (Split-Path $uv4)
		$armRoot = Join-Path $keilRoot 'ARM'
		$dfp = @()
		# 布局1：标准 Pack 安装器 ARM\PACK\<vendor>\<pack>\<ver>
		$packRoot = Join-Path $armRoot 'PACK'
		if (Test-Path $packRoot) {
			$dfp += @(Get-ChildItem $packRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
				$vendor = $_.Name
				Get-ChildItem $_.FullName -Directory -Filter '*_DFP' -ErrorAction SilentlyContinue | ForEach-Object {
					$pack = $_.Name
					Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object { "$vendor.$pack.$($_.Name)" }
				}
			})
		}
		# 布局2：Keil ARM 下 vendor 直布局 ARM\<vendor>\<pack>\<ver>
		if (Test-Path $armRoot) {
			$dfp += @(Get-ChildItem $armRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
				$vendor = $_.Name
				Get-ChildItem $_.FullName -Directory -Filter '*_DFP' -ErrorAction SilentlyContinue | ForEach-Object {
					$pack = $_.Name
					Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object { "$vendor.$pack.$($_.Name)" }
				}
			})
		}
		$result.DfpList = @($dfp | Select-Object -Unique)
	}
	$c51 = Find-KeilC51
	if ($c51) { $result.C51 = $c51 }

	# ESP-IDF 框架版本（候选路径 + 存在性）
	$espRoots = @(
		'D:\ESP32\Espressif',
		'C:\Espressif',
		'C:\esp',
		"$env:USERPROFILE\esp\Espressif",
		"$env:USERPROFILE\.espressif"
	)
	foreach ($r in $espRoots) {
		$fw = Join-Path $r 'frameworks'
		if (Test-Path $fw) {
			$result.EspIdfList += @(Get-ChildItem $fw -Directory -Filter 'esp-idf-*' -ErrorAction SilentlyContinue |
				ForEach-Object { $_.Name })
		}
	}
	$result.EspIdfList = @($result.EspIdfList | Select-Object -Unique)
	return $result
}

# ============================================================
# 3. 比对结论
# ============================================================
function Find-PackInstaller {
	$uv4 = Find-KeilUv4
	if (-not $uv4) { return }
	$keilRoot = Split-Path (Split-Path $uv4)
	$cands = @(
		"$keilRoot\UV4\PackInstaller.exe",
		"$keilRoot\PackInstaller.exe",
		"$keilRoot\ARM\PackInstaller.exe",
		"$keilRoot\KDK\PackInstaller.exe"
	)
	return ($cands | Where-Object { Test-Path $_ } | Select-Object -First 1)
}

function Get-Conclusion {
	param($Decl, $Toolchain)
	$verdict = @{ Status = 'OK'; Msg = ''; Guide = ''; MissingPack = '' }
	switch ($Decl.Type) {
		'Keil ARM' {
			if ($Decl.PackID) {
				if ($Toolchain.DfpList -contains $Decl.PackID) {
					$verdict.Msg = "DFP $($Decl.PackID) 已装，可直接开工"
				} else {
					$verdict.Status = 'WARN'
					$verdict.Msg = "缺 DFP：需要 $($Decl.PackID)，已装：$($Toolchain.DfpList -join ', ')"
					$verdict.Guide = "缺包安装：Keil Pack Installer 搜索 $($Decl.PackID) 安装；或打开该工程 .uvprojx 按 Keil 提示一键下载"
					$verdict.MissingPack = $Decl.PackID
				}
			} elseif (-not $Toolchain.Uv4) {
				$verdict.Status = 'WARN'
				$verdict.Msg = '未找到 Keil UV4'
			} else {
				$verdict.Msg = '工程未声明 PackID，Keil 已装，默认可用'
			}
		}
		'Keil C51' {
			if (-not $Toolchain.C51) {
				$verdict.Status = 'WARN'
				$verdict.Msg = '未找到 Keil C51（8051 编译器）'
			} else {
				$verdict.Msg = 'Keil C51 已装，可直接开工'
			}
		}
		'ESP-IDF' {
			if ($Toolchain.EspIdfList.Count -eq 0) {
				$verdict.Status = 'WARN'
				$verdict.Msg = '未检测到 ESP-IDF 框架（候选路径均无）'
			} else {
				$verdict.Msg = "已装 ESP-IDF：$($Toolchain.EspIdfList -join ', ')，可直接开工"
			}
		}
		default {
			$verdict.Status = 'ERR'
			$verdict.Msg = '无法识别工程类型（需要 sdkconfig / .uvprojx / .uvproj），缺资料需人工确认'
			$verdict.Guide = '确认目录含 sdkconfig 或 Keil 工程文件；新芯片项目先在 Pack Installer 装对应 DFP，再按 chip-rules 查该系列规则，走官方例程基线'
		}
	}
	return $verdict
}

# ============================================================
# 主流程
# ============================================================
if (-not (Test-Path $ProjectDir)) {
	Write-Host "[X] 项目目录不存在: $ProjectDir" -ForegroundColor Red
	exit 1
}

Write-Hr '开工预检'
Write-Host "  项目: $ProjectDir" -ForegroundColor Gray

# 1. 工程声明
Write-Hr '[1/3] 工程声明'
$decl = Get-ProjDeclare -Path $ProjectDir
Write-Host "  类型: $($decl.Type)" -ForegroundColor Cyan
if ($decl.Chip)        { Write-Host "  芯片: $($decl.Chip)" -ForegroundColor Cyan }
if ($decl.PackID)      { Write-Host "  需求 DFP: $($decl.PackID)" -ForegroundColor Cyan }
if ($decl.IdfTarget)   { Write-Host "  IDF target: $($decl.IdfTarget)" -ForegroundColor Cyan }

# 2. 工具链清单
Write-Hr '[2/3] 本机工具链清单'
$tc = Get-ToolchainList
if ($tc.Uv4)   { Write-Host "  Keil UV4: $($tc.Uv4)" -ForegroundColor Green } else { Write-Host '  Keil UV4: 未找到' -ForegroundColor Yellow }
if ($tc.C51)   { Write-Host "  Keil C51: $($tc.C51)" -ForegroundColor Green } else { Write-Host '  Keil C51: 未找到' -ForegroundColor Yellow }
if ($tc.DfpList.Count -gt 0) {
	Write-Host '  已装 DFP:' -ForegroundColor Green
	$tc.DfpList | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
} else { Write-Host '  已装 DFP: 无' -ForegroundColor Yellow }
if ($tc.EspIdfList.Count -gt 0) {
	Write-Host "  已装 ESP-IDF: $($tc.EspIdfList -join ', ')" -ForegroundColor Green
} else { Write-Host '  已装 ESP-IDF: 无' -ForegroundColor Yellow }

# 3. 硬件证据（可选）
if ($Board) {
	Write-Hr '[3/3] 硬件实测（detect-chip）'
	$hw = & "$PSScriptRoot\detect-chip.ps1" 2>&1
	$hw | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
	if (($hw -join "`n") -match '未能自动识别|低置信') {
		Write-Host '  [!] 未识别芯片：按 chip-rules 查该系列规则；或人工看丝印/查型号后告知助手，再走官方例程基线' -ForegroundColor Yellow
	}
}


# 结论
Write-Hr '结论'
$verdict = Get-Conclusion -Decl $decl -Toolchain $tc
switch ($verdict.Status) {
	'OK'   { Write-Host "  [OK] $($verdict.Msg)" -ForegroundColor Green }
	'WARN' { Write-Host "  [!] $($verdict.Msg)" -ForegroundColor Yellow }
	default { Write-Host "  [X] $($verdict.Msg)" -ForegroundColor Red }
}
	if ($verdict.Guide) { Write-Host "  指引: $($verdict.Guide)" -ForegroundColor Cyan }
if ($FixAuto -and $verdict.MissingPack) {
	$pi = Find-PackInstaller
	if ($pi) {
		Write-Host "  [安装] 检测到缺 $($verdict.MissingPack)，正在打开 Keil Pack Installer…" -ForegroundColor Cyan
		Start-Process $pi -ArgumentList "-install $($verdict.MissingPack)"
		Write-Host '  [安装] 请确认下载/安装完成后，重跑 preflight 验证'
	} else {
		Write-Host '  [x] 未找到 PackInstaller.exe，请手动打开 Keil Pack Installer 搜索安装' -ForegroundColor Yellow
	}
}
Write-Host ''
Write-Hr '个人流程规范（开工对照执行）'
$normCands = @(
    (Join-Path $env:USERPROFILE 'Desktop\<项目根目录>\个人嵌入式开发流程规范.md'),
    (Join-Path $env:USERPROFILE 'Desktop\个人嵌入式开发流程规范.md')
)
$normDoc = $normCands | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($normDoc) {
    Write-Host '  规范: 四步准备 / 红线 / 门禁三件套 / 验证 / 归档 / 经验沉淀' -ForegroundColor Green
    Write-Host "  位置: $normDoc" -ForegroundColor Gray
} else {
    Write-Host '  [i] 未找到《个人嵌入式开发流程规范》文档（可按 embedded-dev-rules 执行）' -ForegroundColor Yellow
}
exit 0
