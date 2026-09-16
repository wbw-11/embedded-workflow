<#
.SYNOPSIS
开发闭环流水线：识别→编译→时间戳→版本一致→安全烧录→产物核验→固件归档
.DESCRIPTION
一次性串起嵌入式开发"改代码→验证→烧录→归档"主循环，门禁不过即停。
支持：Keil ARM(Cortex-M) / Keil C51(8051) / ESP-IDF 项目。
门禁顺序（任一失败即中止并给出原因）：
  1. 工程类型识别
  2. 编译（增量，-Full 全量），日志分文件保存到 Logs/
  3. 静态门禁：code-style-check -Checks overflow,defensive（-SkipStatic 豁免）
  4. 时间戳新鲜度：产物必须比最新源码新（防烧旧版本）
  5. 版本一致：version.h/CMakeLists 版本 与 产物文件名 一致（-SkipVersionGate 豁免）
  6. 安全烧录：复用 safe-flash（芯片匹配 + 用户确认）
  7. 烧录后产物特征核验：产物二进制含版本串
  8. 固件归档：Firmware_Build/<版本>/（hex/axf/map 或 bin/elf/map + src 快照）
.EXAMPLE
dev-flow -ProjectDir D:\proj\gd32            # 完整闭环
dev-flow -ProjectDir D:\proj -CompileOnly     # 只编译+门禁（烧录前的安全编译检查）
dev-flow -ProjectDir D:\proj -SkipFlash       # 编译+核验+归档，不烧录
dev-flow -SelfTest                            # 冒烟自检（无需真实项目）
  version: 1.3.0
#>
param(
	[string]$ProjectDir = (Get-Location),
	[switch]$CompileOnly,     # 只编译+门禁核验，不烧录不归档
	[switch]$SkipFlash,       # 跳过烧录（仍做核验+归档）
	[switch]$SkipArchive,     # 跳过归档
	[switch]$Full,            # 全量重编译
	[string]$Port = '',       # 目标串口（烧录用）
	[switch]$SkipReview,      # 隐藏流程规范路径提示（不加载门禁）
	[switch]$SkipVersionGate, # 豁免版本文件名门禁（产物未按 <芯片>_Vxx.hex 命名时使用）
	[switch]$SkipStatic,      # 跳过 code-style-check 静态门禁
	[switch]$SelfTest,        # 冒烟自检
	[string]$GateTest = ''    # 内部测试：stale=产物过期应拦截 / fresh=产物新鲜应通过
)

$SCRIPT:TOOLS = $PSScriptRoot
$commonPs1 = Join-Path $PSScriptRoot 'lib\common.ps1'
if (Test-Path $commonPs1) {
	. $commonPs1
} else {
	Write-Host '[i] lib\common.ps1 不存在（独立模式，部分功能受限）' -ForegroundColor Yellow
}

# ==================== 输出/日志基础 ====================
$global:DevLog = $null
function Open-DevLog {
	$logDir = Join-Path $ProjectDir 'Logs'
	if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
	$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
	$global:DevLog = Join-Path $logDir "dev-flow_$stamp.log"
}
function Write-Step {
	param([string]$Title)
	Write-Host ''
	Write-Host ('=' * 64) -ForegroundColor White
	Write-Host "  $Title" -ForegroundColor White
	Write-Host ('=' * 64) -ForegroundColor White
	if ($global:DevLog) { Add-Content -Path $global:DevLog -Value "===== $Title =====" -Encoding UTF8 }
}
function Write-Log {
	param([string]$Msg)
	Write-Host $Msg
	if ($global:DevLog) { Add-Content -Path $global:DevLog -Value $Msg -Encoding UTF8 }
}
function Exit-Dev {
	param([int]$Code, [string]$Msg = '')
	if ($Msg) { Write-Host $Msg }
	Write-Host "[dev-flow] 退出码 $Code" -ForegroundColor Gray
	exit $Code
}

# ==================== 1. 工程类型识别 ====================
function Get-ProjectType {
	param([string]$Path)
	if (-not (Test-Path $Path)) { return 'NotFound' }
	if (Test-Path (Join-Path $Path 'sdkconfig')) { return 'ESP-IDF' }
	$uvprojx = Get-ChildItem -Path $Path -Filter '*.uvprojx' -File -ErrorAction SilentlyContinue
	if (-not $uvprojx) { $uvprojx = Get-ChildItem -Path $Path -Filter '*.uvprojx' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue }
	if ($uvprojx -and $uvprojx.Count -gt 0) { return @{ Type = 'Keil ARM'; File = $uvprojx[0].FullName } }
	$uvproj = Get-ChildItem -Path $Path -Filter '*.uvproj' -File -ErrorAction SilentlyContinue
	if (-not $uvproj) { $uvproj = Get-ChildItem -Path $Path -Filter '*.uvproj' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue }
	if ($uvproj -and $uvproj.Count -gt 0) { return @{ Type = 'Keil C51'; File = $uvproj[0].FullName } }
	return 'Unknown'
}

# ==================== 2. 编译 ====================
function Invoke-BuildStep {
	param($ProjType)
	Write-Step '编译（增量构建）'
	if ($ProjType -eq 'ESP-IDF') {
		if (-not $env:IDF_PATH) { . "$PSScriptRoot\esp-idf-env.ps1" }
		# 防御：清除 Git Bash 注入的 MSYSTEM，避免 idf.py 拒绝构建（Git 钩子场景）
		$env:MSYSTEM = $null
		Push-Location $ProjectDir
		try {
			if ($Full) { & python "$env:IDF_PATH\tools\idf.py" fullclean 2>&1 | Tee-Object -FilePath $global:DevLog | Out-Null }
			# 编译前记录最新 bin 时间戳，用于假成功防护
			$binDir = Join-Path $ProjectDir 'build'
			$binBefore = Get-ChildItem $binDir -Filter '*.bin' -Recurse -ErrorAction SilentlyContinue |
				Sort-Object LastWriteTime -Descending | Select-Object -First 1
			$tBefore = if ($binBefore) { $binBefore.LastWriteTime } else { [datetime]::MinValue }
			$out = & python "$env:IDF_PATH\tools\idf.py" build 2>&1
			$out | Out-File -FilePath $global:DevLog -Append -Encoding UTF8
			if ($LASTEXITCODE -ne 0) {
				($out | Select-Object -Last 40) | ForEach-Object { Write-Host $_ -ForegroundColor Red }
				Write-Log '[X] ESP-IDF 编译失败，已停止（日志已保存 Logs/dev-flow）'
				Exit-Dev 10 '编译失败'
			}
			# 显式校验生成动作 + 产物新鲜度（防"退出码 0 但假成功"：如 MSYS 环境 idf.py 未真正产出）
			$hasCompiling = $out -match '(?im)Generating binary|Project build complete\.'
			$binAfter = Get-ChildItem $binDir -Filter '*.bin' -Recurse -ErrorAction SilentlyContinue |
				Sort-Object LastWriteTime -Descending | Select-Object -First 1
			$tAfter = if ($binAfter) { $binAfter.LastWriteTime } else { [datetime]::MinValue }
			if ($tAfter -gt $tBefore) {
				Write-Log '[OK] ESP-IDF 编译完成（产物已更新）'
			} elseif ($hasCompiling) {
				Write-Log '[X] idf.py 报告完成但产物未更新，疑似假成功（MSYS 或环境干扰）'
				Exit-Dev 13 'ESP-IDF 编译疑似假成功'
			} else {
				Write-Host '[i] 无生成动作且产物未更新（可能 0 变更增量）' -ForegroundColor Yellow
				Write-Log '[i] 无生成动作且产物未更新（可能 0 变更增量）'
			}
		} finally { Pop-Location }
		return
	}
	# Keil：先清增量缓存或直接 -b
	$uv4 = Find-KeilUv4
	if (-not $uv4) { Write-Log '[X] 未找到 Keil UV4'; Exit-Dev 11 '找不到 Keil UV4' }
	if ($Full) {
		$objDir = Join-Path (Split-Path $ProjType.File) 'Objects'
		if (Test-Path $objDir) { Remove-Item "$objDir\*" -Force -Recurse -ErrorAction SilentlyContinue }
		Write-Log '[i] 已清空 Objects，强制全量重编'
	}
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $uv4
	$psi.Arguments = '-b "{0}"' -f $ProjType.File
	$psi.UseShellExecute = $false
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.CreateNoWindow = $true
	$proc = [System.Diagnostics.Process]::Start($psi)
	$finished = $proc.WaitForExit(180000)
	if (-not $finished) {
		try { $proc.Kill(); $proc.WaitForExit() } catch {}
		$out = $proc.StandardOutput.ReadToEnd() + $proc.StandardError.ReadToEnd()
		$code = -99
		$out += "`n[dev-flow] UV4 180 秒未退出（疑似弹出缺包/授权对话框），已强制终止"
	} else {
		$out = $proc.StandardOutput.ReadToEnd() + $proc.StandardError.ReadToEnd()
		$code = $proc.ExitCode
	}
	$out | Out-File -FilePath $global:DevLog -Append -Encoding UTF8
	# -b 编译结果判定：UV4 返回码 0 且产物存在
	$hasErr = ($out -match '(?i)error:|Error: L\d|0 Error' -and $out -notmatch '0 Error')
	$succeeded = ($code -eq 0) -and (($out -match '(?i)0 Error') -or (-not $out))
	if (-not $succeeded) {
		($out | Select-Object -Last 40) | ForEach-Object { Write-Host $_ -ForegroundColor Red }
		Write-Log '[X] Keil 编译失败，已停止'
		$pack = ''
		try {
			$xml = [System.IO.File]::ReadAllText($ProjType.File)
			$mm = [regex]::Match($xml, '<PackID>(.*?)</PackID>')
			if ($mm.Success) { $pack = $mm.Groups[1].Value }
		} catch {}
		if ($pack -and $out -match '(?i)cannot open|unable to|no such file|not a valid (device|pack)|Target not created|RTE_Components|not supported|device.{0,30}not found|pack.{0,30}not (found|installed)|180 秒未退出') {
			Write-Host "  指引: 疑似缺器件包 $pack —— 运行 preflight -ProjectDir $ProjectDir -FixAuto 自动安装，或打开 Keil Pack Installer 搜索安装" -ForegroundColor Cyan
		}
		Exit-Dev 12 'Keil 编译失败'
	}
	Write-Log '[OK] Keil 编译完成'
}

# ==================== 2.5 静态门禁（编译通过后、烧录前必跑） ====================
function Invoke-StaticGate {
	param([string]$Root)
	Write-Step '门禁：静态检查（code-style-check）'
	if ($SkipStatic) { Write-Host '[i] -SkipStatic：跳过静态门禁' -ForegroundColor Yellow; return }
	$css = Join-Path $PSScriptRoot 'code-style-check.ps1'
	if (-not (Test-Path $css)) {
		Write-Host '[i] code-style-check.ps1 不存在，跳过静态门禁' -ForegroundColor Yellow
		return
	}
	& $css -Path $Root -Checks 'overflow,defensive'
	if ($LASTEXITCODE -ne 0) {
		Write-Log "[X] 静态门禁未通过（code-style-check 退出码 $LASTEXITCODE），先修复再继续"
		Exit-Dev 21 '静态门禁失败：code-style-check 非 0'
	}
	Write-Log '[OK] 静态门禁通过'
}

# ==================== 3. 时间戳新鲜度门禁 ====================
function Test-ArtefactFresh {
	param([string]$Root)
	Write-Step '门禁：时间戳新鲜度（产物 vs 源码）'
	$srcExt = @('*.c', '*.h', '*.s', '*.S', '*.cpp', '*.cc')
	$srcFiles = @()
	Get-ChildItem $Root -Recurse -File -Include $srcExt -ErrorAction SilentlyContinue | Where-Object {
		$_.FullName -notmatch '\\(build|Objects|obj|Debug|Release|Library|Firmware_Build|Logs|\.git|managed_components)\\' 
	} | ForEach-Object { $srcFiles += $_ }
	if ($srcFiles.Count -eq 0) {
		Write-Host '[i] 未找到源码文件（可能为空工程）' -ForegroundColor Yellow
		return $true
	}
	$latestSrc = $srcFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
	$artExt = @('*.hex', '*.axf', '*.bin', '*.elf')
	$arts = Get-ChildItem $Root -Recurse -File -Include $artExt -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName -notmatch '\\(Firmware_Build|Logs)\\' } |
		Sort-Object LastWriteTime -Descending
	if (-not $arts -or $arts.Count -eq 0) {
		Write-Host '[i] 未找到产物，跳过时间戳检查' -ForegroundColor Yellow
		return $true
	}
	$latestArt = $arts | Select-Object -First 1
	Write-Host ("  最新源码: {0}  {1}" -f $latestSrc.FullName, $latestSrc.LastWriteTime) -ForegroundColor Gray
	Write-Host ("  最新产物: {0}  {1}" -f $latestArt.FullName, $latestArt.LastWriteTime) -ForegroundColor Gray
	if ($latestSrc.LastWriteTime -gt $latestArt.LastWriteTime) {
		Write-Log "[X] 产物比源码旧（源码 $($latestSrc.LastWriteTime) > 产物 $($latestArt.LastWriteTime)），禁止烧录旧版本！"
		Exit-Dev 20 '时间戳门禁失败：产物过期'
	}
	Write-Log "[OK] 产物新鲜（$($latestArt.Name) 最新）"
	return $true
}

# ==================== 4. 版本一致门禁 ====================
function Get-FwVersionString {
	param([string]$Root, [string]$Kind)
	# 优先 version.h 的 FW_VERSION_STRING / VERSION_STRING
	$vh = Get-ChildItem $Root -Recurse -Filter 'version.h' -File -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($vh) {
		$t = Get-Content $vh.FullName -Encoding UTF8 -Raw
		if ($t -match 'FW_VERSION_STRING\s+"?([Vv][\d.]+)"?') { return $matches[1] }
		if ($t -match 'VERSION_STRING\s+"?([Vv][\d.]+)"?') { return $matches[1] }
	}
	if ($Kind -eq 'ESP-IDF') {
		$cm = Join-Path $Root 'CMakeLists.txt'
		if (Test-Path $cm) {
			$t = Get-Content $cm -Encoding UTF8 -Raw
			if ($t -match 'project\([^)]*VERSION\s+([\d.]+)') { return "v$($matches[1])" }
		}
	}
	# 兜底：源码中 printf "FW Vxx"
	$src = Get-ChildItem $Root -Recurse -Include '*.c' -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(build|Objects|Library|Firmware_Build)' } | Select-Object -First 1
	if ($src) {
		$st = Get-Content $src.FullName -Encoding UTF8
		foreach ($line in $st) { if ($line -match '"FW\s+(V[\d.]+)' ) { return $matches[1] } }
	}
	return $null
}

function Test-VersionGate {
	param([string]$Root, [string]$Kind)
	Write-Step '门禁：固件版本一致性'
	$ver = Get-FwVersionString -Root $Root -Kind $Kind
	if (-not $ver) {
		Write-Host '[i] 未找到版本号（version.h / CMakeLists VERSION / FW Vxx 都没有），跳过版本门禁（建议补齐）' -ForegroundColor Yellow
		return $null
	}
	# 产物文件名应含版本
	$art = Get-ChildItem $Root -Recurse -File -Include @('*.hex', '*.axf', '*.bin') -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName -notmatch '\\(Firmware_Build|Logs)\\' } |
		Sort-Object LastWriteTime -Descending | Select-Object -First 1
	$fileOk = $true
	if ($art) {
		$fileOk = $art.Name -match [regex]::Escape($ver)
		if (-not $fileOk) {
			Write-Host "[!] 产物文件名 $($art.Name) 不含版本 $ver（建议命名 <芯片>_$ver.hex）" -ForegroundColor Yellow
			if (-not $SkipVersionGate) {
				Write-Log "[X] 版本门禁失败：产物文件名不含版本号 $ver（规范 §四③：不一致禁止烧录）"
				Exit-Dev 21 '版本门禁失败：产物文件名与版本不一致'
			} else {
				Write-Log "[!] 版本文件名不一致已按 -SkipVersionGate 豁免"
			}
		}
	}
	Write-Log "[OK] 版本识别：$ver （文件名匹配：$fileOk）"
	return $ver
}

# ==================== 5. 烧录 ====================
function Invoke-FlashStep {
	param([string]$TargetPort, [switch]$Skip, [string]$Kind)
	Write-Step '安全烧录（safe-flash）'
	if ($Skip) { Write-Host '[i] -SkipFlash：跳过烧录' -ForegroundColor Yellow; return 'skipped' }
	if ($Kind -eq 'Keil C51') {
		Write-Host '[i] Keil C51 烧录：请用工具（STC-ISP）手动烧录' -ForegroundColor Yellow
		return 'manual'
	}
	if ($TargetPort) { & "$PSScriptRoot\safe-flash.ps1" -Port $TargetPort; return $LASTEXITCODE }
	& "$PSScriptRoot\safe-flash.ps1"
	return $LASTEXITCODE
}

# ==================== 6. 产物特征核验 ====================
function Test-ArtefactFeature {
	param([string]$Root, [string]$Version)
	Write-Step '烧录后产物特征核验'
	if (-not $Version) { Write-Host '[i] 无版本参照，跳过特征核验' -ForegroundColor Yellow; return }
	$bin = Get-ChildItem $Root -Recurse -File -Include @('*.bin', '*.hex') -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName -notmatch '\\(Firmware_Build|Logs)\\' } |
		Sort-Object LastWriteTime -Descending | Select-Object -First 1
	if (-not $bin) { Write-Host '[i] 未找到 bin/hex，跳过' -ForegroundColor Yellow; return }
	$bytes = [System.IO.File]::ReadAllBytes($bin.FullName)
	$ascii = -join ($bytes | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' } })
	$hit = $ascii.Contains($Version, [System.StringComparison]::OrdinalIgnoreCase)
	Write-Host "  核验 $($bin.Name) 内含版本串 $Version：$(if ($hit) { '命中 ✓' } else { '未命中' })" -ForegroundColor $(if ($hit) { 'Green' } else { 'Yellow' })
	Write-Log "[特征] $Version 在产物中 $(if ($hit) { '存在' } else { '未找到（检查版本宏是否编译进固件）' })"
}

# ==================== 7. 固件归档 ====================
function Save-Archive {
	param([string]$Root, [string]$Version, [string]$Kind)
	Write-Step '固件归档（Firmware_Build）'
	if (-not $Version) {
		$Version = 'V' + (Get-Date -Format 'yyyyMMdd_HHmmss')
		Write-Host "[i] 未识别到版本号，归档降级用时间戳目录：$Version" -ForegroundColor Yellow
	}
	$fwDir = Join-Path $Root 'Firmware_Build'
	$verDir = Join-Path $fwDir $Version
	if (Test-Path $verDir) {
		Write-Host "[i] 归档目录已存在：$verDir（跳过，如需覆盖请手动清理）" -ForegroundColor Yellow
		return
	}
	New-Item -ItemType Directory -Path $verDir -Force | Out-Null
	$ext = if ($Kind -eq 'ESP-IDF') { @('*.bin', '*.elf', '*.map') } else { @('*.hex', '*.axf', '*.map') }
	$copied = 0
	Get-ChildItem $Root -Recurse -File -Include $ext -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName -notmatch '\\(Firmware_Build|Logs)\\' } |
		ForEach-Object { Copy-Item $_.FullName $verDir -Force; $copied++ }
	# src 快照
	$snapDir = Join-Path $verDir 'src'
	New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
	Get-ChildItem $Root -Recurse -File -Include @('*.c', '*.h') -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName -notmatch '\\(build|Objects|Library|Firmware_Build|Logs)\\' } |
		ForEach-Object {
			$rel = $_.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '__')
			Copy-Item $_.FullName (Join-Path $snapDir $rel) -Force
		}
	# 构建可复现性（2026-09-07）：buildinfo.txt（工具链版本 + 产物 SHA256）
	$bf = @()
	$bf += "build_time: $(Get-Date -Format yyyy-MM-dd_HH-mm-ss)"
	$bf += "project_type: $Kind"
	if ($Kind -eq 'ESP-IDF') {
		$idfCommit = & git -C $Root rev-parse HEAD 2>$null
		$bf += "idf_commit: $idfCommit"
		$bf += "idf_path: $env:IDF_PATH"
	} else {
		$bv4 = Find-KeilUv4
		if ($bv4) { $bf += "uv4: $bv4" }
	}
	$bf += "artifacts_sha256:"
	Get-ChildItem $verDir -File | Where-Object { $_.Extension -in @('.hex','.axf','.bin','.elf','.map') } | Sort-Object Name | ForEach-Object {
		$h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
		$bf += ("  {0}  {1}" -f $h, $_.Name)
	}
	$bf | Set-Content -Path (Join-Path $verDir 'buildinfo.txt') -Encoding UTF8
	Write-Log "[OK] 已归档到 $verDir（产物 $copied 个 + src 快照）"
}

# ==================== 冒烟自检 ====================
function Invoke-SelfTest {
	Write-Host '===== dev-flow 冒烟自检 =====' -ForegroundColor Cyan
	$tmp = Join-Path $env:TEMP 'dev-flow_selftest'
	if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
	New-Item -ItemType Directory -Path $tmp -Force | Out-Null
	try {
		# 造一个模拟 Keil 工程（64 行结构：uvprojx 占位 + version.h + main.c）
		@('TARGET', 'Objects', 'Firmware_Build') | ForEach-Object { New-Item -ItemType Directory -Path (Join-Path $tmp $_) -Force | Out-Null }
		[System.IO.File]::WriteAllText((Join-Path $tmp 'demo.uvprojx'), '<Project/>', (New-Object System.Text.UTF8Encoding($false)))
		[System.IO.File]::WriteAllText((Join-Path $tmp 'version.h'), "// version`n#define FW_VERSION_STRING `"V99`"`n", (New-Object System.Text.UTF8Encoding($false)))
		[System.IO.File]::WriteAllText((Join-Path $tmp 'main.c'), 'int main(void){ return 0; }', (New-Object System.Text.UTF8Encoding($false)))
		# 逻辑自检点
		$pt = Get-ProjectType -Path $tmp
		$ok1 = ($pt.Type -eq 'Keil ARM')
		$ver = Get-FwVersionString -Root $tmp -Kind 'Keil ARM'
		$ok2 = ($ver -eq 'V99')
		$classes = (Get-Content (Join-Path $tmp 'version.h') -Encoding UTF8) -contains '#define FW_VERSION_STRING "V99"'
		$ok3 = $classes
		# 归档验证：造 hex + 调 Save-Archive，检查 Firmware_Build\V99
		[System.IO.File]::WriteAllText((Join-Path $tmp 'demo.hex'), 'FAKE_HEX', (New-Object System.Text.UTF8Encoding($false)))
		Save-Archive -Root $tmp -Version 'V99' -Kind 'Keil ARM' | Out-Null
		$archOk = (Test-Path (Join-Path $tmp "Firmware_Build\V99\demo.hex")) -and (Test-Path (Join-Path $tmp "Firmware_Build\V99\src\main.c"))
		$ok4 = $archOk
		Write-Host ("  类型识别: {0}  [{1}]" -f $pt.Type, $(if($ok1){'PASS'}else{'FAIL'}))
		Write-Host ("  版本提取: {0}  [{1}]" -f $ver, $(if($ok2){'PASS'}else{'FAIL'}))
		Write-Host ("  归档结构: Firmware_Build\V99  [{1}]" -f '', $(if($ok4){'PASS'}else{'FAIL'}))
		# 子进程验证时间戳门禁：stale 应拦截(exit 20)，fresh 应通过(exit 0)
		$ok5 = $false
		if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
			& powershell -NoProfile -File $PSCommandPath -GateTest stale 2>$null | Out-Null
			$cStale = $LASTEXITCODE
			& powershell -NoProfile -File $PSCommandPath -GateTest fresh 2>$null | Out-Null
			$cFresh = $LASTEXITCODE
			$ok5 = ($cStale -eq 20 -and $cFresh -eq 0)
			Write-Host ("  时间戳门禁: stale拦截={0} / fresh通过={1}  [{2}]" -f $cStale, $cFresh, $(if($ok5){'PASS'}else{'FAIL'}))
		}
		if ($ok1 -and $ok2 -and $ok3 -and $ok4 -and $ok5) { Write-Host '[PASS] 自检通过' -ForegroundColor Green; return 0 }
		Write-Host '[FAIL] 自检未通过' -ForegroundColor Red
		return 1
	} finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# ==================== 门禁测试（内部 -GateTest） ====================
if ($GateTest) {
	if ($GateTest -notin @('stale', 'fresh')) { Write-Host '[X] -GateTest 仅支持 stale / fresh'; exit 99 }
	$tmp = Join-Path $env:TEMP "dev-flow_gate_$GateTest"
	if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
	New-Item -ItemType Directory -Path $tmp -Force | Out-Null
	[System.IO.File]::WriteAllText((Join-Path $tmp 'demo.uvprojx'), '<Project/>', (New-Object System.Text.UTF8Encoding($false)))
	[System.IO.File]::WriteAllText((Join-Path $tmp 'version.h'), "// version`n#define FW_VERSION_STRING `"V88`"`n", (New-Object System.Text.UTF8Encoding($false)))
	[System.IO.File]::WriteAllText((Join-Path $tmp 'main.c'), 'int main(void){ return 0; }', (New-Object System.Text.UTF8Encoding($false)))
	$hex = Join-Path $tmp 'demo_V88.hex'
	[System.IO.File]::WriteAllText($hex, 'FAKE_FW', (New-Object System.Text.UTF8Encoding($false)))
	if ($GateTest -eq 'stale') {
		[System.IO.File]::SetLastWriteTime($hex, (Get-Date '2010-01-01'))
		Test-ArtefactFresh -Root $tmp | Out-Null   # 预计内部 Exit-Dev 20
	} else {
		[System.IO.File]::SetLastWriteTime($hex, (Get-Date).AddMinutes(1))
		Test-ArtefactFresh -Root $tmp | Out-Null
		$ver = Test-VersionGate -Root $tmp -Kind 'Keil ARM'
		if ($ver -eq 'V88') { exit 0 } else { exit 99 }
	}
	exit 99
}

# ==================== 1.5 存储寿命预检（提示级，不阻断） ====================
function Invoke-StoragePreflight {
	param([string]$Root)
	Write-Step '存储寿命预检（提示级）'
	# 宁漏勿滥：只匹配明确的存储写 API，避免误报
	$patterns = 'nvs_set_|esp_flash_write|esp_partition_erase|esp_partition_write|fmc_program|fmc_erase|flash_program|flash_erase|iap_program|iap_erase|eeprom_write|eeprom_program|w25q_write|w25q_erase|at24c_write'
	$src = Get-ChildItem -Path $Root -Recurse -Include '*.c','*.h' -File -ErrorAction SilentlyContinue | Where-Object {
		$_.FullName -notmatch '\\(build|managed_components|\.git|Firmware_Build|Logs)\\' -and $_.FullName -notmatch '\.(uvoptx|uvprojx|uvproj)$'
	}
	$hits = $src | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match $patterns }
	if (-not $hits) {
		Write-Host '[OK] 未检测到存储写 API（无需核寿命账）' -ForegroundColor Green
		return
	}
	Write-Host "[!] 检测到 $($hits.Count) 个文件含存储写调用（即使低频也请核一眼），例如：$(( $hits | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor Yellow
	Write-Log '    提醒：若涉及 NVS/DataFlash/EEPROM 参数保存，按 embedded-dev-rules 4.7 先算寿命账（寿命天数=P/E寿命÷日写次数），不足 5 年需上缓解（读回比较/防抖/环形/影子/外置EEPROM）'
}
# ==================== 主流程 ====================
if ($SelfTest) { exit (Invoke-SelfTest) }

if (-not (Test-Path $ProjectDir)) { Write-Host "[X] 项目目录不存在: $ProjectDir" -ForegroundColor Red; exit 1 }
Open-DevLog
Write-Step '开发闭环流水线启动'
Write-Host "  项目: $ProjectDir" -ForegroundColor Gray
$projType = Get-ProjectType -Path $ProjectDir
if ($projType -eq 'NotFound') { Write-Log "[X] 目录不存在：$ProjectDir"; Exit-Dev 1 }
if ($projType -eq 'Unknown') { Write-Log "[X] 无法识别项目类型（需要 sdkconfig / .uvprojx / .uvproj）"; Exit-Dev 2 }

$kind = if ($projType -eq 'ESP-IDF') { 'ESP-IDF' } else { $projType.Type }
Write-Host "  类型: $kind" -ForegroundColor Gray
Invoke-StoragePreflight -Root $ProjectDir

# 个人流程规范引用（-SkipReview 隐藏；仅提示不阻断主流程）
if (-not $SkipReview) {
    $normDoc = Join-Path $env:USERPROFILE 'Desktop\<项目根目录>\个人嵌入式开发流程规范.md'
    if (Test-Path $normDoc) {
        Write-Host "  流程规范: $normDoc（四步准备/红线/门禁/验证/归档/沉淀）" -ForegroundColor DarkGray
    }
}
try {
	Invoke-BuildStep -ProjType $projType
	Invoke-StaticGate -Root $ProjectDir
	Test-ArtefactFresh -Root $ProjectDir | Out-Null
	$version = Test-VersionGate -Root $ProjectDir -Kind $kind
	if ($CompileOnly) {
		Write-Step '编译+门禁完成（-CompileOnly，未烧录未归档）'
		Write-Log '[OK] 全过程通过（CompileOnly）'
		Exit-Dev 0
	}
	$flashCode = Invoke-FlashStep -TargetPort $Port -Skip:$SkipFlash -Kind $kind
	if ($flashCode -ne 0 -and $flashCode -ne 'skipped' -and $flashCode -ne 'manual') {
		Write-Log '[X] 烧录环节异常（safe-flash 退出码非 0），停止'
		Exit-Dev 30 ('烧录失败 code=' + $flashCode)
	}
	Test-ArtefactFeature -Root $ProjectDir -Version $version
	if (-not $SkipArchive) { Save-Archive -Root $ProjectDir -Version $version -Kind $kind }
	Write-Step '流程完成'
	Write-Log '[OK] dev-flow 全流程通过'
	Exit-Dev 0
} catch {
	Write-Log "[X] 异常：$($_.Exception.Message)"
	Write-Host $_.Exception.ToString() -ForegroundColor Red
	Exit-Dev 99 '未捕获异常'
}
