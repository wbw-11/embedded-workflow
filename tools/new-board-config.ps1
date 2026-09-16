<#
.SYNOPSIS
	新板子配置生成器
.DESCRIPTION
	快速创建新的板子配置文件
.EXAMPLE
	new-board-config -Name "ESP32-S2-WROVER" -Type "ESP32-S2" -FlashSize "4MB" -DefaultUart "COM3"
	new-board-config -Auto    # 交互式创建
  version: 1.0.0
#>

param(
	[string]$Name,
	[string]$Type,
	[string]$FlashSize,
	[string]$RamSize,
	[string]$CrystalFreq,
	[string]$DefaultUart,
	[switch]$Auto
)

$configDir = Join-Path $PSScriptRoot 'board-config'

function New-BoardConfig {
	param(
		[string]$Name,
		[string]$Type,
		[string]$FlashSize,
		[string]$RamSize,
		[string]$CrystalFreq,
		[string]$DefaultUart
	)
	
	try {
		if (-not (Test-Path $configDir)) {
			New-Item -ItemType Directory -Path $configDir -Force | Out-Null
		}
		
		$fileName = $Name.ToLower().Replace(' ', '-').Replace('_', '-')
		$filePath = Join-Path $configDir "$fileName.ps1"
		
		if (Test-Path $filePath) {
			Write-Host "[!] 配置已存在: $fileName" -ForegroundColor Yellow
			$overwrite = Read-Host '是否覆盖？(Y/N)'
			if ($overwrite -notmatch '^[Yy]') {
				Write-Host '已取消' -ForegroundColor Gray
				return $false
			}
		}
		
		$psramLine = ''
		if ($RamSize -and $Type -match 'ESP32') {
			$psramLine = "`n	PsramSize = '$RamSize'"
		}
		
		$configContent = @"
@{
	Name = '$Name'
	Type = '$Type'
	FlashSize = '$FlashSize'$psramLine
	CrystalFreq = '$CrystalFreq'
	ReservedPins = @()
	ReservedDesc = @{}
	AvailablePins = @()
	DefaultUart = '$DefaultUart'
	Toolchain = '$(if ($Type -match 'ESP32') { 'ESP-IDF' } elseif ($Type -match 'STM32|GD32') { 'Keil ARM' } else { 'Keil C51' })'
}
"@
		
		Set-Content $filePath $configContent -Encoding UTF8
		Write-Host "[OK] 配置已创建: $filePath" -ForegroundColor Green
		Write-Host ''
		Write-Host '提示: 请编辑配置文件，补充引脚信息' -ForegroundColor Yellow
		Write-Host "  编辑 $filePath" -ForegroundColor Gray
		return $true
	} catch {
		Write-Host "[X] 创建失败: $($_.Exception.Message)" -ForegroundColor Red
		return $false
	}
}

function New-BoardConfigInteractive {
	Write-Host ''
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host '  新板子配置向导' -ForegroundColor Cyan
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host ''
	
	$name = Read-Host '芯片名称 (如: ESP32-S2-WROVER)'
	$type = Read-Host '芯片类型 (如: ESP32-S2, GD32F4, STM32F4, STC8H)'
	$flashSize = Read-Host 'Flash大小 (如: 4MB, 64KB)'
	
	if ($type -match 'ESP32') {
		$ramSize = Read-Host 'PSRAM大小 (如: 2MB, 8MB)'
	} else {
		$ramSize = Read-Host 'RAM大小 (如: 128KB, 8KB)'
	}
	
	$crystalFreq = Read-Host '晶振频率 (如: 40MHz, 24MHz)'
	$defaultUart = Read-Host '默认串口 (如: COM8)'
	
	Write-Host ''
	New-BoardConfig -Name $name -Type $type -FlashSize $flashSize -RamSize $ramSize -CrystalFreq $crystalFreq -DefaultUart $defaultUart
}

try {
	if ($Auto) {
		New-BoardConfigInteractive
		exit 0
	}
	
	if ($Name -and $Type) {
		$result = New-BoardConfig -Name $Name -Type $Type -FlashSize $FlashSize -RamSize $RamSize -CrystalFreq $CrystalFreq -DefaultUart $DefaultUart
		exit $(if ($result) { 0 } else { 1 })
	}
	
	Write-Host ''
	Write-Host '新板子配置生成器' -ForegroundColor Cyan
	Write-Host ''
	Write-Host '用法:' -ForegroundColor Yellow
	Write-Host '  new-board-config -Auto                          # 交互式创建' -ForegroundColor Gray
	Write-Host '  new-board-config -Name "xxx" -Type "xxx" ...    # 参数创建' -ForegroundColor Gray
	Write-Host ''
	Write-Host '参数:' -ForegroundColor Yellow
	Write-Host '  -Name          芯片名称' -ForegroundColor Gray
	Write-Host '  -Type          芯片类型' -ForegroundColor Gray
	Write-Host '  -FlashSize     Flash大小' -ForegroundColor Gray
	Write-Host '  -RamSize       RAM/PSRAM大小' -ForegroundColor Gray
	Write-Host '  -CrystalFreq   晶振频率' -ForegroundColor Gray
	Write-Host '  -DefaultUart   默认串口' -ForegroundColor Gray
	Write-Host ''
} catch {
	Write-Host "[X] 执行失败: $($_.Exception.Message)" -ForegroundColor Red
	exit 1
}
