<#
.SYNOPSIS
	ESP-IDF v5.5.4 环境变量持久化脚本
.DESCRIPTION
	一键设置 ESP-IDF 所需的全部环境变量（IDF_PATH / IDF_TOOLS_PATH / IDF_PYTHON_ENV_PATH / PATH）。
	自动检测 Python 虚拟环境路径，解决系统 Python 版本与安装时不一致导致的环境初始化失败问题。
	每次开始 ESP32 开发前在当前 PowerShell 会话执行：. esp-idf-env.ps1
	即可在当前会话直接调用 idf.py / esptool.py / xtensa-esp-elf-gcc 等命令。
.EXAMPLE
	. esp-idf-env.ps1           # 在当前会话加载环境
	. esp-idf-env.ps1 -Check    # 加载并验证关键工具可用性
  version: 1.0.0
#>

param(
	[switch]$Check
)

# ====
# 重复加载检测
# ====
if ($env:IDF_PATH -and $env:IDF_PATH.EndsWith('esp-idf-v5.5.4')) {
	Write-Host '[!] ESP-IDF 环境已加载' -ForegroundColor Yellow
	if ($Check) { Test-IdfTools }
	return
}

# ============================================================
# ============================================================
# 基础配置（动态检测 ESP-IDF 安装路径）
# ============================================================
# 1. 优先使用环境变量
$espRoot = $env:ESP_IDF_ROOT

# 2. 候选路径列表（按优先级排序）
if (-not $espRoot) {
    $candidates = @(
        'D:\ESP32\Espressif',
        'C:\Espressif',
        'C:\esp\esp-idf-tools',
        "$env:USERPROFILE\esp\Espressif",
        "$env:USERPROFILE\.espressif"
    )
    $espRoot = $candidates | Where-Object { Test-Path "$_\frameworks\esp-idf-v5.5.4\export.ps1" } | Select-Object -First 1
}

if (-not $espRoot) {
    Write-Host '[X] 未检测到 ESP-IDF v5.5.4 安装路径' -ForegroundColor Red
    Write-Host '    请设置环境变量 ESP_IDF_ROOT 指向 Espressif 目录' -ForegroundColor Yellow
    Write-Host '    （包含 frameworks/tools/python_env 子目录）' -ForegroundColor Yellow
    return
}

$script:ESP_IDF_PATH       = "$espRoot\frameworks\esp-idf-v5.5.4"
$script:ESP_IDF_TOOLS_PATH = "$espRoot\tools"
$script:ESP_PYTHON_ENV_BASE = "$espRoot\python_env"
# ============================================================

# 默认候选虚拟环境列表（按优先级排序）
$script:PYTHON_ENV_CANDIDATES = @(
	"$script:ESP_PYTHON_ENV_BASE\idf5.5_py3.11_env",
	"$script:ESP_PYTHON_ENV_BASE\idf5.5_py3.10_env",
	"$script:ESP_PYTHON_ENV_BASE\idf5.5_py3.9_env",
	"$script:ESP_PYTHON_ENV_BASE\idf5.5_py3.8_env"
)

# ============================================================
# 自动检测 Python 虚拟环境路径
# ============================================================
function Find-PythonEnv {
	Write-Host '[0/3] 自动检测 Python 虚拟环境...' -ForegroundColor Cyan

	foreach ($candidate in $script:PYTHON_ENV_CANDIDATES) {
		$pythonExe = "$candidate\Scripts\python.exe"
		if (Test-Path $pythonExe) {
			Write-Host "  [OK] 找到 Python 环境: $candidate" -ForegroundColor Green
			return $candidate
		}
	}

	Write-Host "  [!] 未在候选路径中找到 Python 环境，尝试扫描 $script:ESP_PYTHON_ENV_BASE..." -ForegroundColor Yellow
	$envDirs = Get-ChildItem -Path $script:ESP_PYTHON_ENV_BASE -Directory -ErrorAction SilentlyContinue
	if ($envDirs) {
		foreach ($dir in $envDirs) {
			$pythonExe = "$($dir.FullName)\Scripts\python.exe"
			if (Test-Path $pythonExe) {
				Write-Host "  [OK] 扫描发现 Python 环境: $($dir.FullName)" -ForegroundColor Green
				return $dir.FullName
			}
		}
	}

	Write-Host "  [X] 未找到 Python 虚拟环境，请检查 ESP-IDF 安装" -ForegroundColor Red
	return $null
}

# ============================================================
# 自动检测工具链子路径
# ============================================================
function Find-ToolchainPaths {
	Write-Host '[0/3] 自动检测工具链子路径...' -ForegroundColor Cyan

	$script:XTENSA_BIN = Find-ToolPath "xtensa-esp-elf" "bin" $script:ESP_IDF_TOOLS_PATH
	$script:CMAKE_BIN   = Find-ToolPath "cmake" "bin" $script:ESP_IDF_TOOLS_PATH
	$script:NINJA_BIN   = Find-ToolPath "ninja" "" $script:ESP_IDF_TOOLS_PATH
	$script:PYTHON_BIN  = "$script:ESP_PYTHON_ENV_PATH\Scripts"

	Write-Host "  xtensa-esp-elf: $script:XTENSA_BIN"
	Write-Host "  cmake:          $script:CMAKE_BIN"
	Write-Host "  ninja:          $script:NINJA_BIN"
	Write-Host "  python:         $script:PYTHON_BIN"
}

function Find-ToolPath {
	param(
		[string]$ToolName,
		[string]$SubDir,
		[string]$BasePath
	)

	$searchPath = "$BasePath\$ToolName"
	if (-not (Test-Path $searchPath)) {
		Write-Host "  [!] 未找到 $ToolName 目录" -ForegroundColor Yellow
		return ""
	}

	$versions = Get-ChildItem -Path $searchPath -Directory -ErrorAction SilentlyContinue
	if (-not $versions) {
		Write-Host "  [!] $ToolName 目录为空" -ForegroundColor Yellow
		return ""
	}

	$latestVersion = $versions | Sort-Object Name -Descending | Select-Object -First 1
	$result = "$($latestVersion.FullName)"
	if ($SubDir) {
		$result = "$result\$SubDir"
	}

	if (Test-Path $result) {
		return $result
	}


	# 回退：部分工具链多一层同名目录（如 xtensa-esp-elf/<版本>/xtensa-esp-elf/bin）
	if ($SubDir) {
		$fallback = Join-Path $latestVersion.FullName (Join-Path $ToolName $SubDir)
		if (Test-Path $fallback) {
			return $fallback
		}
	}
	return ""
}

# ============================================================
# 设置环境变量（仅当前会话生效）
# ============================================================
function Set-IdfEnv {
	Write-Host '[1/3] 设置 ESP-IDF 环境变量...' -ForegroundColor Cyan
	$env:IDF_PATH            = $script:ESP_IDF_PATH
	$env:IDF_TOOLS_PATH      = $script:ESP_IDF_TOOLS_PATH
	$env:IDF_PYTHON_ENV_PATH = $script:ESP_PYTHON_ENV_PATH

	Write-Host "  IDF_PATH            = $env:IDF_PATH"
	Write-Host "  IDF_TOOLS_PATH      = $env:IDF_TOOLS_PATH"
	Write-Host "  IDF_PYTHON_ENV_PATH = $env:IDF_PYTHON_ENV_PATH"
}

# ============================================================
# 更新 PATH（追加工具链路径，避免重复）
# ============================================================
function Update-IdfPath {
	Write-Host '[2/3] 更新 PATH...' -ForegroundColor Cyan
	$pathsToAdd = @()

	if ($script:XTENSA_BIN) { $pathsToAdd += $script:XTENSA_BIN }
	if ($script:CMAKE_BIN)   { $pathsToAdd += $script:CMAKE_BIN }
	if ($script:NINJA_BIN)   { $pathsToAdd += $script:NINJA_BIN }
	if ($script:PYTHON_BIN)  { $pathsToAdd += $script:PYTHON_BIN }
	if ($env:IDF_PATH) {
		$pathsToAdd += "$env:IDF_PATH\components\esptool_py\esptool"
		$pathsToAdd += "$env:IDF_PATH\tools"
	}

	$currentPaths = $env:PATH -split ';'
	foreach ($p in $pathsToAdd) {
		if ($currentPaths -notcontains $p) {
			$env:PATH = "$p;$env:PATH"
			Write-Host "  + $p" -ForegroundColor Green
		}
		else {
			Write-Host "  = $p (已存在)" -ForegroundColor Gray
		}
	}
}

# ============================================================
# 验证关键工具
# ============================================================
function Test-IdfTools {
	Write-Host '[3/3] 验证关键工具...' -ForegroundColor Cyan

	$tools = @(
		@{ Name = 'idf.py';              Path = "$env:IDF_PATH\tools\idf.py";                  Desc = 'ESP-IDF 主入口' },
		@{ Name = 'xtensa-esp-elf-gcc';  Path = "$script:XTENSA_BIN\xtensa-esp-elf-gcc.exe";  Desc = 'Xtensa 交叉编译器' },
		@{ Name = 'cmake';               Path = "$script:CMAKE_BIN\cmake.exe";                Desc = 'CMake 构建' },
		@{ Name = 'ninja';               Path = "$script:NINJA_BIN\ninja.exe";                Desc = 'Ninja 构建器' },
		@{ Name = 'python';              Path = "$script:PYTHON_BIN\python.exe";              Desc = 'Python 解释器' },
		@{ Name = 'esptool.py';          Path = "$env:IDF_PATH\components\esptool_py\esptool\esptool.py"; Desc = 'ESP 烧录工具' }
	)

	$allOk = $true
	foreach ($t in $tools) {
		if (Test-Path $t.Path) {
			Write-Host "  [OK] $($t.Name) - $($t.Desc)" -ForegroundColor Green
		}
		else {
			Write-Host "  [X]  $($t.Name) - 缺失: $($t.Path)" -ForegroundColor Red
			$allOk = $false
		}
	}

	if (-not $allOk) {
		Write-Host ''
		Write-Host '[X] 部分工具缺失，请检查 ESP-IDF 安装路径:' -ForegroundColor Red
		Write-Host "    $env:IDF_PATH"
		return $false
	}

	try {
		$version = & python "$env:IDF_PATH\tools\idf.py" --version 2>&1 | Select-Object -First 1
		Write-Host "  ESP-IDF 版本: $version" -ForegroundColor Green
	}
	catch {
		Write-Host '  (无法读取 idf.py 版本，但不影响使用)' -ForegroundColor Yellow
	}

	return $true
}

# ============================================================
# 主流程
# ============================================================
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  ESP-IDF v5.5.4 环境加载' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

$script:ESP_PYTHON_ENV_PATH = Find-PythonEnv
if (-not $script:ESP_PYTHON_ENV_PATH) {
	Write-Host ''
	Write-Host '[X] 无法找到 Python 虚拟环境，环境加载失败' -ForegroundColor Red
	Write-Host '    请检查 ESP-IDF 是否正确安装' -ForegroundColor Yellow
	return
}

Find-ToolchainPaths

Set-IdfEnv
Update-IdfPath

if ($Check) {
	$ok = Test-IdfTools
	if ($ok) {
		Write-Host ''
		Write-Host '[OK] ESP-IDF 环境就绪，可直接使用 idf.py build / flash / monitor' -ForegroundColor Green
	}
	else {
		Write-Host ''
		Write-Host '[!] 环境加载完成但部分工具缺失，请检查路径' -ForegroundColor Yellow
	}
}
else {
	Write-Host ''
	Write-Host '[OK] ESP-IDF 环境已加载（如需验证工具可用性：. esp-idf-env.ps1 -Check）' -ForegroundColor Green
}
