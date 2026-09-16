<#
.SYNOPSIS
安装 / 卸载 / 查看 git post-commit 自动构建钩子（本地版 CI，借鉴 Arm CI 形态）
.DESCRIPTION
给仓库安装 .git/hooks/post-commit：
- 提交后若有源码改动（.c/.h/.cpp/CMakeLists/Makefile/.uvprojx/.uvproj），自动跑 dev-flow -CompileOnly -SkipReview
- 纯反馈不阻塞：commit 已完成，构建结果 PASS/FAIL 打印给用户，日志由 dev-flow 落 Logs\
- dev-flow 路径安装时动态注入（$PSScriptRoot），不硬编码；钩子文件强制 LF 行尾（git bash 执行）
- 日志防膨胀由 dev-flow 自带（Logs\dev-flow_<时间戳>.log），本钩子不重复落盘
.USAGE
install-autobuild                        # 装到当前目录仓库
install-autobuild -RepoPath D:\proj      # 指定仓库
install-autobuild -Status                # 查看状态
install-autobuild -Remove                # 卸载（备份 .bak_<时间戳>）
.EXAMPLE
install-autobuild -RepoPath D:\EPS32\hello_world
  version: 1.1.0
#>
param(
	[string]$RepoPath = '',
	[switch]$Remove,
	[switch]$Status
)

$ErrorActionPreference = 'Stop'

if (-not $RepoPath) { $RepoPath = (Get-Location).Path }

function Get-HooksDir {
	param([string]$Path)
	$dir = Join-Path $Path '.git\hooks'
	if (-not (Test-Path (Join-Path $Path '.git'))) { return $null }
	return $dir
}

try {
	$hooksDir = Get-HooksDir -Path $RepoPath
	if (-not $hooksDir) {
		Write-Host "[X] 不是 git 仓库: $RepoPath" -ForegroundColor Red
		exit 2
	}
	if (-not (Test-Path $hooksDir)) { New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null }
	$hookFile = Join-Path $hooksDir 'post-commit'

	if ($Status) {
		if (Test-Path $hookFile) {
			Write-Host "[OK] 已安装: $hookFile" -ForegroundColor Green
			$content = Get-Content $hookFile -Raw
			if ($content -match 'dev-flow\.ps1') { Write-Host "    指向 dev-flow: 有效" -ForegroundColor Green }
			else { Write-Host "    [!] 非本工具生成（可能自定义钩子）" -ForegroundColor Yellow }
		} else {
			Write-Host "[*] 未安装 post-commit 钩子" -ForegroundColor Cyan
		}
		exit 0
	}

	if ($Remove) {
		if (Test-Path $hookFile) {
			$bak = "$hookFile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
			Copy-Item $hookFile $bak -Force
			Remove-Item $hookFile -Force
			Write-Host "[OK] 已卸载，备份到: $bak" -ForegroundColor Green
		} else {
			Write-Host "[*] 未安装，无需卸载" -ForegroundColor Cyan
		}
		exit 0
	}

	# 安装：动态定位 dev-flow.ps1（本脚本目录 → PATH），且必须与 lib\common.ps1 同目录（完整部署），禁止硬编码绝对路径
	$candidates = @()
	$candidates += Join-Path $PSScriptRoot 'dev-flow.ps1'
	$cmd = Get-Command 'dev-flow.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($cmd) { $candidates += $cmd.Source }
	$devflowPath = $candidates | Where-Object { $_ -and (Test-Path $_) -and (Test-Path (Join-Path (Split-Path $_) 'lib\common.ps1')) } | Select-Object -First 1
	if (-not $devflowPath) {
		Write-Host "[X] 未找到完整 dev-flow.ps1（需与 lib\common.ps1 同目录；本目录与 PATH 均无）" -ForegroundColor Red
		exit 2
	}

	if (Test-Path $hookFile) {
		$bak = "$hookFile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
		Copy-Item $hookFile $bak -Force
		Write-Host "[!] 已有钩子，备份到: $bak" -ForegroundColor Yellow
	}

	$devflowForSh = $devflowPath -replace '\\', '/'
	$hookContent = @'
#!/bin/sh
# post-commit: 提交后自动增量编译（借鉴 Arm CI 形态：纯反馈，不阻塞提交）
SCRIPT="__DEVFLOW__"
[ -f "$SCRIPT" ] || exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] || exit 0

FILES=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | grep -Ei '\.(c|h|cpp|cxx|mk|uvprojx|uvproj)$|(CMakeLists|Makefile|sdkconfig)')
[ -n "$FILES" ] || { echo "[auto-build] skip: 本次无源码改动"; exit 0; }

echo "[auto-build] 源码有改动，自动构建中…"
# 清除 Git Bash 注入的 MSYSTEM，避免 ESP-IDF idf.py 检测到 MSys 环境拒绝构建
unset MSYSTEM 2>/dev/null || true
if powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT" -ProjectDir "$ROOT" -CompileOnly -SkipReview; then
  echo "[auto-build] PASS 构建通过 ($(git rev-parse --short HEAD))"
else
  LOG=$(ls -t "$ROOT/Logs"/dev-flow_*.log 2>/dev/null | head -n 1)
  echo "[auto-build] FAIL 构建失败，最近 dev-flow 日志尾部:"
  [ -n "$LOG" ] && tail -n 20 "$LOG" || echo "  (日志未生成)"
fi
exit 0
'@
	$hookContent = $hookContent.Replace('__DEVFLOW__', $devflowForSh)

	# 钩子必须 LF 行尾（git bash 才能执行，沿用 pre-commit 经验）
	$hookContent = $hookContent -replace "`r`n", "`n"
	[System.IO.File]::WriteAllText($hookFile, $hookContent, (New-Object System.Text.UTF8Encoding($false)))
	Write-Host "[OK] post-commit 钩子已安装: $hookFile" -ForegroundColor Green
	Write-Host "    构建器: $devflowPath"
	Write-Host "    规则: 有源码改动提交后自动 dev-flow -CompileOnly（纯反馈不阻塞）" -ForegroundColor Cyan
	exit 0
} catch {
	Write-Host "[X] 安装失败: $($_.Exception.Message)" -ForegroundColor Red
	exit 1
}