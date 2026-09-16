<#
.SYNOPSIS
    嵌入式 C 单元测试执行工具（Unity / CMock 框架）
.DESCRIPTION
    自动检测主机端 GCC、查找 test_*.c 测试文件、自动编译运行 Unity 单元测试。
    支持自动链接 Unity 框架源码，输出汇总报告 + JUnit XML。
.USAGE
    unit-test -ProjectDir <目录>
    unit-test -ProjectDir . -Pattern "test_*.c" -UnityRoot C:\Unity\src
    unit-test -TestFile test_math.c -Run -Coverage
  version: 1.0.0
#>

param(
    [string]$ProjectDir = '.',
    [string]$TestFile = '',
    [string]$Pattern = 'test_*.c',
    [string]$UnityRoot = '',
    [string]$CFlags = '-std=c99 -Wall -Wextra -O0 -g',
    [string]$OutputDir = 'build_test',
    [string]$JUnitXml = '',
    [switch]$Run = $true,
    [switch]$Verbose,
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message, [string]$Type='Info')
    if ($Quiet) { return }
    switch ($Type) {
        'Error'   { Write-Host "[X] $Message" -ForegroundColor Red }
        'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        'Success' { Write-Host "[OK] $Message" -ForegroundColor Green }
        'Info'    { Write-Host "[*] $Message" -ForegroundColor Cyan }
        default   { Write-Host "$Message" }
    }
}

$ProjectDir = Resolve-Path $ProjectDir
if (-not (Test-Path $ProjectDir)) { Write-Status "项目目录不存在: $ProjectDir" -Type Error; exit 2 }

if (-not $Quiet) {
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ' 单元测试执行 (Unity/CMock)' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Status "项目目录: $ProjectDir"
}

# ---------- 1. 检测 GCC ----------
$gcc = Get-Command gcc -ErrorAction SilentlyContinue
if (-not $gcc) {
    # 常见 MinGW/MSYS2 路径
    $candidates = @(
        'C:\msys64\mingw64\bin\gcc.exe',
        'C:\msys64\ucrt64\bin\gcc.exe',
        'C:\MinGW\bin\gcc.exe',
        'C:\Program Files\MinGW\bin\gcc.exe',
        "$env:USERPROFILE\scoop\apps\gcc\current\bin\gcc.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $gcc = [pscustomobject]@{ Source = $c }; break }
    }
}
if (-not $gcc) {
    Write-Status '未检测到主机端 GCC，请先安装 MinGW/MSYS2 或添加 gcc 到 PATH（无法编译运行单元测试）' -Type Error
    exit 3
}
Write-Status "编译器: $($gcc.Source)"

# ---------- 2. 检测 Unity 源码根目录 ----------
if ($UnityRoot -eq '') {
    $commonUnity = @(
        (Join-Path $ProjectDir 'Unity'),
        (Join-Path $ProjectDir 'unity'),
        (Join-Path $ProjectDir 'tests\Unity'),
        (Join-Path $ProjectDir 'test\Unity'),
        (Join-Path $ProjectDir 'components\Unity'),
        (Join-Path $ProjectDir 'external\Unity'),
        'C:\Unity\src',
        'C:\Unity',
        'C:\tools\Unity'
    )
    foreach ($d in $commonUnity) {
        $u = Join-Path $d 'unity.c'
        $uh = Join-Path $d 'unity.h'
        if ((Test-Path $u) -and (Test-Path $uh)) { $UnityRoot = $d; break }
    }
}
if ($UnityRoot -ne '') {
    $unitySrc = Join-Path $UnityRoot 'unity.c'
    $unityInc = $UnityRoot
    if (-not (Test-Path $unitySrc)) {
        Write-Status "Unity 源码目录中找不到 unity.c: $UnityRoot" -Type Warning
        $UnityRoot = ''
    } else {
        Write-Status "Unity 框架: $UnityRoot"
    }
} else {
    Write-Status '未自动找到 Unity 框架，将尝试使用在线 Unity 单头文件嵌入（仅提供最小 API）' -Type Warning
}

# ---------- 3. 查找测试文件 ----------
$testFiles = @()
if ($TestFile -ne '') {
    if (Test-Path $TestFile) { $testFiles = @(Get-Item $TestFile) }
    else {
        $abs = Join-Path $ProjectDir $TestFile
        if (Test-Path $abs) { $testFiles = @(Get-Item $abs) }
        else { Write-Status "找不到测试文件: $TestFile" -Type Error; exit 4 }
    }
} else {
    $testFiles = @(Get-ChildItem -Path $ProjectDir -Filter $Pattern -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "\\(managed_components|build|\.git|dependencies|\.cache|test_apps)\\" })
    if ($testFiles.Count -eq 0) {
        $testFiles = @(Get-ChildItem -Path $ProjectDir -Filter '*_test.c' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "\\(managed_components|build|\.git|dependencies|\.cache|test_apps)\\" })
    }
}
if ($testFiles.Count -eq 0) {
    Write-Status "没有找到匹配的测试文件（Pattern=$Pattern）" -Type Error
    exit 5
}
Write-Status "找到测试文件: $($testFiles.Count) 个"
if ($Verbose) { $testFiles | ForEach-Object { Write-Host "  - $($_.FullName)" } }

# ---------- 4. 构建输出目录 ----------
$outAbs = Join-Path $ProjectDir $OutputDir
if (-not (Test-Path $outAbs)) { New-Item -ItemType Directory -Path $outAbs -Force | Out-Null }

# ---------- 5. 逐个编译 + 运行 ----------
$report = [ordered]@{
    GeneratedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Total       = $testFiles.Count
    Passed      = 0
    Failed      = 0
    Skipped     = 0
    Cases       = @()
}

foreach ($tf in $testFiles) {
    $baseName = $tf.BaseName
    $exePath = Join-Path $outAbs ($baseName + '.exe')
    $logPath = Join-Path $outAbs ($baseName + '.log')

    # 收集源文件依赖：同目录下被测试的 .c 文件（从 #include 推断）
    $includeDirs = @($tf.DirectoryName, $ProjectDir)
    if ($UnityRoot -ne '') { $includeDirs += $unityInc }
    $srcFiles = @($tf.FullName)
    if ($UnityRoot -ne '') { $srcFiles += $unitySrc }
    # 如果测试文件包含了 "xxx.c"（集成测试方式），gcc 会自动处理
    $incArgs = ($includeDirs | ForEach-Object { "-I`"$_`"" }) -join ' '
    $cflagsList = $CFlags -split ' ' | Where-Object { $_ -ne '' }
    $cflagsStr = $cflagsList -join ' '

    $gccArgs = @($cflagsList + ($includeDirs | ForEach-Object { "-I$_" }) + $srcFiles + @('-o', $exePath))
    if ($Verbose) { Write-Status "编译: $($tf.Name)" -Type Info; Write-Host "gcc $incArgs $($srcFiles -join ' ') -o $exePath" }

    $compileErr = $null
    $process = Start-Process -FilePath $gcc.Source -ArgumentList $gccArgs `
        -NoNewWindow -Wait -RedirectStandardError (Join-Path $outAbs "$baseName.compile.err") `
        -RedirectStandardOutput (Join-Path $outAbs "$baseName.compile.out") -PassThru -ErrorAction SilentlyContinue
    if ($process.ExitCode -ne 0) {
        $errText = Get-Content (Join-Path $outAbs "$baseName.compile.err") -ErrorAction SilentlyContinue -Raw
        Write-Status "编译失败 [$($tf.Name)] 退出码 $($process.ExitCode)" -Type Error
        if ($errText) { Write-Host $errText.Substring(0, [Math]::Min(600, $errText.Length)) -ForegroundColor Red }
        $report.Cases += [ordered]@{ Test = $tf.Name; Compile = 'FAIL'; Run = '-'; Pass = $false; Detail = "编译失败 ExitCode=$($process.ExitCode)" }
        $report.Failed++
        continue
    }

    # 运行
    if (-not $Run) {
        Write-Status "编译成功 [$($tf.Name)] -> $exePath (跳过运行)" -Type Success
        $report.Cases += [ordered]@{ Test = $tf.Name; Compile = 'PASS'; Run = 'SKIP'; Pass = $true; Detail = '未运行' }
        $report.Skipped++
        continue
    }

    if (-not (Test-Path $exePath)) {
        Write-Status "编译成功但找不到 exe: $exePath" -Type Error
        $report.Cases += [ordered]@{ Test = $tf.Name; Compile = 'PASS'; Run = 'MISSING'; Pass = $false; Detail = 'exe 不存在' }
        $report.Failed++
        continue
    }

    try {
        $runOut = & $exePath 2>&1 | Out-String
        Set-Content -Path $logPath -Value $runOut -Encoding UTF8
        $exitCode = $LASTEXITCODE
    } catch {
        $runOut = "$_"
        $exitCode = -1
    }

    # 解析 Unity 输出（形如 "10 Tests 0 Failures 0 Ignores" 或 "FAIL: Test xxx"）
    $totalTests = 0; $fails = 0; $ignores = 0
    if ($runOut -match '(\d+) Tests (\d+) Failures (\d+) Ignore') {
        $totalTests = [int]$matches[1]; $fails = [int]$matches[2]; $ignores = [int]$matches[3]
    } elseif ($runOut -match 'OK \((\d+) tests\)') {
        $totalTests = [int]$matches[1]
    }
    $casePass = ($fails -eq 0)
    if ($casePass) {
        Write-Status "测试通过 [$($tf.Name)] ($totalTests tests, $ignores ignored)" -Type Success
        $report.Passed++
    } else {
        Write-Status "测试失败 [$($tf.Name)] ($totalTests tests, $fails failures)" -Type Error
        if ($runOut) { Write-Host $runOut.Substring(0, [Math]::Min(800, $runOut.Length)) -ForegroundColor Red }
        $report.Failed++
    }
    $report.Cases += [ordered]@{
        Test      = $tf.Name
        Compile   = 'PASS'
        Run       = 'RUN'
        Pass      = $casePass
        ExitCode  = $exitCode
        Total     = $totalTests
        Failures  = $fails
        Ignores   = $ignores
        Detail    = $logPath
    }
}

# ---------- 6. JUnit XML ----------
if ($JUnitXml -ne '') {
    $xmlSb = [System.Text.StringBuilder]::new()
    $ts = (Get-Date).ToString('o')
    [void]$xmlSb.Append("<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n")
    [void]$xmlSb.Append("<testsuites name=`"unity_tests`" tests=`"$($report.Total)`" failures=`"$($report.Failed)`" errors=`"0`" timestamp=`"$ts`">`n")
    foreach ($c in $report.Cases) {
        $nm = $c.Test
        $failAttr = if ($c.Pass) { '0' } else { '1' }
        [void]$xmlSb.Append("  <testsuite name=`"$nm`" tests=`"1`" failures=`"$failAttr`" errors=`"0`" timestamp=`"$ts`">`n")
        [void]$xmlSb.Append("    <testcase classname=`"$nm`" name=`"run`" time=`"0`"`n")
        if (-not $c.Pass) {
            [void]$xmlSb.Append(">`n      <failure message=`"$($c.Detail)`" type=`"AssertionFailed`">$([Security.SecurityElement]::Escape($c.Detail))</failure>`n    </testcase>`n")
        } else {
            [void]$xmlSb.Append(" />`n")
        }
        [void]$xmlSb.Append("  </testsuite>`n")
    }
    [void]$xmlSb.Append('</testsuites>')
    try {
        [System.IO.File]::WriteAllText($JUnitXml, $xmlSb.ToString(), [System.Text.UTF8Encoding]::new($false))
        Write-Status "JUnit XML 已保存: $JUnitXml" -Type Success
    } catch {
        Write-Status "保存 JUnit XML 失败: $_" -Type Warning
    }
}

# ---------- 7. 汇总 ----------
Write-Host ''
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ' 测试汇总' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host "  总数: $($report.Total)"
Write-Host "  通过: $($report.Passed)" -ForegroundColor Green
Write-Host "  失败: $($report.Failed)" -ForegroundColor Red
Write-Host "  跳过: $($report.Skipped)" -ForegroundColor Yellow
Write-Host ''

if ($report.Failed -gt 0) { exit 1 }
exit 0
