<#
.SYNOPSIS
	板子连接监控 - 自动检测板子连接并切换配置
.DESCRIPTION
	后台监控 USB 设备变化，检测到新板子连接时自动切换配置
.EXAMPLE
	watch-board              # 启动监控（前台运行）
	watch-board -Background  # 后台运行
	watch-board -Stop        # 停止监控
  version: 1.0.0
#>

param(
	[switch]$Background,
	[switch]$Stop
)

$pidFile = Join-Path $env:TEMP 'watch-board.pid'
$boardStateFile = Join-Path $env:LOCALAPPDATA 'trae-tools\current-board.txt'

function Save-BoardState {
	param([string]$BoardName)
	
	try {
		$stateDir = Split-Path $boardStateFile -Parent
		if (-not (Test-Path $stateDir)) {
			New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
		}
		
		$state = @{
			BoardName = $BoardName
			SavedTime = (Get-Date).ToString('o')
		}
		$state | ConvertTo-Json | Set-Content $boardStateFile -Encoding UTF8
		$env:CURRENT_BOARD = $BoardName
	} catch {}
}

if ($Stop) {
	if (Test-Path $pidFile) {
		$pid = Get-Content $pidFile -Raw -Encoding UTF8
		try {
			Stop-Process -Id $pid -Force -ErrorAction Stop
			Remove-Item $pidFile -Force
			Write-Host '[OK] 监控已停止' -ForegroundColor Green
		} catch {
			Write-Host '[X] 停止失败' -ForegroundColor Red
		}
	} else {
		Write-Host '[!] 未找到监控进程' -ForegroundColor Yellow
	}
	exit
}

if ($Background) {
	Start-Process powershell -ArgumentList "-Command `"& '$PSCommandPath'`"" -WindowStyle Hidden
	$PID | Set-Content $pidFile -Encoding UTF8
	Write-Host '[OK] 监控已在后台启动' -ForegroundColor Green
	Write-Host '使用 watch-board -Stop 停止' -ForegroundColor Gray
	exit
}

try {
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host '  板子连接监控 v1.0' -ForegroundColor Cyan
	Write-Host '  按 Ctrl+C 停止监控' -ForegroundColor Cyan
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host ''
	
	$lastPorts = @()
	$boardConfigDir = Join-Path $PSScriptRoot 'board-config'
	
	while ($true) {
		$currentPorts = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
		
		$newPorts = Compare-Object $lastPorts $currentPorts | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -ExpandProperty InputObject
		$removedPorts = Compare-Object $lastPorts $currentPorts | Where-Object { $_.SideIndicator -eq '<=' } | Select-Object -ExpandProperty InputObject
		
		if ($newPorts) {
			$time = Get-Date -Format 'HH:mm:ss'
			Write-Host "[$time] 检测到新串口: $($newPorts -join ', ')" -ForegroundColor Green
			
			foreach ($port in $newPorts) {
				Start-Sleep -Seconds 1
				
				try {
					$pnpDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
						Where-Object { $_.Caption -match '\(COM\d+\)' }
					
					foreach ($dev in $pnpDevices) {
						if ($dev.Caption -match '\(COM(\d+)\)') {
							$portName = "COM$($matches[1])"
							if ($portName -eq $port) {
								$chipType = 'Unknown'
								if ($dev.Caption -match 'CH340|CH341') { $chipType = 'CH340/CH341' }
								elseif ($dev.Caption -match 'CP210') { $chipType = 'CP210x' }
								elseif ($dev.Caption -match 'FT232') { $chipType = 'FTDI' }
								elseif ($dev.Caption -match 'J-Link') { $chipType = 'J-Link' }
								elseif ($dev.Caption -match 'ST-Link') { $chipType = 'ST-Link' }
								
								Write-Host "  $port -> $chipType" -ForegroundColor Yellow
								
								if (Test-Path $boardConfigDir) {
									Get-ChildItem -Path $boardConfigDir -Filter '*.ps1' | ForEach-Object {
										$configName = $_.BaseName
										try {
											$config = & $_.FullName
											if ($config.DefaultUart -eq $port) {
												Write-Host "  自动切换到: $configName" -ForegroundColor Green
												Save-BoardState -BoardName $configName
											}
										} catch {}
									}
								}
							}
						}
					}
				} catch {
					Write-Host "  无法识别 $port" -ForegroundColor Gray
				}
			}
		}
		
		if ($removedPorts) {
			$time = Get-Date -Format 'HH:mm:ss'
			Write-Host "[$time] 串口断开: $($removedPorts -join ', ')" -ForegroundColor Yellow
		}
		
		$lastPorts = $currentPorts
		Start-Sleep -Seconds 2
	}
} finally {
	if (Test-Path $pidFile) {
		$pidContent = Get-Content $pidFile -Raw -Encoding UTF8
		if ($pidContent -eq $PID) {
			Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
		}
	}
	Write-Host ''
	Write-Host '[OK] 监控已停止' -ForegroundColor Green
}
