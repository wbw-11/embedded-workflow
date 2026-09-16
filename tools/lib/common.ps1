<#
.SYNOPSIS
	公共模块库 - 所有脚本共享的函数
.DESCRIPTION
	包含串口扫描、板子配置、环境初始化等公共功能
#>

function Get-CurrentBoard {
	if (-not $env:CURRENT_BOARD) {
		return $null
	}
	$configPath = Join-Path $PSScriptRoot "..\board-config\$($env:CURRENT_BOARD).ps1"
	if (-not (Test-Path $configPath)) {
		return $null
	}
	& $configPath
}

function Get-AvailablePorts {
	[System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
}

function Get-PortInfo {
	param([string]$Port)
	
	try {
		$pnpDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
			Where-Object { $_.Caption -match "\(COM\d+\)" }
		
		foreach ($dev in $pnpDevices) {
			if ($dev.Caption -match "\(COM(\d+)\)") {
				$portName = "COM$($matches[1])"
				if ($portName -eq $Port) {
					$chipType = 'Unknown'
					if ($dev.Caption -match 'CH340|CH341') { $chipType = 'CH340/CH341' }
					elseif ($dev.Caption -match 'CP210') { $chipType = 'CP210x' }
					elseif ($dev.Caption -match 'FT232|FT2232') { $chipType = 'FTDI' }
					elseif ($dev.Caption -match 'PL2303') { $chipType = 'PL2303' }
					elseif ($dev.Caption -match 'J-Link') { $chipType = 'J-Link' }
					elseif ($dev.Caption -match 'ST-Link') { $chipType = 'ST-Link' }
					elseif ($dev.Caption -match 'USB Serial') { $chipType = 'USB Serial' }
					return @{ Port = $portName; ChipType = $chipType; Caption = $dev.Caption }
				}
			}
		}
	} catch {}
	return @{ Port = $Port; ChipType = 'Unknown'; Caption = '' }
}

function Find-EspIdfEnv {
	if ($env:IDF_PATH) {
		return $true
	}
	try {
		. "$PSScriptRoot\..\esp-idf-env.ps1"
		if ($env:IDF_PATH) {
			return $true
		}
	} catch {}
	return $false
}

function Invoke-SafeConfirm {
	param(
		[string]$Message,
		[string]$Warning = '',
		[switch]$Force
	)
	
	if ($Force) { return $true }
	
	if ($Warning) {
		Write-Host $Warning -ForegroundColor Red
	}
	Write-Host "$Message (Y/N)" -ForegroundColor Yellow
	$confirm = Read-Host
	return ($confirm -match '^[Yy]')
}

function Write-Status {
	param(
		[string]$Message,
		[string]$Type = 'Info'
	)
	
	switch ($Type) {
		'Error' { Write-Host "[X] $Message" -ForegroundColor Red }
		'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
		'Success' { Write-Host "[OK] $Message" -ForegroundColor Green }
		'Info' { Write-Host "[*] $Message" -ForegroundColor Cyan }
		default { Write-Host "$Message" }
	}
}

function Select-SerialPort {
	param(
		[string]$DefaultPort,
		[string]$TargetPort
	)
	
	$ports = Get-AvailablePorts
	if (-not $ports) {
		Write-Status '未检测到任何串口' -Type Error
		return $null
	}
	
	if ($TargetPort) {
		if ($ports -contains $TargetPort) {
			return $TargetPort
		}
		Write-Status "串口 $TargetPort 不存在" -Type Error
		Write-Status "可用串口: $($ports -join ', ')" -Type Warning
		return $null
	}
	
	if ($DefaultPort -and $ports -contains $DefaultPort) {
		return $DefaultPort
	}
	
	if ($ports.Count -eq 1) {
		return $ports[0]
	}
	
	Write-Status '检测到多个串口，请选择:' -Type Warning
	for ($i = 0; $i -lt $ports.Count; $i++) {
		$info = Get-PortInfo $ports[$i]
		Write-Host "  $($i+1). $($info.Port) - $($info.ChipType)" -ForegroundColor White
	}
	
	$choice = Read-Host "输入序号 (1-$($ports.Count))"
	$idx = 0
	if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $ports.Count) {
		return $ports[$idx - 1]
	}
	
	Write-Status '无效选择' -Type Error
	return $null
}

# 查找 Keil UV4 可执行文件路径（动态检测）
function Find-KeilUv4 {
	# 1. 优先使用环境变量
	if ($env:KEIL_UV4_PATH -and (Test-Path $env:KEIL_UV4_PATH)) {
		return $env:KEIL_UV4_PATH
	}
	if ($env:KEIL_ROOT) {
		$candidate = Join-Path $env:KEIL_ROOT "UV4\UV4.exe"
		if (Test-Path $candidate) { return $candidate }
	}
	# 2. 注册表查找
	try {
		$reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Keil\Products\MDK" -ErrorAction Stop
		if ($reg.Path) {
			$candidate = Join-Path $reg.Path "UV4\UV4.exe"
			if (Test-Path $candidate) { return $candidate }
		}
	} catch {}
	# 3. 常见候选路径
	$candidates = @(
		"C:\Keil_v5\UV4\UV4.exe",
		"D:\Keil_v5\UV4\UV4.exe",
		"E:\Keil_v5\UV4\UV4.exe"
	) | Where-Object { Test-Path $_ }
	if ($candidates) { return $candidates | Select-Object -First 1 }
	# 4. 未找到
	return $null
}

# 查找 Keil ARMCC 编译器路径（动态检测）
function Find-KeilArmcc {
	$uv4 = Find-KeilUv4
	if ($uv4) {
		$keilRoot = Split-Path (Split-Path $uv4)
		$armcc = Join-Path $keilRoot "ARM\ARMCC\bin\armcc.exe"
		if (Test-Path $armcc) { return $armcc }
	}
	if ($env:KEIL_ROOT) {
		$armcc = Join-Path $env:KEIL_ROOT "ARM\ARMCC\bin\armcc.exe"
		if (Test-Path $armcc) { return $armcc }
	}
	return $null
}

# 查找 Keil C51 编译器路径（动态检测）
function Find-KeilC51 {
	$uv4 = Find-KeilUv4
	if ($uv4) {
		$keilRoot = Split-Path (Split-Path $uv4)
		$c51 = Join-Path $keilRoot "C51\BIN\C51.exe"
		if (Test-Path $c51) { return $c51 }
	}
	if ($env:KEIL_ROOT) {
		$c51 = Join-Path $env:KEIL_ROOT "C51\BIN\C51.exe"
		if (Test-Path $c51) { return $c51 }
	}
	return $null
}
# 仅在作为模块导入时导出（dot-source 场景跳过，避免报错）
if ($null -ne $ExecutionContext.SessionState.Module) {
	Export-ModuleMember -Function Get-CurrentBoard, Get-AvailablePorts, Get-PortInfo, Find-EspIdfEnv, Find-KeilUv4, Find-KeilArmcc, Find-KeilC51, Invoke-SafeConfirm, Write-Status, Select-SerialPort
}
