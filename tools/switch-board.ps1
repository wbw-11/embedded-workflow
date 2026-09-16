<#
.SYNOPSIS
	板子配置切换工具
.DESCRIPTION
	切换当前使用的板子配置，所有工具会自动读取当前配置
.EXAMPLE
	switch-board esp32-s3-wroom-1-n16r8   # 切换到指定板子
	switch-board -Current                   # 查看当前板子
	switch-board -List                      # 列出所有可用板子
  version: 1.0.0
#>

param(
	[string]$BoardName,
	[switch]$Current,
	[switch]$List
)

$configDir = Join-Path $PSScriptRoot 'board-config'
$boardStateFile = Join-Path $env:LOCALAPPDATA 'trae-tools\current-board.txt'

function Get-BoardConfigs {
	if (-not (Test-Path $configDir)) {
		Write-Host '[!] 板子配置目录不存在' -ForegroundColor Yellow
		return @()
	}
	
	$configs = @()
	Get-ChildItem -Path $configDir -Filter '*.ps1' | ForEach-Object {
		try {
			$config = & $_.FullName
			$configs += @{
				File = $_.BaseName
				Name = $config.Name
				Type = $config.Type
				Flash = $config.FlashSize
			}
		} catch {
			Write-Host "[!] 加载配置失败: $($_.Name)" -ForegroundColor Yellow
		}
	}
	return $configs
}

function Load-CurrentBoard {
	try {
		if (Test-Path $boardStateFile) {
			$state = Get-Content $boardStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
			$env:CURRENT_BOARD = $state.BoardName
			return $state.BoardName
		}
	} catch {}
	return $null
}

function Save-CurrentBoard {
	param([string]$Name)
	
	try {
		$stateDir = Split-Path $boardStateFile -Parent
		if (-not (Test-Path $stateDir)) {
			New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
		}
		
		$state = @{
			BoardName = $Name
			SavedTime = (Get-Date).ToString('o')
		}
		$state | ConvertTo-Json | Set-Content $boardStateFile -Encoding UTF8
		$env:CURRENT_BOARD = $Name
	} catch {
		Write-Host "[!] 保存状态失败: $($_.Exception.Message)" -ForegroundColor Yellow
	}
}

try {
	if ($List) {
		$configs = Get-BoardConfigs
		if ($configs.Count -eq 0) {
			Write-Host '[!] 没有可用的板子配置' -ForegroundColor Yellow
			exit 1
		}
		
		Write-Host '可用板子:' -ForegroundColor Cyan
		foreach ($cfg in $configs) {
			Write-Host "  $($cfg.File) -> $($cfg.Name)" -ForegroundColor White
		}
		exit 0
	}
	
	if ($Current) {
		$current = Load-CurrentBoard
		if ($current) {
			Write-Host "当前板子: $current" -ForegroundColor Green
			
			$configPath = Join-Path $configDir "$current.ps1"
			if (Test-Path $configPath) {
				$config = & $configPath
				Write-Host "类型: $($config.Type)" -ForegroundColor Gray
				Write-Host "Flash: $($config.FlashSize)" -ForegroundColor Gray
				if ($config.PsramSize) {
					Write-Host "PSRAM: $($config.PsramSize)" -ForegroundColor Gray
				}
				Write-Host "晶振: $($config.CrystalFreq)" -ForegroundColor Gray
				Write-Host "串口: $($config.DefaultUart)" -ForegroundColor Gray
			}
		} else {
			Write-Host '[!] 当前未设置板子' -ForegroundColor Yellow
			Write-Host '使用 switch-board <板子名> 切换' -ForegroundColor Gray
		}
		exit 0
	}
	
	if ($BoardName) {
		$configs = Get-BoardConfigs
		$matched = $configs | Where-Object { $_.File -eq $BoardName -or $_.Name -eq $BoardName }
		
		if (-not $matched) {
			Write-Host "[!] 未找到板子: $BoardName" -ForegroundColor Red
			Write-Host '使用 switch-board -List 查看所有可用板子' -ForegroundColor Gray
			exit 1
		}
		
		$matchedFile = $matched.File
		Save-CurrentBoard -Name $matchedFile
		
		Write-Host ''
		Write-Host '========================================' -ForegroundColor Green
		Write-Host "  已切换到: $($matched.Name)" -ForegroundColor Green
		Write-Host '========================================' -ForegroundColor Green
		Write-Host "类型: $($matched.Type)" -ForegroundColor Gray
		Write-Host "Flash: $($matched.Flash)" -ForegroundColor Gray
		Write-Host ''
		exit 0
	}
	
	# 默认显示帮助
	Write-Host ''
	Write-Host '板子配置切换工具' -ForegroundColor Cyan
	Write-Host ''
	Write-Host '用法:' -ForegroundColor Yellow
	Write-Host '  switch-board <板子名>    # 切换到指定板子' -ForegroundColor Gray
	Write-Host '  switch-board -Current    # 查看当前板子' -ForegroundColor Gray
	Write-Host '  switch-board -List       # 列出所有板子' -ForegroundColor Gray
	Write-Host ''
} catch {
	Write-Host "[X] 执行失败: $($_.Exception.Message)" -ForegroundColor Red
	exit 1
}
