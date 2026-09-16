<#
.SYNOPSIS
	ESP32 一键烧录工具（自动扫描串口 + 烧录 + 监控）
.DESCRIPTION
	烧录前自动扫描所有 COM 口，识别真实连接的 ESP32 设备，避免依赖记忆。
	支持模式：
	  - auto（默认）：扫描 + 列出设备 + 询问操作
	  - flash：扫描 + 直接烧录（需 -Firmware 指定 bin 路径或 -ProjectDir 指定项目目录）
	  - monitor：仅扫描 + 打开监控
	  - build-flash-monitor：项目目录模式下，编译+烧录+监控一条龙
	烧录失败时自动重试（最多3次），并根据错误信息给出排查建议。
.EXAMPLE
	esp-burn                                   # 自动扫描并列出可用 ESP32
	esp-burn -Mode build-flash-monitor -ProjectDir D:\path\to\project
	esp-burn -Mode flash -Port COM8 -Firmware D:\build\firmware.bin
	esp-burn -Mode monitor -Port COM8
  version: 1.0.0
#>

param(
	[ValidateSet('auto', 'flash', 'monitor', 'build-flash-monitor')]
	[string]$Mode = 'auto',

	[string]$Port = '',                  # 指定串口（不指定则自动选择）
	[string]$Firmware = '',              # 直接烧录的 bin 文件路径
	[string]$ProjectDir = '',            # idf.py 项目目录
	[int]$Baud = 921600,                 # 烧录波特率
	[int]$MonitorBaud = 115200,          # 监控波特率
	[int]$MaxRetries = 3                 # 最大重试次数
)

# ============================================================
# 自动检测 ESP-IDF 环境
# ============================================================
function Initialize-EspIdfEnv {
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
# 扫描所有 COM 口，返回 ESP32 设备列表
# ============================================================
function Find-Esp32Devices {
	Write-Host ''
	Write-Host '[1/3] 扫描 COM 口中的 ESP32 设备...' -ForegroundColor Cyan

	$ports = @()
	try {
		$ports = [System.IO.Ports.SerialPort]::getportnames()
	}
	catch {
		Write-Host "  串口枚举失败: $($_.Exception.Message)" -ForegroundColor Red
		return @()
	}

	if ($ports.Count -eq 0) {
		Write-Host '  未检测到任何 COM 口' -ForegroundColor Yellow
		return @()
	}

	Write-Host "  发现 $($ports.Count) 个 COM 口: $($ports -join ', ')" -ForegroundColor Gray
	Write-Host ''

	$devices = New-Object System.Collections.ArrayList
	$idx = 0
	foreach ($p in $ports) {
		$idx++
		Write-Host "  [$idx/$($ports.Count)] 探测 $p ..." -ForegroundColor Gray -NoNewline

		$argList = @($env:IDF_PATH + '\components\esptool_py\esptool\esptool.py', '--port', $p, '--chip', 'auto', '--baud', '115200', 'flash_id')
		$proc = Start-Process -FilePath 'python' -ArgumentList $argList `
			-NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\esp_probe_$p.out" `
			-RedirectStandardError "$env:TEMP\esp_probe_$p.err"

		if (-not $proc.WaitForExit(8000)) {
			try { $proc.Kill() } catch {}
			Write-Host ' 超时' -ForegroundColor Yellow
			continue
		}

		$stdout = Get-Content "$env:TEMP\esp_probe_$p.out" -Raw -ErrorAction SilentlyContinue
		$stderr = Get-Content "$env:TEMP\esp_probe_$p.err" -Raw -ErrorAction SilentlyContinue
		$combined = "$stdout $stderr"

		$chipType = ''
		if ($combined -match 'Chip is (ESP32-\S+)') {
			$chipType = $matches[1]
		}

		if ($chipType) {
			$flashSize = ''
			$macAddr = ''
			if ($combined -match 'Detected flash size:\s*(\S+)') { $flashSize = $matches[1] }
			if ($combined -match 'MAC:\s*([\da-fA-F:]+)') { $macAddr = $matches[1] }

			$device = @{
				Port      = $p
				ChipType  = $chipType
				FlashSize = $flashSize
				MacAddr   = $macAddr
			}
			[void]$devices.Add($device)

			Write-Host " [OK] $chipType" -ForegroundColor Green
			Write-Host "        Flash: $flashSize  MAC: $macAddr" -ForegroundColor Gray
		}
		else {
			Write-Host ' 不是 ESP32' -ForegroundColor Gray
		}

		Remove-Item "$env:TEMP\esp_probe_$p.out", "$env:TEMP\esp_probe_$p.err" -ErrorAction SilentlyContinue
	}

	$cleanDevices = @($devices | Where-Object { $_ -and $_.Port -and $_.Port -ne '' })
	return $cleanDevices
}

# ============================================================
# 列出设备并让用户选择
# ============================================================
function Select-Device {
	param([array]$Devices)
	$Devices = @($Devices)

	if ($Devices.Count -eq 0) {
		Write-Host ''
		Write-Host '[X] 未检测到任何 ESP32 设备' -ForegroundColor Red
		Write-Host '  请检查:' -ForegroundColor Yellow
		Write-Host '    1. USB 线是否插好（注意数据线 vs 充电线）'
		Write-Host '    2. 设备管理器中是否识别到 COM 口'
		Write-Host '    3. 是否有其他程序占用 COM 口'
		return $null
	}

	if ($Host.Name -match 'NonInteractive' -or [Console]::IsInputRedirected) {
		Write-Host "[!] NonInteractive 模式，自动选择第 1 个: $($Devices[0].Port)" -ForegroundColor Yellow
		return $Devices[0]
	}

	if ($Devices.Count -eq 1) {
		Write-Host ''
		Write-Host "[OK] 仅检测到 1 个 ESP32 设备: $($Devices[0].Port) ($($Devices[0].ChipType))" -ForegroundColor Green
		return $Devices[0]
	}

	Write-Host ''
	Write-Host '检测到多个 ESP32 设备，请选择:' -ForegroundColor Yellow
	for ($i = 0; $i -lt $Devices.Count; $i++) {
		$d = $Devices[$i]
		Write-Host "  [$($i+1)] $($d.Port) - $($d.ChipType) (Flash: $($d.FlashSize), MAC: $($d.MacAddr))"
	}

	$choice = Read-Host "输入序号 (1-$($Devices.Count))"
	$idx = 0
	if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $Devices.Count) {
		return $Devices[$idx - 1]
	}

	Write-Host '[X] 无效选择' -ForegroundColor Red
	return $null
}

# ============================================================
# 烧录错误诊断
# ============================================================
function Invoke-FlashErrorDiagnosis {
	param(
		[string]$ErrorOutput,
		[string]$Port
	)

	Write-Host ''
	Write-Host '[!] 烧录错误诊断:' -ForegroundColor Yellow

	if ($ErrorOutput -match 'Failed to connect') {
		Write-Host '  原因: 无法连接到 ESP32' -ForegroundColor Red
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 按住 BOOT 键后再按复位键，进入下载模式'
		Write-Host '    2. 检查 USB 线是否为数据线（非充电线）'
		Write-Host '    3. 降低波特率: -Baud 115200'
		return $true
	}

	if ($ErrorOutput -match 'Invalid head of packet') {
		Write-Host '  原因: 数据包头部无效' -ForegroundColor Red
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 按住 BOOT 键后再按复位键，进入下载模式'
		Write-Host '    2. 降低波特率: -Baud 115200'
		Write-Host '    3. 检查串口是否被其他程序占用'
		return $true
	}

	if ($ErrorOutput -match 'Permission denied') {
		Write-Host '  原因: 权限不足或串口被占用' -ForegroundColor Red
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 关闭串口助手、监控等占用串口的程序'
		Write-Host '    2. 以管理员身份运行 PowerShell'
		return $true
	}

	if ($ErrorOutput -match 'Serial port.*not found') {
		Write-Host '  原因: 指定的串口号不存在' -ForegroundColor Red
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 在设备管理器中确认正确的串口号'
		Write-Host '    2. 重新插拔 USB 线后重试'
		return $true
	}

	if ($ErrorOutput -match 'Timed out waiting for packet header') {
		Write-Host '  原因: 等待数据包超时' -ForegroundColor Red
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 按住 BOOT 键后再按复位键，进入下载模式'
		Write-Host '    2. 降低波特率: -Baud 115200'
		Write-Host '    3. 检查 USB 线接触是否良好'
		return $true
	}

	Write-Host '  未知错误，请查看完整错误输出' -ForegroundColor Yellow
	return $false
}

# ============================================================
# 安全提醒：建议使用 build-all -Flash 或 safe-flash 进行烧录
# 这些工具会在烧录前验证芯片类型，防止烧录错误
# idf.py build + flash + monitor（带重试）
# ============================================================
function Invoke-IdfBuildFlashMonitor {
	param(
		[string]$TargetPort,
		[string]$TargetProjectDir,
		[bool]$DoBuild,
		[bool]$DoFlash,
		[bool]$DoMonitor
	)

	if (-not (Test-Path $TargetProjectDir)) {
		Write-Host "[X] 项目目录不存在: $TargetProjectDir" -ForegroundColor Red
		return
	}

	if (-not (Initialize-EspIdfEnv)) {
		return
	}

	Push-Location $TargetProjectDir
	try {
		if ($DoBuild) {
			Write-Host ''
			Write-Host '>>> idf.py build' -ForegroundColor Cyan
			& python "$env:IDF_PATH\tools\idf.py" build
			if ($LASTEXITCODE -ne 0) {
				Write-Host '[X] 编译失败' -ForegroundColor Red
				return
			}
		}

		if ($DoFlash) {
			$retryCount = 0
			$flashSuccess = $false

			while (-not $flashSuccess -and $retryCount -lt $MaxRetries) {
				$retryCount++
				Write-Host ''
				if ($retryCount -gt 1) {
# 安全提醒：建议使用 build-all -Flash 或 safe-flash 进行烧录
# 这些工具会在烧录前验证芯片类型，防止烧录错误
					Write-Host ">>> idf.py -p $TargetPort -b $Baud flash (重试 $retryCount/$MaxRetries)" -ForegroundColor Yellow
				}
				else {
# 安全提醒：建议使用 build-all -Flash 或 safe-flash 进行烧录
# 这些工具会在烧录前验证芯片类型，防止烧录错误
					Write-Host ">>> idf.py -p $TargetPort -b $Baud flash" -ForegroundColor Cyan
				}

# 安全提醒：建议使用 build-all -Flash 或 safe-flash 进行烧录
# 这些工具会在烧录前验证芯片类型，防止烧录错误
				& python "$env:IDF_PATH\tools\idf.py" -p $TargetPort -b $Baud flash 2>&1 | Tee-Object -Variable flashOutput

				if ($LASTEXITCODE -eq 0) {
					$flashSuccess = $true
				}
				else {
					if ($retryCount -lt $MaxRetries) {
						Invoke-FlashErrorDiagnosis -ErrorOutput $flashOutput -Port $TargetPort
						Write-Host "  等待 3 秒后重试..." -ForegroundColor Yellow
						Start-Sleep -Seconds 3
					}
					else {
						Write-Host '[X] 烧录失败（已达最大重试次数）' -ForegroundColor Red
						Invoke-FlashErrorDiagnosis -ErrorOutput $flashOutput -Port $TargetPort
						return
					}
				}
			}
		}

		if ($DoMonitor) {
			Write-Host ''
			Write-Host ">>> idf.py -p $TargetPort monitor" -ForegroundColor Cyan
			Write-Host '    退出监控: Ctrl+]' -ForegroundColor Gray
			& python "$env:IDF_PATH\tools\idf.py" -p $TargetPort monitor
		}
	}
	finally {
		Pop-Location
	}
}

# ============================================================
# 直接 esptool 写 bin（带重试）
# ============================================================
function Invoke-EsptoolFlash {
	param(
		[string]$TargetPort,
		[string]$BinPath
	)

	if (-not (Test-Path $BinPath)) {
		Write-Host "[X] 固件不存在: $BinPath" -ForegroundColor Red
		return
	}

	if (-not (Initialize-EspIdfEnv)) {
		return
	}

	$retryCount = 0
	$flashSuccess = $false

	while (-not $flashSuccess -and $retryCount -lt $MaxRetries) {
		$retryCount++
		Write-Host ''
		if ($retryCount -gt 1) {
			Write-Host ">>> esptool --port $TargetPort write_flash 0x0 $BinPath (重试 $retryCount/$MaxRetries)" -ForegroundColor Yellow
		}
		else {
			Write-Host ">>> esptool --port $TargetPort write_flash 0x0 $BinPath" -ForegroundColor Cyan
		}

		& python "$env:IDF_PATH\components\esptool_py\esptool\esptool.py" --port $TargetPort --baud $Baud write_flash 0x0 $BinPath 2>&1 | Tee-Object -Variable flashOutput

		if ($LASTEXITCODE -eq 0) {
			$flashSuccess = $true
		}
		else {
			if ($retryCount -lt $MaxRetries) {
				Invoke-FlashErrorDiagnosis -ErrorOutput $flashOutput -Port $TargetPort
				Write-Host "  等待 3 秒后重试..." -ForegroundColor Yellow
				Start-Sleep -Seconds 3
			}
			else {
				Write-Host '[X] 烧录失败（已达最大重试次数）' -ForegroundColor Red
				Invoke-FlashErrorDiagnosis -ErrorOutput $flashOutput -Port $TargetPort
				return
			}
		}
	}
}

# ============================================================
# 仅打开监控
# ============================================================
function Invoke-IdfMonitor {
	param([string]$TargetPort)

	if (-not (Initialize-EspIdfEnv)) {
		return
	}

	Write-Host ''
	Write-Host ">>> idf.py -p $TargetPort monitor" -ForegroundColor Cyan
	Write-Host '    退出监控: Ctrl+]' -ForegroundColor Gray
	& python "$env:IDF_PATH\tools\idf.py" -p $TargetPort monitor
}

# ============================================================
# 主流程
# ============================================================
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  ESP32 一键烧录工具 v1.3' -ForegroundColor Cyan
Write-Host '  烧录前自动扫描串口，支持重试和错误诊断' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

if (-not (Initialize-EspIdfEnv)) {
	Write-Host '[X] 无法初始化 ESP-IDF 环境，退出' -ForegroundColor Red
	exit 1
}

$selected = $null

if ($Port) {
	Write-Host "[1/3] 使用指定串口: $Port" -ForegroundColor Cyan
	$selected = @{ Port = $Port; ChipType = 'ESP32 (用户指定)'; FlashSize = ''; MacAddr = '' }
}
else {
	$devices = Find-Esp32Devices
	$selected = Select-Device -Devices $devices
}

if (-not $selected) {
	exit 1
}

Write-Host ''
Write-Host "[2/3] 选定设备: $($selected.Port) ($($selected.ChipType))" -ForegroundColor Green

Write-Host ''
Write-Host '[3/3] 选择操作:' -ForegroundColor Cyan

$targetPort = $selected.Port

switch ($Mode) {
	'auto' {
		if ($ProjectDir) {
			Write-Host '  检测到 -ProjectDir，进入项目模式' -ForegroundColor Gray
			Invoke-IdfBuildFlashMonitor -TargetPort $targetPort -TargetProjectDir $ProjectDir `
				-DoBuild $true -DoFlash $true -DoMonitor $true
		}
		elseif ($Firmware) {
			Write-Host '  检测到 -Firmware，进入 bin 烧录模式' -ForegroundColor Gray
			Invoke-EsptoolFlash -TargetPort $targetPort -BinPath $Firmware
		}
		else {
			Write-Host '  [1] 编译 + 烧录 + 监控（需要 -ProjectDir）'
			Write-Host '  [2] 仅烧录 bin（需要 -Firmware）'
			Write-Host '  [3] 仅监控'
			Write-Host '  [4] 退出'
			$op = Read-Host '选择 (1-4)'
			switch ($op) {
				'1' {
					if (-not $ProjectDir) {
						$ProjectDir = Read-Host '输入项目目录（含 CMakeLists.txt 的目录）'
					}
					Invoke-IdfBuildFlashMonitor -TargetPort $targetPort -TargetProjectDir $ProjectDir `
						-DoBuild $true -DoFlash $true -DoMonitor $true
				}
				'2' {
					if (-not $Firmware) {
						$Firmware = Read-Host '输入 bin 文件完整路径'
					}
					Invoke-EsptoolFlash -TargetPort $targetPort -BinPath $Firmware
				}
				'3' { Invoke-IdfMonitor -TargetPort $targetPort }
				default { Write-Host '已退出' }
			}
		}
	}
	'flash' {
		if ($Firmware) {
			Invoke-EsptoolFlash -TargetPort $targetPort -BinPath $Firmware
		}
		elseif ($ProjectDir) {
			Invoke-IdfBuildFlashMonitor -TargetPort $targetPort -TargetProjectDir $ProjectDir `
				-DoBuild $false -DoFlash $true -DoMonitor $false
		}
		else {
			Write-Host '[X] flash 模式需要 -Firmware 或 -ProjectDir' -ForegroundColor Red
		}
	}
	'monitor' {
		Invoke-IdfMonitor -TargetPort $targetPort
	}
	'build-flash-monitor' {
		if (-not $ProjectDir) {
			Write-Host '[X] build-flash-monitor 模式需要 -ProjectDir' -ForegroundColor Red
			exit 1
		}
		Invoke-IdfBuildFlashMonitor -TargetPort $targetPort -TargetProjectDir $ProjectDir `
			-DoBuild $true -DoFlash $true -DoMonitor $true
	}
}

Write-Host ''
Write-Host '[OK] 完成' -ForegroundColor Green
