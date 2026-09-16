<#
.SYNOPSIS
	ESP32 调试启动脚本
  version: 1.0.0
#>

param([string]$TargetPort=$defaultPort, [switch]$EspProg, [switch]$NoGdb)

$openocdLog = "$env:TEMP\openocd.log"
$openocdErr = "$env:TEMP\openocd.err"
$gdbInit = "$env:TEMP\gdbinit.txt"

try {
	if (-not $env:IDF_PATH) { . "$PSScriptRoot\esp-idf-env.ps1" }

	$boardConfig = $null
if ($env:CURRENT_BOARD) {
    $configPath = Join-Path $PSScriptRoot "board-config\$($env:CURRENT_BOARD).ps1"
    if (Test-Path $configPath) {
        $boardConfig = & $configPath
    }
}
$defaultPort = if ($boardConfig -and $boardConfig.DefaultUart) { $boardConfig.DefaultUart } else { 'COM8' }

$openocdDir = Join-Path $env:IDF_TOOLS_PATH 'openocd-esp32'
	$openocdExe = Get-ChildItem -Path $openocdDir -Filter 'openocd.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $openocdExe) { Write-Host '[X] 未找到 OpenOCD'; exit 1 }

	$openocdPath = $openocdExe.FullName
	$boardConfig = $null
if ($env:CURRENT_BOARD) {
    $configPath = Join-Path $PSScriptRoot "board-config\$($env:CURRENT_BOARD).ps1"
    if (Test-Path $configPath) {
        $boardConfig = & $configPath
    }
}
$openocdConfig = if ($boardConfig -and $boardConfig.OpenOcdConfig) { $boardConfig.OpenOcdConfig } else { 'board/esp32s3-builtin.cfg' }
$scriptsDir = Join-Path (Split-Path $openocdPath) 'share\openocd\scripts'

	$openocdArgs = @('-s', $scriptsDir, '-f', $openocdConfig)
	if ($EspProg) { $openocdArgs += '-c', "adapter serial $TargetPort" }

	$openocdProc = Start-Process -FilePath $openocdPath -ArgumentList $openocdArgs -NoNewWindow -PassThru -RedirectStandardOutput $openocdLog -RedirectStandardError $openocdErr
	Start-Sleep -Seconds 3

	if ($openocdProc.HasExited) {
		Write-Host '[X] OpenOCD 启动失败'
		if (Test-Path $openocdErr) { Get-Content $openocdErr | Write-Host }
		exit 1
	}
	Write-Host '[OK] OpenOCD 已启动'

	if (-not $NoGdb) {
		$gdbTarget = if ($boardConfig -and $boardConfig.GdbTarget) { $boardConfig.GdbTarget } else { xtensa-esp32s3-elf-gdb.exe }
$gdbExe = Get-ChildItem -Path $env:IDF_TOOLS_PATH -Filter $gdbTarget -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
		if (-not $gdbExe) { Write-Host '[X] 未找到 GDB'; exit 1 }
		Set-Content $gdbInit "target extended-remote :3333`nset remote hardware-watchpoint-limit 2`nmon reset halt" -Encoding UTF8
		& $gdbExe.FullName -x $gdbInit
	}
}
finally {
	try { $openocdProc.Kill() } catch {}
	Remove-Item $openocdLog, $openocdErr, $gdbInit -ErrorAction SilentlyContinue
	Write-Host '[OK] 调试环境已关闭'
}
