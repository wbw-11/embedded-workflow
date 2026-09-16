<#
.SYNOPSIS
    code-style-check.ps1 验证脚本 — 改完脚本后一条命令验证不误报不漏检
.DESCRIPTION
    自动跑 3 个基线文件，对比 baseline.json，输出 PASS/FAIL
    ALL PASS 时写入 .last_verified 时间戳（供 self-update 时效门禁使用）
.USAGE
    .\verify-check.ps1
    .\verify-check.ps1 -ScriptPath .\code-style-check.ps1
  version: 1.0.0
#>
param(
    [string]$ScriptPath = ".\code-style-check.ps1",
    [string]$BaselinePath = ".\baseline.json"
)

$ErrorActionPreference = "Stop"

# ── 加载基线 ──
if (-not (Test-Path $BaselinePath)) {
    Write-Host "[FATAL] baseline.json 不存在: $BaselinePath" -ForegroundColor Red
    exit 99
}
$baseline = Get-Content $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json

# ── 检查脚本和测试文件是否存在 ──
if (-not (Test-Path $ScriptPath)) {
    Write-Host "[FATAL] code-style-check.ps1 不存在: $ScriptPath" -ForegroundColor Red
    exit 99
}

$testFiles = @{
    "clean_code.c"             = $baseline."clean_code.c"
    "test_q10.c"               = $baseline."test_q10.c"
    "test_q45_8051_stubs.c"    = $baseline."test_q45_8051_stubs.c"
}

foreach ($f in $testFiles.Keys) {
    if (-not (Test-Path $f)) {
        Write-Host "[FATAL] 测试文件不存在: $f" -ForegroundColor Red
        exit 99
    }
}

# ── 逐个跑 ──
$results = @{}
$allPass = $true

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " code-style-check 验证脚本" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($file in $testFiles.Keys | Sort-Object) {
    $expected = $testFiles[$file]
    $expectedAlerts = $expected.expected_total_alerts
    $expectedExit = $expected.expected_exit_code

    # 跑脚本，捕获输出
    $output = & powershell -ExecutionPolicy Bypass -File $ScriptPath -Path $file -Checks "overflow,defensive" 2>&1
    $actualExit = $LASTEXITCODE
    $outputStr = $output -join "`n"

    # 从输出中提取总问题数
    $totalMatch = [regex]::Match($outputStr, "总问题数:\s*(\d+)")
    $actualAlerts = if ($totalMatch.Success) { [int]$totalMatch.Groups[1].Value } else { 0 }

    # 判定
    $exitMatch = ($actualExit -eq $expectedExit)
    $countMatch = ($actualAlerts -eq $expectedAlerts)
    $filePass = $exitMatch -and $countMatch

    if (-not $filePass) { $allPass = $false }

    # 输出
    $tag = if ($filePass) { "[PASS]" } else { "[FAIL]" }
    $color = if ($filePass) { "Green" } else { "Red" }

    Write-Host "$tag $file" -ForegroundColor $color -NoNewline
    Write-Host "  告警 $actualAlerts/$expectedAlerts  退出码 $actualExit/$expectedExit" -ForegroundColor $color

    # 失败时输出详情
    if (-not $filePass) {
        if (-not $countMatch) {
            $diff = $actualAlerts - $expectedAlerts
            if ($diff -gt 0) {
                Write-Host "       ⚠ 多了 $diff 项 → 可能产生 FP（误报）" -ForegroundColor Yellow
            } else {
                Write-Host "       ⚠ 少了 $([Math]::Abs($diff)) 项 → 可能漏检（回归 bug）" -ForegroundColor Yellow
            }
        }
        if (-not $exitMatch) {
            Write-Host "       ⚠ 退出码不匹配（期望 $expectedExit，实际 $actualExit）" -ForegroundColor Yellow
        }
        # 输出最后 20 行帮助定位
        $lines = $outputStr -split "`n"
        $tail = if ($lines.Count -gt 25) { $lines[-25..-1] } else { $lines }
        Write-Host "       --- 输出尾部 ---" -ForegroundColor DarkGray
        foreach ($l in $tail) { Write-Host "       $l" -ForegroundColor DarkGray }
    }

    $results[$file] = @{
        Pass           = $filePass
        ActualAlerts   = $actualAlerts
        ExpectedAlerts = $expectedAlerts
        ActualExit     = $actualExit
        ExpectedExit   = $expectedExit
    }
}

# ── 汇总 ──
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
if ($allPass) {
    Write-Host " [ALL PASS] 3/3 文件全部匹配基线" -ForegroundColor Green
    Write-Host ""
    Write-Host " clean_code.c   = 0 告警 (无误报)" -ForegroundColor Green
    Write-Host " test_q10.c     = 9 告警 (Q1~Q7 全检出)" -ForegroundColor Green
    Write-Host " test_q45       = 16 告警 (Q4+D2 全检出)" -ForegroundColor Green
    Write-Host ""
    Write-Host " -> 可以部署：复制到 Tools + 更新 baseline + 记录 memory" -ForegroundColor Green
    # 记录验证时间戳（供 self-update config 时效门禁：脚本改动后未回归即告警）
    try {
        $stampFile = Join-Path $PSScriptRoot '.last_verified'
        [System.IO.File]::WriteAllText($stampFile, (Get-Date).ToString('o'))
    } catch {}
    exit 0
} else {
    $failCount = ($results.Values | Where-Object { -not $_.Pass }).Count
    Write-Host " [FAIL] $failCount/3 文件不匹配基线" -ForegroundColor Red
    Write-Host ""
    Write-Host " -> 不要部署！排查原因后重新验证" -ForegroundColor Red
    exit 1
}
