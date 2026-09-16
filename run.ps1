<#
.SYNOPSIS
embedded-workflow 便携运行器：不安装、不改 PATH、零残留，直接跑仓库内工具
.DESCRIPTION
不想全局安装时的替代入口：本脚本临时把 tools/ 加入当前进程 PATH 并调用目标工具，
不改写用户 PATH 环境变量、不复制任何文件。删除本仓库文件夹即完全卸载。
.EXAMPLE
.\run.ps1 detect-chip                    # 跑 detect-chip
.\run.ps1 dev-flow -ProjectDir D:\proj   # 跑 dev-flow 并透传参数
.\run.ps1 tool-guide                     # 查看全部可用工具
  version: 1.0.0
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$Tool,                        # 工具名（不带 .ps1 后缀）

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ToolArgs                   # 透传给目标工具的参数
)

$ErrorActionPreference = 'Stop'
$repo_root = $PSScriptRoot
$tools_src = Join-Path $repo_root 'tools'
$target = Join-Path $tools_src ($Tool + '.ps1')

if (-not (Test-Path $tools_src)) { throw "未找到 tools 目录: $tools_src" }
if (-not (Test-Path $target)) {
    Write-Host "[X] 未找到工具: $Tool（可用工具列表见 .\run.ps1 tool-guide）" -ForegroundColor Red
    exit 1
}

# 临时 PATH：仅对当前进程生效，不写入用户环境变量
$env:PATH = "$tools_src;$env:PATH"

Write-Host "==> 便携运行 $Tool $($ToolArgs -join ' ')（不改全局环境）" -ForegroundColor Cyan
# 子进程调用：目标脚本内 exit 码可靠透传，输出原样透出
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $target @ToolArgs
exit $LASTEXITCODE
