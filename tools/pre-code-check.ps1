<#
.SYNOPSIS
	编码前依赖检查工具 - 修改代码前必跑的前置检查
.DESCRIPTION
	整合工具链可用性、头文件存在性、引脚冲突、宏定义、NOP 内联函数、目录权限等检查项，
	在编码前一次性确认环境就绪，避免编码到一半才发现缺头文件/工具链不可用等问题。
.USAGE
	pre-code-check -ProjectDir <目录>
	pre-code-check -ProjectDir voice_assistant -Checks toolchain,header,pin,macro
	pre-code-check -ProjectDir . -All
  version: 1.0.0
#>

param(
	[Parameter(Mandatory = $true)]
	[string]$ProjectDir,

	[string]$Checks = 'all',

	[switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# 解析 Checks 参数（支持逗号分隔：toolchain,header,pin）
$script:ChecksList = @()
foreach ($c in $Checks -split ',') {
	$cTrim = $c.Trim().ToLower()
	if ('toolchain', 'header', 'pin', 'macro', 'nop', 'permission', 'all' -contains $cTrim) {
		$script:ChecksList += $cTrim
	}
}
if ($script:ChecksList.Count -eq 0) { $script:ChecksList = @('all') }

# ============================================================
# 内联必要的工具函数（避免 common.ps1 编码问题）
# ============================================================
function Write-Status {
	param(
		[string]$Message,
		[string]$Type = 'Info'
	)
	switch ($Type) {
		'Error'   { Write-Host "[X] $Message" -ForegroundColor Red }
		'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
		'Success' { Write-Host "[OK] $Message" -ForegroundColor Green }
		'Info'    { Write-Host "[*] $Message" -ForegroundColor Cyan }
		default   { Write-Host "$Message" }
	}
}
function Find-EspIdfEnvLocal {
	if ($env:IDF_PATH) { return $true }
	try {
		$envScript = Join-Path $PSScriptRoot "esp-idf-env.ps1"
		if (Test-Path $envScript) {
			. $envScript
			if ($env:IDF_PATH) { return $true }
		}
	} catch {}
	return $false
}

$ProjectDir = Resolve-Path $ProjectDir
if (-not (Test-Path $ProjectDir)) {
	Write-Status "项目目录不存在: $ProjectDir" -Type Error
	exit 2
}

$script:Issues = @()
$script:Warnings = @()
$script:PassCount = 0

function Add-Issue {
	param([string]$Msg)
	$script:Issues += $Msg
	if (-not $Quiet) { Write-Status $Msg -Type Error }
}
function Add-Warning {
	param([string]$Msg)
	$script:Warnings += $Msg
	if (-not $Quiet) { Write-Status $Msg -Type Warning }
}
function Add-Pass {
	param([string]$Msg)
	$script:PassCount++
	if (-not $Quiet) { Write-Status $Msg -Type Success }
}

# ============================================================
# 检测项目类型
# ============================================================
function Detect-ProjectType {
	$result = 'Unknown'
	# ESP-IDF
	$hasCMake = Test-Path (Join-Path $ProjectDir "CMakeLists.txt")
	$hasSdkconfig = (Test-Path (Join-Path $ProjectDir "sdkconfig")) -or
		(Test-Path (Join-Path $ProjectDir "sdkconfig.defaults"))
	if ($hasCMake -and $hasSdkconfig) {
		$result = 'ESP-IDF'
	}
	# Keil ARM
	$uvprojx = Get-ChildItem -Path $ProjectDir -Filter "*.uvprojx" -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($uvprojx) {
		$content = Get-Content $uvprojx.FullName -Raw -ErrorAction SilentlyContinue
		if ($content -match 'C51') { $result = 'Keil-C51' }
		else { $result = 'Keil-ARM' }
	}
	return $result
}

$ProjectType = Detect-ProjectType
if (-not $Quiet) {
	Write-Host ""
	Write-Host "==========================================" -ForegroundColor Cyan
	Write-Host " 编码前依赖检查" -ForegroundColor Cyan
	Write-Host "==========================================" -ForegroundColor Cyan
	Write-Status "项目目录: $ProjectDir"
	Write-Status "项目类型: $ProjectType"
	Write-Host ""
}

# ============================================================
# 1. 工具链检测
# ============================================================
function Check-Toolchain {
	if ($script:ChecksList -notcontains 'toolchain' -and $script:ChecksList -notcontains 'all') { return }
	if (-not $Quiet) { Write-Host "--- [1/6] 工具链检测 ---" -ForegroundColor White }

	switch ($ProjectType) {
		'ESP-IDF' {
			$idfOk = Find-EspIdfEnvLocal
			if ($idfOk) {
				Add-Pass "ESP-IDF 环境可用: $env:IDF_PATH"
				$pyEnv = $env:IDF_PYTHON_ENV_PATH
				if ($pyEnv -and (Test-Path $pyEnv)) {
					Add-Pass "Python 虚拟环境可用: $pyEnv"
				} else {
					Add-Warning "ESP-IDF Python 虚拟环境未设置，可能导致 idf.py 失败"
				}
			} else {
				Add-Issue "ESP-IDF 环境不可用，请先运行 . esp-idf-env.ps1"
			}
		}
		'Keil-C51' {
			$c51Path = Find-KeilC51Local
			if ($c51Path -and (Test-Path $c51Path)) {
				Add-Pass "Keil C51 编译器可用: $c51Path"
			} else {
				Add-Issue "Keil C51 编译器不可用，请检查 Keil 安装"
			}
			$uv4 = Find-KeilUv4Local
			if ($uv4) { Add-Pass "Keil UV4 可用: $uv4" }
		}
		'Keil-ARM' {
			$armcc = Find-KeilArmccLocal
			if ($armcc -and (Test-Path $armcc)) {
				Add-Pass "Keil ARMCC 编译器可用: $armcc"
			} else {
				Add-Warning "Keil ARMCC 编译器未检测到，请检查 Keil 安装（不影响命令行编译 UV4）"
			}
			$uv4 = Find-KeilUv4Local
			if ($uv4) { Add-Pass "Keil UV4 可用: $uv4" }
			else { Add-Issue "Keil UV4 不可用，无法执行命令行编译" }
		}
		default {
			Add-Warning "无法识别项目类型，跳过工具链检测"
		}
	}
	if (-not $Quiet) { Write-Host "" }
}

# ============================================================
# 2. 头文件存在性检查
# ============================================================
function Check-Headers {
	if ($script:ChecksList -notcontains 'header' -and $script:ChecksList -notcontains 'all') { return }
	if (-not $Quiet) { Write-Host "--- [2/6] 头文件存在性 ---" -ForegroundColor White }

	$cFiles = @(Get-ChildItem -Path $ProjectDir -Include "*.c" -Recurse -ErrorAction SilentlyContinue)
	if ($cFiles.Count -eq 0) {
		Add-Warning "未找到 .c 源文件，跳过头文件检查"
		if (-not $Quiet) { Write-Host "" }
		return
	}

	$includeDirs = @()
	# 常见 include 目录
	$commonInclude = @("include", "Include", "inc", "Inc", "main", "components")
	foreach ($dir in $commonInclude) {
		$full = Join-Path $ProjectDir $dir
		if (Test-Path $full) { $includeDirs += $full }
	}
	# ESP-IDF 特有 include 目录
	if ($ProjectType -eq 'ESP-IDF') {
		if ($env:IDF_PATH) {
			$idfInc = Join-Path $env:IDF_PATH "components"
			if (Test-Path $idfInc) { $includeDirs += $idfInc }
		}
	}
	# 递归查找所有含 .h 的目录
	$allDirsWithH = Get-ChildItem -Path $ProjectDir -Include "*.h" -Recurse -ErrorAction SilentlyContinue |
		ForEach-Object { $_.DirectoryName } | Select-Object -Unique
	$includeDirs = ($includeDirs + $allDirsWithH) | Select-Object -Unique

	$missing = @{}
	foreach ($cFile in $cFiles) {
		$lines = Get-Content $cFile.FullName -ErrorAction SilentlyContinue
		foreach ($line in $lines) {
			if ($line -match '^\s*#\s*include\s+[<"]([^>"]+)[>"]') {
				$hdr = $matches[1]
				# 过滤标准 C 库头文件
				if ($hdr -match '^(stdio|stdlib|string|stdint|stdbool|stddef|math|ctype|time|assert|errno|setjmp|signal|stdarg|limits|float|inttypes|wchar|locale|wctype|complex|tgmath|fenv|stdatomic|threads|uchar)\.h$') {
					continue
				}
				# 过滤 ESP-IDF 组件头文件（由 idf.py 构建系统保证存在）
				if ($hdr -match '^(esp_|freertos/|driver/|hal/|soc/|components/|nvs|unity|cmock|mbedtls/|lwip/|esp_rom/|esp_timer|esp_event|esp_netif|esp_wifi|esp_http|esp_mqtt|bootloader|esp_partition|esp_system|esp_ipc|spi_flash|esp_flash|esp_hw_support|esp_common|newlib|xtensa/|riscv/)') {
					continue
				}
				# 过滤常见第三方库头（由构建系统管理）
				if ($hdr -match '^(cJSON|jsmn|core2forAWS|mongoose|heatshrink|miniz|tjpgd|pmap|quirc|sh2lib|coap|expat|lz4|zlib|png|jpeg|tinyusb|tinyproto|nanopb|protobuf-c)') {
					continue
				}
				# 查是否存在
				$found = $false
				foreach ($incDir in $includeDirs) {
					$candidate = Join-Path $incDir $hdr
					if (Test-Path $candidate) { $found = $true; break }
				}
				if (-not $found) {
					if (-not $missing.ContainsKey($hdr)) {
						$missing[$hdr] = @()
					}
					$missing[$hdr] += $cFile.Name
				}
			}
		}
	}

	if ($missing.Count -eq 0) {
		Add-Pass "项目内引用的头文件均已找到（共扫描 $($cFiles.Count) 个 .c 文件）"
	} else {
		$count = 0
		foreach ($hdr in $missing.Keys) {
			$usedBy = ($missing[$hdr] | Select-Object -Unique) -join ', '
			Add-Issue "找不到头文件 '$hdr'（被 $usedBy 引用）"
			$count++
			if ($count -ge 15) {
				Add-Warning "还有 $($missing.Count - $count) 个头文件缺失，省略显示"
				break
			}
		}
	}
	if (-not $Quiet) { Write-Host "" }
}

# ============================================================
# 3. 引脚冲突检测
# ============================================================
function Check-PinConflict {
	if ($script:ChecksList -notcontains 'pin' -and $script:ChecksList -notcontains 'all') { return }
	if (-not $Quiet) { Write-Host "--- [3/6] 引脚冲突检测 ---" -ForegroundColor White }

	# 仅 ESP32 项目做引脚检查（其他架构可后续扩展）
	if ($ProjectType -ne 'ESP-IDF') {
		Add-Warning "非 ESP-IDF 项目，跳过引脚冲突检测"
		if (-not $Quiet) { Write-Host "" }
		return
	}

	# 检查 pin-check 工具是否存在
	$pinCheck = Join-Path $PSScriptRoot "pin-check.ps1"
	if (-not (Test-Path $pinCheck)) {
		Add-Warning "pin-check.ps1 工具不存在，跳过引脚检测"
		if (-not $Quiet) { Write-Host "" }
		return
	}

	# 从 project_memory 读已分配引脚（简单 grep 模式）
	$pinUsage = @{}
	$cAndH = Get-ChildItem -Path $ProjectDir -Include "*.c", "*.h" -Recurse -ErrorAction SilentlyContinue
	foreach ($f in $cAndH) {
		$lines = Get-Content $f.FullName -ErrorAction SilentlyContinue
		foreach ($line in $lines) {
			# 匹配 GPIO_PIN(xx) 或 GPIO_NUM_xx 或 #define XXX_GPIO xx
			if ($line -match 'GPIO_PIN\s*\(\s*(\d+)\s*\)') {
				$pin = [int]$matches[1]
				if (-not $pinUsage.ContainsKey($pin)) { $pinUsage[$pin] = @() }
				$pinUsage[$pin] += "$($f.Name):$($line.Trim())"
			}
			if ($line -match 'GPIO_NUM_(\d+)') {
				$pin = [int]$matches[1]
				if (-not $pinUsage.ContainsKey($pin)) { $pinUsage[$pin] = @() }
				$pinUsage[$pin] += "$($f.Name):$($line.Trim())"
			}
			if ($line -match '^\s*#\s*define\s+\S+_GPIO\s+(\d+)') {
				$pin = [int]$matches[1]
				if (-not $pinUsage.ContainsKey($pin)) { $pinUsage[$pin] = @() }
				$pinUsage[$pin] += "$($f.Name):$($line.Trim())"
			}
			if ($line -match '^\s*#\s*define\s+\S+_PIN\s+(\d+)') {
				$pin = [int]$matches[1]
				if (-not $pinUsage.ContainsKey($pin)) { $pinUsage[$pin] = @() }
				$pinUsage[$pin] += "$($f.Name):$($line.Trim())"
			}
		}
	}

	$conflicts = 0
	foreach ($pin in ($pinUsage.Keys | Sort-Object { [int]$_ })) {
		$usages = $pinUsage[$pin] | Select-Object -Unique
		if ($usages.Count -gt 1) {
			Add-Issue "GPIO$pin 被分配给多个用途:"
			foreach ($u in $usages) { Add-Issue "  -> $u" }
			$conflicts++
		}
	}

	# 调用 pin-check 列出模组保留引脚
	$reserved = & $pinCheck -List -Quiet 2>$null | Out-String
	if ($LASTEXITCODE -eq 0 -and $reserved -match '不可用|禁止使用') {
		$reservedPins = @()
		if ($reserved -match 'GPIO\s*(\d+)') {
			# 简化：如果检测到模组有保留引脚，与已用引脚对比
			foreach ($pin in $pinUsage.Keys) {
				# ESP32-S3 WROOM-1 模组常用保留引脚（裸片除外，这里仅做警告）
				if ($pin -ge 26 -and $pin -le 33) {
					Add-Warning "GPIO$pin 位于模组保留引脚范围（26-33），如使用 WROOM-1 模组请确认硬件连接"
				}
			}
		}
	}

	if ($conflicts -eq 0 -and $pinUsage.Count -gt 0) {
		Add-Pass "未检测到 GPIO 引脚冲突（共发现 $($pinUsage.Count) 个引脚使用定义）"
	} elseif ($pinUsage.Count -eq 0) {
		Add-Warning "未找到任何 GPIO 引脚定义（可能未使用 GPIO 命名宏）"
	}
	if (-not $Quiet) { Write-Host "" }
}

# ============================================================
# 4. 宏定义验证
# ============================================================
function Check-Macros {
	if ($script:ChecksList -notcontains 'macro' -and $script:ChecksList -notcontains 'all') { return }
	if (-not $Quiet) { Write-Host "--- [4/6] 宏定义与魔法数检测 ---" -ForegroundColor White }

	$allCFiles = Get-ChildItem -Path $ProjectDir -Include "*.c" -Recurse -ErrorAction SilentlyContinue
	$allHFiles = Get-ChildItem -Path $ProjectDir -Include "*.h" -Recurse -ErrorAction SilentlyContinue
	$allFiles = @($allCFiles) + @($allHFiles)
	if ($allFiles.Count -eq 0) {
		Add-Warning "未找到 .c/.h 文件，跳过宏定义检查"
		if (-not $Quiet) { Write-Host "" }
		return
	}

	$magicCount = 0
	foreach ($f in $allFiles) {
		$lines = Get-Content $f.FullName -ErrorAction SilentlyContinue
		$lineNum = 0
		foreach ($line in $lines) {
			$lineNum++
			# 跳过注释行（粗略）
			if ($line -match '^\s*//') { continue }
			if ($line -match '^\s*\*') { continue }
			# 跳过 #define / #include / #pragma 行
			if ($line -match '^\s*#\s*(define|include|pragma|if|ifdef|ifndef|endif)') { continue }
			# 跳过枚举值（0x 开头的十六进制、十进制数，枚举中通常可接受）
			# 检测 if/while/for 条件里的裸数字（魔法数）
			if ($line -match '(if|while|for|switch)\s*\([^)]*\b(\d{2,}|0x[0-9a-fA-F]{2,})\b[^)]*\)') {
				$num = $matches[2]
				# 排除 0/1/2 这类常见值（过于严格会噪音大）
				if ($num -ne '0' -and $num -ne '1' -and $num -ne '2' -and -not [string]::IsNullOrEmpty($num)) {
					if ($magicCount -lt 20) {
						Add-Warning "疑似魔法数（请改为宏定义）: $($f.Name):$lineNum -> $num in '$($line.Trim().Substring(0, [Math]::Min(80, $line.Trim().Length)))'"
					}
					$magicCount++
				}
			}
		}
	}

	# 复杂宏括号保护检查（简单规则：带参数的宏必须有多层括号）
	$badMacroCount = 0
	foreach ($f in $allHFiles) {
		$lines = Get-Content $f.FullName -ErrorAction SilentlyContinue
		$lineNum = 0
		foreach ($line in $lines) {
			$lineNum++
			if ($line -match '^\s*#\s*define\s+\w+\s*\(') {
				# 带参数的宏
				# 简单检查：如果右侧含有运算符号且最外层没 ()
				$after = $line -replace '^\s*#\s*define\s+\w+\s*\([^)]*\)\s*', ''
				if ($after -match '[\*\+\-\/\&\|]' -and $after -notmatch '^\s*\(.*\)\s*$') {
					if ($badMacroCount -lt 10) {
						Add-Warning "宏参数缺少括号保护（建议加 ()）: $($f.Name):$lineNum -> $($line.Trim())"
					}
					$badMacroCount++
				}
			}
		}
	}

	if ($magicCount -gt 0 -or $badMacroCount -gt 0) {
		$summary = "发现 $magicCount 处疑似魔法数，$badMacroCount 处宏括号不规范"
		if ($magicCount -eq 0 -and $badMacroCount -eq 0) {
			Add-Pass $summary
		} else {
			Add-Warning $summary
		}
	} else {
		Add-Pass "未发现明显的魔法数和宏括号问题"
	}
	if (-not $Quiet) { Write-Host "" }
}

# ============================================================
# 5. NOP 内联函数检查
# ============================================================
function Check-NopInline {
	if ($script:ChecksList -notcontains 'nop' -and $script:ChecksList -notcontains 'all') { return }
	if (-not $Quiet) { Write-Host "--- [5/6] NOP 内联函数检查 ---" -ForegroundColor White }

	$allFiles = @(Get-ChildItem -Path $ProjectDir -Include "*.c", "*.h" -Recurse -ErrorAction SilentlyContinue)
	if ($allFiles.Count -eq 0) {
		if (-not $Quiet) { Write-Host "" }
		return
	}

	$hasNopDef = $false
	$usesNop = $false
	foreach ($f in $allFiles) {
		$lines = Get-Content $f.FullName -ErrorAction SilentlyContinue
		foreach ($line in $lines) {
			if ($line -match 'NOP\s*\(\s*\)' -or $line -match '__NOP\s*\(\s*\)' -or
				$line -match 'asm\s*\(\s*["'']nop["'']' -or $line -match 'asm\s+volatile\s*\(\s*["'']nop["'']') {
				$usesNop = $true
			}
			if ($line -match '^\s*(static\s+)?__INLINE|^\s*(static\s+)?inline' -and $line -match 'nop') {
				$hasNopDef = $true
			}
			if ($line -match '^\s*#\s*define\s+(_+NOP|NOP)\s*\(') {
				$hasNopDef = $true
			}
		}
	}

	if ($usesNop) {
		if ($hasNopDef) {
			Add-Pass "检测到 NOP 定义且代码有使用 NOP"
		} else {
			Add-Issue "代码中使用了 NOP/__NOP 但未找到 NOP 宏/内联函数定义，请检查是否遗漏头文件"
		}
	} else {
		Add-Warning "未检测到 NOP 相关使用（如无需延时循环可忽略）"
	}
	if (-not $Quiet) { Write-Host "" }
}

# ============================================================
# 6. 目录权限检查
# ============================================================
function Check-Permission {
	if ($script:ChecksList -notcontains 'permission' -and $script:ChecksList -notcontains 'all') { return }
	if (-not $Quiet) { Write-Host "--- [6/6] 目录读写权限 ---" -ForegroundColor White }

	# 尝试写测试文件
	$testFile = Join-Path $ProjectDir ".write_test_$(Get-Random)"
	try {
		[System.IO.File]::WriteAllText($testFile, "test")
		Remove-Item $testFile -Force -ErrorAction SilentlyContinue
		Add-Pass "项目目录有读写权限"
	} catch {
		Add-Issue "项目目录无写权限，无法编译/生成文件: $_"
	}

	# 检查 sandbox.json（如果有）
	$sbFile = Join-Path $ProjectDir "sandbox.json"
	if (Test-Path $sbFile) {
		Add-Warning "存在 sandbox.json，修改外部目录前请确认权限"
	}

	# build 目录（如存在）
	$buildDir = Join-Path $ProjectDir "build"
	if (Test-Path $buildDir) {
		try {
			$testFile2 = Join-Path $buildDir ".write_test_$(Get-Random)"
			[System.IO.File]::WriteAllText($testFile2, "test")
			Remove-Item $testFile2 -Force -ErrorAction SilentlyContinue
			Add-Pass "build 目录有读写权限"
		} catch {
			Add-Warning "build 目录无写权限，可能需先清理或重新生成"
		}
	}
	if (-not $Quiet) { Write-Host "" }
}

# ============================================================
# 主流程
# ============================================================
Check-Toolchain
Check-Headers
Check-PinConflict
Check-Macros
Check-NopInline
Check-Permission

# 汇总
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 检查汇总" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  通过项: $script:PassCount" -ForegroundColor Green
Write-Host "  警告数: $($script:Warnings.Count)" -ForegroundColor Yellow
Write-Host "  错误数: $($script:Issues.Count)" -ForegroundColor Red
Write-Host ""

if ($script:Issues.Count -gt 0) {
	Write-Host "[X] 发现 $($script:Issues.Count) 个错误，请先修复后再开始编码" -ForegroundColor Red
	exit 1
} elseif ($script:Warnings.Count -gt 0) {
	Write-Host "[!] 通过，但有 $($script:Warnings.Count) 个警告建议处理" -ForegroundColor Yellow
	exit 0
} else {
	Write-Host "[OK] 所有检查通过，可以开始编码" -ForegroundColor Green
	exit 0
}
