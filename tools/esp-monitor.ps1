<#
.SYNOPSIS
	ESP32 串口监控工具（自动扫描串口 + 启动 IDF 监视器）
.DESCRIPTION
	自动扫描所有 COM 口，识别 CH340/CP2102 等常见 USB 转串口芯片（优先推荐）。
	调用 idf.py monitor 启动 IDF 监视器（推荐方式，支持菜单快捷键）。
	支持错误诊断：串口被占用、串口不存在、IDF 环境未初始化等。
.EXAMPLE
	esp-monitor                                    # 自动扫描串口并让用户选择
	esp-monitor -Port COM8                         # 指定串口启动监视器
	esp-monitor -Port COM8 -Baud 921600            # 指定串口和波特率
	esp-monitor -ProjectDir D:\path\to\project     # 指定项目目录
	esp-monitor -Port COM8 -ProjectDir D:\proj     # 同时指定串口和项目目录
  version: 1.0.0
#>

param(
	[string]$Port = '',                  # 指定串口（不指定则自动选择）
	[int]$Baud = 115200,                 # 监控波特率（默认 115200）
	[string]$ProjectDir = ''             # idf.py 项目目录（默认当前目录）
)

# ============================================================
# 查找 ESP-IDF 环境
# ============================================================
function Find-EspIdfEnv {
	if ($env:IDF_PATH) {
		return $true
	}

	Write-Host '[!] IDF_PATH 未设置，正在加载 esp-idf-env.ps1...' -ForegroundColor Yellow
	try {
		. "$PSScriptRoot\esp-idf-env.ps1"
		if ($env:IDF_PATH) {
			Write-Host '  [OK] ESP-IDF 环境加载成功' -ForegroundColor Green
			return $true
		}
	}
	catch {
		Write-Host "  [X] 环境加载失败: $($_.Exception.Message)" -ForegroundColor Red
	}

	return $false
}

# ============================================================
# 枚举 COM 口，附带芯片信息（优先 CH340/CP2102）
# ============================================================
function Get-ComPorts {
	Write-Host ''
	Write-Host '[1/3] 扫描可用串口...' -ForegroundColor Cyan

	# 通过 Win32_PnPEntity 获取 COM 口及其芯片信息
	$pnpDevices = @()
	try {
		$pnpDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
			Where-Object { $_.Caption -match '\(COM\d+\)' }
	}
	catch {
		Write-Host "  串口枚举失败: $($_.Exception.Message)" -ForegroundColor Red
		return @()
	}

	if ($pnpDevices.Count -eq 0) {
		Write-Host '  未检测到任何 COM 口' -ForegroundColor Yellow
		return @()
	}

	# 解析每个 COM 口的信息
	$ports = New-Object System.Collections.ArrayList
	foreach ($dev in $pnpDevices) {
		$caption = $dev.Caption
		if ($caption -match '\(COM(\d+)\)') {
			$portName = "COM$($matches[1])"
			$chipType = 'Unknown'

			# 识别常见 USB 转串口芯片
			if ($caption -match 'CH340|CH341') { $chipType = 'CH340/CH341' }
			elseif ($caption -match 'CP210') { $chipType = 'CP210x' }
			elseif ($caption -match 'FT232|FT2232|FT4232') { $chipType = 'FTDI' }
			elseif ($caption -match 'PL2303') { $chipType = 'PL2303' }
			elseif ($caption -match 'J-Link') { $chipType = 'J-Link' }
			elseif ($caption -match 'ST-Link') { $chipType = 'ST-Link' }
			elseif ($caption -match 'USB Serial') { $chipType = 'USB Serial' }

			$port = @{
				Port     = $portName
				ChipType = $chipType
				Caption  = $caption
			}
			[void]$ports.Add($port)
		}
	}

	# 按芯片优先级排序：CH340/CH341 > CP210x > FTDI > 其他
	$priority = @{
		'CH340/CH341' = 1
		'CP210x'      = 2
		'FTDI'        = 3
		'PL2303'      = 4
		'USB Serial'  = 5
		'J-Link'      = 6
		'ST-Link'     = 7
		'Unknown'     = 99
	}

	$sortedPorts = @($ports | Sort-Object { $priority[$_.ChipType] })

	Write-Host "  发现 $($sortedPorts.Count) 个 COM 口:" -ForegroundColor Gray
	foreach ($p in $sortedPorts) {
		$mark = ''
		if ($p.ChipType -match 'CH340|CP210') {
			$mark = ' [推荐]'
		}
		Write-Host "    $($p.Port) - $($p.ChipType)$mark" -ForegroundColor Gray
	}

	return $sortedPorts
}

# ============================================================
# 选择串口
# ============================================================
function Select-Port {
	param([array]$Ports)
	$Ports = @($Ports)

	if ($Ports.Count -eq 0) {
		Write-Host ''
		Write-Host '[X] 未检测到任何可用串口' -ForegroundColor Red
		Write-Host '  请检查:' -ForegroundColor Yellow
		Write-Host '    1. USB 线是否插好（注意数据线 vs 充电线）'
		Write-Host '    2. 设备管理器中是否识别到 COM 口'
		Write-Host '    3. 是否需要安装 CH340/CP2102 驱动'
		return $null
	}

	if ($Host.Name -match 'NonInteractive' -or [Console]::IsInputRedirected) {
		Write-Host "[!] NonInteractive 模式，自动选择第 1 个: $($Ports[0].Port)" -ForegroundColor Yellow
		return $Ports[0]
	}

	if ($Ports.Count -eq 1) {
		Write-Host ''
		Write-Host "[OK] 仅检测到 1 个串口: $($Ports[0].Port) ($($Ports[0].ChipType))" -ForegroundColor Green
		return $Ports[0]
	}

	Write-Host ''
	Write-Host '检测到多个串口，请选择:' -ForegroundColor Yellow
	for ($i = 0; $i -lt $Ports.Count; $i++) {
		$p = $Ports[$i]
		$mark = ''
		if ($p.ChipType -match 'CH340|CP210') {
			$mark = ' [推荐]'
		}
		Write-Host "  [$($i+1)] $($p.Port) - $($p.ChipType)$mark" -ForegroundColor White
		Write-Host "      $($p.Caption)" -ForegroundColor Gray
	}

	$choice = Read-Host "输入序号 (1-$($Ports.Count))"
	$idx = 0
	if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $Ports.Count) {
		return $Ports[$idx - 1]
	}

	Write-Host '[X] 无效选择' -ForegroundColor Red
	return $null
}

# ============================================================
# 显示 IDF 监视器快捷键
# ============================================================
function Show-MonitorShortcuts {
	Write-Host ''
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host '  IDF 监视器快捷键' -ForegroundColor Cyan
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host '  Ctrl + ]             退出监视器' -ForegroundColor White
	Write-Host '  Ctrl + T             显示菜单' -ForegroundColor White
	Write-Host '  Ctrl + T  Ctrl + H   显示帮助' -ForegroundColor White
	Write-Host '  Ctrl + T  Ctrl + R   复位芯片' -ForegroundColor White
	Write-Host '  Ctrl + T  Ctrl + F   编译并烧录' -ForegroundColor White
	Write-Host '  Ctrl + T  Ctrl + S   暂停输出' -ForegroundColor White
	Write-Host '  Ctrl + T  Ctrl + U   上传文件' -ForegroundColor White
	Write-Host '========================================' -ForegroundColor Cyan
}

# ============================================================
# 启动 IDF 监视器
# ============================================================
function Invoke-EspMonitor {
	param(
		[string]$TargetPort,
		[int]$TargetBaud,
		[string]$TargetProjectDir
	)

	# 验证串口是否存在
	$allPorts = @()
	try {
		$allPorts = [System.IO.Ports.SerialPort]::GetPortNames()
	}
	catch {
		Write-Host "[X] 无法枚举串口: $($_.Exception.Message)" -ForegroundColor Red
		return $false
	}

	if ($allPorts -notcontains $TargetPort) {
		Write-Host ''
		Write-Host "[X] 串口 $TargetPort 不存在" -ForegroundColor Red
		Write-Host '  可用串口:' -ForegroundColor Yellow
		if ($allPorts.Count -gt 0) {
			foreach ($p in $allPorts) {
				Write-Host "    $p" -ForegroundColor Gray
			}
		}
		else {
			Write-Host '    (无)' -ForegroundColor Gray
		}
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 检查 USB 线是否插好'
		Write-Host '    2. 在设备管理器中确认串口号'
		Write-Host '    3. 重新插拔 USB 线后重试'
		return $false
	}

	# 检查串口是否被占用
	Write-Host ''
	Write-Host "[2/3] 检查串口 $TargetPort 是否可用..." -ForegroundColor Cyan
	$testPort = $null
	try {
		$testPort = New-Object System.IO.Ports.SerialPort($TargetPort, $TargetBaud)
		$testPort.ReadTimeout = 500
		$testPort.WriteTimeout = 500
		$testPort.Open()
		Write-Host "  [OK] 串口 $TargetPort 可用" -ForegroundColor Green
	}
	catch {
		$errMsg = $_.Exception.Message
		Write-Host "[X] 串口 $TargetPort 被占用或无法打开" -ForegroundColor Red
		Write-Host "  错误: $errMsg" -ForegroundColor Yellow
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 关闭其他串口工具（串口助手、PuTTY、其他监视器等）'
		Write-Host '    2. 等待几秒后重试（串口释放可能需要时间）'
		Write-Host '    3. 拔插 USB 线重新枚举设备'
		return $false
	}
	finally {
		if ($testPort -and $testPort.IsOpen) {
			$testPort.Close()
			$testPort.Dispose()
		}
	}

	# 显示快捷键说明
	Show-MonitorShortcuts

	# 确定工作目录
	$workDir = if ($TargetProjectDir) { $TargetProjectDir } else { (Get-Location).Path }

	if (-not (Test-Path $workDir)) {
		Write-Host "[X] 项目目录不存在: $workDir" -ForegroundColor Red
		return $false
	}

	# 启动 idf.py monitor
	Write-Host ''
	Write-Host "[3/3] 启动 IDF 监视器..." -ForegroundColor Cyan
	Write-Host "  串口:     $TargetPort" -ForegroundColor Gray
	Write-Host "  波特率:   $TargetBaud" -ForegroundColor Gray
	Write-Host "  工作目录: $workDir" -ForegroundColor Gray
	Write-Host ''

	Push-Location $workDir
	try {
		& python "$env:IDF_PATH\tools\idf.py" -p $TargetPort --baud $TargetBaud monitor
	}
	finally {
		Pop-Location
	}

	return $true
}

# ============================================================
# 主流程
# ============================================================
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  ESP32 串口监控工具 v1.0' -ForegroundColor Cyan
Write-Host '  自动扫描串口 + 启动 IDF 监视器' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

# 1. 初始化 ESP-IDF 环境
if (-not (Find-EspIdfEnv)) {
	Write-Host ''
	Write-Host '[X] 无法初始化 ESP-IDF 环境，退出' -ForegroundColor Red
	Write-Host '  排查:' -ForegroundColor Yellow
	Write-Host '    1. 确认 ESP-IDF 已正确安装'
	Write-Host '    2. 确认 esp-idf-env.ps1 位于同目录'
	Write-Host '    3. 手动执行: . $env:USERPROFILE\Tools\esp-idf-env.ps1'
	exit 1
}

# 2. 确定串口
$selected = $null
if ($Port) {
	Write-Host ''
	Write-Host "[1/3] 使用指定串口: $Port" -ForegroundColor Cyan
	$selected = @{ Port = $Port; ChipType = '(用户指定)'; Caption = '' }
}
else {
	$ports = Get-ComPorts
	$selected = Select-Port -Ports $ports
}

if (-not $selected) {
	exit 1
}

Write-Host ''
Write-Host "[OK] 选定串口: $($selected.Port) ($($selected.ChipType))" -ForegroundColor Green

# 3. 启动监视器
$ok = Invoke-EspMonitor -TargetPort $selected.Port -TargetBaud $Baud -TargetProjectDir $ProjectDir

if ($ok) {
	Write-Host ''
	Write-Host '[OK] 监视器已退出' -ForegroundColor Green
}
