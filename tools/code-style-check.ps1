<#
.SYNOPSIS
    嵌入式 C 代码规范检查工具（含数据溢出检测）
.DESCRIPTION
    根据用户自定义代码规范，检查 .c/.h 文件的命名、缩进（空格风格，禁用 Tab）、大括号、头文件保护、const、static 等问题，
    并额外检测 7 类数据溢出隐患（sprintf/strcpy/gets/memcpy 裸长度/移位溢出等）。
    生成规范化报告，供编码后自查。
.USAGE
    code-style-check -Path <目录或文件>
    code-style-check -Path src -Checks indent,brace,naming,header,const
    code-style-check -Path main.c -All -Json report.json
    code-style-check -Path main.c -Checks overflow   # 只跑溢出检测
    code-style-check -Path src -Checks overflow,defensive -ChangedOnly  # 增量：只扫 git diff 改动文件
  version: 1.0.1
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$Checks = 'all',

    [int]$MaxLineWidth = 120,

    [string]$Json = '',

    [switch]$Quiet,

    [switch]$ChangedOnly
)

$ErrorActionPreference = 'Stop'

# ============================================================
# 内联工具函数
# ============================================================
function Write-Status {
    param(
        [string]$Message,
        [string]$Type = 'Info'
    )
    if ($Quiet) { return }
    switch ($Type) {
        'Error'   { Write-Host "[X] $Message" -ForegroundColor Red }
        'Warning' { Write-Host "[!] $Message" -ForegroundColor Yellow }
        'Success' { Write-Host "[OK] $Message" -ForegroundColor Green }
        'Info'    { Write-Host "[*] $Message" -ForegroundColor Cyan }
        default   { Write-Host "$Message" }
    }
}

# 解析 Checks 参数
$ChecksList = @()
foreach ($c in $Checks -split ',') {
    $cTrim = $c.Trim().ToLower()
    if ('indent', 'linewidth', 'brace', 'naming', 'header', 'const', 'static', 'comment', 'global', 'magic', 'overflow', 'defensive', 'all' -contains $cTrim) {
        $ChecksList += $cTrim
    }
}
if ($ChecksList.Count -eq 0) { $ChecksList = @('all') }
function Test-CheckEnabled([string]$Name) {
    return ($ChecksList -contains $Name) -or ($ChecksList -contains 'all')
}

# ============================================================
# 统计数据结构
# ============================================================
$report = [ordered]@{
    GeneratedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Path        = (Resolve-Path $Path -ErrorAction SilentlyContinue).Path
    Files       = @()
    Summary     = [ordered]@{
        TotalFiles      = 0
        TotalIssues     = 0
        TotalWarnings   = 0
        ByCategory      = [ordered]@{}
    }
}

# ============================================================
# 收集待检查文件
# ============================================================
$filesToCheck = @()
$resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
if (-not $resolved) {
    Write-Status "路径不存在: $Path" -Type Error
    exit 2
}
$item = Get-Item $resolved
if ($item.PSIsContainer) {
    if ($ChangedOnly) {
        # 增量模式：用 git diff 获取改动文件，只扫 .c/.h
        $gitDir = $item.FullName
        $changedRaw = @()
        try {
            $changedRaw = @(git -C $gitDir diff --name-only --diff-filter=ACM HEAD 2>$null)
            if ($changedRaw.Count -eq 0) {
                # HEAD 没有提交时尝试 staged + unstaged
                $changedRaw = @(git -C $gitDir diff --name-only --cached 2>$null) + @(git -C $gitDir diff --name-only 2>$null) | Sort-Object -Unique
            }
        } catch {}
        $changedFiles = $changedRaw | Where-Object { $_ -match '\.[ch]$' } | ForEach-Object {
            $full = Join-Path $gitDir $_
            if (Test-Path $full) { Get-Item $full }
        }
        $filesToCheck = @($changedFiles)
        if (-not $Quiet -and $filesToCheck.Count -eq 0) {
            Write-Status "增量模式：未检测到 git 改动的 .c/.h 文件（如果是新项目未 git init，请去掉 -ChangedOnly 参数）" -Type Warning
        }
    } else {
        $filesToCheck = @(Get-ChildItem -Path $item.FullName -Include '*.c', '*.h' -Recurse -ErrorAction SilentlyContinue)
    }
} else {
    if ($item.Extension -in @('.c', '.h')) {
        $filesToCheck = @($item)
    }
}
$report.Summary.TotalFiles = $filesToCheck.Count

if (-not $Quiet) {
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ' 嵌入式 C 代码规范检查 (含溢出检测)' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Status "扫描路径: $($resolved.Path)"
    if ($ChangedOnly) { Write-Status "模式: 增量审查（仅 git diff 改动的 .c/.h 文件）" }
    Write-Status "待检查文件: $($filesToCheck.Count) 个"
    Write-Host ''
}

# ============================================================
# 辅助：判断行是否在字符串/注释中（粗略模式）
# ============================================================
function New-LineState {
    param([bool]$InBlockComment = $false)
    return [pscustomobject]@{
        InBlockComment = $InBlockComment
        InString       = $false
        StringChar     = ''
    }
}
function Update-LineState {
    param(
        [pscustomobject]$State,
        [string]$Line
    )
    $i = 0
    $len = $Line.Length
    while ($i -lt $len) {
        $ch = $Line[$i]
        $next = if ($i + 1 -lt $len) { $Line[$i + 1] } else { [char]0 }

        if ($State.InBlockComment) {
            if ($ch -eq '*' -and $next -eq '/') {
                $State.InBlockComment = $false
                $i += 2
                continue
            }
            $i++
            continue
        }
        if ($State.InString) {
            if ($ch -eq '\' -and $next -ne 0) { $i += 2; continue }
            if ($ch -eq $State.StringChar) { $State.InString = $false; $State.StringChar = '' }
            $i++
            continue
        }
        # 非注释非字符串
        if ($ch -eq '/' -and $next -eq '*') { $State.InBlockComment = $true; $i += 2; continue }
        if ($ch -eq '/' -and $next -eq '/') { break } # 行注释，结束本行
        if ($ch -eq '"' -or $ch -eq "'"[0]) { $State.InString = $true; $State.StringChar = [string]$ch; $i++; continue }
        $i++
    }
}

function Remove-Comments-Strings {
    param([string]$Line, [pscustomobject]$State)
    # 返回纯代码内容（不含注释和字符串），用于语法敏感检查
    $result = [System.Text.StringBuilder]::new()
    $i = 0
    $len = $Line.Length
    while ($i -lt $len) {
        $ch = $Line[$i]
        $next = if ($i + 1 -lt $len) { $Line[$i + 1] } else { [char]0 }
        if ($State.InBlockComment) {
            if ($ch -eq '*' -and $next -eq '/') { $State.InBlockComment = $false; $i += 2; continue }
            $i++; [void]$result.Append(' ')
            continue
        }
        if ($State.InString) {
            if ($ch -eq '\' -and $next -ne 0) { $i += 2; [void]$result.Append('  '); continue }
            if ($ch -eq $State.StringChar) { $State.InString = $false; $State.StringChar = '' }
            $i++; [void]$result.Append(' ')
            continue
        }
        if ($ch -eq '/' -and $next -eq '*') { $State.InBlockComment = $true; $i += 2; [void]$result.Append('  '); continue }
        if ($ch -eq '/' -and $next -eq '/') { break }
        if ($ch -eq '"' -or $ch -eq "'"[0]) { $State.InString = $true; $State.StringChar = [string]$ch; $i++; [void]$result.Append(' '); continue }
        [void]$result.Append($ch)
        $i++
    }
    return $result.ToString()
}

# ============================================================
# 检查项实现
# ============================================================
$categories = @{
    Indent    = @{ Name = '缩进（空格风格，禁用 Tab）'; Issues = @() }
    LineWidth = @{ Name = '行宽限制';       Issues = @() }
    Brace     = @{ Name = '大括号不省略';   Issues = @() }
    Naming    = @{ Name = '命名规范';       Issues = @() }
    Header    = @{ Name = '头文件保护';     Issues = @() }
    Const     = @{ Name = 'const 使用';     Issues = @() }
    Static    = @{ Name = 'static 使用';    Issues = @() }
    Comment   = @{ Name = '注释风格';       Issues = @() }
    Global    = @{ Name = '头文件全局变量'; Issues = @() }
    Magic     = @{ Name = '魔法数';         Issues = @() }
    Overflow  = @{ Name = '数据溢出隐患';   Issues = @() }
    Defensive = @{ Name = '防御性编程';     Issues = @() }
}

foreach ($file in $filesToCheck) {
    $fileReport = [ordered]@{
        File    = $file.FullName
        Ext     = $file.Extension
        Issues  = @()
        Counts  = [ordered]@{}
    }
    $lines = @()
    try {
        $lines = Get-Content $file.FullName -Encoding UTF8 -ErrorAction Stop
    } catch {
        $fileReport.Issues += [ordered]@{ Category = 'Header'; Line = 0; Message = "无法读取文件: $_" }
        $report.Files += $fileReport
        continue
    }

    $lineState = New-LineState
    [int]$braceDepth = 0
    $isHeader = ($file.Extension -eq '.h')
    $hasIfndefGuard = $false
    $hasDefineGuard = $false
    $hasEndifGuard = $false
    $guardMacroName = ''

    # 记录已声明的函数（用于建议static）
    $funcDeclarations = @{}
    $funcDefinitions = @{}
    # 记录文件级全局变量定义和声明
    $globalVars = @()

    # D1 检测：switch 跟踪栈（每层 switch: @{ SwitchLine=...; HasDefault=$false; ExpectedDepth=...; Popped=$false }）
    $switchStack = [System.Collections.ArrayList]::new()
    # Q1 检测：struct 跟踪栈（每层 struct: @{ OpenLine=...; Closed=$false; ClosedLine=...; HasAssert=$false; SearchLeft=6 }）
    $structAssertStack = [System.Collections.ArrayList]::new()
    # Q2 检测：文件级跟踪【外设写行】与【对应时钟使能行】，最后对比同类型外设是否写反了顺序
    $q2PeriphWrites = [System.Collections.ArrayList]::new()
    $q2ClockEnables  = [System.Collections.ArrayList]::new()
    # Q4 检测：8051 项目特征（sfr / sbit / __SDCC / pdata / xdata / STC8）命中后记录 MOVX @R0/@R1 和页切换出现的行号；最后做分段分析
    [bool]$q4Is8051 = $false
    $q4MovxLines   = [System.Collections.ArrayList]::new()
    $q4BankSwitchLines = [System.Collections.ArrayList]::new()
    # Q5 检测：8051 项目 16/32 位全局变量声明 -> 后续读行附近是否有 EA=0/disable_irq 关中断保护
    $q5GlobalWideVars = [System.Collections.ArrayList]::new()
    $q5WideReads    = [System.Collections.ArrayList]::new()
    $q5CritLines    = [System.Collections.ArrayList]::new()

    # Q7 检测：main() 前 50 行内是否出现 NVIC 优先级分组设置函数
    [int]$q7MainLine = 0
    [bool]$q7HasPriorityGroup = $false

    # Q6 检测：ISR 函数跟踪（记录当前是否在 *IRQHandler / *ISR 函数体内，及进入时的 braceDepth，离开后复位）
    $currentIsrInfo = $null  # $null = 不在 ISR 中；非 null = { Name=..., EnterLine=..., EnterDepth=... }
    # D2 辅助：是否在 struct/enum/union/typedef 定义体里（记录进入时的 braceDepth）
    $inTypeDefAtDepth = -1  # -1 表示不在，>=0 表示在对应深度以下都是类型定义体
    $prevBraceDepth = 0

    for ($ln = 0; $ln -lt $lines.Count; $ln++) {
        $lineNo = $ln + 1
        $raw = $lines[$ln]

        # ============== 行宽检查 ==============
        if (Test-CheckEnabled 'linewidth') {
            if ($raw.Length -gt $MaxLineWidth) {
                $categories.LineWidth.Issues += "$($file.Name):$lineNo 行宽 $($raw.Length) > $MaxLineWidth"
                $fileReport.Issues += [ordered]@{ Category='LineWidth'; Line=$lineNo; Message="行宽 $($raw.Length) > $MaxLineWidth" }
            }
        }

        # ============== 缩进检查（Tab vs 空格） ==============
        if (Test-CheckEnabled 'indent') {
            if ($ln -eq 0 -and $raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
            $trimmedRaw = $raw.TrimStart()
            $isCommentLine = $false
            if ($lineState.InBlockComment) { $isCommentLine = $true }
            if ($trimmedRaw.StartsWith("*")) { $isCommentLine = $true }
            if ($trimmedRaw.StartsWith("//")) { $isCommentLine = $true }
            if ($trimmedRaw.StartsWith("/*")) { $isCommentLine = $true }
            if (-not $isCommentLine -and $raw -match '^(\s+)') {
                $indent = $matches[1]
                $hasTab = $indent.Contains("`t")
                $hasSpace = $indent.Contains(' ')
                if ($hasTab -and $hasSpace) {
                    $categories.Indent.Issues += "$($file.Name):$lineNo Tab mixed with space"
                    $fileReport.Issues += [ordered]@{ Category="Indent"; Line=$lineNo; Message="Tab mixed with space" }
                } elseif ($hasTab -and -not $hasSpace) {
                    $categories.Indent.Issues += "$($file.Name):$lineNo uses Tab (should use spaces)"
                    $fileReport.Issues += [ordered]@{ Category="Indent"; Line=$lineNo; Message="Uses Tab (should use spaces)" }
                }
            }
        }

        # 更新 struct/enum/union 大括号深度（用于区分成员 vs 全局变量）
        $pureForDepth = $raw -replace '//.*', '' -replace '".*?(?<!\\)"', ''
        $openBraces  = ([regex]::Matches($pureForDepth, '\{')).Count
        $closeBraces = ([regex]::Matches($pureForDepth, '\}')).Count
        $prevBraceDepth = $braceDepth
        $braceDepth += ($openBraces - $closeBraces)
        if ($braceDepth -lt 0) { $braceDepth = 0 }

        # D2 辅助：检测是否进入/退出 struct/enum/union/typedef 定义体
        if ($inTypeDefAtDepth -ge 0 -and $braceDepth -le $inTypeDefAtDepth) {
            $inTypeDefAtDepth = -1  # 闭合了，退出类型定义体
        }
        if ($inTypeDefAtDepth -lt 0) {
            # 进入：typedef struct XXX {  /  typedef enum {  /  struct XXX {  等
            if ($t -match '^\s*(typedef\s+)?(struct|enum|union)\b[^{]*\{') {
                $inTypeDefAtDepth = $braceDepth - 1  # 记录当前开括号的外层深度
            }
        }

        # 更新行状态，并获取纯代码版本
        $state = New-LineState -InBlockComment $lineState.InBlockComment
        $code = Remove-Comments-Strings -Line $raw -State $state
        $lineState = $state
        $t = $code   # 后面很多检查用纯代码版本

        # ============== 大括号不省略检查 ==============
        if (Test-CheckEnabled 'brace') {
            # 检查 if/else/for/while/do 后面没有 {
            if ($code -match '(^|[^a-zA-Z_])(if|else\s*if|for|while|do)\s*\([^;{]*\)\s*$') {
                $categories.Brace.Issues += "$($file.Name):$lineNo $($matches[2]) 行末缺少 {（大括号不可省略）"
                $fileReport.Issues += [ordered]@{ Category='Brace'; Line=$lineNo; Message="$($matches[2]) 语句大括号省略" }
            } elseif ($code -match '(^|[^a-zA-Z_])(if|else\s*if|for|while)\s*\([^;{]*\)\s*[^{;]*;') {
                $categories.Brace.Issues += "$($file.Name):$lineNo $($matches[2]) single-line stmt missing braces"
                $fileReport.Issues += [ordered]@{ Category='Brace'; Line=$lineNo; Message="$($matches[2]) single-line missing braces" }
            } elseif ($code -match '(^|[^a-zA-Z_])else\s*$') {
                $categories.Brace.Issues += "$($file.Name):$lineNo else 行末缺少 {（大括号不可省略）"
                $fileReport.Issues += [ordered]@{ Category='Brace'; Line=$lineNo; Message='else 语句大括号省略' }
            }
        }

        # ============== 头文件保护检查 ==============
        if ($isHeader -and (Test-CheckEnabled 'header') -and $lineNo -lt 50) {
            if ($raw -match '^\s*#\s*ifndef\s+(\S+)') {
                $hasIfndefGuard = $true
                $guardMacroName = $matches[1]
            }
            if ($hasIfndefGuard -and $guardMacroName -ne '' -and
                $raw -match ("^\s*#\s*define\s+" + [regex]::Escape($guardMacroName) + "\b")) {
                $hasDefineGuard = $true
            }
        }
        if ($isHeader -and (Test-CheckEnabled 'header') -and $lineNo -eq $lines.Count) {
            # 粗略检查最后非空行是否 #endif
            for ($endLn = $lines.Count - 1; $endLn -ge 0; $endLn--) {
                if ($lines[$endLn].Trim() -ne '') {
                    if ($lines[$endLn] -match '^\s*#\s*endif') {
                        $hasEndifGuard = $true
                    }
                    break
                }
            }
        }

        # ============== 头文件中是否定义全局变量（只允许extern） ==============
        if ($isHeader -and (Test-CheckEnabled 'global')) {
            $t2 = $code.Trim()
            if ($t2 -ne '' -and $t2 -notmatch '^#' -and $t2 -notmatch '^typedef' -and $t2 -notmatch '^extern\b' -and
                $t2 -notmatch '^struct\s+\w*\s*$' -and $t2 -notmatch '^union\s+\w*\s*$' -and $t2 -notmatch '^enum\s+\w*\s*$' -and
                $t2 -notmatch '^\}' -and $t2 -notmatch '^\s*$') {
                if ($braceDepth -eq 0 -and $t2 -notmatch '^typedef\b' -and $t2 -notmatch '^extern\b' -and $t2 -notmatch '^struct\s+\w*\s*\{' -and $t2 -notmatch '^union\s+\w*\s*\{' -and $t2 -notmatch '^enum\s+\w*\s*\{' -and
                $t2 -match '^\s*(volatile\s+|static\s+|const\s+|unsigned\s+|signed\s+)*(int|char|short|long|float|double|bool|uint8_t|uint16_t|uint32_t|uint64_t|int8_t|int16_t|int32_t|int64_t|size_t|esp_err_t|bool|gpio_num_t|uart_port_t|i2c_port_t|spi_host_device_t)\s+\*?\s*([A-Za-z_]\w*)\s*(\[.*\]|=\s*[^;]*)?\s*;') {
                    $varName = $matches[3]
                    if ($varName -notmatch '^(NULL|true|false|TRUE|FALSE|OK|ERROR|ESP_OK|ESP_FAIL)$') {
                        $categories.Global.Issues += "$($file.Name):$lineNo 头文件中定义了全局变量 '$varName'（应在 .c 中定义，头文件只 extern 声明）"
                        $fileReport.Issues += [ordered]@{ Category='Global'; Line=$lineNo; Message="头文件中定义全局变量 '$varName'" }
                    }
                }
            }
        }

        # ============== 命名规范检查 ==============
        if (Test-CheckEnabled 'naming') {

            # 1. 宏定义：必须全大写
            if ($t -match '^\s*#\s*define\s+([A-Za-z_]\w*)') {
                $macro = $matches[1]
                if ($macro -cmatch '[a-z]' -and $macro -notmatch '^_') {
                    if ($macro -notmatch '^(UNITY|TEST|CMOCK|ASSERT|config|MIN|MAX|MIN2|MAX2|BIT|SET_BIT|CLR_BIT|UNUSED)$') {
                        $categories.Naming.Issues += "$($file.Name):$lineNo 宏 '$macro' 命名包含小写字母（宏应全大写）"
                        $fileReport.Issues += [ordered]@{ Category='Naming'; Line=$lineNo; Message="宏 '$macro' 未使用全大写命名" }
                    }
                }
            }

            # 2. 全局变量定义：g_ 前缀（非 static 且在文件级）
            if ($braceDepth -eq 0 -and $t -notmatch 'extern\b' -and
                $t -match '^\s*(?:volatile\s+|const\s+)?(?:unsigned\s+|signed\s+)?(?:int|char|short|long|float|double|bool|uint8_t|uint16_t|uint32_t|uint64_t|int8_t|int16_t|int32_t|int64_t|size_t|esp_err_t|gpio_num_t|uart_port_t|i2c_port_t|spi_host_device_t)\s+\*?\s*([A-Za-z_]\w*)\s*(?:\[.*\]|=\s*[^;]*)?\s*;') {
                $varName = $matches[1]
                if ($varName -notmatch '^(NULL|true|false|TRUE|FALSE|main)$' -and
                    -not ($t -match '^\s*static\b')) {
                    if ($varName -notmatch '^g_' -and $varName -notmatch '^s_' -and $t -notmatch 'extern\b') {
                        $categories.Naming.Issues += "$($file.Name):$lineNo 全局变量 '$varName' 缺少 g_ 前缀"
                        $fileReport.Issues += [ordered]@{ Category='Naming'; Line=$lineNo; Message="全局变量 '$varName' 缺少 g_ 前缀" }
                    }
                }
            }

            # 3. 静态变量：s_ 前缀（文件级）
            if ($braceDepth -eq 0 -and
                $t -match '^\s*static\s+(?:volatile\s+|const\s+)?(?:unsigned\s+|signed\s+)?(?:int|char|short|long|float|double|bool|uint8_t|uint16_t|uint32_t|uint64_t|int8_t|int16_t|int32_t|int64_t|size_t|esp_err_t|gpio_num_t|uart_port_t|i2c_port_t)\s+\*?\s*([A-Za-z_]\w*)\s*(?:\[.*\]|=\s*[^;]*)?\s*;') {
                $varName = $matches[1]
                if ($varName -notmatch '^s_') {
                    $categories.Naming.Issues += "$($file.Name):$lineNo 静态变量 '$varName' 缺少 s_ 前缀"
                    $fileReport.Issues += [ordered]@{ Category='Naming'; Line=$lineNo; Message="静态变量 '$varName' 缺少 s_ 前缀" }
                }
            }

            # 4. 结构体/枚举/联合类型后缀：_t / _e / _u
            if ($t -match '^\s*typedef\s+struct\s*\{[^}]*\}\s*([A-Za-z_]\w*)\s*;') {
                $tn = $matches[1]
                if ($tn -notmatch '_t$') {
                    $categories.Naming.Issues += "$($file.Name):$lineNo 结构体类型 '$tn' 缺少 _t 后缀"
                    $fileReport.Issues += [ordered]@{ Category='Naming'; Line=$lineNo; Message="typedef 结构体 '$tn' 缺少 _t 后缀" }
                }
            }
            if ($t -match '^\s*typedef\s+enum\s*\{[^}]*\}\s*([A-Za-z_]\w*)\s*;') {
                $tn = $matches[1]
                if ($tn -notmatch '_e$') {
                    $categories.Naming.Issues += "$($file.Name):$lineNo 枚举类型 '$tn' 缺少 _e 后缀"
                    $fileReport.Issues += [ordered]@{ Category='Naming'; Line=$lineNo; Message="typedef 枚举 '$tn' 缺少 _e 后缀" }
                }
            }

            # 5. 枚举值：全大写 + 模块前缀
            if ($t -match '^\s*([A-Z_][A-Z0-9_]*)\s*(?:=\s*[^,]+)?\s*,?\s*$') {
                $ev = $matches[1]
                $prev = ''
                for ($bk = [Math]::Max(0, $ln - 5); $bk -lt $ln; $bk++) { $prev += $lines[$bk] + "`n" }
                if ($prev -match 'typedef\s+enum|enum\s+\w+\s*\{|enum\s*\{') {
                    if ($ev -cnotmatch '^[A-Z0-9_]+$') {
                        $categories.Naming.Issues += "$($file.Name):$lineNo 枚举值 '$ev' 未使用全大写"
                        $fileReport.Issues += [ordered]@{ Category='Naming'; Line=$lineNo; Message="枚举值 '$ev' 未使用全大写" }
                    }
                }
            }
        }

        # ============== const 最大化检查（仅做建议） ==============
        if (Test-CheckEnabled 'const') {
            if ($t -match '\w+\s*\([^;]*\)\s*\{?\s*$' -and $t -notmatch '^#') {
                if ($t -match '\(([^()]*)\)') {
                    $paramList = $matches[1]
                    foreach ($param in ($paramList -split ',')) {
                        $p = $param.Trim()
                        if ($p -match '(^|\s)(char|int|short|long|float|double|uint8_t|uint16_t|uint32_t|uint64_t|int8_t|int16_t|int32_t|int64_t|size_t|void|esp_err_t|bool|gpio_num_t|uart_port_t|i2c_port_t|spi_host_device_t|[A-Za-z_]\w*_t|struct\s+\w+)\s*\*\s*([A-Za-z_]\w*)') {
                            $typePart = $matches[1] + $matches[2]
                            $pName = $matches[3]
                            if ($typePart -notmatch '\bconst\b' -and $pName -notmatch '^(NULL)$') {
                                if ($categories.Const.Issues.Count -lt 30 -and $fileReport.Issues.Count -lt 50) {
                                    $categories.Const.Issues += "$($file.Name):$lineNo 参数 '$pName' 如为只读输入，建议加 const 修饰指向的数据: const $($matches[2]) *$pName"
                                    $fileReport.Issues += [ordered]@{ Category='Const'; Line=$lineNo; Message="指针参数 '$pName' 建议加 const（如为输入参数）" }
                                }
                            }
                        }
                    }
                }
            }
        }

        # ============== static 最大化检查（仅做建议） ==============
        if (Test-CheckEnabled 'static') {
            if ($t -match '^\s*(?:static\s+)?(?:inline\s+)?(?:const\s+|volatile\s+)?(?:unsigned\s+|signed\s+)?(?:int|char|short|long|float|double|bool|void|uint8_t|uint16_t|uint32_t|uint64_t|int8_t|int16_t|int32_t|int64_t|size_t|esp_err_t|gpio_num_t|uart_port_t|i2c_port_t|spi_host_device_t|[A-Za-z_]\w*_t)\s+([A-Za-z_]\w*)\s*\(') {
                $fn = $matches[1]
                if ($fn -ne 'main' -and $fn -ne 'app_main' -and $fn -notmatch '^(app_main|xTask|TaskFunction|event_handler|esp_event|timer_callback|gpio_isr|uart_event)' -and $t -notmatch '^\s*static\b' -and $t -notmatch 'extern\b') {
                    $funcDefinitions[$fn] = @{ File = $file.Name; Line = $lineNo }
                    if ($fn -cmatch '[a-z][A-Z]') {
                        $categories.Naming.Issues += "$($file.Name):$lineNo function '$fn' uses CamelCase (should be snake_case)"
                        $fileReport.Issues += [ordered]@{ Category='Naming'; Line=$lineNo; Message="function '$fn' CamelCase" }
                    }
                }
            }
        }

        # ============== 魔法数（与 pre-code-check 类似，但这里更宽松） ==============
        if (Test-CheckEnabled 'magic' -and $file.Extension -eq '.c') {
            if ($t -match '(if|while|for|switch)\s*\([^)]*\b(\d{1,}|0x[0-9a-fA-F]{1,})\b[^)]*\)') {
                $num = $matches[2]
                if ($num -ne '0' -and $num -ne '1' -and $num -ne '2' -and $num -ne '8' -and $num -ne '16' -and $num -ne '32' -and $num -ne '64' -and $num -ne '100' -and $num -ne '1000') {
                    if ($categories.Magic.Issues.Count -lt 20) {
                        $categories.Magic.Issues += "$($file.Name):$lineNo 魔法数 $num（建议改为宏定义）"
                        $fileReport.Issues += [ordered]@{ Category='Magic'; Line=$lineNo; Message="魔法数 $num，建议用宏代替" }
                    }
                }
            }
        }

        # ============== 数据溢出专项检测（P0+P1） + Q1/Q2/Q3/Q4/Q5 跨分类检测 ==============
        # 【修复】原仅 overflow 开启才进块，导致只开 defensive 时 Q1/Q2/Q3/Q4/Q5 全不执行。Q1/Q3 属 overflow，Q2/Q4/Q5/Q6 属 defensive，两类任意开启都应跑
        if (Test-CheckEnabled 'overflow' -or Test-CheckEnabled 'defensive') {

            # ---------- P0-1 / P0-2：危险字符串函数（sprintf/vsprintf/strcpy/strcat/gets） ----------
            if ($t -match '(^|[^a-zA-Z_])(sprintf|vsprintf|strcpy|strcat|gets)\s*\(') {
                $fnName = $matches[2]
                $severity = 'P0 致命'
                if ($fnName -eq 'gets') {
                    $msg = "gets() 已被 C11 标准废弃，任何场景都禁止使用！（无长度限制，100% 溢出风险）"
                } elseif ($fnName -eq 'sprintf' -or $fnName -eq 'vsprintf') {
                    $msg = "$fnName() 无长度限制，禁止使用！建议改为 snprintf()，长度参数用 sizeof(buf)"
                } else {
                    $msg = "$fnName() 无长度限制，禁止使用！建议改为 strncpy()/strncat()，长度传 sizeof(dst)-1 并手动补 \0"
                }
                $categories.Overflow.Issues += "[P0 致命] $($file.Name):$lineNo $msg"
                $fileReport.Issues += [ordered]@{ Category='Overflow'; Line=$lineNo; Severity='P0'; Message="$fnName() 危险：$msg" }
            }

            # ---------- P0-1：snprintf 长度参数是裸数字（不是 sizeof/变量/宏） ----------
            # 匹配 snprintf(xxx, 数字, ...)
            if ($t -match 'snprintf\s*\(\s*[^,]+,\s*(\d+)\s*,') {
                $hardLen = $matches[1]
                $msg = "snprintf() 第 2 个参数写死为 $hardLen（应该用 sizeof(目标缓冲区)），缓冲区大小改了这里容易忘改导致溢出"
                $categories.Overflow.Issues += "[P0 致命] $($file.Name):$lineNo $msg"
                $fileReport.Issues += [ordered]@{ Category='Overflow'; Line=$lineNo; Severity='P0'; Message="snprintf 长度写死：$msg" }
            }

            # ---------- P0-4：memcpy/memmove/memset 长度参数是裸数字 ----------
            # 匹配 memcpy(xxx, xxx, 数字)，数字太小(<=4)放过（可能是故意写单字节/小结构体）
            if ($t -match '(memcpy|memmove|memset)\s*\(\s*[^,]+,\s*[^,]+,\s*(\d+)\s*\)') {
                $memFn = $matches[1]
                $hardLen = [int]$matches[2]
                if ($hardLen -gt 4) {
                    $msg = "$memFn() 长度参数是裸数字 $hardLen（禁止 >4 的裸数字）！应该传 sizeof(目标) 或已校验过的变量，防止缓冲区改大小后这里忘改"
                    $categories.Overflow.Issues += "[P0 致命] $($file.Name):$lineNo $msg"
                    $fileReport.Issues += [ordered]@{ Category='Overflow'; Line=$lineNo; Severity='P0'; Message="$memFn 长度裸数字：$msg" }
                }
            }

            # ---------- P1-1：移位溢出（移位位数 >= 常见类型位宽） ----------
            # 匹配 << 8 / << 16 / << 32 / << 64 等（可能刚好是类型宽度或超过），数字模式
            if ($t -match '<<\s*(\d+)') {
                $shiftBits = [int]$matches[1]
                if ($shiftBits -ge 32) {
                    $msg = "移位位数 = $shiftBits 位，uint32_t/int32_t 移位 >=32 是 C 标准未定义行为（UB）！若目标是 uint64_t 请使用 1ULL 先扩宽；若位数是变量请先 if (bits < 32) 判断"
                    $categories.Overflow.Issues += "[P1 高]   $($file.Name):$lineNo $msg"
                    $fileReport.Issues += [ordered]@{ Category='Overflow'; Line=$lineNo; Severity='P1'; Message="移位 UB：$msg" }
                } elseif ($shiftBits -ge 16) {
                    $msg = "移位位数 = $shiftBits，uint16_t/uint8_t 变量左移 $shiftBits 位是 C 标准未定义行为（UB）。如果目标是宽类型请先强制类型提升：((uint32_t)val) << $shiftBits"
                    $categories.Overflow.Issues += "[P1 高]   $($file.Name):$lineNo $msg"
                    $fileReport.Issues += [ordered]@{ Category='Overflow'; Line=$lineNo; Severity='P1'; Message="移位可疑：$msg" }
                }
            }

            # ---------- P1-3：int（有符号）和 sizeof/size_t（无符号）比较 ----------
            # 匹配 if ( xxx < sizeof ... )，粗略看变量部分（不可能完全精确，但能抓住常见模式）
            if ($t -match '(if|while)\s*\(\s*([A-Za-z_]\w*)\s*[<>]=?\s*sizeof\s*\(') {
                $varName = $matches[2]
                # 过滤常见的无符号变量名前缀（u_/us_/ul_/g_u/s_u/size_/len_/count_ 不一定，但抓常见错误）
                # 这里的策略是：只要不是明确无符号前缀，就警告（宁杀错不放过）
                if ($varName -notmatch '^(sizeof|strlen|u_|us_|ul_|ull_|size_|len_)' -and
                    $varName -notmatch 'U32|U16|U8|U64|_u32|_u16|_u8|_u64|Uint|uint') {
                    $msg = "有符号变量 '$varName' 与无符号 sizeof() 直接比较（$($matches[1]) 条件）。若 $varName 为负（错误返回值 -1 等），会隐式转成巨大的无符号数导致条件恒真/恒假。建议先判 $varName >= 0，再转 (size_t)$varName 比较"
                    $categories.Overflow.Issues += "[P1 高]   $($file.Name):$lineNo $msg"
                    $fileReport.Issues += [ordered]@{ Category='Overflow'; Line=$lineNo; Severity='P1'; Message="有符号/无符号比较：$msg" }
                }
            }

            # ---------- P1-3a：无符号循环变量递减死循环 ----------
            # 匹配单行 for (uintX_t var = ...; var >= 0; --var 或 var--)
            # 无符号变量永远 >= 0，条件恒真，--到 0 后回绕为 UINT_MAX → 死循环
            # 注意：仅检测单行 for 循环；多行 for 头需人工审查
            if ($t -match 'for\s*\(\s*(uint8_t|uint16_t|uint32_t|uint64_t|unsigned\s+char|unsigned\s+short|unsigned\s+int|unsigned\s+long|size_t)\s+(\w+)\s*=\s*[^;]*;\s*\2\s*>=\s*0\s*;') {
                $varName = $matches[2]
                $typeName = $matches[1]
                $msg = "无符号循环变量 '$varName' ($typeName) 用 '>= 0' 做递减循环条件！无符号数永远 >= 0 条件恒真，--到 0 后回绕为 UINT_MAX → 死循环。改用有符号类型（int8_t/int16_t/int32_t），或改用递增循环 for (uintX_t i=0; i<=N; ++i)"
                $categories.Overflow.Issues += "[P1 高]   $($file.Name):$lineNo $msg"
                $fileReport.Issues += [ordered]@{ Category='Overflow'; Line=$lineNo; Severity='P1'; Message="无符号循环递减死循环：$msg" }
            }

            # ---------- P1-3b：strlen() 减法回绕 ----------
            # 匹配 strlen(s) - N（N 为正整数），空字符串时 strlen=0，0-N=SIZE_MAX → 越界访问
            # 注意：静态分析无法判断上游是否已判空，统一标记为待人工确认
            if ($t -match 'strlen\s*\([^)]*\)\s*-\s*[1-9]\d*') {
                $msg = "strlen() 结果减正整数可能回绕！若字符串为空 strlen 返回 0，0-N=SIZE_MAX → 越界访问。请确认上游已判空：if (strlen(s) > 0) { ... strlen(s)-N ... }，或改用有符号变量接收 len = (int)strlen(s)"
                $categories.Overflow.Issues += "[P1 高]   $($file.Name):$lineNo $msg"
                $fileReport.Issues += [ordered]@{ Category='Overflow'; Line=$lineNo; Severity='P1'; Message="strlen 减法回绕：$msg" }
            }

            # ---------- Q1：struct 协议结构体缺 _Static_assert(sizeof 校验) ----------
            # 模式：typedef struct / struct XXX { 定义了 } pkt_t; 之后若干行，没有 static_assert/_Static_assert(sizeof(pkt_t) == N)
            # 原因：ARM/32 位编译器自动 padding，肉眼算的字节数 != sizeof，memcpy 裸长度会少拷 padding 字节
            # 策略：跟踪 struct 栈，记录进入时的行号、结构体名候选、braceDepth，闭合后 5 行内搜索 static_assert，没找到则告警
            # 注意：仅对 typedef struct + 定义了名字的协议型 struct 告警（通常是 pkt/msg/frame/cmd/rsp 等后缀），普通 struct 如结构体数组/局部临时 struct 忽略
            if ($raw -match 'typedef\s+struct\b') {
                # 进入 typedef struct 块：记录开启行的 braceDepth（下一行出现 { 时才是真正进入深度，用栈）
                [void]$structAssertStack.Add([ordered]@{
                    OpenLine    = $lineNo
                    CloseDepth  = -1  # 遇到 } 时记录当时的 braceDepth（闭合后回到这个深度）
                    Closed      = $false
                    ClosedLine  = -1
                    HasAssert   = $false
                    SearchLeft  = 6   # 闭合后再查 6 行（允许 1-2 行空行后写 static_assert）
                })
            }
            # 普通命名 struct：struct XXX {
            if ($raw -match '^\s*struct\s+([A-Za-z_]\w*)\s*\{' -and -not ($raw -match '^\s*typedef')) {
                [void]$structAssertStack.Add([ordered]@{
                    OpenLine    = $lineNo
                    CloseDepth  = -1
                    Closed      = $false
                    ClosedLine  = -1
                    HasAssert   = $false
                    SearchLeft  = 6
                })
            }
            # struct 闭合：braceDepth 从高变低时，栈中所有 CloseDepth 未设置的条目设置 CloseDepth = 当前 braceDepth
            # 方式：prevBraceDepth 已在循环开头记录（比 braceDepth 先更新），所以闭合时 braceDepth < prevBraceDepth
            if ($prevBraceDepth -gt $braceDepth) {
                # 至少有一个闭合：处理 struct 栈
                for ($si = 0; $si -lt $structAssertStack.Count; $si++) {
                    $s = $structAssertStack[$si]
                    if (-not $s.Closed -and $s.CloseDepth -lt 0) {
                        # 遇到第一个 } 时认为当前 struct 关闭了（简化：只跟最近一次闭合匹配，嵌套 struct 用 braceDepth 层次区分）
                        # 更稳妥的方式：struct 开 { 的深度 = prevBraceDepth - 1？不，我们记录不到开 { 的确切深度。
                        # 简化策略：栈中最后一个未闭合的 struct 就是这次 } 对应的。
                    }
                }
                # 简化：从栈顶找第一个未 Closed 的条目，把它标记为 Closed
                for ($si = $structAssertStack.Count - 1; $si -ge 0; $si--) {
                    $s = $structAssertStack[$si]
                    if (-not $s.Closed) {
                        $s.Closed = $true
                        $s.ClosedLine = $lineNo
                        $s.CloseDepth = $braceDepth
                        break
                    }
                }
            }
            # 扫描 static_assert 行：如果已 Closed 但 SearchLeft>0 且未 HasAssert，则检测当前行是否含 static_assert(sizeof
            for ($si = 0; $si -lt $structAssertStack.Count; $si++) {
                $s = $structAssertStack[$si]
                if ($s.Closed -and -not $s.HasAssert -and $s.SearchLeft -gt 0) {
                    if ($raw -match '_?Static_assert\s*\(\s*sizeof\s*\(') { $s.HasAssert = $true }
                    $s.SearchLeft = $s.SearchLeft - 1
                    # SearchLeft 耗尽且仍未 assert → 告警（仅在 SearchLeft 刚减到 0 时报一次）
                    if ($s.SearchLeft -eq 0 -and -not $s.HasAssert) {
                        $msg = "结构体定义（L$($s.OpenLine)）缺少 _Static_assert(sizeof(...)) 编译期断言！32 位 ARM 编译器会自动按 4 字节对齐 padding，肉眼算的字节数 != sizeof。协议结构体（用于串口/SPI memcpy 解析）请立即添加：_Static_assert(sizeof(pkt_t) == N, `"pkt_t size mismatch`")。纯内部状态 struct 可忽略（确认无协议用途后可 suppress）"
                        $categories.Overflow.Issues += "[P0 致命] $($file.Name):$($s.ClosedLine) $msg"
                        $fileReport.Issues += [ordered]@{ Category='Overflow'; Line=$s.ClosedLine; Severity='P0'; Message="Q1 struct 缺 static_assert：$msg" }
                    }
                }
            }

            # ---------- Q3：#define 宏含运算符但缺最外层括号 ----------
            # 模式：#define XXX(a) expr，expr 中有 + - * / << >> 但整个替换表达式没有用最外层括号包起来
            # 反例（错）：#define SQUARE(x) x*x          → SQUARE(a+b) 展开为 a+b*a+b
            # 正例（对）：#define SQUARE(x) ((x)*(x))    → 双重括号，内外都安全
            # 规则（简化）：宏值中如果有运算符且宏值第一个和最后一个非空字符不是配对的 ( ) → 告警
            if ($raw -match '^\s*#\s*define\s+([A-Za-z_]\w*)\s*(?:\([^)]*\))?\s*(.+)$') {
                $macroName = $matches[1]    # 立即保存宏名，避免后续 -match 覆盖 $matches
                $macroValue = $matches[2].Trim()
                # 【FP 修复】先剥 C 注释：/* ... */（单行内）和 // 行尾，避免注释里的 * / - 被误判为运算符
                $macroNoComment = $macroValue -replace '/\*.*?\*/',' ' -replace '//.*$',''
                # 跳过以 # / ##（字符串化/令牌粘贴）、do {、if、while 开头的语句宏（有自己的 do{}while(0) 保护）
                if ($macroNoComment -match '^(''|#|##|do\s*\{|if\s*\(|while\s*\()') {
                    # 不用检测
                } elseif ($macroNoComment -match '[+\-*/]|<<|>>') {
                    $trimmedVal = $macroNoComment.Trim()
                    $firstChar = if ($trimmedVal.Length -gt 0) { $trimmedVal[0] } else { [char]0 }
                    $lastChar  = if ($trimmedVal.Length -gt 0) { $trimmedVal[$trimmedVal.Length-1] } else { [char]0 }
                    $isWrapped = ($firstChar -eq [char]'(' -and $lastChar -eq [char]')')
                    if (-not $isWrapped) {
                        $msg = "宏 '$macroName' 的值含运算符 (+ - * / << >>) 但缺少最外层括号！宏展开是纯文本替换，没有整体括号会导致 SQUARE(a+b) 这样的调用展开为 a+b*a+b 而非 (a+b)*(a+b)。请改为：#define $macroName ((...)) 双重括号包围整体和每个参数引用"
                        $categories.Overflow.Issues += "[P1 高]   $($file.Name):$lineNo $msg"
                        $fileReport.Issues += [ordered]@{ Category='Overflow'; Line=$lineNo; Severity='P1'; Message="Q3 宏缺括号：$msg" }
                    }
                }
            }

            # ---------- Q2 行内记录：外设写 & 时钟使能 ----------
            if ($raw -match "(^|[^a-zA-Z_])(usart|spi|i2c|timer|tim|adc|can|dma)_[A-Za-z_]\w*\s*\(" ) {
                $pt = $matches[2].ToUpper() -replace "^TIM$","TIMER"
                # 【FP 修复1】去掉 \b 词边界：_read / _get / _receive / _data_get / _flag 等可能后跟 _xxx（如 _read_data），_ 也是词字符导致 \b 不匹配
                # 【FP 修复2】跳过"函数声明行"：void / extern / static 前缀 + 行尾 ; 的是前向声明，不是实际调用，不计入"写外设"
                $q2EndsWithSemi = $raw.TrimEnd().EndsWith(";")
                $q2CallStartIdx = $raw.IndexOf($matches[0])
                $q2Prefix = if ($q2CallStartIdx -gt 0) { $raw.Substring(0, $q2CallStartIdx) } else { "" }
                $q2LooksLikeDecl = ($q2EndsWithSemi -and (
                    $q2Prefix -match "(extern|void|unsigned|signed|int|short|long|uint|bool|hal_status)\b" -or
                    $raw -match "^\s*(extern|void|unsigned|signed|int|short|long|uint|bool|hal_status)\b"
                ))
                if (-not $q2LooksLikeDecl -and ($raw -notmatch "_clock_enable|_clk_enable|periph_clock_enable|_enable_clock|_deinit|_init_struct|_interrupt_enable|_flag_get|_flag_clear|_flag|_rx_flag|_tx_flag|_get|_read|_receive|_data_get|_status|_is_")) {
                    [void]$q2PeriphWrites.Add([ordered]@{ Line=$lineNo; PeriphType=$pt; Raw=$raw.Trim() })
                }
            }
            # 时钟使能：必须是调用不是声明（声明行 = 前缀 extern/void/static/int/uint + 行尾 ;）
            if ($raw -match "(rcu_periph_clock_enable|__HAL_RCC_([A-Z0-9_]+)_CLK_ENABLE|CLK_([A-Z0-9_]+)_ENABLE|rcu_([A-Za-z0-9_]+)_clock_enable)\s*\(" ) {
                $callStart = $matches[0]
                $endsWithSemi = $raw.TrimEnd().EndsWith(";")
                $prefixLen = $raw.IndexOf($callStart)
                $prefix = if ($prefixLen -gt 0) { $raw.Substring(0, $prefixLen) } else { "" }
                $looksLikeDecl = ($endsWithSemi -and (
                    $prefix -match "(extern|void|unsigned|signed|int|short|long|uint|bool|hal_status)\b" -or
                    $raw -match "^\s*(extern|void|unsigned|signed|int|short|long|uint|bool|hal_status)\b"
                ))
                if (-not $looksLikeDecl) {
                    $periphRaw = ""
                    if ($raw -match "RCU_([A-Z0-9_]+)\s*[,)]")  { $periphRaw = $matches[1] }
                    elseif ($raw -match "__HAL_RCC_([A-Z0-9_]+)_CLK") { $periphRaw = $matches[1] }
                    elseif ($raw -match "CLK_([A-Z0-9_]+)_ENABLE")  { $periphRaw = $matches[1] }
                    elseif ($raw -match "rcu_([A-Za-z0-9_]+)_clock_enable") { $periphRaw = $matches[1].ToUpper() }
                    $ptype = ""
                    if ($periphRaw -match "^(USART|UART|SPI|I2C|TIMER|TIM|ADC|CAN|DMA)[0-9_]*") { $ptype = $matches[1] -replace "^TIM$","TIMER" }
                    if ($ptype.Length -gt 0) {
                        [void]$q2ClockEnables.Add([ordered]@{ Line=$lineNo; PeriphType=$ptype; PeriphName=$periphRaw; Raw=$raw.Trim() })
                    }
                }
            }

            # ---------- Q4 行内记录：8051 项目特征 + MOVX / pdata 数组访问 + 页切换 ----------
            # 【FP 修复】去掉 \bdata\b 和 \bcode\b：太通用，注释中常见 code-style / data 字段名，会误判为 8051 项目
            # 只保留 8051 独有的存储类关键字 idata/pdata/xdata/bdata 和厂商名/编译器宏/中断语法
            if (-not $q4Is8051 -and (
                $raw -match "\b(sfr|sbit|__SDCC|__ICC8051__|__C51__|idata|pdata|xdata|bdata|STC8|STC15|STC12|8052|8051|8031|AT89C)\b" -or
                $raw -match "#include\s+[<""](STC|8052|8051|compiler|C51|REG51|REG52|AT89)" -or
                $raw -match "__interrupt\s*\(" -or $raw -match "interrupt\s+\d+" -or $raw -match "using\s+\d"
            )) {
                $q4Is8051 = $true
            }
            if ($raw -match "\bMOVX\b" -or ($raw -match "__asm" -and $raw -match "@R[01]")) {
                $reg = "R0"; if ($raw -match "@R1") { $reg = "R1" }
                [void]$q4MovxLines.Add([ordered]@{ Line=$lineNo; Register=$reg; Raw=$raw.Trim() })
            }
            # pdata[] 数组访问也算分页访问（8051 项目中 pdata buf[i] = MOVX @R0/@R1）
            if ($q4Is8051 -and $raw -match "(\w+)\s*\[[^\]]+\]") {
                if ($raw -notmatch "^\s*(?:extern\s+|static\s+|const\s+|volatile\s+|unsigned\s+|signed\s+)?\s*(?:uint\d+_t|int\d+_t|char|short|long|int|void|bool|unsigned|signed)\b\s+\w+\s*\[") {
                    [void]$q4MovxLines.Add([ordered]@{ Line=$lineNo; Register="ARR"; Raw=$raw.Trim() })
                }
            }
            if ($raw -match "(SETB\s+RS1|CLR\s+RS1|MOV\s+DPH\s*,|P2\s*=|PDATA_BANK|BANK[0-9]\s*=|PSW\s*=|__critical|EA\s*=\s*0)") {
                $kind = "BANK"; if ($raw -match "RS1|PSW") { $kind = "RS1" } elseif ($raw -match "DPH|P2|PDATA_BANK|BANK[0-9]") { $kind = "DPH/P2" } elseif ($raw -match "EA\s*=\s*0") { $kind = "EA0" }
                [void]$q4BankSwitchLines.Add([ordered]@{ Line=$lineNo; Type=$kind; Raw=$raw.Trim() })
            }

            # ---------- Q5 行内记录：8051 16/32/64 位全局宽变量声明 + 使用位置 + 关/开中断 ----------
            [bool]$isSelfDecl = $false
            $declVN_Self = ""
            if ($braceDepth -eq 0 -or $raw -match "\bg_\w+") {
                if ($raw -match "^\s*(?:extern\s+|static\s+|const\s+|volatile\s+)*\s*(?:signed\s+|unsigned\s+)?(uint16_t|uint32_t|uint64_t|int16_t|int32_t|unsigned\s+short|unsigned\s+long|unsigned\s+int|short|long|int)\b\s+((?:\*\s*)?[A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:=\s*[^;]+)?\s*;") {
                    $vt = $matches[1]; $vn = $matches[2] -replace "^\*+",""
                    $bits = 0
                    if ($vt -match "16|short") { $bits = 16 }
                    elseif ($vt -match "32|long|^int$") { $bits = 32 }
                    elseif ($vt -match "64") { $bits = 64 }
                    if ($bits -ge 16 -and $vn.Length -gt 0 -and $vn -ne "main" -and $vn -notmatch "_t$") {
                        $dup = $false
                        foreach ($ex in $q5GlobalWideVars) { if ($ex.Name -eq $vn) { $dup = $true; break } }
                        if (-not $dup) {
                            [void]$q5GlobalWideVars.Add([ordered]@{ DeclLine=$lineNo; Name=$vn; Bits=$bits; Type=$vt })
                            $isSelfDecl = $true
                            $declVN_Self = $vn
                        }
                    }
                }
            }
            # 宽变量使用记录（非声明行出现就算一次读/写，都要关中断保护）
            foreach ($gv in $q5GlobalWideVars) {
                $esc = [regex]::Escape($gv.Name)
                if ($isSelfDecl -and $gv.Name -eq $declVN_Self) { continue }
                # 再用声明正则二次确认：如果本行刚好是该变量的声明也跳过
                if ($raw -match "^\s*(?:extern\s+|static\s+|const\s+|volatile\s+)*\s*(?:signed\s+|unsigned\s+)?(uint16_t|uint32_t|uint64_t|int16_t|int32_t|unsigned\s+short|unsigned\s+long|unsigned\s+int|short|long|int)\b\s+(?:(?:\*\s*)?[A-Za-z_]\w*\s*,\s*)*((?:\*\s*)?$esc)\s*(?:\[[^\]]*\])?\s*(?:=\s*[^;]+)?\s*;") {
                    continue
                }
                if ($raw -match "\b$esc\b") {
                    [void]$q5WideReads.Add([ordered]@{ ReadLine=$lineNo; UsedVar=$gv.Name; Text=$raw.Trim() })
                }
            }
            if ($raw -match "(EA\s*=\s*0\b|__disable_irq\s*\(|_DI\s*\(|ENTER_CRITICAL\s*\(|portENTER_CRITICAL\s*\(|disable_all_interrupts?\s*\(|__critical\s*\{|__monitor\s*\{|irq_disable\s*\(|DISABLE_INT\s*\()") {
                [void]$q5CritLines.Add([ordered]@{ Line=$lineNo; Type="ENTER"; Raw=$raw.Trim() })
            }
            if ($raw -match "(EA\s*=\s*1\b|__enable_irq\s*\(|_EI\s*\(|EXIT_CRITICAL\s*\(|portEXIT_CRITICAL\s*\(|enable_all_interrupts?\s*\(|irq_enable\s*\(|ENABLE_INT\s*\()") {
                [void]$q5CritLines.Add([ordered]@{ Line=$lineNo; Type="EXIT"; Raw=$raw.Trim() })
            }
        }

        # ============== 防御性编程检测（D1 / D2） ==============
        if (Test-CheckEnabled 'defensive') {

            # ===== D1：switch 必须有 default 分支 =====
            # 注意：braceDepth 已经在本循环开头更新过（包含了当前行的 {} 变化）
            # 所以如果 switch 行本身有 {，braceDepth 已经是 switch 块内部的深度了
            if ($t -match '(^|[^a-zA-Z_])switch\s*\(') {
                $hasOpenBrace = ($t -match '\{\s*$' -or $t -match '\{\s*/\*.*\*/\s*$')
                if ($hasOpenBrace) {
                    # 当前行结尾有 {：braceDepth 已更新 → ExpectedDepth = 当前 braceDepth（switch 内部深度）
                    $expectedDepth = $braceDepth
                } else {
                    # 下一行才有 {：ExpectedDepth = 当前 + 1（下一行的 { 会让它 +1）
                    $expectedDepth = $braceDepth + 1
                }
                [void]$switchStack.Add([ordered]@{
                    SwitchLine    = $lineNo
                    HasDefault    = $false
                    ExpectedDepth = $expectedDepth
                    Popped        = $false
                })
            }

            # 检测 default: 标签 → 只标记栈顶（最内层）未闭合的 switch
            if ($switchStack.Count -gt 0 -and $t -match '(^|[^a-zA-Z_])default\s*:') {
                for ($si = $switchStack.Count - 1; $si -ge 0; $si--) {
                    if (-not $switchStack[$si].Popped) {
                        $switchStack[$si].HasDefault = $true
                        break
                    }
                }
            }

            # 检测 switch 结束：从栈顶往下，任何 ExpectedDepth > 当前 braceDepth 的未闭合 switch → 已闭合
            if ($switchStack.Count -gt 0) {
                for ($si = $switchStack.Count - 1; $si -ge 0; $si--) {
                    $sw = $switchStack[$si]
                    if (-not $sw.Popped -and $braceDepth -lt $sw.ExpectedDepth) {
                        $sw.Popped = $true
                        if (-not $sw.HasDefault) {
                            $msg = "switch 语句缺少 default 分支！未列出的 case 会走编译器默认值（通常是继续执行），极端输入下会进入未知状态。请添加 default: 分支，显式处理非法值（报错/断言/进入安全态）"
                            $categories.Defensive.Issues += "[P1 高]   $($file.Name):$($sw.SwitchLine) $msg"
                            $fileReport.Issues += [ordered]@{ Category='Defensive'; Line=$sw.SwitchLine; Severity='P1'; Message="D1 switch 无 default：$msg" }
                        }
                    }
                }
            }

            # ===== D2：函数体内局部变量声明必须初始化 =====
            # 跳过条件：在 struct/enum/union 定义体里、typedef/extern、for 循环头
            if ($braceDepth -ge 1 -and $inTypeDefAtDepth -lt 0) {
                $skipLine = $false
                if ($t -match '^\s*(typedef|extern)\b') { $skipLine = $true }
                if ($t -match '^\s*(struct|enum|union)\s+\w*\s*\{') { $skipLine = $true }
                if ($t -match '^\s*for\s*\(') { $skipLine = $true }

                if (-not $skipLine) {
                    # 匹配声明模式：[修饰] 类型 [*] 变量名 [数组] [,;]
                    $declPattern = '^\s*(?:const\s+|static\s+|volatile\s+)*\b(?:uint8_t|uint16_t|uint32_t|uint64_t|int8_t|int16_t|int32_t|int64_t|unsigned\s+int|signed\s+int|unsigned\s+char|signed\s+char|unsigned\s+short|signed\s+short|unsigned\s+long|signed\s+long|int|char|short|long|float|double|size_t|bool|BOOL|u8|u16|u32|s8|s16|s32|[A-Za-z_]\w*_t|struct\s+\w+|enum\s+\w+)\b\s+(?:\*+\s*)?([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:,\s*[A-Za-z_]\w*\s*(?:\[[^\]]*\])?\s*)*[;]'
                    if ($t -match $declPattern) {
                        $origMatches = $matches  # ← 关键：立即保存，避免后续 -match 覆盖
                        $varDecl = $t.Trim()
                        $hasInit = $false
                        # 检查是否有初始化符号 =
                        if ($varDecl -match '(?<![=!<>])=(?!=)') { $hasInit = $true }
                        # 行尾不是 ; 说明可能是多行声明（函数参数列表之类），跳过
                        if (-not $hasInit -and $varDecl -match ';\s*$') {
                            $varName = $origMatches[1]
                            if ([string]::IsNullOrWhiteSpace($varName)) { $varName = '<变量>' }
                            if ($varDecl -notmatch '^\s*extern\b') {
                                # 额外排除：static 全局声明（braceDepth=0 不会进来）、声明且已赋值的情况
                                $msg = "局部变量 '$varName' 声明未初始化！函数体内局部变量值为随机垃圾，直接使用会导致逻辑错乱。即使后面马上赋值也建议显式初始化（= 0 / = {0}），避免中间路径出错时读到垃圾值"
                                $categories.Defensive.Issues += "[P2 中]   $($file.Name):$lineNo $msg"
                                $fileReport.Issues += [ordered]@{ Category='Defensive'; Line=$lineNo; Severity='P2'; Message="D2 变量未初始化：$msg" }
                            }
                        }
                    }
                }
            }

            # ===== Q7：记录 main() 行号 + 检测优先级分组设置函数 =====
            if ($q7MainLine -eq 0 -and $raw -match '(?i)\bint\s+main\s*\(') {
                $q7MainLine = $lineNo
            }
            if ($raw -match '(?i)\b(nvic_priority_group_set|HAL_NVIC_SetPriorityGrouping|NVIC_PriorityGroupConfig)\s*\(') {
                $q7HasPriorityGroup = $true
            }

            # ===== Q6：ISR 函数体中禁止调用看门狗喂狗 / fwdgt_counter_reload 等 =====
            # 原因：如果主循环卡死了，但定时 ISR 还在跑（比如 SysTick / TIMER），ISR 中喂狗 → 系统挂了但看门狗不会复位，硬件看门狗形同虚设
            # 喂狗必须只在主循环 while(1) 最外层，禁止在任何 ISR 中
            # 跟踪：检测进入/离开 *IRQHandler / *ISR 函数定义（GD32 命名 XX_IRQHandler，ESP32 命名 xx_isr）

            # ① 进入 ISR 函数：匹配行内函数定义头，下一行/同行有 { 后 braceDepth 上升 1，记录 EnterDepth = 上升后的深度
            # 定义头：返回值 函数名(...) {
            if ($currentIsrInfo -eq $null) {
                if ($t -match '(^|[^a-zA-Z_0-9])([A-Za-z_]\w*(?:IRQHandler|IRQn_Handler|_isr|ISR))\s*\(') {
                    $funcName = $matches[2]
                    # 看当前行有没有 { 或下一行有 {
                    $hasOpenBrace = ($t -match '\{')
                    # 简化：进入 ISR 标记（等 braceDepth 真正增加时再记录 EnterDepth）
                    # 方式：记录"待进入"的候选，当下一次 braceDepth 增加时就把它标记为 EnterDepth
                    $script:isrPendingEnter = [ordered]@{
                        Name      = $funcName
                        EnterLine = $lineNo
                        Pending   = $true
                    }
                }
            }
            # ② 当 braceDepth 增加时，把 pending 的 ISR 真正标为"进入中"
            if ($braceDepth -gt $prevBraceDepth -and $null -ne $script:isrPendingEnter -and $script:isrPendingEnter.Pending) {
                $currentIsrInfo = [ordered]@{
                    Name      = $script:isrPendingEnter.Name
                    EnterLine = $script:isrPendingEnter.EnterLine
                    EnterDepth = $braceDepth
                }
                $script:isrPendingEnter = $null
            }
            # ③ 当 braceDepth 减少到 < EnterDepth 时，认为 ISR 函数体结束
            if ($null -ne $currentIsrInfo -and $braceDepth -lt $currentIsrInfo.EnterDepth) {
                $currentIsrInfo = $null
            }
            # ④ 在 ISR 函数体内检测喂狗调用
            if ($null -ne $currentIsrInfo) {
                if ($t -match '(fwdgt_counter_reload|wwdgt_counter_update|iwdg_feed|iwdg_reload|wdt_feed|wdt_reload|WatchdogFeed|HAL_IWDG_Refresh|vTaskDelayUntil|esp_task_wdt_reset)') {
                    $msg = "ISR 函数 '$($currentIsrInfo.Name)' 中调用了看门狗喂狗/刷新函数！如果主循环卡死（比如 while(1) 死循环），但 SysTick/TIMER ISR 还在跑并喂狗，硬件看门狗就形同虚设永远不会复位。喂狗代码必须只在主循环 while(1) 的最外层调用，且结合任务心跳确认所有任务都跑到才喂"
                    $categories.Defensive.Issues += "[P1 高]   $($file.Name):$lineNo $msg"
                    $fileReport.Issues += [ordered]@{ Category='Defensive'; Line=$lineNo; Severity='P1'; Message="Q6 ISR 内喂狗：$msg" }
                }
            }
        }
    }

    # ============== Q2 / Q4 / Q5 文件级汇总 ==============
    if (Test-CheckEnabled "overflow" -or Test-CheckEnabled "defensive") {
        # ===== Q2：外设写 vs 时钟使能 顺序 =====
        $writeByType = @{}
        foreach ($w in $q2PeriphWrites) { if (-not $writeByType.Contains($w.PeriphType)) { $writeByType[$w.PeriphType] = [System.Collections.ArrayList]::new() }; [void]$writeByType[$w.PeriphType].Add($w) }
        $clockByType = @{}
        foreach ($c in $q2ClockEnables)  { if ([string]::IsNullOrWhiteSpace($c.PeriphType)) { continue }; if (-not $clockByType.Contains($c.PeriphType)) { $clockByType[$c.PeriphType] = [System.Collections.ArrayList]::new() }; [void]$clockByType[$c.PeriphType].Add($c) }
        foreach ($tp in $writeByType.Keys) {
            if (-not $clockByType.Contains($tp)) { continue }
            $writes = $writeByType[$tp]
            $clocks = $clockByType[$tp]
            $minWrite = 999999; $earliestWrite = $null; foreach ($w in $writes) { if ($w.Line -lt $minWrite) { $minWrite = $w.Line; $earliestWrite = $w } }
            $minClock = 999999; $earliestClock = $null; foreach ($c in $clocks) { if ($c.Line -lt $minClock) { $minClock = $c.Line; $earliestClock = $c } }
            if ($earliestWrite -and $earliestClock -and $earliestWrite.Line -lt $earliestClock.Line) {
                $cut1 = [Math]::Min(90,$earliestWrite.Raw.Length)
                $cut2 = [Math]::Min(90,$earliestClock.Raw.Length)
                $msg = "[Q2 初始化顺序反了] $tp 类外设的第一次写寄存器（L$($earliestWrite.Line): $($earliestWrite.Raw.Substring(0,$cut1))）早于同类型时钟使能调用（L$($earliestClock.Line): $($earliestClock.Raw.Substring(0,$cut2))）。如果先写外设寄存器再开对应 RCU 时钟，写入会静默失败（寄存器写不进，外设表现为 配置无效），调试耗时极长。正确顺序：开时钟 → GPIO/AF → 外设 init → 中断使能"
                $categories.Defensive.Issues += "[P1 高]   $($file.Name):$($earliestWrite.Line) $msg"
                $fileReport.Issues += [ordered]@{ Category="Defensive"; Line=$earliestWrite.Line; Severity="P1"; Message="Q2 时钟使能顺序反了：$msg" }
            }
        }

        # ===== Q4：8051 分页访问跨边界分析 =====
        if ($q4Is8051) {
            # 防御性排序：页切换记录按行号递增排列，避免后面 break 提前终止导致漏查
            $q4BankSwitchLines = $q4BankSwitchLines | Sort-Object Line
            for ($mi=0; $mi -lt $q4MovxLines.Count; $mi++) {
                $mv = $q4MovxLines[$mi]
                $lastBank = -1
                foreach ($bk in $q4BankSwitchLines) { if ($bk.Line -lt $mv.Line) { $lastBank = $bk.Line } else { break } }
                $dist = if ($lastBank -ge 0) { ($mv.Line - $lastBank) } else { $mv.Line }
                if ($dist -gt 25) {
                    $msg = "[Q4 8051 SFR 分页访问可疑] MOVX @$($mv.Register) (L$($mv.Line)) 距最近一次页切换（SETB RS1/DPH=#/P2=，L$lastBank）已经 $dist 行没看到切页动作。@R0/@R1 是 8 位指针，SFR/IRAM 高 128 字节（0x80~0xFF）需要切 RS1 或 DPH/P2 页寄存器；若连续访问跨越 256 字节页边界（如 pdata 环形缓冲自增越界）会读到错误页的 SFR 值/未知 RAM。请确认：指针不会跨页，或每页切换处已显式写 P2/RS1/DPH"
                    $categories.Defensive.Issues += "[P1 高]   $($file.Name):$($mv.Line) $msg"
                    $fileReport.Issues += [ordered]@{ Category="Defensive"; Line=$mv.Line; Severity="P1"; Message="Q4 8051 SFR 分页：$msg" }
                }
            }
            if ($q4MovxLines.Count -ge 3 -and $q4BankSwitchLines.Count -lt [Math]::Ceiling($q4MovxLines.Count/2.0)) {
                $firstM = ($q4MovxLines | Sort-Object Line | Select-Object -First 1).Line
                $msg = "[Q4 8051 页切换稀疏] 文件中 MOVX @R0/@R1 出现 $($q4MovxLines.Count) 次，但仅看到 $($q4BankSwitchLines.Count) 处页切换（RS1/DPH/P2/PDATA_BANK）。若这是 pdata/xdata 循环读写（for/while 中 p++ 读下一个），跨 256 字节边界时未切 P2 会读错页。建议：确认 pdata 指针不跨页，或在循环外/if (idx==0) 分支中写入 P2 = PDATA_PAGE"
                $categories.Defensive.Issues += "[P2 中]   $($file.Name):$firstM $msg"
                $fileReport.Issues += [ordered]@{ Category="Defensive"; Line=$firstM; Severity="P2"; Message="Q4 页切换稀疏：$msg" }
            }
        }

        # ===== Q5：8051 16/32/64 位全局非原子读写保护分析 =====
        if ($q4Is8051 -and $q5GlobalWideVars.Count -gt 0) {
            $seen5 = @{}
            foreach ($rd in $q5WideReads) {
                $key = "$($rd.ReadLine)|$($rd.UsedVar)"
                if ($seen5.ContainsKey($key)) { continue }
                $seen5[$key] = 1

                $gvInfo = $q5GlobalWideVars | Where-Object { $_.Name -eq $rd.UsedVar } | Select-Object -First 1
                $bitsStr = if ($gvInfo) { "$($gvInfo.Bits)位 (L$($gvInfo.DeclLine)声明)" } else { "16/32/64 位" }
                $hasProtect = $false
                foreach ($cl in $q5CritLines) {
                    if ([Math]::Abs($cl.Line - $rd.ReadLine) -le 5) { $hasProtect = $true; break }
                }
                if (-not $hasProtect) {
                    $msg = "[Q5 8051 非原子访问可疑] L$($rd.ReadLine) 使用宽变量 '$($rd.UsedVar)'（$bitsStr），但前后 5 行未看到 EA=0/__disable_irq/ENTER_CRITICAL/disable_all_interrupts/DISABLE_INT 关中断。8051 是 8 位 CPU，读/写 16/32 位变量要用 2~4 条 MOV 指令；若此变量同时在 ISR/Timer 中断中改写，主循环看到的会是高低字节来自两次更新的混合值（半更新状态），随机错且极难抓。正确做法：读前关中断读完开 EA=1，或 ISR 只置标志位主循环中统一读"
                    $categories.Defensive.Issues += "[P1 高]   $($file.Name):$($rd.ReadLine) $msg"
                    $fileReport.Issues += [ordered]@{ Category="Defensive"; Line=$rd.ReadLine; Severity="P1"; Message="Q5 8051 非原子：$msg" }
                }
            }
        }

        # ===== Q7：NVIC 中断优先级分组缺失检测 =====
        # main() 前 50 行内未出现 nvic_priority_group_set / HAL_NVIC_SetPriorityGrouping / NVIC_PriorityGroupConfig
        if ($q7MainLine -gt 0 -and -not $q7HasPriorityGroup) {
            $msg = "[Q7 NVIC 优先级分组缺失] L$($q7MainLine) main() 前 50 行内未检测到优先级分组设置函数（nvic_priority_group_set / HAL_NVIC_SetPriorityGrouping / NVIC_PriorityGroupConfig）。默认分组 0 意味着所有中断抢占级相同、互相不能抢占，UART 收包时被 EXTI 按键 ISR 阻塞会导致 Overrun 丢包。正确做法：main() 开头第一时间调用 nvic_priority_group_set(NVIC_PRIGROUP_PRE2_SUB2)（GD32）或 HAL_NVIC_SetPriorityGrouping(NVIC_PRIORITYGROUP_2)（STM32），再按 通信>定时器>EXTI 顺序设抢占级"
            $categories.Defensive.Issues += "[P1 高]   $($file.Name):$($q7MainLine) $msg"
            $fileReport.Issues += [ordered]@{ Category="Defensive"; Line=$q7MainLine; Severity="P1"; Message="Q7 NVIC 优先级分组缺失：$msg" }
        }
    }
    # ============== 头文件保护汇总 ==============
    if ($isHeader -and (Test-CheckEnabled 'header')) {
        if (-not $hasIfndefGuard -or -not $hasDefineGuard -or -not $hasEndifGuard) {
            $categories.Header.Issues += "$($file.Name) 缺少标准 #ifndef / #define / #endif 头文件保护"
            $fileReport.Issues += [ordered]@{ Category='Header'; Line=0; Message='缺少头文件保护（#ifndef/#define/#endif）' }
        }
    }

    $report.Files += $fileReport
}

# ============== 全局静态建议 ==============
if (Test-CheckEnabled 'static') {
    $allOtherContent = @{}
    foreach ($f in $filesToCheck) {
        if ($f.Extension -eq '.h' -or $f.Extension -eq '.c') {
            try {
                $allOtherContent[$f.FullName] = (Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
            } catch {}
        }
    }
    foreach ($fnName in $funcDefinitions.Keys) {
        $loc = $funcDefinitions[$fnName]
        $foundElsewhere = $false
        foreach ($fp in $allOtherContent.Keys) {
            if ($fp -like "*\$($loc.File)") { continue }
            if ($allOtherContent[$fp] -and $allOtherContent[$fp] -match "(\bextern\b.*\b$fnName\b|\b$fnName\s*\()") {
                $foundElsewhere = $true; break
            }
        }
        if (-not $foundElsewhere) {
            $categories.Static.Issues += "$($loc.File):$($loc.Line) 函数 '$fnName' 未在其他文件中引用，建议加 static 修饰"
        }
    }
}

# ============================================================
# 输出报告
# ============================================================
if (-not $Quiet) {
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ' 检查结果' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    foreach ($key in $categories.Keys) {
        $cat = $categories[$key]
        if ($cat.Issues.Count -eq 0) { continue }
        $report.Summary.ByCategory[$key] = $cat.Issues.Count
        Write-Host ''
        Write-Host "--- [$key] $($cat.Name) ($($cat.Issues.Count) 项) ---" -ForegroundColor White
        $limit = [Math]::Min($cat.Issues.Count, 15)
        for ($i = 0; $i -lt $limit; $i++) {
            if ($key -eq 'Overflow') {
                # 溢出隐患按 P0/P1 级别标红/黄
                if ($cat.Issues[$i] -match 'P0') {
                    Write-Status $cat.Issues[$i] -Type Error
                } else {
                    Write-Status $cat.Issues[$i] -Type Warning
                }
            } elseif ($key -eq 'Defensive') {
                # 防御性编程按 P1/P2 级别
                if ($cat.Issues[$i] -match 'P1') {
                    Write-Status $cat.Issues[$i] -Type Warning
                } else {
                    Write-Status $cat.Issues[$i] -Type Warning
                }
            } elseif ($key -in @('Indent', 'Naming', 'Global', 'Magic', 'LineWidth', 'Brace', 'Header')) {
                Write-Status $cat.Issues[$i] -Type Warning
            } else {
                Write-Status $cat.Issues[$i] -Type Warning
            }
        }
        if ($cat.Issues.Count -gt $limit) {
            Write-Status "... 还有 $($cat.Issues.Count - $limit) 项，见 JSON 报告" -Type Warning
        }
    }

    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ' 汇总' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    $totalIssues = 0
    foreach ($k in $categories.Keys) { $totalIssues += $categories[$k].Issues.Count }
    $report.Summary.TotalIssues = $totalIssues
    Write-Host " 总文件数: $($report.Summary.TotalFiles)" -ForegroundColor White
    Write-Host " 总问题数: $totalIssues" -ForegroundColor Yellow
    if ($categories.Overflow.Issues.Count -gt 0) {
        Write-Host " 数据溢出隐患: $($categories.Overflow.Issues.Count) 项 (P0 致命需优先修复!)" -ForegroundColor Red
    }
    if ($categories.Defensive.Issues.Count -gt 0) {
        Write-Host " 防御性编程问题: $($categories.Defensive.Issues.Count) 项 (P1 高风险需重点修复)" -ForegroundColor Yellow
    }
    Write-Host ''
    if ($totalIssues -eq 0) {
        Write-Host '[OK] 所有规范检查通过' -ForegroundColor Green
    } else {
        if ($categories.Overflow.Issues.Count -gt 0) {
            Write-Host '[X] 发现数据溢出隐患，请优先修复 P0 致命项再处理其他规范' -ForegroundColor Red
        } elseif ($categories.Defensive.Issues.Count -gt 0) {
            Write-Host '[!] 发现防御性编程问题（未初始化/缺 default），长期运行项目建议全部修复' -ForegroundColor Yellow
        } else {
            Write-Host '[!] 发现规范问题，建议逐一修复' -ForegroundColor Yellow
        }
    }
}

# JSON 报告输出
if ($Json -ne '') {
    try {
        $allIssuesArr = @()
        foreach ($key in $categories.Keys) {
            foreach ($issue in $categories[$key].Issues) {
                $allIssuesArr += [ordered]@{ Category = $key; Message = $issue }
            }
        }
        $report.AllIssues = $allIssuesArr
        $report.Summary.TotalIssues = $allIssuesArr.Count
        $jsonStr = $report | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($Json, $jsonStr, [System.Text.UTF8Encoding]::new($true))
        if (-not $Quiet) { Write-Status "JSON 报告已保存: $Json" -Type Success }
    } catch {
        Write-Status "保存 JSON 失败: $_" -Type Error
    }
}

if ($report.Summary.TotalIssues -gt 0) {
    # 溢出隐患 P0 单独返回更高退出码，便于 CI 拦截
    if ($categories.Overflow.Issues.Count -gt 0) {
        $hasP0 = $false
        foreach ($iss in $categories.Overflow.Issues) { if ($iss -match 'P0') { $hasP0 = $true; break } }
        if ($hasP0) { exit 3 }  # 3 = 含 P0 级溢出隐患
        exit 2                  # 2 = 仅含 P1 级溢出或其他规范问题
    }
    exit 1
}
exit 0
