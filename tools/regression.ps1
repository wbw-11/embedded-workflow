<#
.SYNOPSIS
嵌入式回归一键检查：静态门禁 → L0 单测 → 编译门禁（dev-flow：静态+时间戳+版本）
.DESCRIPTION
开工前 / 改架构前 / 交付前必跑：串起 code-style-check(overflow,defensive)
+ unit-test(L0) + dev-flow -CompileOnly。任一步失败即停并给出原因。
.EXAMPLE
regression -ProjectDir D:\proj\gd32
regression -ProjectDir D:\proj -SkipCompile
  version: 1.0.0
#>
param(
    [string]$ProjectDir = (Get-Location),
    [switch]$SkipCompile   # 跳过编译门禁（仅静态+单测）
)
$ErrorActionPreference = 'Continue'
$tools = $PSScriptRoot

Write-Host ('=' * 60) -ForegroundColor White
Write-Host '  回归检查（静态 → 单测 → 编译门禁）' -ForegroundColor White
Write-Host ('=' * 60) -ForegroundColor White
Write-Host "  项目: $ProjectDir" -ForegroundColor Gray
if (-not (Test-Path $ProjectDir)) { Write-Host "[X] 项目目录不存在: $ProjectDir" -ForegroundColor Red; exit 1 }

# 1. 静态门禁
Write-Host "`n[1/3] code-style-check（overflow, defensive）" -ForegroundColor Cyan
& "$tools\code-style-check.ps1" -Path $ProjectDir -Checks 'overflow,defensive'
if ($LASTEXITCODE -ne 0) { Write-Host '[X] 静态检查未通过，停止' -ForegroundColor Red; exit 10 }

# 2. L0 单元测试（无 test_*.c 视为跳过）
Write-Host "`n[2/3] unit-test（L0，主机端）" -ForegroundColor Cyan
$tests = Get-ChildItem -Path $ProjectDir -Recurse -Filter 'test_*.c' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(build|Objects|Library|Firmware_Build|Logs)\\' }
if ($tests -and $tests.Count -gt 0) {
    & "$tools\unit-test.ps1" -ProjectDir $ProjectDir
    if ($LASTEXITCODE -ne 0) { Write-Host '[X] 单元测试未通过，停止' -ForegroundColor Red; exit 20 }
} else {
    Write-Host '[i] 未发现 test_*.c，跳过 L0 单测（开发期建议补）' -ForegroundColor Yellow
}

# 3. 编译 + 门禁
if (-not $SkipCompile) {
    Write-Host "`n[3/3] dev-flow -CompileOnly（编译+静态+时间戳+版本门禁）" -ForegroundColor Cyan
    & "$tools\dev-flow.ps1" -ProjectDir $ProjectDir -CompileOnly
    if ($LASTEXITCODE -ne 0) {
        if ($LASTEXITCODE -eq 2) { Write-Host '[i] 无法识别项目类型——回归跳过编译段（非 Keil/ESP-IDF 目录）' -ForegroundColor Yellow; exit 0 }
        Write-Host '[X] 编译门禁未通过，停止' -ForegroundColor Red; exit 30
    }
}

Write-Host "`n[OK] 回归全部通过" -ForegroundColor Green
exit 0