<#
.SYNOPSIS
    Git Commit 规范辅助工具（基于 Conventional Commits）
.DESCRIPTION
    分析 git diff / git status 改动文件类型与内容，自动推荐 commit 类型和范围，
    生成规范化 commit message 模板（Angular 规范），可选自动执行 commit。
.USAGE
    git-commit-helper -ProjectDir <目录>
    git-commit-helper -Mode suggest (仅生成建议)
    git-commit-helper -Mode commit  -Message "xxx"  (生成+提交)
    git-commit-helper -BreakInfo "音频路径修复"  (添加破坏性变更说明)
  version: 1.0.0
#>

param(
    [string]$ProjectDir = '.',
    [ValidateSet('suggest','commit','interactive')]
    [string]$Mode = 'suggest',
    [string]$Message = '',
    [string]$Scope = '',
    [string]$Body = '',
    [string]$BreakInfo = '',
    [switch]$All,       # 等同 git commit -a
    [switch]$Amend,
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

function Get-FileTypeCategory([string]$ext) {
    switch -Exact ($ext) {
        '.c'     { return 'src' }
        '.h'     { return 'include' }
        '.cpp'   { return 'src' }
        '.hpp'   { return 'include' }
        '.s'     { return 'asm' }
        '.S'     { return 'asm' }
        '.ld'    { return 'linker' }
        '.cmake' { return 'build' }
        '.txt'   { return 'doc' }
        '.md'    { return 'doc' }
        '.ps1'   { return 'tool' }
        '.bat'   { return 'tool' }
        '.sh'    { return 'tool' }
        '.py'    { return 'tool' }
        '.json'  { return 'config' }
        '.yml'   { return 'ci' }
        '.yaml'  { return 'ci' }
        '.xml'   { return 'config' }
        default  { return 'other' }
    }
}

$ProjectDir = Resolve-Path $ProjectDir
Push-Location $ProjectDir
try {
    # 检查 git 是否可用
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { Write-Status 'git 命令不可用，请先安装 Git 并加入 PATH' -Type Error; exit 2 }

    if (-not $Quiet) {
        Write-Host ''
        Write-Host '==========================================' -ForegroundColor Cyan
        Write-Host ' Git Commit 规范辅助 (Conventional Commits)' -ForegroundColor Cyan
        Write-Host '==========================================' -ForegroundColor Cyan
        Write-Status "项目目录: $ProjectDir"
    }

    # 获取状态
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $status = git -c color.status=false status --short --untracked-files=all 2>$null; $ErrorActionPreference = $eap
    if ($LASTEXITCODE -ne 0) { Write-Status '当前目录不是 git 仓库' -Type Error; exit 3 }

    if ([string]::IsNullOrWhiteSpace($status)) {
        Write-Status '工作区干净，没有可提交的改动' -Type Warning
        exit 0
    }
    $changes = @()
    foreach ($line in ($status -split "`n")) {
        if ($line -match '^(..)\s+(.+)$') {
            $code = $matches[1]
            $file = $matches[2].Trim()
            $changes += [ordered]@{ Code=$code; File=$file; Category = Get-FileTypeCategory ([IO.Path]::GetExtension($file)) }
        }
    }
    if (-not $Quiet) {
        Write-Status "改动文件: $($changes.Count) 个"
        $changes | Group-Object Category | ForEach-Object {
            Write-Host "  [$($_.Name)] $($_.Count) 个文件" -ForegroundColor White
        }
    }

    # ---------- 推荐 commit 类型 ----------
    $catCounts = @{}
    foreach ($c in $changes) {
        if (-not $catCounts.ContainsKey($c.Category)) { $catCounts[$c.Category] = 0 }
        $catCounts[$c.Category]++
    }
    # 简单启发式
    $suggestType = 'chore'
    $hasSrc = ($catCounts['src'] -gt 0) -or ($catCounts['include'] -gt 0)
    $hasTest = @($changes | Where-Object { $_.File -match 'test_|_test\.|\/tests?\/' }).Count -gt 0
    $hasDoc  = ($catCounts['doc'] -gt 0)
    $hasTool = ($catCounts['tool'] -gt 0)
    $hasBuild = ($catCounts['build'] -gt 0) -or ($changes.File -match 'CMakeLists|Makefile|uvprojx')
    $hasCi   = ($catCounts['ci'] -gt 0)
    $hasConfig = ($catCounts['config'] -gt 0)

    # 检测 fix 关键词（diff 中含有 bug/fix/修复/修复错误/修复 bug 等）
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $diffStat = git diff --cached --stat 2>$null; $ErrorActionPreference = $eap
    if ([string]::IsNullOrWhiteSpace($diffStat)) { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $diffStat = git diff --stat 2>$null; $ErrorActionPreference = $eap }
    $eap2 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $diffWords = git diff --cached 2>$null; $ErrorActionPreference = $eap2
    if ([string]::IsNullOrWhiteSpace($diffWords)) { $eap2 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $diffWords = git diff 2>$null; $ErrorActionPreference = $eap2 }
    $isFix = $false
    if ($diffWords -match '(修复|fix|bug|error|wrong|crash|leak|panic|assert|assertion|oops|hang|deadlock|race)' -or
        ($Body -match '修复|bug|错误|崩溃')) { $isFix = $true }
    $isFeat = $false
    if ($diffWords -match '(新增|添加|create|add|implement|feat|新功能|支持)' -and -not $isFix) { $isFeat = $true }
    $isRefactor = $false
    if ($diffWords -match '(重构|refactor|rename|move|split|combine|cleanup)' -and -not $isFix -and -not $isFeat) { $isRefactor = $true }

    if ($isFix)                { $suggestType = 'fix' }
    elseif ($isFeat)           { $suggestType = 'feat' }
    elseif ($isRefactor -and $hasSrc) { $suggestType = 'refactor' }
    elseif ($hasTest)          { $suggestType = 'test' }
    elseif ($hasDoc)           { $suggestType = 'docs' }
    elseif ($hasBuild)         { $suggestType = 'build' }
    elseif ($hasTool)          { $suggestType = 'chore' }
    elseif ($hasCi)            { $suggestType = 'ci' }
    elseif ($hasConfig)        { $suggestType = 'chore' }
    elseif ($hasSrc)           { $suggestType = 'refactor' }

    # ---------- 推荐 scope ----------
    $suggestScope = $Scope
    if ([string]::IsNullOrWhiteSpace($suggestScope)) {
        $topDirs = @{}
        foreach ($c in $changes) {
            $rel = $c.File
            if ($rel -match '^([^/\\]+)[/\\]') {
                $d = $matches[1]
                if ($d -notin @('build','dist','out','.git','.vscode','.idea')) {
                    if (-not $topDirs.ContainsKey($d)) { $topDirs[$d] = 0 }
                    $topDirs[$d]++
                }
            }
        }
        if ($topDirs.Count -gt 0) {
            $suggestScope = ($topDirs.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
        }
    }

    if (-not $Quiet) {
        Write-Host ''
        Write-Status "推荐类型: $suggestType" -Type Success
        if ($suggestScope) { Write-Status "推荐范围: $suggestScope" -Type Success }
    }

    # ---------- 生成 message ----------
    $typeList = @('feat','fix','docs','style','refactor','perf','test','build','ci','chore','revert')
    $typeDesc = @{
        feat     = '新功能（feature）'
        fix      = 'Bug 修复'
        docs     = '文档变更'
        style    = '代码格式（不影响功能，空格/分号等）'
        refactor = '重构（既不新增功能也不修Bug）'
        perf     = '性能优化'
        test     = '新增/修正测试'
        build    = '构建系统或外部依赖变更'
        ci       = 'CI 配置变更'
        chore    = '杂项（工具/脚本/配置等）'
        revert   = '回滚之前提交'
    }

    $header = if ($suggestScope) { "$suggestType($suggestScope): " } else { "${suggestType}: " }
    if ($Message -ne '') {
        $subject = $Message
        if ($subject.Length -gt 72) { Write-Status "主题超过 72 字符（$($subject.Length)），建议缩短" -Type Warning }
        $finalMsg = $header + $subject
        if ($Body -ne '') { $finalMsg += "`n`n" + $Body }
        if ($BreakInfo -ne '') { $finalMsg += "`n`nBREAKING CHANGE: $BreakInfo" }
    } else {
        $finalMsg = $header + '<在此填写简短描述 (≤72字符)>'
        if (-not $Quiet) {
            $finalMsg += "`n`n<可选：详细描述，换行分隔>`n`n类型说明：`n"
            foreach ($t in $typeList) { $finalMsg += "  $t - $($typeDesc[$t])`n" }
        }
    }

    if (-not $Quiet) {
        Write-Host ''
        Write-Host '----- 建议的 Commit Message -----' -ForegroundColor White
        Write-Host $finalMsg
        Write-Host '----------------------------------' -ForegroundColor White
        Write-Host ''
    }

    # ---------- 交互式 / 执行 ----------
    if ($Mode -eq 'interactive') {
        Write-Host "请选择 commit 类型 (1-$($typeList.Count)):"
        for ($i=0; $i -lt $typeList.Count; $i++) { Write-Host "  $($i+1). $($typeList[$i])  $($typeDesc[$typeList[$i]])" }
        $ch = Read-Host "回车默认=$($typeList.IndexOf($suggestType)+1)"
        if ($ch -ne '' -and [int]::TryParse($ch, [ref]$null) -and [int]$ch -ge 1 -and [int]$ch -le $typeList.Count) {
            $suggestType = $typeList[[int]$ch - 1]
        }
        $sc = Read-Host "请输入 scope（回车默认: $suggestScope）"
        if ($sc -ne '') { $suggestScope = $sc }
        $subj = Read-Host "请输入主题 (必填)"
        if ([string]::IsNullOrWhiteSpace($subj)) { Write-Status '主题不能为空' -Type Error; exit 4 }
        $bod = Read-Host "请输入正文（可空，回车跳过）"
        $brk = Read-Host "破坏性变更说明（可空，回车跳过）"
        $header2 = if ($suggestScope) { "$suggestType($suggestScope): " } else { "${suggestType}: " }
        $finalMsg = $header2 + $subj
        if ($bod -ne '') { $finalMsg += "`n`n" + $bod }
        if ($brk -ne '') { $finalMsg += "`n`nBREAKING CHANGE: $brk" }
        Write-Host ''; Write-Host $finalMsg; Write-Host ''
        $confirm = Read-Host '是否执行 git commit? (Y/N)'
        if ($confirm -match '^[Yy]') {
            git commit -m $finalMsg $(if ($All) { '-a' } else { '' }) $(if ($Amend) { '--amend' } else { '' })
            if ($LASTEXITCODE -eq 0) { Write-Status 'Commit 成功' -Type Success; exit 0 }
            else { Write-Status "Commit 失败，退出码 $LASTEXITCODE" -Type Error; exit 1 }
        }
        exit 0
    }

    if ($Mode -eq 'commit') {
        if ([string]::IsNullOrWhiteSpace($Message)) { Write-Status '-Message 必填 (commit 模式)' -Type Error; exit 4 }
        if ($All) {
            git add -A 2>$null
            Write-Status '已执行 git add -A' -Type Info
        }
        git commit -m $finalMsg $(if ($Amend) { '--amend' } else { '' })
        if ($LASTEXITCODE -eq 0) { Write-Status 'Commit 成功' -Type Success; exit 0 }
        else { Write-Status "Commit 失败，退出码 $LASTEXITCODE" -Type Error; exit 1 }
    }

    # suggest 模式：不执行
    exit 0
} finally {
    Pop-Location
}
