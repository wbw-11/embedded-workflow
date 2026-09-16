<#
.SYNOPSIS
	通用构建脚本
  version: 1.0.0
#>

param([switch]$Clean, [switch]$Flash, [string]$ProjectDir=(Get-Location), [string]$Port, [switch]$SkipReviewCheck)

. "$PSScriptRoot\lib\common.ps1"

function Get-ProjectType {
	param([string]$Path)
	if (Test-Path (Join-Path $Path 'sdkconfig')) { return 'ESP-IDF' }
	$uvprojx = Get-ChildItem -Path $Path -Filter '*.uvprojx' -File -ErrorAction SilentlyContinue
	if (-not $uvprojx) { $uvprojx = Get-ChildItem -Path $Path -Filter '*.uvprojx' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue }
	if ($uvprojx.Count -gt 0) { return @{Type='Keil ARM';File=$uvprojx[0].FullName} }
	$uvproj = Get-ChildItem -Path $Path -Filter '*.uvproj' -File -ErrorAction SilentlyContinue
	if (-not $uvproj) { $uvproj = Get-ChildItem -Path $Path -Filter '*.uvproj' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue }
	if ($uvproj.Count -gt 0) { return @{Type='Keil C51';File=$uvproj[0].FullName} }
	return 'Unknown'
}

function Invoke-ReviewGate {
	<#
	烧录前审查门槛：检查是否已跑过代码审查
	返回 $true = 允许烧录，$false = 中止
	#>
	if ($SkipReviewCheck) { return $true }

	Write-Host ''
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host '  烧录前审查检查' -ForegroundColor Cyan
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host '[!] 烧录前建议先完成以下检查：' -ForegroundColor Yellow
	Write-Host '    1. code-style-check.ps1（自动检测溢出/防御性编程/命名规范）'
	Write-Host '    2. embedded-code-review Skill（人工审查 22 类 90+ 项）'
	Write-Host ''
	$answer = Read-Host '已跑过代码审查？(Y=已审查/直接烧录, N=没跑过/先审查, S=跳过本次检查)'
	if ($answer -eq 'N' -or $answer -eq 'n') {
		Write-Host '[i] 建议操作：' -ForegroundColor Yellow
		Write-Host '    1. code-style-check -Path <代码.c> -Checks "brace,overflow,defensive,naming"'
		Write-Host '    2. 让助手执行 embedded-code-review Skill 审查代码'
		Write-Host '    3. 审查通过后重新执行编译烧录'
		Write-Host '[X] 烧录已中止（如需跳过检查，加 -SkipReviewCheck 参数）' -ForegroundColor Red
		return $false
	}
	if ($answer -eq 'S' -or $answer -eq 's') {
		Write-Host '[!] 已跳过审查检查，继续烧录...' -ForegroundColor Yellow
	}
	return $true
}

function Build-EspIdf {
	param([string]$Path, [bool]$DoClean, [bool]$DoFlash, [string]$TargetPort)
	Push-Location $Path
	try {
		if ($DoClean) { & python "$env:IDF_PATH\tools\idf.py" fullclean }
		& python "$env:IDF_PATH\tools\idf.py" build
		if ($DoFlash) {
			if (-not (Invoke-ReviewGate)) { return }
			Write-Host '[!] 使用安全烧录模式...' -ForegroundColor Yellow
			if ($TargetPort) {
				& "$PSScriptRoot\safe-flash.ps1" -Port $TargetPort
			} else {
				& "$PSScriptRoot\safe-flash.ps1"
			}
		}
	} finally { Pop-Location }
}

function Build-Keil {
	param([string]$ProjectFile, [bool]$DoClean, [bool]$DoFlash)
	if ($DoClean) { keil-clean -All }
	$uv4 = Find-KeilUv4
	if (-not $uv4) { Write-Host '[X] 未找到 Keil UV4' -ForegroundColor Red; return }
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $uv4
	$psi.Arguments = '-b "{0}" -o build.log' -f $ProjectFile
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true
	$proc = [System.Diagnostics.Process]::Start($psi)
	$proc.WaitForExit()
	if (Test-Path 'build.log') {
		Remove-Item 'build.log' -Force -ErrorAction SilentlyContinue
	}
	if ($DoFlash) {
		if (-not (Invoke-ReviewGate)) { return }
		Write-Host '[!] ARM/C51 烧录请使用对应工具（Keil 下载 / STC-ISP）' -ForegroundColor Yellow
	}
}

$projType = Get-ProjectType -Path $ProjectDir
if ($projType -eq 'Unknown') { Write-Host '[X] 无法识别项目类型'; exit 1 }

Push-Location $ProjectDir
try {
	if ($projType -eq 'ESP-IDF') {
		if (-not $env:IDF_PATH) { . "$PSScriptRoot\esp-idf-env.ps1" }
		Build-EspIdf -Path $ProjectDir -DoClean $Clean -DoFlash $Flash -TargetPort $Port
	} else {
		Build-Keil -ProjectFile $projType.File -DoClean $Clean -DoFlash $Flash
	}
} finally { Pop-Location }

