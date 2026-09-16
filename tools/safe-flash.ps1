<#
.SYNOPSIS
	安全烧录工具 - 防止烧录到错误的板子
.DESCRIPTION
	烧录前进行多重验证：
	1. 检测所有可用串口
	2. 如果有多个串口，提示用户选择
	3. 验证目标串口连接的芯片是否匹配当前配置
	4. 要求用户确认后才执行烧录
.EXAMPLE
	safe-flash                    # 安全烧录（自动检测+确认）
	safe-flash -Port COM8         # 指定串口烧录
	safe-flash -Force             # 跳过确认直接烧录
	safe-flash -ListPorts         # 列出所有可用串口
  version: 1.0.0
#>

param(
	[string]$Port,
	[switch]$Force,
	[switch]$ListPorts
)

function Get-AvailablePorts {
	[System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
}

function Get-ChipFromPort {
	param([string]$targetPort)
	
	try {
		$serial = New-Object System.IO.Ports.SerialPort($targetPort, 115200, 'None', 8, 'One')
		$serial.ReadTimeout = 1000
		$serial.WriteTimeout = 1000
		$serial.Open()
		
		$serial.DtrEnable = $true
		$serial.RtsEnable = $true
		Start-Sleep -Milliseconds 500
		
		$serial.WriteLine("")
		Start-Sleep -Milliseconds 200
		
		$response = ""
		for ($i = 0; $i -lt 10; $i++) {
			if ($serial.BytesToRead -gt 0) {
				$response += $serial.ReadExisting()
			}
			Start-Sleep -Milliseconds 100
		}
		
		$serial.Close()
		
		if ($response -match 'ESP32') {
			return @{ Type = 'ESP32'; Port = $targetPort }
		} elseif ($response -match 'GD32') {
			return @{ Type = 'GD32'; Port = $targetPort }
		} elseif ($response -match 'STM32') {
			return @{ Type = 'STM32'; Port = $targetPort }
		} elseif ($response -match 'STC') {
			return @{ Type = 'STC'; Port = $targetPort }
		} else {
			return @{ Type = 'Unknown'; Port = $targetPort }
		}
	} catch {
		return @{ Type = 'Unavailable'; Port = $targetPort }
	}
}

function Get-CurrentBoard {
	if (-not $env:CURRENT_BOARD) {
		Write-Host '[X] 未选择板子，请使用 switch-board 切换' -ForegroundColor Red
		return $null
	}
	$configPath = Join-Path $PSScriptRoot "board-config\$($env:CURRENT_BOARD).ps1"
	if (-not (Test-Path $configPath)) {
		Write-Host "[X] 未找到板子配置: $($env:CURRENT_BOARD)" -ForegroundColor Red
		return $null
	}
	& $configPath
}

if ($ListPorts) {
	Write-Host '可用串口:' -ForegroundColor Cyan
	$ports = Get-AvailablePorts
	foreach ($p in $ports) {
		$chip = Get-ChipFromPort $p
		$status = switch ($chip.Type) {
			'ESP32' { 'ESP32 芯片' }
			'GD32' { 'GD32 芯片' }
			'STM32' { 'STM32 芯片' }
			'STC' { 'STC 芯片' }
			'Unavailable' { '不可用' }
			default { '未知设备' }
		}
		Write-Host "  $p → $status" -ForegroundColor Yellow
	}
	return
}

$boardConfig = Get-CurrentBoard
if (-not $boardConfig) { exit }

$ports = Get-AvailablePorts

if (-not $ports) {
	Write-Host '[X] 未检测到任何串口' -ForegroundColor Red
	exit
}

if ($Port) {
	if (-not ($ports -contains $Port)) {
		Write-Host "[X] 串口 $Port 不存在" -ForegroundColor Red
		Write-Host "可用串口: $($ports -join ', ')" -ForegroundColor Yellow
		exit
	}
	$targetPort = $Port
} else {
	$targetPort = $boardConfig.DefaultUart
	if (-not ($ports -contains $targetPort)) {
		Write-Host "[!] 默认串口 $targetPort 不可用" -ForegroundColor Yellow
		
		if ($ports.Count -eq 1) {
			$targetPort = $ports[0]
			Write-Host "自动选择唯一可用串口: $targetPort" -ForegroundColor Green
		} else {
			Write-Host ''
			Write-Host '可用串口:' -ForegroundColor Cyan
			for ($i = 0; $i -lt $ports.Count; $i++) {
				$chip = Get-ChipFromPort $ports[$i]
				$status = switch ($chip.Type) {
					'ESP32' { 'ESP32 芯片' }
					'GD32' { 'GD32 芯片' }
					'STM32' { 'STM32 芯片' }
					'STC' { 'STC 芯片' }
					'Unavailable' { '不可用' }
					default { '未知设备' }
				}
				Write-Host "  $($i+1). $($ports[$i]) → $status" -ForegroundColor Yellow
			}
			$selection = Read-Host "请选择串口 (1-$($ports.Count))"
			$index = [int]$selection - 1
			if ($index -lt 0 -or $index -ge $ports.Count) {
				Write-Host '[X] 无效选择' -ForegroundColor Red
				exit
			}
			$targetPort = $ports[$index]
		}
	}
}

$connectedChip = Get-ChipFromPort $targetPort
$expectedType = $boardConfig.Type

$typeMatches = $false
if ($expectedType -match 'ESP32' -and $connectedChip.Type -eq 'ESP32') { $typeMatches = $true }
if ($expectedType -match 'GD32' -and $connectedChip.Type -eq 'GD32') { $typeMatches = $true }
if ($expectedType -match 'STM32' -and $connectedChip.Type -eq 'STM32') { $typeMatches = $true }
if ($expectedType -match 'STC8' -and $connectedChip.Type -eq 'STC') { $typeMatches = $true }

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  烧录前验证' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host "当前板子配置: $($boardConfig.Name)" -ForegroundColor Yellow
Write-Host "期望芯片类型: $expectedType" -ForegroundColor Yellow
Write-Host "目标串口: $targetPort" -ForegroundColor Yellow
Write-Host "连接芯片类型: $($connectedChip.Type)" -ForegroundColor Yellow
Write-Host ''

if (-not $typeMatches) {
	Write-Host '[!] 警告: 芯片类型不匹配！' -ForegroundColor Red
	Write-Host "  期望: $expectedType" -ForegroundColor Red
	Write-Host "  实际: $($connectedChip.Type)" -ForegroundColor Red
	Write-Host ''
	if (-not $Force) {
		$confirm = Read-Host '继续烧录？(Y/N)'
		if ($confirm -ne 'Y' -and $confirm -ne 'y') {
			Write-Host '已取消烧录' -ForegroundColor Gray
			exit
		}
	}
} else {
	Write-Host '[OK] 芯片类型匹配' -ForegroundColor Green
}

if (-not $Force) {
	Write-Host ''
	$confirm = Read-Host "确认烧录到 $targetPort？(Y/N)"
	if ($confirm -ne 'Y' -and $confirm -ne 'y') {
		Write-Host '已取消烧录' -ForegroundColor Gray
		exit
	}
}

Write-Host ''
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] 开始烧录到 $targetPort..." -ForegroundColor Green

switch -Wildcard ($expectedType) {
	'ESP32*' {
		if (-not $env:IDF_PATH) {
			. "$PSScriptRoot\esp-idf-env.ps1"
		}
		& python "$env:IDF_PATH\tools\idf.py" -p $targetPort flash
	}
	'GD32*' {
		Write-Host '[!] GD32 芯片请使用 Keil MDK 烧录' -ForegroundColor Yellow
		Write-Host '打开 Keil 工程 → Flash → Download' -ForegroundColor Gray
	}
	'STM32*' {
		Write-Host '[!] STM32 芯片请使用 Keil MDK 烧录' -ForegroundColor Yellow
		Write-Host '打开 Keil 工程 → Flash → Download' -ForegroundColor Gray
	}
	'STC8*' {
		Write-Host '[!] STC8 芯片请使用 STC-ISP 烧录' -ForegroundColor Yellow
		Write-Host '打开 STC-ISP → 选择串口 → 点击下载' -ForegroundColor Gray
	}
	default {
		Write-Host "[X] 未支持的芯片类型: $expectedType" -ForegroundColor Red
	}
}

if ($LASTEXITCODE -eq 0) {
	Write-Host "[$(Get-Date -Format 'HH:mm:ss')] 烧录成功！" -ForegroundColor Green
} else {
	Write-Host "[$(Get-Date -Format 'HH:mm:ss')] 烧录失败！" -ForegroundColor Red
}
