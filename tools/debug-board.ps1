<#
.SYNOPSIS
	通用调试工具 - 支持多种开发板调试
.DESCRIPTION
	根据当前选择的板子配置，自动选择合适的调试方式：
	- ESP32 系列: OpenOCD + GDB
	- ARM 系列 (GD32/STM32): Keil Debug 或 OpenOCD
	- 8051 系列 (STC8): 串口调试 + 变量查看
.EXAMPLE
	debug-board                    # 启动调试
	debug-board -TargetPort COM8   # 指定目标串口
	debug-board -NoGdb             # 仅启动调试器（不启动GDB）
	debug-board -Mode Monitor      # 进入串口监控模式
  version: 1.0.0
#>

param(
	[string]$TargetPort,
	[switch]$NoGdb,
	[string]$Mode = 'Debug'
)

. "$PSScriptRoot\lib\common.ps1"

function Debug-Esp32 {
	param($boardConfig, $targetPort, $noGdb)

	if (-not $env:IDF_PATH) {
		Write-Host '[!] 加载 ESP-IDF 环境...' -ForegroundColor Yellow
		. "$PSScriptRoot\esp-idf-env.ps1"
	}

	$openocdDir = Join-Path $env:IDF_TOOLS_PATH 'openocd-esp32'
	$openocdExe = Get-ChildItem -Path $openocdDir -Filter 'openocd.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $openocdExe) {
		Write-Host '[X] 未找到 OpenOCD' -ForegroundColor Red
		return
	}

	$openocdPath = $openocdExe.FullName
	$scriptsDir = Join-Path (Split-Path $openocdPath) 'share\openocd\scripts'
	$openocdConfig = if ($boardConfig.OpenOcdConfig) { $boardConfig.OpenOcdConfig } else { 'board/esp32s3-builtin.cfg' }
	$gdbTarget = if ($boardConfig.GdbTarget) { $boardConfig.GdbTarget } else { 'xtensa-esp32s3-elf-gdb.exe' }

	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host "  ESP32 调试环境启动 - $($boardConfig.Name)" -ForegroundColor Cyan
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host "OpenOCD: $openocdPath" -ForegroundColor Gray
	Write-Host "配置: $openocdConfig" -ForegroundColor Gray

	$openocdArgs = @('-s', $scriptsDir, '-f', $openocdConfig)
	$port = if ($targetPort) { $targetPort } else { $boardConfig.DefaultUart }
	if ($boardConfig.OpenOcdConfig -match 'builtin') {
		$openocdArgs += '-c', "adapter serial $port"
	}

	$openocdLog = "$env:TEMP\openocd.log"
	$openocdErr = "$env:TEMP\openocd.err"
	$gdbInit = "$env:TEMP\gdbinit.txt"

	try {
		$openocdProc = Start-Process -FilePath $openocdPath -ArgumentList $openocdArgs -NoNewWindow -PassThru -RedirectStandardOutput $openocdLog -RedirectStandardError $openocdErr
		Start-Sleep -Seconds 3

		if ($openocdProc.HasExited) {
			Write-Host '[X] OpenOCD 启动失败' -ForegroundColor Red
			if (Test-Path $openocdErr) { Get-Content $openocdErr | Write-Host }
			return
		}
		Write-Host '[OK] OpenOCD 已启动' -ForegroundColor Green

		if (-not $noGdb) {
			$gdbExe = Get-ChildItem -Path $env:IDF_TOOLS_PATH -Filter $gdbTarget -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
			if (-not $gdbExe) {
				Write-Host "[X] 未找到 $gdbTarget" -ForegroundColor Red
				return
			}
			Set-Content $gdbInit "target extended-remote :3333`nset remote hardware-watchpoint-limit 2`nmon reset halt" -Encoding UTF8
			Write-Host "[OK] 启动 $gdbTarget..." -ForegroundColor Cyan
			& $gdbExe.FullName -x $gdbInit
			Remove-Item $gdbInit -ErrorAction SilentlyContinue
		}
	}
	finally {
		try { $openocdProc.Kill() } catch {}
		Remove-Item $openocdLog, $openocdErr -ErrorAction SilentlyContinue
		Write-Host '[OK] 调试环境已关闭' -ForegroundColor Green
	}
}

function Debug-Arm {
	param($boardConfig, $targetPort)

	$toolchain = if ($boardConfig.Toolchain) { $boardConfig.Toolchain } else { 'Keil ARM' }
	$port = if ($targetPort) { $targetPort } else { $boardConfig.DefaultUart }

	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host "  ARM 调试环境启动 - $($boardConfig.Name)" -ForegroundColor Cyan
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host "工具链: $toolchain" -ForegroundColor Yellow
	Write-Host "串口: $port" -ForegroundColor Yellow
	Write-Host ''

	Write-Host '[!] ARM 芯片推荐使用 Keil MDK 进行调试' -ForegroundColor Yellow
	Write-Host '请按以下步骤操作:' -ForegroundColor Gray
	Write-Host '  1. 打开 Keil MDK 工程文件' -ForegroundColor Gray
	Write-Host '  2. 点击 Debug 按钮 (Ctrl+F5)' -ForegroundColor Gray
	Write-Host '  3. 在 Debug Settings 中配置调试器:' -ForegroundColor Gray
	Write-Host '     - ST-Link Debugger (STM32)' -ForegroundColor Gray
	Write-Host '     - CMSIS-DAP Debugger (GD32)' -ForegroundColor Gray
	Write-Host '  4. 开始调试' -ForegroundColor Gray
	Write-Host ''

	$uvprojx = Get-ChildItem -Filter '*.uvprojx' -ErrorAction SilentlyContinue
	if ($uvprojx) {
		Write-Host "找到工程文件: $($uvprojx.Name)" -ForegroundColor Green
		Write-Host "是否打开？(Y/N)" -ForegroundColor Yellow
		$confirm = Read-Host
		if ($confirm -eq 'Y' -or $confirm -eq 'y') {
			Start-Process (Find-KeilUv4) $uvprojx.FullName
			Write-Host '[OK] 已打开 Keil MDK' -ForegroundColor Green
		}
	}
}

function Debug-8051 {
	param($boardConfig, $targetPort)

	$port = if ($targetPort) { $targetPort } else { $boardConfig.DefaultUart }

	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host "  8051 芯片调试环境启动 - $($boardConfig.Name)" -ForegroundColor Cyan
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host "串口: $port" -ForegroundColor Yellow
	Write-Host ''

	Write-Host '[!] 8051 芯片调试方式:' -ForegroundColor Yellow
	Write-Host ''
	Write-Host '方式一: 串口调试（推荐）' -ForegroundColor Cyan
	Write-Host '  - 使用 printf 输出调试信息' -ForegroundColor Gray
	Write-Host '  - 使用 serial-debug 工具监控' -ForegroundColor Gray
	Write-Host ''
	Write-Host '方式二: Keil C51 软件仿真' -ForegroundColor Cyan
	Write-Host '  1. 打开 Keil C51 工程' -ForegroundColor Gray
	Write-Host '  2. Debug Settings -> Simulator' -ForegroundColor Gray
	Write-Host '  3. 启动调试，查看变量和寄存器' -ForegroundColor Gray
	Write-Host ''
	Write-Host '方式三: STC-ISP 下载' -ForegroundColor Cyan
	Write-Host '  - 使用 STC-ISP 工具下载程序' -ForegroundColor Gray
	Write-Host '  - 通过串口输出查看运行结果' -ForegroundColor Gray
	Write-Host ''

	Write-Host '是否启动串口监控？(Y/N)' -ForegroundColor Yellow
	$confirm = Read-Host
	if ($confirm -eq 'Y' -or $confirm -eq 'y') {
		serial-debug $port 115200 0
	}
}

function Monitor-Serial {
	param($boardConfig, $targetPort)

	$port = if ($targetPort) { $targetPort } else { $boardConfig.DefaultUart }
	Write-Host "[OK] 启动串口监控: $port @ 115200" -ForegroundColor Cyan
	serial-debug $port 115200 0
}

$boardConfig = Get-CurrentBoard
if (-not $boardConfig) { exit }

switch ($Mode) {
	'Monitor' {
		Monitor-Serial -boardConfig $boardConfig -targetPort $TargetPort
		return
	}
}

$type = $boardConfig.Type
switch -Wildcard ($type) {
	'ESP32*' {
		Debug-Esp32 -boardConfig $boardConfig -targetPort $TargetPort -noGdb:$NoGdb
	}
	'GD32*' {
		Debug-Arm -boardConfig $boardConfig -targetPort $TargetPort
	}
	'STM32*' {
		Debug-Arm -boardConfig $boardConfig -targetPort $TargetPort
	}
	'STC8*' {
		Debug-8051 -boardConfig $boardConfig -targetPort $TargetPort
	}
	default {
		Write-Host "[!] 未支持的芯片类型: $type" -ForegroundColor Yellow
		Write-Host '请手动使用对应工具进行调试' -ForegroundColor Gray
	}
}
