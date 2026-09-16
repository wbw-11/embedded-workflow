<#
.SYNOPSIS
	ESP32 一键擦除 Flash 工具
.DESCRIPTION
	自动检测 ESP-IDF 环境，扫描可用串口（优先 CH340/CP2102 串口芯片），
	调用 esptool.py erase_flash 擦除整个 Flash。
	擦除前显示警告并要求用户确认（除非 -Force 参数）。
	擦除完成后给出后续操作建议，并对常见错误进行诊断。
.EXAMPLE
	esp-erase-flash                            # 自动扫描串口并询问确认
	esp-erase-flash -Port COM8                 # 指定串口
	esp-erase-flash -Port COM8 -Baud 460800    # 加速擦除
	esp-erase-flash -Force                     # 跳过确认直接擦除
	esp-erase-flash -Port COM8 -Baud 460800 -Force  # 指定串口+加速+跳过确认
  version: 1.0.0
#>

param(
	[string]$Port = '',           # 指定串口（不指定则自动选择）
	[int]$Baud = 115200,          # 波特率（默认 115200，擦除时可用 460800 加速）
	[switch]$Force               # 跳过确认直接擦除
)

# ============================================================
# 函数：查找 ESP-IDF 环境（参考 esp-burn.ps1，使用 esp-idf-env.ps1）
# ============================================================
function Find-EspIdfEnv {
	# 已设置 IDF_PATH 且 esptool.py 存在则直接返回
	if ($env:IDF_PATH -and (Test-Path "$env:IDF_PATH\components\esptool_py\esptool\esptool.py")) {
		return $true
	}

	Write-Host '[!] IDF_PATH 未设置或无效，正在加载 esp-idf-env.ps1...' -ForegroundColor Yellow
	try {
		$envScript = "$PSScriptRoot\esp-idf-env.ps1"
		if (-not (Test-Path $envScript)) {
			Write-Host "  [X] 未找到 esp-idf-env.ps1: $envScript" -ForegroundColor Red
			return $false
		}
		. $envScript
		if ($env:IDF_PATH -and (Test-Path "$env:IDF_PATH\components\esptool_py\esptool\esptool.py")) {
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
# 函数：枚举串口（优先 CH340/CP2102 串口芯片，与 esp-burn.ps1 一致）
# ============================================================
function Get-ComPorts {
	Write-Host ''
	Write-Host '[1/3] 扫描 COM 口...' -ForegroundColor Cyan

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

	# 通过 USB VID/PID 识别串口芯片类型，优先选择 CH340/CP2102
	$priorityPorts = @()
	$otherPorts = @()

	try {
		$pnpEntities = Get-WmiObject Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
			$_.DeviceID -match 'USB' -or $_.Name -match 'COM'
		}

		# 常见 USB 串口芯片 VID 对照表
		$serialChipVids = @{
			'1A86' = 'CH340/CH343'   # QinHeng Electronics
			'10C4' = 'CP2102/CP2105'  # Silicon Labs
			'0403' = 'FT232'         # FTDI
			'303A' = 'ESP32 原生USB'  # Espressif
		}

		foreach ($p in $ports) {
			$isPriority = $false
			$chipDesc = ''
			foreach ($entity in $pnpEntities) {
				if ($entity.Name -match [regex]::Escape($p)) {
					if ($entity.DeviceID -match 'VID_([0-9A-Fa-f]{4})') {
						$vid = $matches[1].ToUpper()
						if ($serialChipVids.ContainsKey($vid)) {
							$isPriority = $true
							$chipDesc = $serialChipVids[$vid]
						}
					}
					break
				}
			}
			if ($isPriority) {
				$priorityPorts += $p
				Write-Host "  $p -> $chipDesc [优先]" -ForegroundColor Green
			}
			else {
				$otherPorts += $p
			}
		}
	}
	catch {
		Write-Host "  [!] 串口芯片识别失败，按默认顺序处理: $($_.Exception.Message)" -ForegroundColor Yellow
		$otherPorts = $ports
	}

	# 优先返回 CH340/CP2102 串口，然后是其他串口
	$sortedPorts = @($priorityPorts) + @($otherPorts)
	return $sortedPorts
}

# ============================================================
# 函数：让用户选择串口
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
		Write-Host '    3. 是否有其他程序占用 COM 口'
		return $null
	}

	if ($Host.Name -match 'NonInteractive' -or [Console]::IsInputRedirected) {
		Write-Host "[!] NonInteractive 模式，自动选择第 1 个: $($Ports[0])" -ForegroundColor Yellow
		return $Ports[0]
	}

	if ($Ports.Count -eq 1) {
		Write-Host ''
		Write-Host "[OK] 仅检测到 1 个 COM 口: $($Ports[0])" -ForegroundColor Green
		return $Ports[0]
	}

	Write-Host ''
	Write-Host '检测到多个串口，请选择:' -ForegroundColor Yellow
	for ($i = 0; $i -lt $Ports.Count; $i++) {
		Write-Host "  [$($i+1)] $($Ports[$i])"
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
# 函数：执行 Flash 擦除
# ============================================================
function Invoke-FlashErase {
	param(
		[string]$TargetPort,
		[int]$TargetBaud,
		[bool]$SkipConfirm
	)

	# 擦除前的警告确认
	if (-not $SkipConfirm) {
		Write-Host ''
		Write-Host '=========================================' -ForegroundColor Red
		Write-Host '  警告：即将擦除 ESP32 整个 Flash！' -ForegroundColor Red
		Write-Host '=========================================' -ForegroundColor Red
		Write-Host "  串口：$TargetPort" -ForegroundColor Yellow
		Write-Host "  波特率：$TargetBaud" -ForegroundColor Yellow
		Write-Host '  此操作将清空：' -ForegroundColor Yellow
		Write-Host '    - 应用程序固件'
		Write-Host '    - NVS 分区（WiFi 凭据、用户配置等）'
		Write-Host '    - FatFS / SPIFFS 文件系统'
		Write-Host '    - OTA 分区'
		Write-Host '  操作不可恢复！' -ForegroundColor Red
		Write-Host ''
		$confirm = Read-Host '确认擦除？(Y/N)'
		if ($confirm -notmatch '^[Yy]') {
			Write-Host '[!] 用户取消擦除' -ForegroundColor Yellow
			return $false
		}
	}

	# 执行擦除
	Write-Host ''
	Write-Host "[3/3] 执行擦除: esptool.py --port $TargetPort --baud $TargetBaud erase_flash" -ForegroundColor Cyan

	$esptoolPath = "$env:IDF_PATH\components\esptool_py\esptool\esptool.py"
	if (-not (Test-Path $esptoolPath)) {
		Write-Host "[X] 未找到 esptool.py: $esptoolPath" -ForegroundColor Red
		return $false
	}

	$argList = @($esptoolPath, '--port', $TargetPort, '--baud', $TargetBaud, 'erase_flash')
	& python @argList 2>&1 | Tee-Object -Variable eraseOutput

	if ($LASTEXITCODE -eq 0) {
		Write-Host ''
		Write-Host '[OK] Flash 擦除完成' -ForegroundColor Green
		Write-Host '后续操作建议：' -ForegroundColor Cyan
		Write-Host '  1. 重新烧录固件：esp-burn'
		Write-Host '  2. 重新配置 WiFi：应用程序会进入配网模式'
		Write-Host '  3. 如需擦除特定分区：使用 esptool.py erase_region <偏移> <长度>'
		return $true
	}
	else {
		Write-Host ''
		Write-Host '[X] Flash 擦除失败' -ForegroundColor Red
		Invoke-EraseErrorDiagnosis -ErrorOutput $eraseOutput -Port $TargetPort
		return $false
	}
}

# ============================================================
# 函数：擦除错误诊断
# ============================================================
function Invoke-EraseErrorDiagnosis {
	param(
		[string]$ErrorOutput,
		[string]$Port
	)

	Write-Host ''
	Write-Host '[!] 擦除错误诊断:' -ForegroundColor Yellow

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

	if ($ErrorOutput -match 'Permission denied|Access is denied|无法访问') {
		Write-Host '  原因: 权限不足或串口被占用' -ForegroundColor Red
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 关闭串口助手、监控等占用串口的程序'
		Write-Host '    2. 以管理员身份运行 PowerShell'
		return $true
	}

	if ($ErrorOutput -match 'Serial port.*not found|could not open.*COM|Failed to open') {
		Write-Host '  原因: 指定的串口号不存在或无法打开' -ForegroundColor Red
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 在设备管理器中确认正确的串口号'
		Write-Host '    2. 重新插拔 USB 线后重试'
		Write-Host '    3. 检查是否需要安装 CH340/CP2102 驱动'
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

	if ($ErrorOutput -match 'No module named esptool|ModuleNotFoundError|can.t find') {
		Write-Host '  原因: esptool 未安装或 Python 环境异常' -ForegroundColor Red
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 重新加载 ESP-IDF 环境: . esp-idf-env.ps1'
		Write-Host '    2. 检查 IDF_PATH 是否正确: $env:IDF_PATH'
		Write-Host '    3. 确认 Python 虚拟环境已激活'
		return $true
	}

	if ($ErrorOutput -match 'device not found|A device attached|cannot connect|无响应') {
		Write-Host '  原因: 芯片无响应' -ForegroundColor Red
		Write-Host '  排查:' -ForegroundColor Yellow
		Write-Host '    1. 确认 ESP32 已通电（板载 LED 是否亮起）'
		Write-Host '    2. 按住 BOOT 键后再按复位键，进入下载模式'
		Write-Host '    3. 检查 USB 线是否为数据线'
		return $true
	}

	Write-Host '  未知错误，请查看完整错误输出' -ForegroundColor Yellow
	return $false
}

# ============================================================
# 主流程
# ============================================================
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  ESP32 一键擦除 Flash 工具 v1.0' -ForegroundColor Cyan
Write-Host '  自动扫描串口 + 擦除整个 Flash' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

# 步骤 1：检测 ESP-IDF 环境
if (-not (Find-EspIdfEnv)) {
	Write-Host '[X] 无法初始化 ESP-IDF 环境，退出' -ForegroundColor Red
	exit 1
}

# 步骤 2：确定串口
$targetPort = ''
if ($Port) {
	Write-Host ''
	Write-Host "[1/3] 使用指定串口: $Port" -ForegroundColor Cyan
	$targetPort = $Port
}
else {
	$ports = Get-ComPorts
	$targetPort = Select-Port -Ports $ports
}

if (-not $targetPort) {
	exit 1
}

Write-Host ''
Write-Host "[2/3] 选定串口: $targetPort" -ForegroundColor Green

# 步骤 3：执行擦除
$success = Invoke-FlashErase -TargetPort $targetPort -TargetBaud $Baud -SkipConfirm $Force

if ($success) {
	Write-Host ''
	Write-Host '[OK] 完成' -ForegroundColor Green
	exit 0
}
else {
	Write-Host ''
	Write-Host '[X] 擦除未完成' -ForegroundColor Red
	exit 1
}
