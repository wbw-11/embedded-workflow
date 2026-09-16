<#
.SYNOPSIS
	音频通路自检工具（voice_assistant 项目专用）
.DESCRIPTION
	封装音频自检的触发、监控、报告解析全流程。支持两种触发方式：
	  - 交互模式（BOOT 键）：启动后 5 秒内按住 BOOT 键进入，需人工确认
	  - 无人值守模式（NVS 触发）：远程设置 NVS 标志后自动进入，自动判断

	工具核心价值：
	  1. 自动监控串口，捕获 AUDIO_TEST 日志
	  2. 解析完整自检报告（分层状态/逐项详情/根因分析/量化指标）
	  3. 输出彩色汇总，返回退出码（0=全通过 1=有失败 2=超时无报告）
	  4. 保存完整日志到文件，便于回溯

	工作流规则：修改 audio/es8311/recorder 代码前必须先跑此工具确认基线。
.PARAMETER Mode
	guide       - 打印两种触发方式的操作指引
	interactive - 引导按 BOOT 键 + 监控 + 解析（默认）
	monitor     - 仅监控 + 解析（自检已在运行时用）
	parse       - 解析已保存的日志文件（需 -LogFile）
	setup-nvs   - 引导设置 NVS 无人值守触发标志
.PARAMETER Port
	串口号（不指定则自动扫描选择）
.PARAMETER Baud
	监控波特率（默认 115200）
.PARAMETER LogFile
	parse 模式下指定日志文件路径；monitor/interactive 模式下指定保存路径
.PARAMETER Timeout
	监控超时秒数（默认 120，含 5 秒 BOOT 倒计时 + 自检执行）
.EXAMPLE
	audio-path-self-test                           # 交互模式（BOOT 键）
	audio-path-self-test -Mode monitor -Port COM8  # 仅监控解析
	audio-path-self-test -Mode parse -LogFile log.txt
	audio-path-self-test -Mode guide               # 打印操作指引
	audio-path-self-test -Mode setup-nvs           # NVS 触发设置指引
  version: 1.0.0
#>

param(
	[ValidateSet('guide', 'interactive', 'monitor', 'parse', 'setup-nvs')]
	[string]$Mode = 'interactive',
	[string]$Port = '',
	[int]$Baud = 115200,
	[string]$LogFile = '',
	[int]$Timeout = 120
)

$ToolVersion = 'v1.0'
$LogTag = 'AUDIO_TEST'

# ============================================================
# 模式：guide - 打印操作指引
# ============================================================
function Show-Guide {
	Write-Host ''
	Write-Host '╔══════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
	Write-Host '║          音频通路自检 · 操作指引                          ║' -ForegroundColor Cyan
	Write-Host '╚══════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
	Write-Host ''
	Write-Host '  固件支持两种自检触发方式：' -ForegroundColor White
	Write-Host ''
	Write-Host '  ── 方式 1：BOOT 键交互触发（推荐，最简单）──' -ForegroundColor Yellow
	Write-Host ''
	Write-Host '    1. 烧录固件后正常上电启动' -ForegroundColor Gray
	Write-Host '    2. 启动后会显示 5 秒倒计时提示' -ForegroundColor Gray
	Write-Host '    3. 在倒计时期间按住 BOOT 键（GPIO0）' -ForegroundColor Gray
	Write-Host '    4. 进入 INTERACTIVE 模式自检' -ForegroundColor Gray
	Write-Host ''
	Write-Host '    工具命令：' -ForegroundColor Cyan
	Write-Host '      audio-path-self-test -Mode interactive -Port COM8' -ForegroundColor Green
	Write-Host ''
	Write-Host '  ── 方式 2：NVS 无人值守触发（用于回归测试/CI）──' -ForegroundColor Yellow
	Write-Host ''
	Write-Host '    原理：在 NVS 的 "audio_test" 命名空间写入 trigger=1，' -ForegroundColor Gray
	Write-Host '          下次启动固件自动检测并进入 UNATTENDED 模式' -ForegroundColor Gray
	Write-Host ''
	Write-Host '    设置方法（选一）：' -ForegroundColor White
	Write-Host ''
	Write-Host '    [A] 临时改代码（安全，推荐）' -ForegroundColor Cyan
	Write-Host '        1. 在 main.c 的自检入口前临时加一行：' -ForegroundColor Gray
	Write-Host '           audio_self_test_set_nvs_trigger();' -ForegroundColor Green
	Write-Host '        2. 编译烧录，启动一次（设置标志后自动重启）' -ForegroundColor Gray
	Write-Host '        3. 删除临时代码，重新烧录' -ForegroundColor Gray
	Write-Host '        4. 下次启动自动进入无人值守自检' -ForegroundColor Gray
	Write-Host ''
	Write-Host '    [B] BOOT 键替代（半自动）' -ForegroundColor Cyan
	Write-Host '        用 BOOT 键触发，工具自动监控并解析报告' -ForegroundColor Gray
	Write-Host '        虽然需按一次键，但报告解析全自动' -ForegroundColor Gray
	Write-Host ''
	Write-Host '    工具命令（设置好 NVS 后监控）：' -ForegroundColor Cyan
	Write-Host '      audio-path-self-test -Mode monitor -Port COM8' -ForegroundColor Green
	Write-Host ''
	Write-Host '  ── 自检测试项（6 项）──' -ForegroundColor Yellow
	Write-Host ''
	Write-Host '    Layer 0/1: I2C 连通性（ES8311 响应）' -ForegroundColor Gray
	Write-Host '    Layer 2:   DAC 播放（880Hz 测试音 + Goertzel 检测）' -ForegroundColor Gray
	Write-Host '    Layer 2:   ADC 采集（环境音幅值统计）' -ForegroundColor Gray
	Write-Host '    Layer 3:   ES8311 内部 DAC→ADC 回环（REG44）' -ForegroundColor Gray
	Write-Host '    Layer 3:   外部 ADC→DAC 回环（信噪比判定）' -ForegroundColor Gray
	Write-Host '    Layer 3:   I2S 外部回环（需杜邦线连 DOUT→DIN）' -ForegroundColor Gray
	Write-Host ''
	Write-Host '  ── 退出码 ──' -ForegroundColor Yellow
	Write-Host '    0 = 全部通过' -ForegroundColor Green
	Write-Host '    1 = 存在失败项' -ForegroundColor Red
	Write-Host '    2 = 超时未检测到报告' -ForegroundColor Yellow
	Write-Host ''
}

# ============================================================
# 模式：setup-nvs - NVS 触发设置指引
# ============================================================
function Show-NvsSetupGuide {
	Write-Host ''
	Write-Host '╔══════════════════════════════════════════════════════════╗' -ForegroundColor Cyan
	Write-Host '║       NVS 无人值守触发 · 设置指引                         ║' -ForegroundColor Cyan
	Write-Host '╚══════════════════════════════════════════════════════════╝' -ForegroundColor Cyan
	Write-Host ''
	Write-Host '  目标：在 NVS "audio_test" 命名空间写入 trigger=1' -ForegroundColor White
	Write-Host '  效果：下次启动固件自动进入 UNATTENDED 自检模式' -ForegroundColor White
	Write-Host ''
	Write-Host '  注意：不擦除整个 NVS 分区（会丢失 wifi/API密钥等数据）' -ForegroundColor Yellow
	Write-Host '         使用固件内置的 set_nvs_trigger() API 安全写入' -ForegroundColor Yellow
	Write-Host ''
	Write-Host '  ── 推荐方法：临时代码法 ──' -ForegroundColor Cyan
	Write-Host ''
	Write-Host '  步骤 1：在 main.c 的 app_main() 开头临时添加' -ForegroundColor White
	Write-Host ''
	Write-Host '    nvs_flash_init();' -ForegroundColor Green
	Write-Host '    audio_self_test_set_nvs_trigger();' -ForegroundColor Green
	Write-Host '    esp_restart();' -ForegroundColor Green
	Write-Host ''
	Write-Host '  步骤 2：编译烧录' -ForegroundColor White
	Write-Host '    esp-burn -Mode build-flash-monitor -ProjectDir <项目目录>' -ForegroundColor Green
	Write-Host ''
	Write-Host '  步骤 3：设备启动后自动设置标志并重启，串口可见：' -ForegroundColor White
	Write-Host '    NVS 自检标志已设置，下次启动将进入无人值守自检' -ForegroundColor Gray
	Write-Host ''
	Write-Host '  步骤 4：删除步骤 1 的临时代码，重新编译烧录' -ForegroundColor White
	Write-Host ''
	Write-Host '  步骤 5：设备启动后自动进入无人值守自检，用本工具监控：' -ForegroundColor White
	Write-Host '    audio-path-self-test -Mode monitor -Port COM8' -ForegroundColor Green
	Write-Host ''
	Write-Host '  ── 清除 NVS 触发标志 ──' -ForegroundColor Cyan
	Write-Host '  自检执行后固件会自动清除标志（check_nvs_trigger 读取后清零）' -ForegroundColor Gray
	Write-Host '  如需手动清除：esp-erase-flash（会清空所有 NVS，慎用）' -ForegroundColor Yellow
	Write-Host ''
}

# ============================================================
# 扫描 COM 口
# ============================================================
function Get-ComPorts {
	$pnpDevices = @()
	try {
		$pnpDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
			Where-Object { $_.Caption -match '\(COM\d+\)' }
	}
	catch { return @() }

	$ports = New-Object System.Collections.ArrayList
	foreach ($dev in $pnpDevices) {
		if ($dev.Caption -match '\(COM(\d+)\)') {
			$portName = "COM$($matches[1])"
			$chipType = 'Unknown'
			if ($dev.Caption -match 'CH340|CH341') { $chipType = 'CH340/CH341' }
			elseif ($dev.Caption -match 'CP210') { $chipType = 'CP210x' }
			elseif ($dev.Caption -match 'USB Serial') { $chipType = 'USB Serial' }
			[void]$ports.Add(@{ Port=$portName; ChipType=$chipType; Caption=$dev.Caption })
		}
	}
	return $ports
}

function Select-Port {
	param([array]$Ports)
	$Ports = @($Ports)
	if ($Ports.Count -eq 0) {
		Write-Host '[X] 未检测到任何 COM 口' -ForegroundColor Red
		return $null
	}
	if ($Ports.Count -eq 1) {
		Write-Host "[OK] 检测到串口: $($Ports[0].Port) ($($Ports[0].ChipType))" -ForegroundColor Green
		return $Ports[0]
	}
	Write-Host '检测到多个串口，请选择:' -ForegroundColor Yellow
	for ($i = 0; $i -lt $Ports.Count; $i++) {
		Write-Host "  [$($i+1)] $($Ports[$i].Port) - $($Ports[$i].ChipType)" -ForegroundColor White
	}
	$choice = Read-Host "输入序号 (1-$($Ports.Count))"
	$idx = 0
	if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $Ports.Count) {
		return $Ports[$idx - 1]
	}
	return $null
}

# ============================================================
# 解析自检报告（核心）
# ============================================================
function Parse-AudioTestLog {
	param([string[]]$Lines)

	$result = @{
		Found      = $false
		Complete   = $false
		AllPass    = $false
		HasFail    = $false
		Items      = @()
		Summary    = ''
		Layers     = @()
		RootCauses = @()
	}

	$inReport = $false

	foreach ($rawLine in $Lines) {
		$line = $rawLine.Trim()

		# 提取 AUDIO_TEST 日志消息部分：格式 "I (12345) AUDIO_TEST: message"
		$msg = $line
		if ($line -match '\(\d+\)\s*' + [regex]::Escape($LogTag) + '\s*:\s*(.*)') {
			$msg = $matches[1]
		} elseif ($line -match 'AUDIO_TEST\s*:\s*(.*)') {
			$msg = $matches[1]
		}

		# 报告开始
		if ($msg -match '音频通路自检.*完整报告') {
			$result.Found = $true
			$inReport = $true
			continue
		}
		# 兼容旧版结果汇总
		if (-not $result.Found -and $msg -match '自检结果汇总') {
			$result.Found = $true
			$inReport = $true
			continue
		}

		if (-not $inReport) { continue }

		# 分层状态
		if ($msg -match '(基础层|通信层|单外设层|整合层).*:\s*(通过|失败|跳过|未执行)') {
			$result.Layers += $msg
			continue
		}

		# 逐项详情：格式 "+ name [ PASS ]" / "X name [ FAIL ]" / "- name [ SKIP ]"
		if ($msg -match '^[+X\-]\s+(.+?)\s+\[\s*(PASS|FAIL|SKIP)\s*\]') {
			$itemName = $matches[1].Trim()
			$itemStatus = $matches[2]
			# 提取量化值（如果有）
			$metric = ''
			if ($msg -match '量化=(\S+)') { $metric += " 量化=$($matches[1])" }
			if ($msg -match '基准=(\S+)') { $metric += " 基准=$($matches[1])" }
			if ($msg -match '偏差=([+-]?\d+%)') { $metric += " 偏差=$($matches[1])" }
			$result.Items += @{ Name=$itemName; Status=$itemStatus; Metric=$metric }
			continue
		}

		# 根因分析：只捕获编号的根因项，跳过标题和汇总行
		if ($msg -match '^\s*(\d+)\.\s+(.+)') {
			$result.RootCauses += "$($matches[1]). $($matches[2].Trim())"
			continue
		}

		# 统计行
		if ($msg -match '通过:\s*(\d+)\s+失败:\s*(\d+)\s+跳过:\s*(\d+)') {
			$result.Summary = "通过=$($matches[1]) 失败=$($matches[2]) 跳过=$($matches[3])"
			if ([int]$matches[2] -gt 0) { $result.HasFail = $true }
			continue
		}

		# 最终判定
		if ($msg -match '全部通过') {
			$result.AllPass = $true
			$result.Complete = $true
			continue
		}
		if ($msg -match '存在失败项') {
			$result.HasFail = $true
			$result.Complete = $true
			continue
		}

		# 报告结束（╚ 装饰线）
		if ($msg -match '^╚') {
			$result.Complete = $true
			continue
		}
	}

	return $result
}

# ============================================================
# 打印解析结果
# ============================================================
function Show-ParsedResult {
	param($Result)

	if (-not $Result.Found) {
		Write-Host ''
		Write-Host '[!] 未检测到自检报告' -ForegroundColor Yellow
		Write-Host '    可能原因：' -ForegroundColor Gray
		Write-Host '    1. 未进入自检模式（BOOT 键未按或 NVS 未触发）' -ForegroundColor Gray
		Write-Host '    2. 自检尚未完成（超时太短）' -ForegroundColor Gray
		Write-Host '    3. 串口波特率不匹配' -ForegroundColor Gray
		return 2
	}

	Write-Host ''
	Write-Host '╔══════════════════════════════════════════╗' -ForegroundColor Cyan
	Write-Host '║       自检报告解析结果                    ║' -ForegroundColor Cyan
	Write-Host '╚══════════════════════════════════════════╝' -ForegroundColor Cyan

	# 分层状态
	if ($Result.Layers.Count -gt 0) {
		Write-Host ''
		Write-Host '  ── 分层状态 ──' -ForegroundColor Cyan
		foreach ($lyr in $Result.Layers) {
			$color = 'Gray'
			if ($lyr -match '通过') { $color = 'Green' }
			elseif ($lyr -match '失败') { $color = 'Red' }
			elseif ($lyr -match '跳过') { $color = 'Yellow' }
			Write-Host "  $lyr" -ForegroundColor $color
		}
	}

	# 逐项详情
	if ($Result.Items.Count -gt 0) {
		Write-Host ''
		Write-Host '  ── 逐项详情 ──' -ForegroundColor Cyan
		foreach ($item in $Result.Items) {
			$icon = ' '
			$color = 'Gray'
			switch ($item.Status) {
				'PASS' { $icon = '[+]'; $color = 'Green' }
				'FAIL' { $icon = '[X]'; $color = 'Red' }
				'SKIP' { $icon = '[-]'; $color = 'Yellow' }
			}
			$metricStr = if ($item.Metric) { $item.Metric } else { '' }
			Write-Host "  $icon $($item.Name) [$($item.Status)]$metricStr" -ForegroundColor $color
		}
	}

	# 根因分析
	if ($Result.RootCauses.Count -gt 0) {
		Write-Host ''
		Write-Host '  ── 根因分析 ──' -ForegroundColor Magenta
		foreach ($rc in $Result.RootCauses) {
			Write-Host "  $rc" -ForegroundColor Magenta
		}
	}

	# 汇总
	Write-Host ''
	Write-Host '  ── 汇总 ──' -ForegroundColor Cyan
	if ($Result.Summary) {
		Write-Host "  $($Result.Summary)" -ForegroundColor White
	}

	if ($Result.AllPass) {
		Write-Host ''
		Write-Host '  ★ 全部通过 ★' -ForegroundColor Green
		Write-Host '╚══════════════════════════════════════════╝' -ForegroundColor Cyan
		return 0
	} elseif ($Result.HasFail) {
		Write-Host ''
		Write-Host '  ✗ 存在失败项，请修复后重新测试' -ForegroundColor Red
		Write-Host '╚══════════════════════════════════════════╝' -ForegroundColor Cyan
		return 1
	} elseif ($Result.Complete) {
		Write-Host ''
		Write-Host '  报告已结束' -ForegroundColor Gray
		Write-Host '╚══════════════════════════════════════════╝' -ForegroundColor Cyan
		return 0
	} else {
		Write-Host ''
		Write-Host '  [!] 报告不完整（可能被截断）' -ForegroundColor Yellow
		Write-Host '╚══════════════════════════════════════════╝' -ForegroundColor Cyan
		return 2
	}
}

# ============================================================
# 串口监控 + 实时解析
# ============================================================
function Invoke-SerialMonitor {
	param(
		[string]$TargetPort,
		[int]$TargetBaud,
		[int]$TimeoutSec,
		[string]$SaveLogPath
	)

	Write-Host ''
	Write-Host "[监控] 串口=$TargetPort 波特率=$TargetBaud 超时=${TimeoutSec}s" -ForegroundColor Cyan
	if ($SaveLogPath) {
		Write-Host "[日志] 保存到: $SaveLogPath" -ForegroundColor Gray
	}

	$serial = $null
	try {
		$serial = New-Object System.IO.Ports.SerialPort($TargetPort, $TargetBaud)
		$serial.ReadTimeout = 500
		$serial.WriteTimeout = 500
		$serial.Open()
	}
	catch {
		Write-Host "[X] 串口 $TargetPort 打开失败: $($_.Exception.Message)" -ForegroundColor Red
		return 2
	}

	Write-Host '[OK] 串口已打开，开始监控...' -ForegroundColor Green
	Write-Host '     (等待 AUDIO_TEST 日志输出)' -ForegroundColor Gray
	Write-Host ''

	$allLines = New-Object System.Collections.ArrayList
	$startTime = Get-Date
	$exitCode = 2

	try {
		while ($true) {
			$elapsed = (Get-Date) - $startTime
			if ($elapsed.TotalSeconds -gt $TimeoutSec) {
				Write-Host ''
				Write-Host "[!] 超时 ${TimeoutSec}s，未检测到完整报告" -ForegroundColor Yellow
				break
			}

			$line = ''
			try {
				$line = $serial.ReadLine()
			}
			catch [System.TimeoutException] {
				continue
			}
			catch {
				Start-Sleep -Milliseconds 100
				continue
			}

			if ($line) {
				[void]$allLines.Add($line)
				# 实时打印（高亮 AUDIO_TEST 行）
				if ($line -match $LogTag) {
					if ($line -match 'PASS') {
						Write-Host $line -ForegroundColor Green
					}
					elseif ($line -match 'FAIL') {
						Write-Host $line -ForegroundColor Red
					}
					elseif ($line -match 'SKIP') {
						Write-Host $line -ForegroundColor Yellow
					}
					elseif ($line -match '全部通过') {
						Write-Host $line -ForegroundColor Green
					}
					elseif ($line -match '存在失败') {
						Write-Host $line -ForegroundColor Red
					}
					else {
						Write-Host $line -ForegroundColor White
					}
				}
				else {
					Write-Host $line -ForegroundColor DarkGray
				}

				# 检测报告结束
				if ($line -match '全部通过' -or $line -match '存在失败项' -or
					($line -match '╚' -and $allLines.Count -gt 10)) {
					# 再读 2 秒收尾
					$endTime = Get-Date
					while ((Get-Date) - $endTime -lt [TimeSpan]::FromSeconds(2)) {
						try { $tail = $serial.ReadLine(); [void]$allLines.Add($tail) }
						catch { }
					}
					break
				}
			}
		}
	}
	finally {
		if ($serial -and $serial.IsOpen) {
			$serial.Close()
			$serial.Dispose()
		}
	}

	# 保存日志
	if ($SaveLogPath -and $allLines.Count -gt 0) {
		try {
			$allLines -join "`r`n" | Out-File -FilePath $SaveLogPath -Encoding UTF8
			Write-Host ''
			Write-Host "[日志] 已保存 $($allLines.Count) 行到 $SaveLogPath" -ForegroundColor Green
		}
		catch {
			Write-Host "[!] 日志保存失败: $($_.Exception.Message)" -ForegroundColor Yellow
		}
	}

	# 解析报告
	if ($allLines.Count -gt 0) {
		$parsed = Parse-AudioTestLog -Lines $allLines
		$exitCode = Show-ParsedResult -Result $parsed
	}

	return $exitCode
}

# ============================================================
# 模式：parse - 解析日志文件
# ============================================================
function Invoke-ParseLog {
	param([string]$FilePath)

	if (-not (Test-Path $FilePath)) {
		Write-Host "[X] 日志文件不存在: $FilePath" -ForegroundColor Red
		return 2
	}

	Write-Host "[解析] 读取日志: $FilePath" -ForegroundColor Cyan
	$lines = Get-Content $FilePath -Encoding UTF8 -ErrorAction SilentlyContinue
	if (-not $lines) {
		Write-Host '[X] 文件为空或读取失败' -ForegroundColor Red
		return 2
	}

	Write-Host "[解析] 共 $($lines.Count) 行" -ForegroundColor Gray
	$parsed = Parse-AudioTestLog -Lines $lines
	return (Show-ParsedResult -Result $parsed)
}

# ============================================================
# 主流程
# ============================================================
Write-Host '========================================' -ForegroundColor Cyan
Write-Host "  音频通路自检工具 $ToolVersion" -ForegroundColor Cyan
Write-Host '  voice_assistant 项目专用' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

switch ($Mode) {
	'guide' {
		Show-Guide
		exit 0
	}
	'setup-nvs' {
		Show-NvsSetupGuide
		exit 0
	}
	'parse' {
		if (-not $LogFile) {
			Write-Host '[X] parse 模式需要 -LogFile 参数' -ForegroundColor Red
			exit 2
		}
		$code = Invoke-ParseLog -FilePath $LogFile
		exit $code
	}
	'interactive' {
		Write-Host ''
		Write-Host '╔════════════════════════════════════════╗' -ForegroundColor Yellow
		Write-Host '║  交互模式：请准备按 BOOT 键            ║' -ForegroundColor Yellow
		Write-Host '╚════════════════════════════════════════╝' -ForegroundColor Yellow
		Write-Host ''
		Write-Host '  操作步骤：' -ForegroundColor White
		Write-Host '    1. 确认设备已上电（或按 RESET 复位）' -ForegroundColor Gray
		Write-Host '    2. 串口会显示 5 秒倒计时' -ForegroundColor Gray
		Write-Host '    3. 倒计时期间按住 BOOT 键' -ForegroundColor Gray
		Write-Host '    4. 工具自动监控并解析报告' -ForegroundColor Gray
		Write-Host ''
		Write-Host '  [提示] 如需无人值守模式，运行:' -ForegroundColor Cyan
		Write-Host '    audio-path-self-test -Mode setup-nvs' -ForegroundColor Green
		Write-Host ''
	}
	'monitor' {
		Write-Host ''
		Write-Host '  [监控模式] 假设自检已在运行，直接监控串口' -ForegroundColor Cyan
		Write-Host ''
	}
}

# 确定串口
$selected = $null
if ($Port) {
	Write-Host "[串口] 使用指定串口: $Port" -ForegroundColor Cyan
	$selected = @{ Port=$Port; ChipType='(用户指定)'; Caption='' }
} else {
	$ports = Get-ComPorts
	$selected = Select-Port -Ports $ports
}

if (-not $selected) {
	Write-Host '[X] 未选择串口，退出' -ForegroundColor Red
	exit 2
}

# 确定日志保存路径
$saveLog = $LogFile
if (-not $saveLog) {
	$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
	$saveLog = "audio_self_test_$timestamp.log"
}

# 启动监控
$exitCode = Invoke-SerialMonitor -TargetPort $selected.Port -TargetBaud $Baud -TimeoutSec $Timeout -SaveLogPath $saveLog

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host "  退出码: $exitCode" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

exit $exitCode
