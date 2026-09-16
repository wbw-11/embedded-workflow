<#
.SYNOPSIS
	板子状态持久化 - 解决 CURRENT_BOARD 环境变量多会话冲突
.DESCRIPTION
	将当前板子配置保存到文件，所有 PowerShell 会话共享
.EXAMPLE
	. "$PSScriptRoot\lib\board-state.ps1"
	Save-BoardState -BoardName 'esp32-s3-wroom-1-n16r8'
	$currentBoard = Load-BoardState
#>

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
			PID = $PID
		}
		
		$state | ConvertTo-Json | Set-Content $boardStateFile -Encoding UTF8
		$env:CURRENT_BOARD = $BoardName
		Write-Host "[OK] 板子状态已保存: $BoardName" -ForegroundColor Green
	} catch {
		Write-Host "[!] 保存板子状态失败: $($_.Exception.Message)" -ForegroundColor Yellow
	}
}

function Load-BoardState {
	try {
		if (Test-Path $boardStateFile) {
			$state = Get-Content $boardStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
			$env:CURRENT_BOARD = $state.BoardName
			return $state.BoardName
		}
	} catch {
		Write-Host "[!] 加载板子状态失败: $($_.Exception.Message)" -ForegroundColor Yellow
	}
	return $null
}

function Clear-BoardState {
	try {
		if (Test-Path $boardStateFile) {
			Remove-Item $boardStateFile -Force
		}
		$env:CURRENT_BOARD = $null
		Write-Host '[OK] 板子状态已清除' -ForegroundColor Green
	} catch {
		Write-Host "[!] 清除板子状态失败: $($_.Exception.Message)" -ForegroundColor Yellow
	}
}

Export-ModuleMember -Function Save-BoardState, Load-BoardState, Clear-BoardState
