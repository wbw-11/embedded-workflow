<#
.SYNOPSIS
	嵌入式芯片型号自动检测脚本
.DESCRIPTION
	通过 USB VID/PID 枚举 + 串口/调试器自动探测，组合判断当前连接的芯片型号。
	支持平台：ESP32 全系列 / STC8 / GD32 / STM32
	自动检测 ESP-IDF 工具链路径，无需硬编码。
.EXAMPLE
	detect-chip              # 自动扫描所有端口
	detect-chip -Port COM8   # 指定串口检测
  version: 1.4.0
#>

param(
	[string]$Port = ''
)

# ============================================================
# 工具函数：自动检测 ESP-IDF 工具链路径
# ============================================================

function Find-EspIdfTools {
	<#
	自动检测 ESP-IDF 安装路径和 Python 虚拟环境
	消除硬编码路径，支持多版本 ESP-IDF 安装
	返回哈希表包含: Python, Esptool, Espefuse, Stcgal, Pyocd
	#>
	$result = @{
		Python   = ''
		Esptool  = ''
		Espefuse = ''
		Stcgal   = ''
		Pyocd    = ''
	}

	# 常见 ESP-IDF 安装根目录（按优先级排序）
	$searchRoots = @(
		'D:\ESP32\Espressif',
		'C:\Espressif',
		'C:\esp',
		'D:\Espressif',
		"$env:USERPROFILE\esp",
		"$env:USERPROFILE\Espressif"
	)

	$espRoot = $null
	foreach ($root in $searchRoots) {
		if (Test-Path $root) {
			$espRoot = $root
			break
		}
	}

	if (-not $espRoot) {
		Write-Host '  [!] 未找到 ESP-IDF 安装目录，使用系统 Python' -ForegroundColor Yellow
		$result.Python = 'python'
		$result.Pyocd = 'pyocd'
		return $result
	}

	Write-Host "  ESP-IDF 根目录: $espRoot" -ForegroundColor Gray

	# 查找 Python 虚拟环境
	$pythonExe = Get-ChildItem -Path "$espRoot\python_env" -Filter 'python.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($pythonExe) {
		$result.Python = $pythonExe.FullName
	} else {
		$result.Python = 'python'
	}

	# 查找 esptool.py（在 frameworks 目录下）
	$esptool = Get-ChildItem -Path "$espRoot\frameworks" -Filter 'esptool.py' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($esptool) {
		$result.Esptool = $esptool.FullName
	}

	# 查找 espefuse.py
	$espefuse = Get-ChildItem -Path "$espRoot\frameworks" -Filter 'espefuse.py' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($espefuse) {
		$result.Espefuse = $espefuse.FullName
	}

	# 查找 stcgal.exe
	$stcgal = Get-ChildItem -Path "$espRoot\python_env" -Filter 'stcgal.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($stcgal) {
		$result.Stcgal = $stcgal.FullName
	}

	# 查找 pyocd.exe
	$pyocd = Get-ChildItem -Path "$espRoot\python_env" -Filter 'pyocd.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($pyocd) {
		$result.Pyocd = $pyocd.FullName
	} else {
		$result.Pyocd = 'pyocd'
	}

	return $result
}

# ============================================================
# 全局配置
# ============================================================

Write-Host '[0/4] 检测 ESP-IDF 工具链...' -ForegroundColor Cyan
$IdfTools = Find-EspIdfTools

$ESP_PYTHON    = $IdfTools.Python
$ESP_TOOL      = $IdfTools.Esptool
$ESP_EFUSE     = $IdfTools.Espefuse
$STCGAL_PYTHON = $IdfTools.Python
$STCGAL_CMD    = $IdfTools.Stcgal
$PYOCD_CMD     = $IdfTools.Pyocd

# 超时时间（秒）
$TIMEOUT_SEC = 8

# ============================================================
# USB VID/PID 对照表
# ============================================================

$VidPidTable = @{
	'303A:0001' = @{ Platform = 'ESP32';  Desc = 'ESP32 原生USB' }
	'303A:0002' = @{ Platform = 'ESP32';  Desc = 'ESP32-S2 原生USB' }
	'303A:0003' = @{ Platform = 'ESP32';  Desc = 'ESP32-S3 原生USB' }
	'303A:0005' = @{ Platform = 'ESP32';  Desc = 'ESP32-C3 原生USB' }
	'303A:000C' = @{ Platform = 'ESP32';  Desc = 'ESP32-C6 原生USB' }
	'303A:1001' = @{ Platform = 'ESP32';  Desc = 'ESP32 USB JTAG/serial debug' }
	'1A86:7523' = @{ Platform = 'Serial'; Desc = 'CH340 串口芯片' }
	'1A86:7522' = @{ Platform = 'Serial'; Desc = 'CH340K 串口芯片' }
	'1A86:55D4' = @{ Platform = 'Serial'; Desc = 'CH343 串口芯片' }
	'10C4:EA60' = @{ Platform = 'Serial'; Desc = 'CP2102 串口芯片' }
	'10C4:EA70' = @{ Platform = 'Serial'; Desc = 'CP2105 串口芯片' }
	'0403:6001' = @{ Platform = 'Serial'; Desc = 'FT232 串口芯片' }
	'0D28:0204' = @{ Platform = 'ARM';    Desc = 'CMSIS-DAP 调试器' }
	'C251:F001' = @{ Platform = 'ARM';    Desc = 'jixin.pro CMSIS-DAP 调试器' }
	'0483:3748' = @{ Platform = 'ARM';    Desc = 'ST-Link V2' }
	'0483:374B' = @{ Platform = 'ARM';    Desc = 'ST-Link V2-1' }
	'0483:374F' = @{ Platform = 'ARM';    Desc = 'ST-Link V3' }
	'1366:0101' = @{ Platform = 'ARM';    Desc = 'J-Link' }
	'1366:1051' = @{ Platform = 'ARM';    Desc = 'J-Link' }
}

# ARM IDCODE 对照表

$DevIdTable = @{
	'0x413' = 'STM32F4/GD32F4 (Cortex-M4)'
}
$IdcodeTable = @{
	'0x0BB11477' = @{ Core = 'Cortex-M3'; Series = 'STM32F1/GD32F1' }
	'0x4BA00477' = @{ Core = 'Cortex-M4'; Series = 'STM32F4/GD32F4' }
	'0x0BC11477' = @{ Core = 'Cortex-M7'; Series = 'STM32F7' }
	'0x0BA01477' = @{ Core = 'Cortex-M0'; Series = 'STM32F0/GD32F0' }
	'0x0C090775' = @{ Core = 'Cortex-M0+'; Series = 'STM32L0' }
	'0x5BA02477' = @{ Core = 'Cortex-M33'; Series = 'STM32L4/GD32L4' }
}

# ============================================================
# 数据结构：检测结果
# ============================================================

$DetectResult = @{
	UsbDevices   = @()
	ComPorts     = @()
	Platform     = 'Unknown'
	ChipModel    = 'Unknown'
	FlashSize    = 'Unknown'
	RamSize      = 'Unknown'
	MacAddr      = 'Unknown'
	ExtraInfo    = @()
	Features     = @()
	Confidence   = 0
}

# ============================================================
# 工具函数：带超时的命令执行
# ============================================================

function Invoke-CommandWithTimeout {
	param(
		[string]$FilePath,
		[string[]]$Arguments,
		[int]$TimeoutSeconds = $TIMEOUT_SEC
	)

	$info = New-Object System.Diagnostics.ProcessStartInfo
	$info.FileName = $FilePath
	$info.Arguments = ($Arguments -join ' ')
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	$info.UseShellExecute = $false
	$info.CreateNoWindow = $true

	$proc = New-Object System.Diagnostics.Process
	$proc.StartInfo = $info

	$stdoutBuilder = New-Object System.Text.StringBuilder
	$stderrBuilder = New-Object System.Text.StringBuilder

	$stdoutAction = {
		if (-not [String]::IsNullOrEmpty($EventArgs.Data)) {
			$Event.MessageData.AppendLine($EventArgs.Data) | Out-Null
		}
	}
	$stderrAction = {
		if (-not [String]::IsNullOrEmpty($EventArgs.Data)) {
			$Event.MessageData.AppendLine($EventArgs.Data) | Out-Null
		}
	}

	$stdoutEvent = Register-ObjectEvent -InputObject $proc -EventName 'OutputDataReceived' -Action $stdoutAction -MessageData $stdoutBuilder
	$stderrEvent = Register-ObjectEvent -InputObject $proc -EventName 'ErrorDataReceived' -Action $stderrAction -MessageData $stderrBuilder

	$proc.Start() | Out-Null
	$proc.BeginOutputReadLine()
	$proc.BeginErrorReadLine()

	if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
		try { $proc.Kill() } catch {}
		Unregister-Event -SourceIdentifier $stdoutEvent.Name
		Unregister-Event -SourceIdentifier $stderrEvent.Name
		return @{ Success = $false; Output = ''; Error = 'TIMEOUT' }
	}

	$proc.WaitForExit()
	Unregister-Event -SourceIdentifier $stdoutEvent.Name
	Unregister-Event -SourceIdentifier $stderrEvent.Name

	$stdout = $stdoutBuilder.ToString()
	$stderr = $stderrBuilder.ToString()
	$exitCode = $proc.ExitCode

	return @{
		Success  = ($exitCode -eq 0)
		Output   = $stdout
		Error    = $stderr
		ExitCode = $exitCode
	}
}

# ============================================================
# 检测函数：USB 设备枚举
# ============================================================

function Get-UsbDevices {
	Write-Host ''
	Write-Host '[1/4] 扫描 USB 设备...' -ForegroundColor Cyan

	$devices = @()

	try {
		$pnpEntities = Get-WmiObject Win32_PnPEntity | Where-Object {
			$_.DeviceID -match 'USB' -or $_.Name -match 'COM'
		}

		foreach ($entity in $pnpEntities) {
			if ($entity.DeviceID -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') {
				$vid = $matches[1].ToUpper()
				$devPid = $matches[2].ToUpper()
				$key = "${vid}:${devPid}"

				$desc = $entity.Name
				$platform = 'Unknown'

				if ($VidPidTable.ContainsKey($key)) {
					$platform = $VidPidTable[$key].Platform
					$desc = $VidPidTable[$key].Desc
				}

				$comPort = ''
				if ($entity.Name -match '\(COM(\d+)\)') {
					$comPort = "COM$($matches[1])"
				}

				$device = @{
					VidPid   = $key
					Name     = $desc
					Platform = $platform
					ComPort  = $comPort
					RawName  = $entity.Name
				}

				$dup = $false
				foreach ($d in $devices) {
					if ($d.VidPid -eq $key -and $d.ComPort -eq $comPort) {
						$dup = $true
						break
					}
				}
				if (-not $dup) {
					$devices += $device
					$comStr = if ($comPort) { " -> $comPort" } else { '' }
					Write-Host "  发现: $desc (VID:$vid PID:$devPid)$comStr" -ForegroundColor Green
				}
			}
		}
	}
	catch {
		Write-Host "  USB 枚举失败: $($_.Exception.Message)" -ForegroundColor Red
	}

	if ($devices.Count -eq 0) {
		Write-Host '  未检测到任何 USB 设备' -ForegroundColor Yellow
	}

	return $devices
}

# ============================================================
# 检测函数：串口枚举
# ============================================================

function Get-ComPorts {
	Write-Host ''
	Write-Host '[2/4] 枚举串口...' -ForegroundColor Cyan

	$ports = @()
	try {
		$ports = [System.IO.Ports.SerialPort]::getportnames()
	}
	catch {
		Write-Host "  串口枚举失败: $($_.Exception.Message)" -ForegroundColor Red
	}

	if ($ports.Count -eq 0) {
		Write-Host '  未检测到串口' -ForegroundColor Yellow
	}
	else {
		foreach ($p in $ports) {
			Write-Host "  发现: $p" -ForegroundColor Green
		}
	}

	return $ports
}

# ============================================================
# 检测函数：ESP32 自动探测（优先 USB 特征匹配串口）
# ============================================================

function Test-Esp32 {
	param([string]$TargetPort)

	$portsToTest = @()
	if ($TargetPort) {
		$portsToTest = @($TargetPort)
	}
	else {
		# 跳过 ARM 调试器虚拟串口（CMSIS-DAP/ST-Link/J-Link 的 VCOM 不应被误探测）
		$armPorts = @()
		foreach ($dev in $DetectResult.UsbDevices) {
			if ($dev.Platform -eq 'ARM' -and $dev.ComPort -and $dev.ComPort -notin $armPorts) {
				$armPorts += $dev.ComPort
			}
		}

# 优先探测 USB 特征匹配的串口
		$priorityPorts = @()
		$otherPorts = @()

		foreach ($dev in $DetectResult.UsbDevices) {
			if (($dev.Platform -eq 'ESP32' -or $dev.Platform -eq 'Serial') -and $dev.ComPort) {
				if ($dev.ComPort -notin $priorityPorts) {
					$priorityPorts += $dev.ComPort
				}
			}
		}

		foreach ($p in $DetectResult.ComPorts) {
			if ($p -notin $priorityPorts -and $p -notin $armPorts) {
				$otherPorts += $p
			}
		}

		$portsToTest = $priorityPorts + $otherPorts
	}

	foreach ($p in $portsToTest) {
		# 判断是否为 USB 特征匹配的优先端口
		$isPriority = $false
		foreach ($dev in $DetectResult.UsbDevices) {
			if ($dev.ComPort -eq $p -and ($dev.Platform -eq 'ESP32' -or $dev.Platform -eq 'Serial')) {
				$isPriority = $true
				break
			}
		}
		if ($isPriority) {
			Write-Host "  尝试 ESP32 ($p) [USB特征匹配]..." -ForegroundColor Gray
		} else {
			Write-Host "  尝试 ESP32 ($p)..." -ForegroundColor Gray
		}

		$argList = @($ESP_TOOL, '--port', $p, '--chip', 'auto', '--baud', '115200', 'flash_id')
		$result = Invoke-CommandWithTimeout -FilePath $ESP_PYTHON -Arguments $argList -TimeoutSeconds 15

		$combined = "$($result.Output) $($result.Error)"

		$chipType = ''
		if ($combined -match 'Chip is (ESP32-\S+)') {
			$chipType = $matches[1]
		}

		if ($chipType) {
			$flashSize = ''
			$macAddr = ''
			$features = ''

			if ($combined -match 'Detected flash size:\s*(\S+)') {
				$flashSize = $matches[1]
			}
			if ($combined -match 'MAC:\s*([\da-fA-F:]+)') {
				$macAddr = $matches[1]
			}
			if ($combined -match 'Features:\s*(.+)') {
				$features = $matches[1].Trim()
			}

			$DetectResult.Platform = 'ESP32'
			$DetectResult.ChipModel = $chipType
			$DetectResult.FlashSize = $flashSize
			$DetectResult.MacAddr = $macAddr
			if ($features) {
				$DetectResult.ExtraInfo += "特性: $features"
			}

			if ($features -match 'Embedded PSRAM\s*(\S+)') {
				$DetectResult.RamSize = $matches[1]
			}

			$DetectResult.Features += "esptool 识别为 $chipType"
			if ($flashSize) {
				$DetectResult.Features += "Flash: $flashSize"
			}
			if ($macAddr) {
				$DetectResult.Features += "MAC: $macAddr"
			}

			Write-Host "  [OK] 检测到 ESP32: $chipType" -ForegroundColor Green
			return $true
		}
	}

	return $false
}

# ============================================================
# 检测函数：STC8 自动探测
# ============================================================

function Test-Stc8 {
	param([string]$TargetPort)

	$portsToTest = @()
	if ($TargetPort) {
		$portsToTest = @($TargetPort)
	}
	else {
		# 跳过 ARM 调试器虚拟串口
		$armPorts = @()
		foreach ($dev in $DetectResult.UsbDevices) {
			if ($dev.Platform -eq 'ARM' -and $dev.ComPort -and $dev.ComPort -notin $armPorts) {
				$armPorts += $dev.ComPort
			}
		}
		$portsToTest = @($DetectResult.ComPorts | Where-Object { $_ -notin $armPorts })
	}

	$stcgalPath = $STCGAL_CMD
	if (-not $stcgalPath -or -not (Test-Path $stcgalPath)) {
		Write-Host '  stcgal 未安装，尝试 pip 安装...' -ForegroundColor Yellow
		$installResult = Invoke-CommandWithTimeout -FilePath $STCGAL_PYTHON -Arguments @('-m', 'pip', 'install', 'stcgal') -TimeoutSeconds 30
		$stcgalPath = Get-Command 'stcgal' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
		if (-not $stcgalPath -or -not (Test-Path $stcgalPath)) {
			Write-Host '  stcgal 安装失败，跳过 STC8 检测' -ForegroundColor Red
			return $false
		}
	}

	foreach ($p in $portsToTest) {
		Write-Host "  尝试 STC8 ($p)..." -ForegroundColor Gray
		Write-Host '  [!] STC8 需要手动复位芯片才能连接，请按住复位键后松开...' -ForegroundColor Yellow

		$argList = @('-P', 'stc8', '-p', $p, '-l', '1200')
		$result = Invoke-CommandWithTimeout -FilePath $stcgalPath -Arguments $argList -TimeoutSeconds 15

		$combined = "$($result.Output) $($result.Error)"

		if ($combined -match 'Model name:\s*(.+)') {
			$model = $matches[1].Trim()
			$DetectResult.Platform = 'STC8'
			$DetectResult.ChipModel = $model
			$DetectResult.Features += "stcgal 识别为 $model"

			if ($combined -match 'Flash size:\s*(\S+)') {
				$DetectResult.FlashSize = $matches[1]
				$DetectResult.Features += "Flash: $($matches[1])"
			}
			if ($combined -match 'RAM size:\s*(\S+)') {
				$DetectResult.RamSize = $matches[1]
				$DetectResult.Features += "RAM: $($matches[1])"
			}

			Write-Host "  [OK] 检测到 STC8: $model" -ForegroundColor Green
			return $true
		}
	}

	return $false
}

# ============================================================
# 检测函数：ARM (STM32/GD32) 自动探测
# ============================================================

function Test-Arm {
	Write-Host '  尝试 ARM 调试器...' -ForegroundColor Gray

	$pyocdPath = $PYOCD_CMD
	if (-not $pyocdPath -or -not (Test-Path $pyocdPath)) {
		Write-Host '  pyOCD 未安装，尝试 pip 安装...' -ForegroundColor Yellow
		$installResult = Invoke-CommandWithTimeout -FilePath $ESP_PYTHON -Arguments @('-m', 'pip', 'install', 'pyocd') -TimeoutSeconds 60
		if (-not $pyocdPath -or -not (Test-Path $pyocdPath)) {
			Write-Host '  pyOCD 安装失败，跳过 ARM 检测' -ForegroundColor Red
			return $false
		}
	}

	$listResult = Invoke-CommandWithTimeout -FilePath $pyocdPath -Arguments @('list', '-p') -TimeoutSeconds 10
	$listOut = "$($listResult.Output)"
	$deviceCount = 0
	$probes = @()
	if ($listOut -match '(?im)^\s*\d+\s+\S') {
		$probes = @($listOut -split '\r?\n' | Where-Object { $_ -match '^\s*\d+\s+\S' })
		$deviceCount = $probes.Count
	} elseif ($listOut -match '(\d+)\s+device\(s\)') {
		$deviceCount = [int]$matches[1]
	}
	if ($deviceCount -eq 0) {
		Write-Host '  未检测到 ARM 调试器' -ForegroundColor Yellow
		return $false
	}
	$probeTxt = if ($probes.Count) { ' (' + ($probes -join '; ') + ')' } else { '' }
	Write-Host "  检测到 $deviceCount 个调试器$probeTxt" -ForegroundColor Green

	# 读芯片 Device ID（0xE0042000 = DBGMCU_IDCODE），自动尝试常见 GD32/STM32 target
	$devId = $null
	foreach ($t in @('gd32f407ve', 'gd32f405rg', 'gd32f103cbt6', 'stm32f407vg', 'stm32f103cbt6')) {
		$r = Invoke-CommandWithTimeout -FilePath $pyocdPath -Arguments @('cmd', '-t', $t, '-c', 'read32 0xE0042000') -TimeoutSeconds 12
		$comb = "$($r.Output) $($r.Error)"
		if ($comb -match '(?i)\be0042000:\s*([0-9A-Fa-f]{8})\b') {
			$devId = $matches[1].ToUpper()
			$hitTarget = $t
			break
		}
	}

	if ($devId) {
		$low12 = '0x' + $devId.Substring($devId.Length - 3)
		$DetectResult.Platform = 'ARM'
		if ($DevIdTable.ContainsKey($low12)) {
			$known = $DevIdTable[$low12]
			$DetectResult.ChipModel = $known
			$DetectResult.Features += "DeviceID: 0x$devId -> $known"
			Write-Host "  [OK] 检测到 ARM: $known (DeviceID 0x$devId)" -ForegroundColor Green

			# 读 Flash 大小（F4 系 0x1FFF7A22 半字 = KB，2026-09-10 实测定案：GD32F407VE 读出 0x200=512KB）
			if ($low12 -eq '0x413') {
				$fs = Invoke-CommandWithTimeout -FilePath $pyocdPath -Arguments @('cmd', '-t', $hitTarget, '-c', 'read16 0x1FFF7A22') -TimeoutSeconds 12
				$fsComb = "$($fs.Output) $($fs.Error)"
				if ($fsComb -match '(?i)1fff7a22:\s*([0-9A-Fa-f]{4})') {
					$fsKb = [Convert]::ToInt32($matches[1], 16)
					if ($fsKb -gt 0) {
						$DetectResult.FlashSize = "${fsKb}KB"
						$DetectResult.Features += "Flash: ${fsKb}KB (0x1FFF7A22 实测)"
					}
				}
			}
		} else {
			$DetectResult.ChipModel = "Unknown ARM (DeviceID 0x$devId)"
			$DetectResult.Features += "DeviceID: 0x$devId (未知型号)"
			Write-Host "  [!] 检测到 ARM 芯片，DeviceID 0x$devId 不在已知列表" -ForegroundColor Yellow
		}
		return $true
	}

	Write-Host '  无法读取 ARM 芯片信息（DeviceID 读取失败）' -ForegroundColor Yellow
	return $false
}

# ============================================================
# 检测函数：串口日志特征识别（被动只读，VID 特征失败后的兜底）
# ============================================================

# 日志特征表（宁可漏抓不能 FP：只收录实测确认过的特征，新特征须实测后再加）
$LogSignatureTable = @(
	@{ Pattern = 'lvgl_loop';           Platform = 'ARM (Cortex-M4)'; Model = 'GD32F407VE LVGL 手表'; Desc = 'LVGL+FreeRTOS 运行日志（lvgl_loop/heap_free_min）' }
	@{ Pattern = '[IDEWV] \(\d+\)\s+[a-z_]+:'; Platform = 'ESP32'; Model = 'ESP32 (ESP-IDF 固件)'; Desc = 'ESP-IDF 标准日志格式' }
)

function Read-SerialPassive {
	param([string]$Port, [int]$Baud, [int]$Seconds)

	$sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, 'None', 8, 'One')
	$sb = New-Object System.Text.StringBuilder
	try {
		$sp.ReadTimeout = 300
		$sp.Open()
		$deadline = (Get-Date).AddSeconds($Seconds)
		while ((Get-Date) -lt $deadline) {
			try {
				$chunk = $sp.ReadExisting()
				if ($chunk) { [void]$sb.Append($chunk) }
			} catch {}
			Start-Sleep -Milliseconds 100
		}
	} catch {
		return ''
	} finally {
		try { $sp.Close() } catch {}
	}
	return $sb.ToString()
}

function Test-LogSignature {
	Write-Host ''
	Write-Host '  未识别，被动抓取串口日志做特征匹配（只读不发送数据）...' -ForegroundColor Yellow

	# 端口排序：USB 串行设备端口优先（最可能是目标板，抓 2 秒），其余端口只抓 1 秒提速
	$priorityPorts = @($DetectResult.UsbDevices | Where-Object { $_.ComPort } | ForEach-Object { $_.ComPort })
	$orderedPorts = @()
	foreach ($p in ($priorityPorts + $DetectResult.ComPorts)) {
		if ($p -and $p -notin $orderedPorts) { $orderedPorts += $p }
	}

	foreach ($port in $orderedPorts) {
		$secs = if ($port -in $priorityPorts) { 2 } else { 1 }
		foreach ($baud in @(115200, 9600)) {
			$log = Read-SerialPassive -Port $port -Baud $baud -Seconds $secs
			if ([string]::IsNullOrWhiteSpace($log)) { continue }

			foreach ($sig in $LogSignatureTable) {
				if ($log -match $sig.Pattern) {
					$preview = ($log.Trim() -replace '\s+', ' ')
					if ($preview.Length -gt 120) { $preview = $preview.Substring(0, 120) + '...' }
					$DetectResult.Platform  = $sig.Platform
					$DetectResult.ChipModel = $sig.Model
					$DetectResult.Features += "串口日志特征: $($sig.Desc)"
					$DetectResult.ExtraInfo += "日志特征样本: $preview"
					Write-Host "  [OK] ${port}@${baud} 日志特征命中: $($sig.Desc)" -ForegroundColor Green
					Write-Host "       判定: $($sig.Platform) / $($sig.Model)" -ForegroundColor Green
					Write-Host "       样本: $preview" -ForegroundColor DarkGray
					return $true
				}
			}
		}
	}

	Write-Host '  各串口无特征日志输出' -ForegroundColor Gray
	return $false
}

# ============================================================
# 置信度计算
# ============================================================

function Calculate-Confidence {
	$score = 0
	$maxScore = 0

	$maxScore += 30
	foreach ($dev in $DetectResult.UsbDevices) {
		if ($dev.Platform -eq $DetectResult.Platform) {
			$score += 30
			break
		}
		if ($dev.Platform -eq 'Serial' -and ($DetectResult.Platform -eq 'ESP32' -or $DetectResult.Platform -eq 'STC8')) {
			$score += 15
		}
	}

	$maxScore += 40
	if ($DetectResult.ChipModel -ne 'Unknown' -and $DetectResult.ChipModel -notmatch 'Unknown') {
		$score += 40
	}

	$maxScore += 15
	if ($DetectResult.FlashSize -ne 'Unknown') {
		$score += 15
	}

	$maxScore += 15
	if ($DetectResult.RamSize -ne 'Unknown') {
		$score += 15
	}

	# 串口日志特征 = 运行时固件自报身份，比 VID 猜测更可信，加 45 分权重（40 基分 → 85 高置信）
	if ($DetectResult.Features | Where-Object { $_ -match '^串口日志特征' }) {
		$score += 45
	}

	if ($maxScore -eq 0) { return 0 }
	return [math]::Round(($score / $maxScore) * 100)
}

# ============================================================
# 输出报告
# ============================================================

function Print-Report {
	Write-Host ''
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host '          芯片检测报告' -ForegroundColor Cyan
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host ''

	Write-Host '[USB 设备]' -ForegroundColor Yellow
	if ($DetectResult.UsbDevices.Count -eq 0) {
		Write-Host '  无'
	}
	else {
		foreach ($dev in $DetectResult.UsbDevices) {
			$comStr = if ($dev.ComPort) { " -> $($dev.ComPort)" } else { '' }
			Write-Host "  $($dev.Name) (VID:PID = $($dev.VidPid))$comStr"
		}
	}
	Write-Host ''

	Write-Host '[串口]' -ForegroundColor Yellow
	if ($DetectResult.ComPorts.Count -eq 0) {
		Write-Host '  无'
	}
	else {
		Write-Host "  $($DetectResult.ComPorts -join ', ')"
	}
	Write-Host ''

	Write-Host '[芯片信息]' -ForegroundColor Yellow
	Write-Host "  平台:   $($DetectResult.Platform)"
	Write-Host "  型号:   $($DetectResult.ChipModel)"
	Write-Host "  Flash:  $($DetectResult.FlashSize)"
	Write-Host "  RAM:    $($DetectResult.RamSize)"
	if ($DetectResult.MacAddr -ne 'Unknown') {
		Write-Host "  MAC:    $($DetectResult.MacAddr)"
	}
	Write-Host ''

	Write-Host '[匹配特征]' -ForegroundColor Yellow
	if ($DetectResult.Features.Count -eq 0) {
		Write-Host '  无'
	}
	else {
		foreach ($f in $DetectResult.Features) {
			Write-Host "  [v] $f" -ForegroundColor Green
		}
	}
	Write-Host ''

	$conf = $DetectResult.Confidence
	$confColor = if ($conf -ge 85) { 'Green' } elseif ($conf -ge 60) { 'Yellow' } else { 'Red' }
	Write-Host '[置信度]' -ForegroundColor Yellow
	Write-Host "  $conf%" -ForegroundColor $confColor

	if ($conf -ge 85) {
		Write-Host '  状态: [OK] 高置信度，可以开始开发' -ForegroundColor Green
	}
	elseif ($conf -ge 60) {
		Write-Host '  状态: [!] 中等置信度，建议人工确认型号' -ForegroundColor Yellow
	}
	else {
		Write-Host '  状态: [X] 低置信度，请人工查看芯片丝印' -ForegroundColor Red
	}

	if ($DetectResult.ExtraInfo.Count -gt 0) {
		Write-Host ''
		Write-Host '[额外信息]' -ForegroundColor Yellow
		foreach ($info in $DetectResult.ExtraInfo) {
			Write-Host "  $info"
		}
	}

	Write-Host ''
	Write-Host '========================================' -ForegroundColor Cyan
}

# ============================================================
# 主流程
# ============================================================

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  嵌入式芯片自动检测工具 v1.4' -ForegroundColor Cyan
Write-Host '  支持: ESP32 / STC8 / GD32 / STM32' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

$DetectResult.UsbDevices = Get-UsbDevices
$DetectResult.ComPorts = Get-ComPorts

Write-Host ''
Write-Host '[3/4] 自动探测芯片...' -ForegroundColor Cyan

$hasEsp32Usb = $false
$hasSerial   = $false
$hasArmDebug = $false

foreach ($dev in $DetectResult.UsbDevices) {
	switch ($dev.Platform) {
		'ESP32'  { $hasEsp32Usb = $true }
		'Serial' { $hasSerial = $true }
		'ARM'    { $hasArmDebug = $true }
	}
}

$detected = $false

if (-not $detected) {
	if ($hasEsp32Usb -or $hasSerial -or $DetectResult.ComPorts.Count -gt 0) {
		$detected = Test-Esp32 -TargetPort $Port
	}
}

if (-not $detected -and ($hasSerial -or $DetectResult.ComPorts.Count -gt 0)) {
	$detected = Test-Stc8 -TargetPort $Port
}

if (-not $detected -and $hasArmDebug) {
	$detected = Test-Arm
}

if (-not $detected -and $DetectResult.ComPorts.Count -gt 0 -and -not $hasArmDebug) {
	Write-Host ''
	Write-Host '  未通过 USB 特征识别，尝试 ARM 调试器...' -ForegroundColor Yellow
	$detected = Test-Arm
}

if (-not $detected -and $DetectResult.ComPorts.Count -gt 0) {
	$detected = Test-LogSignature
}

Write-Host ''
Write-Host '[4/4] 生成报告...' -ForegroundColor Cyan
$DetectResult.Confidence = Calculate-Confidence
Print-Report

if (-not $detected) {
	Write-Host ''
	Write-Host '[X] 未能自动识别芯片型号' -ForegroundColor Red
	Write-Host '建议操作:' -ForegroundColor Yellow
	Write-Host '  1. 查看芯片表面激光刻字'
	Write-Host '  2. 查看开发板型号丝印，查官网确定芯片'
	Write-Host '  3. 手动告知芯片型号，由助手验证'
	Write-Host ''
}