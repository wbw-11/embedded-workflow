<#
.SYNOPSIS
	安装 / 卸载 / 查看 Git pre-commit 提交门禁钩子
.DESCRIPTION
	给嵌入式项目仓库安装 .git/hooks/pre-commit：
	- 暂存 .c/.h 自动跑 code-style-check，P0 致命问题（退出码 3）阻止提交
	- 暂存含中文 .ps1 无 UTF-8 BOM 阻止提交
	P1/规范级问题只警告不阻止；紧急情况可用 git commit --no-verify 强制提交。
.USAGE
	install-precommit                        # 给当前目录的仓库安装
	install-precommit -RepoPath D:\project   # 指定仓库路径
	install-precommit -Status                # 查看钩子状态
	install-precommit -Remove                # 卸载钩子（备份后删除）
	install-precommit -Remove -RepoPath D:\project
  version: 1.0.0
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
	if (-not (Test-Path $hooksDir)) {
		New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
	}
	$hookFile = Join-Path $hooksDir 'pre-commit'

	if ($Status) {
		if (Test-Path $hookFile) {
			Write-Host "[OK] 已安装: $hookFile" -ForegroundColor Green
			$content = Get-Content $hookFile -Raw
			if ($content -match 'pre-commit-check\.ps1') {
				Write-Host "    检查器指向: 有效" -ForegroundColor Green
			} else {
				Write-Host "    [!] 内容非本工具安装（可能为自定义钩子）" -ForegroundColor Yellow
			}
		} else {
			Write-Host "[*] 未安装 pre-commit 钩子" -ForegroundColor Cyan
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

	# 安装
	$toolsDir = $PSScriptRoot
	$checkerPath = Join-Path $toolsDir 'pre-commit-check.ps1'
	if (-not (Test-Path $checkerPath)) {
		Write-Host "[X] 检查器不存在: $checkerPath" -ForegroundColor Red
		exit 2
	}

	if (Test-Path $hookFile) {
		$bak = "$hookFile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
		Copy-Item $hookFile $bak -Force
		Write-Host "[!] 已有钩子，备份到: $bak" -ForegroundColor Yellow
	}

	$checkerPathForSh = $checkerPath -replace '\\', '/'
	$hookContent = @"
#!/bin/sh
files=`$(git diff --cached --name-only --diff-filter=ACM | grep -Ei '\.(c|h|ps1)`$')
if [ -z "`$files" ]; then exit 0; fi
powershell -NoProfile -ExecutionPolicy Bypass -File "$checkerPathForSh"
exit `$?
"@
	# 钩子必须是 LF 行尾，git bash 才能正确执行
	[System.IO.File]::WriteAllText($hookFile, $hookContent, (New-Object System.Text.UTF8Encoding($false)))
	Write-Host "[OK] pre-commit 钩子已安装: $hookFile" -ForegroundColor Green
	Write-Host "    检查器: $checkerPath" -ForegroundColor Cyan
	Write-Host "    规则: P0 溢出隐患 / 无BOM含中文 .ps1 阻止提交；P1 仅警告" -ForegroundColor Cyan
	exit 0
} catch {
	Write-Host "[X] 安装失败: $($_.Exception.Message)" -ForegroundColor Red
	exit 1
}
