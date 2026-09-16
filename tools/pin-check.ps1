<#
.SYNOPSIS
	引脚冲突检测工具 - 从 board-config 动态加载引脚数据
.DESCRIPTION
	检查指定 GPIO 引脚是否可用，检测以下两种冲突：
	1. 模组内部占用（SPI Flash/PSRAM 引脚，绝对不可用）
	2. 项目已分配引脚（已用于其他外设）
	引脚保留表从 board-config 动态加载，项目分配从 project_memory.md 动态加载。
	使用前必须确保已通过 switch-board 切换到对应板子。
.EXAMPLE
	pin-check -Pin 2      # 检查 GPIO2 是否可用
	pin-check -Pin 11     # 检查 GPIO11（预期被占用）
	pin-check -List       # 列出所有引脚状态
	pin-check -Allocate 3 "PA控制"  # 分配 GPIO3 给 PA 控制
  version: 1.0.0
#>

param(
	[int]$Pin = -1,
	[switch]$List,
	[string]$Allocate = '',
	[switch]$AutoUpdate,
	[switch]$Dedup,
	[string]$Purpose = ''
)

# ====
# 从 board-config 动态加载引脚保留表
# ====

# 导入公共函数（Get-CurrentBoard 等）
. "$PSScriptRoot\lib\common.ps1"

$board = Get-CurrentBoard
if (-not $board) {
	Write-Host '[X] 未检测到当前板子配置，请先运行 switch-board 选择板子' -ForegroundColor Red
	Write-Host '    用法: switch-board -List    # 查看可用板子' -ForegroundColor Gray
	Write-Host '          switch-board esp32-s3-wroom-1-n16r8    # 切换板子' -ForegroundColor Gray
	exit 1
}

$script:BOARD_NAME = $board.Name
$script:BOARD_TYPE = $board.Type
$script:RESERVED_PINS = @($board.ReservedPins)
$script:RESERVED_DESC = @{}
foreach ($key in $board.ReservedDesc.Keys) {
	$script:RESERVED_DESC[[int]$key] = $board.ReservedDesc[$key]
}
$script:AVAILABLE_PINS = @($board.AvailablePins)

# 项目已分配引脚：只从 project_memory.md 动态加载，不硬编码默认值
$script:ALLOCATED_PINS = @{}

# ====
# 引脚标签转换辅助函数（支持 GPIO/PA/PB/PC/PD/PE 和 P端口.位 格式）
# ====

# 引脚号 -> 引脚标签（根据板子类型）
function Get-PinLabel {
	param([int]$Pin)
	switch -Regex ($script:BOARD_TYPE) {
		'^ESP32' { return "GPIO$Pin" }
		'^(GD32|STM32)' {
			$port = [int]($Pin / 16)
			$bit = $Pin % 16
			if ($port -le 4) {
				$portName = [char](65 + $port)
				return "P$portName$bit"
			}
			return "GPIO$Pin"
		}
		'^STC8' {
			if ($Pin -le 31) {
				$port = [int]($Pin / 8)
				$bit = $Pin % 8
				return "P$port.$bit"
			} elseif ($Pin -ge 32 -and $Pin -le 35) {
				$bit = $Pin - 32
				return "P4.$bit"
			} elseif ($Pin -eq 36) {
				return "P5.4"
			}
			return "P$Pin"
		}
		default { return "GPIO$Pin" }
	}
}

# 引脚标签 -> 引脚号（支持 GPIO13/PA13/PB3/PC14/P3.0 等格式）
function Convert-PinLabelToNumber {
	param([string]$Label)
	$m = [regex]::Match($Label, '^(GPIO|PA|PB|PC|PD|PE)(\d+)$')
	if ($m.Success) {
		$prefix = $m.Groups[1].Value
		$num = [int]$m.Groups[2].Value
		switch ($prefix) {
			'GPIO' { return $num }
			'PA' { return $num }
			'PB' { return 16 + $num }
			'PC' { return 32 + $num }
			'PD' { return 48 + $num }
			'PE' { return 64 + $num }
		}
	}
	$m = [regex]::Match($Label, '^P(\d+)\.(\d+)$')
	if ($m.Success) {
		$port = [int]$m.Groups[1].Value
		$bit = [int]$m.Groups[2].Value
		if ($port -le 4) { return $port * 8 + $bit }
		if ($port -eq 5 -and $bit -eq 4) { return 36 }
	}
	return -1
}

# ====
# 从 project_memory.md 加载项目引脚分配
# ====

function Load-PinAllocationFromMemory {
	param([string]$ProjectPath)
	$memoryFile = Join-Path $ProjectPath 'project_memory.md'
	if (-not (Test-Path $memoryFile)) { return $null }
	try {
		$content = Get-Content $memoryFile -Raw -Encoding UTF8
		$allocationSection = [regex]::Match($content, '## 引脚分配表[\s\S]*?(?=\n## |\Z)')
		if ($allocationSection.Success) { return $allocationSection.Value }
	} catch {}
	return $null
}

function Remove-PinAllocationDuplicates {
	param([string]$ProjectPath)
	$memoryFile = Join-Path $ProjectPath 'project_memory.md'
	if (-not (Test-Path $memoryFile)) { return }
	try {
		$content = Get-Content $memoryFile -Raw -Encoding UTF8
		$allocationSection = [regex]::Match($content, '## 引脚分配表[\s\S]*?(?=\n## |\Z)')
		if (-not $allocationSection.Success) { return }

		$lines = $allocationSection.Value -split "`n"
		$seen = @{}
		$uniqueLines = @()
		foreach ($line in $lines) {
			$match = [regex]::Match($line, 'GPIO(\d+)')
			if ($match.Success) {
				$pin = $match.Groups[1].Value
				if (-not $seen.ContainsKey($pin)) {
					$seen[$pin] = $true
					$uniqueLines += $line
				}
			} else {
				$uniqueLines += $line
			}
		}

		$uniqueContent = $uniqueLines -join "`n"
		if ($uniqueContent -ne $allocationSection.Value) {
			$newContent = $content.Replace($allocationSection.Value, $uniqueContent)
			Set-Content $memoryFile $newContent -Encoding UTF8 -NoNewline
			Write-Host '  [OK] 已去除 project_memory.md 中的重复引脚记录' -ForegroundColor Green
		}
	} catch {
		Write-Host '  [!] 去重失败: ' $_.Exception.Message -ForegroundColor Yellow
	}
}

function Update-PinAllocationInMemory {
	param(
		[int]$TargetPin,
		[string]$UsePurpose,
		[string]$ProjectPath
	)
	$memoryFile = Join-Path $ProjectPath 'project_memory.md'
	if (-not (Test-Path $memoryFile)) {
		Write-Host '  [!] project_memory.md 不存在，跳过自动更新' -ForegroundColor Yellow
		return
	}

	try {
		$content = Get-Content $memoryFile -Raw -Encoding UTF8
		$allocationSection = [regex]::Match($content, '## 引脚分配表[\s\S]*?(?=\n## |\Z)')

		$pinLabel = Get-PinLabel -Pin $TargetPin
		if (-not $allocationSection.Success) {
			$newSection = "`n## 引脚分配表`n- $pinLabel : $UsePurpose`n"
			$content = $content.TrimEnd() + $newSection
		} else {
			$lines = $allocationSection.Value -split "`n"
			$found = $false
			$newLines = @()
			foreach ($line in $lines) {
				$labelMatch = [regex]::Match($line, '(?:GPIO|PA|PB|PC|PD|PE)\d+|P\d+\.\d+')
				if ($labelMatch.Success) {
					$linePin = Convert-PinLabelToNumber -Label $labelMatch.Value
					if ($linePin -eq $TargetPin) {
						# 保持原有标签格式，只更新用途描述
						$originalLabel = $labelMatch.Value
						$newLines += "- $originalLabel : $UsePurpose"
						$found = $true
						continue
					}
				}
				$newLines += $line
			}
			if (-not $found) {
				$newLines += "- $pinLabel : $UsePurpose"
			}
			$uniqueLines = @{}
			foreach ($line in $newLines) {
				$labelMatch = [regex]::Match($line, '(?:GPIO|PA|PB|PC|PD|PE)\d+|P\d+\.\d+')
				if ($labelMatch.Success) {
					$pin = Convert-PinLabelToNumber -Label $labelMatch.Value
					if ($pin -ge 0) {
						$uniqueLines[$pin] = $line
					} else {
						$uniqueLines[$line] = $line
					}
				} else {
					$uniqueLines[$line] = $line
				}
			}
			$newSection = ($uniqueLines.Values | Sort-Object) -join "`n"
			$content = $content.Replace($allocationSection.Value, $newSection)
		}

		# 写入前自动备份
		$backupFile = $memoryFile + '.bak'
		if (Test-Path $memoryFile) {
			Copy-Item $memoryFile $backupFile -Force
		}
		Set-Content $memoryFile $content -Encoding UTF8 -NoNewline
		# 保留最近一次备份
		if (Test-Path $backupFile) {
			Remove-Item $backupFile -Force -ErrorAction SilentlyContinue
		}
		Write-Host '  [OK] project_memory.md 已自动更新' -ForegroundColor Green
	} catch {
		Write-Host '  [!] 更新失败: ' $_.Exception.Message -ForegroundColor Yellow
	}
}

# 从 project_memory.md 加载已分配引脚
$memoryAlloc = Load-PinAllocationFromMemory -ProjectPath (Get-Location).Path
if ($memoryAlloc) {
	# 支持 GPIO13 / PA13 / PB3 / PC14 / P3.0 等多种引脚标签格式
	$matches = [regex]::Matches($memoryAlloc, '(?:((?:GPIO|PA|PB|PC|PD|PE)\d+)|(P\d+\.\d+))\s*[:：]\s*(.+)')
	foreach ($m in $matches) {
		if ($m.Groups[1].Success) {
			$pin = Convert-PinLabelToNumber -Label $m.Groups[1].Value
		} elseif ($m.Groups[2].Success) {
			$pin = Convert-PinLabelToNumber -Label $m.Groups[2].Value
		} else {
			continue
		}
		$desc = $m.Groups[3].Value.Trim()
		if ($pin -ge 0 -and $script:RESERVED_PINS -notcontains $pin) {
			$script:ALLOCATED_PINS[$pin] = $desc
			$script:AVAILABLE_PINS = $script:AVAILABLE_PINS | Where-Object { $_ -ne $pin }
		}
	}
}

# ============================================================
# 检查单个引脚
# ============================================================
function Test-Pin {
	param([int]$TargetPin)

	$pinLabel = Get-PinLabel -Pin $TargetPin
	$maxPin = ($script:AVAILABLE_PINS | Measure-Object -Maximum).Maximum
	if ($TargetPin -lt 0 -or $TargetPin -gt $maxPin) {
		# 如果保留引脚中有更大的值，也要考虑
		$maxReserved = if ($script:RESERVED_PINS.Count -gt 0) { ($script:RESERVED_PINS | Measure-Object -Maximum).Maximum } else { 0 }
		$maxPin = [Math]::Max($maxPin, $maxReserved)
		if ($TargetPin -lt 0 -or $TargetPin -gt $maxPin) {
			Write-Host "[X] $pinLabel 引脚号超出范围（0-$maxPin）" -ForegroundColor Red
			return $false
		}
	}

	if ($script:RESERVED_PINS -contains $TargetPin) {
		$desc = $script:RESERVED_DESC[$TargetPin]
		Write-Host "[X] $pinLabel 被模组内部 $desc 占用，不可使用" -ForegroundColor Red
		return $false
	}

	if ($script:ALLOCATED_PINS.ContainsKey($TargetPin)) {
		$desc = $script:ALLOCATED_PINS[$TargetPin]
		Write-Host "[!] $pinLabel 已分配给 $desc" -ForegroundColor Yellow
		Write-Host "    是否继续使用？可能导致功能冲突" -ForegroundColor Yellow
		return $false
	}

	if ($script:AVAILABLE_PINS -contains $TargetPin) {
		Write-Host "[OK] $pinLabel 可使用" -ForegroundColor Green
		return $true
	}

	Write-Host "[!] $pinLabel 状态未知，请检查硬件手册" -ForegroundColor Yellow
	return $false
}

# ============================================================
# 列出所有引脚状态
# ============================================================
function List-AllPins {
	Write-Host ''
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host "  $script:BOARD_NAME 引脚分配表" -ForegroundColor Cyan
	Write-Host '========================================' -ForegroundColor Cyan
	Write-Host ''

	Write-Host '[已占用（模组内部，绝对不可用）]' -ForegroundColor Red
	foreach ($pin in $script:RESERVED_PINS | Sort-Object) {
		$desc = $script:RESERVED_DESC[$pin]
		Write-Host "  $(Get-PinLabel -Pin $pin) - $desc" -ForegroundColor Gray
	}
	Write-Host ''

	Write-Host '[已分配（项目使用中）]' -ForegroundColor Yellow
	if ($script:ALLOCATED_PINS.Count -eq 0) {
		Write-Host '  （无，请检查 project_memory.md 是否有引脚分配表）' -ForegroundColor Gray
	} else {
		foreach ($pin in ($script:ALLOCATED_PINS.Keys | Sort-Object)) {
			$desc = $script:ALLOCATED_PINS[$pin]
			Write-Host "  $(Get-PinLabel -Pin $pin) - $desc" -ForegroundColor Yellow
		}
	}
	Write-Host ''

	Write-Host '[可使用]' -ForegroundColor Green
	foreach ($pin in $script:AVAILABLE_PINS | Sort-Object) {
		Write-Host "  $(Get-PinLabel -Pin $pin)" -ForegroundColor Green
	}
	Write-Host ''

	Write-Host '[注意]' -ForegroundColor Cyan
	switch -Regex ($script:BOARD_TYPE) {
		'^ESP32' {
			Write-Host '  - GPIO0: BOOT键，正常运行时为高电平，可复用为输入' -ForegroundColor Gray
			Write-Host '  - GPIO1/3: 串口日志 TX/RX，调试完成后可复用' -ForegroundColor Gray
			Write-Host '  - GPIO20/21: USB D-/D+，作为 USB 时不可复用' -ForegroundColor Gray
		}
		'^(GD32|STM32)' {
			Write-Host '  - PA13/PA14 为 SWD 调试接口，请勿占用' -ForegroundColor Gray
		}
		'^STC8' {
			Write-Host '  - P3.0/P3.1 为默认串口，P5.4 为复位引脚' -ForegroundColor Gray
		}
		default {
			Write-Host '  - 请参考芯片数据手册确认特殊引脚' -ForegroundColor Gray
		}
	}
	Write-Host ''
}

# ============================================================
# 分配引脚（更新 project_memory.md）
# ============================================================
function Add-PinAllocation {
	param(
		[int]$TargetPin,
		[string]$UsePurpose,
		[switch]$AutoUpdate
	)

	$pinLabel = Get-PinLabel -Pin $TargetPin
	$maxPin = ($script:AVAILABLE_PINS | Measure-Object -Maximum).Maximum
	if ($TargetPin -lt 0 -or $TargetPin -gt $maxPin) {
		# 如果保留引脚中有更大的值，也要考虑
		$maxReserved = if ($script:RESERVED_PINS.Count -gt 0) { ($script:RESERVED_PINS | Measure-Object -Maximum).Maximum } else { 0 }
		$maxPin = [Math]::Max($maxPin, $maxReserved)
		if ($TargetPin -lt 0 -or $TargetPin -gt $maxPin) {
			Write-Host "[X] $pinLabel 引脚号超出范围（0-$maxPin）" -ForegroundColor Red
			return
		}
	}

	if ($script:RESERVED_PINS -contains $TargetPin) {
		$desc = $script:RESERVED_DESC[$TargetPin]
		Write-Host "[X] $pinLabel 被 $desc 占用，无法分配" -ForegroundColor Red
		return
	}

	if ($script:ALLOCATED_PINS.ContainsKey($TargetPin)) {
		$oldDesc = $script:ALLOCATED_PINS[$TargetPin]
		Write-Host "[!] $pinLabel 已分配给 $oldDesc" -ForegroundColor Yellow
		$confirm = Read-Host "是否覆盖？(Y/N)"
		if ($confirm -ne 'Y' -and $confirm -ne 'y') {
			Write-Host '已取消' -ForegroundColor Gray
			return
		}
	}

	$script:ALLOCATED_PINS[$TargetPin] = $UsePurpose

	if ($script:AVAILABLE_PINS -contains $TargetPin) {
		$script:AVAILABLE_PINS = $script:AVAILABLE_PINS | Where-Object { $_ -ne $TargetPin }
	}

	Write-Host "[OK] $pinLabel 已分配给: $UsePurpose" -ForegroundColor Green
	Write-Host ''
	if ($AutoUpdate) {
		Update-PinAllocationInMemory -TargetPin $TargetPin -UsePurpose $UsePurpose -ProjectPath (Get-Location).Path
	} else {
		Write-Host '请手动更新 project_memory.md 中的引脚分配表，或使用 -AutoUpdate 参数自动更新' -ForegroundColor Yellow
	}

	List-AllPins
}

# ============================================================
# 主流程
# ============================================================
Write-Host '========================================' -ForegroundColor Cyan
Write-Host "  引脚冲突检测工具 v2.0 ($script:BOARD_NAME)" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

if ($List) {
	List-AllPins
	return
}

if ($Dedup) {
	Write-Host '>>> 去除 project_memory.md 中的重复引脚记录...' -ForegroundColor Cyan
	Remove-PinAllocationDuplicates -ProjectPath (Get-Location).Path
	return
}

if ($Allocate -ne '') {
	$targetPin = [int]$Allocate
	Add-PinAllocation -TargetPin $targetPin -UsePurpose $Purpose -AutoUpdate:$AutoUpdate
	return
}

if ($Pin -ge 0) {
	$ok = Test-Pin -TargetPin $Pin
	if ($ok) {
		Write-Host ''
		Write-Host '该引脚可安全使用' -ForegroundColor Green
	}
	else {
		Write-Host ''
		Write-Host '建议选择其他引脚' -ForegroundColor Yellow
		List-AllPins
	}
	return
}

Write-Host ''
Write-Host '用法:' -ForegroundColor Cyan
Write-Host '  pin-check -Pin <引脚号>           # 检查单个引脚' -ForegroundColor Gray
Write-Host '  pin-check -List                    # 列出所有引脚状态' -ForegroundColor Gray
Write-Host '  pin-check -Allocate <引脚> <用途>  # 分配引脚' -ForegroundColor Gray
Write-Host ''
Write-Host '示例:' -ForegroundColor Cyan
Write-Host '  pin-check -Pin 18                  # 检查 GPIO18' -ForegroundColor Gray
Write-Host '  pin-check -Allocate 18 "LED控制"   # 分配 GPIO18' -ForegroundColor Gray

