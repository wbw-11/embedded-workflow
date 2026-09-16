---
name: keil-auto-flash
description: "Keil 项目自动编译烧录：GD32/STM32/8051。代码改完需烧录验证时调用。"
install_method: upload
version: 1.0.0
---

# Keil 自动编译烧录技能

> 一键闭环可直接用 Tools\dev-flow.ps1 -ProjectDir <项目>（自动串联 编译→时间戳→版本→烧录→核验→归档，门禁不过即停）；本技能详解各步细节与踩坑。

## 适用场景

- 完成对 Keil 项目（.uvprojx）源文件的修改后，自动执行编译+烧录
- 用户明确要求"烧录"、"下载"、"烧写"、"flash"到芯片时
- 支持芯片：**GD32**（Cortex-M4）、**STM32**（Cortex-M0/M3/M4/M7）、**STC8**（8051）等所有 Keil 支持的芯片
- 调试器：CMSIS-DAP / ST-Link / J-Link（已在 Keil 工程中手动配置）

## 工具链路径（自动检测）

首次使用时自动检测 Keil 安装路径，不要假设固定位置：

```powershell
# 检测 UV4.exe 位置（按优先级搜索）
$uv4 = @(
    "C:\Keil_v5\UV4\UV4.exe",
    "<KEIL_ROOT>\UV4\UV4.exe",
    "E:\Keil_v5\UV4\UV4.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

# 如果常见路径没找到，搜索注册表
if (-not $uv4) {
    $regPath = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Keil\Products\MDK" -ErrorAction SilentlyContinue
    if ($regPath) { $uv4 = Join-Path $regPath.Path "UV4\UV4.exe" }
}

# 最后手段：全盘搜索
if (-not $uv4) {
    $uv4 = (Get-ChildItem -Path C:\,D:\,E:\ -Recurse -Filter "UV4.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}
```

检测到后记为 `$UV4_PATH`，后续所有命令使用此变量。编译器路径为 `$UV4_PATH` 同级的 `..\ARM\ARMCLANG\Bin`。

## 混合 C/C++ 编译标准方案（2026-08-30 GD32F407VE TFLite Micro 实测定案）

> 触发场景：Keil 工程同时存在 .c（GD32/STM32 库、驱动）和 .cpp（AI 内核、C++ 业务层）。
> 铁律：**动手改代码前先把混编方案定清楚**（曾因边改边试浪费大量轮次）。

### 第一步：写代码前的三件事

1. 确认文件归属：**驱动/硬件层用 .c，AI/上层库用 .cpp**，禁止混在同一文件
2. 确认跨语言头文件必须带 extern "C" 保护（标准写法见下）
3. 一次性确认本表全部开关，不逐个试错

```c
/* 跨语言头文件标准写法（GD32 外设头、自建 bsp 头均需） */
#ifdef __cplusplus
extern "C" {
#endif

void my_c_function(void);

#ifdef __cplusplus
}
#endif
```

### 第二步：Keil AC6 五个开关（少一个必踩坑）

| 项 | 配置 | 原因 |
|---|---|---|
| 编译器 | AC6（uAC6=1） | AC5 不支持 C++11+，TFLM 等库要 C++17 |
| 全局 MiscControls | 追加 `--target=arm-arm-none-eabi -xc++ -std=c++17 -Wno-register` | AC6 对 .cpp 不自动切 C++ 必须 -xc++；-xc++ 会破坏 Keil 自动注入的 --target 需手动补；-Wno-register 压 C 源码被 C++17 编时的 register 报错 |
| UseCPPCompiler | TargetOption/CommonProperty/UseCPPCompiler = 1 | 文件级 FileType=8(设为 C++ 源文件)对 armclang **不生效**（实测），必须全局 -xc++ |
| MicroLIB | **取消勾选** useUlib=0 | MicroLIB 不支持 C++ 运行时（全局对象构造/析构），日志会有明确警告 |
| 半主机 | 关 MicroLIB 后禁用半主机，printf 重定向 fputc 或直接写串口 | 否则"调试器下能跑、脱机就死机" |

> 注意：`-xc++` 是全局生效（所有文件按 C++ 编，包括 .c）。C 源码靠 extern "C" 头保持 C 链接，
> 不需要也不要用文件级 -xc 去切回 C（Keil/AC6 下不可靠）。

### 第三步：链接符号报错时先查 extern "C"，不改编译参数

排查顺序（曾因顺序搞反浪费大量轮次）：
1. 看报错符号是 mangle 形式（`_Z...`）还是普通名
2. C++ 调 C 函数报 undefined → **头文件缺 extern "C"**，补头保护即可，不动编译参数
3. 确认语言模式错了（如 namespace 错=按 C 编了）才动 -xc++/-std

### 第四步：从模板复制工程时 .uvprojx + .uvoptx 一起拷

- CMSIS-DAP/ST-Link 调试器配置存在 **.uvoptx** 里（nTsel + pMon 字段）
- 只拷 .uvprojx 会丢调试器配置，烧录报 `Target DLL has been cancelled`
- 拷后改 .uvoptx 内工程名引用（.uvprojx 文件名）

### 快速诊断速查

| 症状 | 原因 | 处置 |
|---|---|---|
| `namespace`/`constexpr` 莫名报错 | .cpp 被按 C 编译（缺 -xc++ 或 AC5） | 加全局 -xc++ -std=c++17 |
| `register` 关键字报错 | GD32 库 .c 被 C++17 编 | 加 -Wno-register |
| `XXXX undefined (referred from xxx.o)` | 符号 mangle 不匹配，头缺 extern "C" | 补 extern "C" 头保护 |
| `no target architecture` | -xc++ 吃掉了 Keil 的 target | 补 --target=arm-arm-none-eabi |
| `Target DLL has been cancelled` | .uvoptx 丢了调试器配置 | 复制模板时带 .uvoptx |
| `MicroLIB 不支持 C++` 警告 | MicroLIB 未关 | useUlib=0 |

## 核心原则

**标准流程（用户定案 2026-09-01）：所有改动一律全量重编再烧录，强制**。

**全量重编译（先 -cr 或清空 Objects 再 -b，再 -f 烧录）**。虽然会比增量编译久，但：
1. 编译日志和烧录日志分文件保存，诊断可靠
2. 编译失败时直接停止，不浪费时间尝试烧录
3. 嵌入式开发频率低，可靠性比速度重要（实测编译只需 ~8 秒）

## 执行流程

### 第一步：定位 .uvprojx 工程文件

**不要用 Glob**（深中文路径下失效）。必须用 PowerShell `Get-ChildItem`：

```powershell
Get-ChildItem -Path "<项目根目录>" -Recurse -Filter "*.uvprojx" | ForEach-Object { $_.FullName }
```

找到后记录完整路径，后续命令都用这个路径。

### 第二步：全量重编译（清空 Objects + UV4 -b，强制）

**所有改动一律全量重编**——先清空增量缓存，再编译，确保所有 .o 均为本次源码产物，杜绝旧 .o 混入：

```powershell
# 1. 清空 Objects 增量缓存（强制全量重编）
Remove-Item -Path "<项目目录>\Objects\*" -Force -Recurse -ErrorAction SilentlyContinue

# 2. 编译（全部文件重新编译）
<UV4_PATH> -b "<.uvprojx完整路径>" -o "<项目目录>\build_log.txt"
```

- `-b`：仅编译，不烧录（清空后即为全量编译）
- `-o`：编译日志输出到 build_log.txt（GB2312 编码）
- cwd 设为 .uvprojx 所在目录
- 等价替代：UV4 `-cr`（Clean + Rebuild 一步完成）

### 第三步：读取编译日志判断结果

#### 3.1 读取编译日志（显式 GB2312 编码）

**不要用 Read 工具**（UTF-8 解码 GB2312 文件会乱码）。
**不要用 `-Encoding Default`**（PowerShell 7 下 Default 可能不是 GB2312）。

必须用 .NET 显式指定 GB2312（代码页 936）：

```powershell
[System.IO.File]::ReadAllText("<build_log.txt路径>", [System.Text.Encoding]::GetEncoding(936))
```

#### 3.2 提取关键信息（用 Select-String 避免截断）

长日志可能被 RunCommand 输出截断。用 `Select-String` 只搜关键字行：

```powershell
$content = [System.IO.File]::ReadAllText("<路径>", [System.Text.Encoding]::GetEncoding(936))
# 搜索编译结果行
$content -split "`n" | Where-Object { $_ -match "Error\(s\)|Warning\(s)|error:" }
```

#### 3.3 判断编译结果

| 日志特征 | 含义 | 处理 |
|----------|------|------|
| `0 Error(s), 0 Warning(s)` | 编译成功，无警告 | 继续烧录 |
| `0 Error(s), N Warning(s)`（N>0） | 编译成功，有警告 | 继续烧录，告知用户警告数 |
| `N Error(s)`（N>0） | 编译失败 | **停止**，报告错误，不烧录 |
| 无上述关键字 | 异常 | **停止**，报告异常 |

**编译失败处理**：
1. 提取错误行（搜索 `error:`）
2. 向用户报告错误行号和描述
3. **不执行烧录**，等待用户修复

### 第三点五步：代码审查门禁（code-style-check）

> 编译通过后、烧录前，自动执行代码规范检查。有 P0 致命项时**阻止烧录**，P1 高风险项警告用户确认。

#### 3.5.1 定位检测脚本

优先使用工作区版本（最新），其次使用 Tools 目录版本：

```powershell
$csc = @(
    "$PWD\code-style-check.ps1",
    "$env:USERPROFILE\Tools\code-style-check.ps1"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
```

#### 3.5.2 执行检测

扫描 .uvprojx 所在目录下的所有 `.c/.h` 文件，启用 overflow + defensive 两类检测：

```powershell
$result = & powershell -ExecutionPolicy Bypass -File $csc -Path "<项目源码目录>" -Checks "overflow,defensive" -Quiet 2>&1
$exitCode = $LASTEXITCODE
```

#### 3.5.3 根据退出码决定是否放行

| 退出码 | 含义 | 处理 |
|--------|------|------|
| 0 | 全部通过 | ✅ 放行，继续烧录 |
| 1 | 仅低级规范问题（命名/缩进等） | ✅ 放行，告知用户问题数 |
| 2 | P1 级问题（溢出隐患/防御性） | ⚠️ 警告用户，列出问题摘要，**询问是否继续烧录** |
| 3 | **P0 致命级问题**（sprintf/strcpy/gets/memcpy 裸长度等） | ❌ **阻止烧录**，列出全部 P0 项，要求用户修复后重试 |

**P0 阻止示例**：
```
========================================
  代码审查门禁 — 检测到 P0 致命隐患
========================================
[X] main.c:15 禁止使用 sprintf（无长度限制，必炸）
[X] main.c:42 memcpy 长度使用裸数字 128，目标缓冲区仅 64 字节

烧录已阻止。请修复以上 P0 项后重新执行。
```

**P1 警告示例**：
```
========================================
  代码审查门禁 — 检测到 P1 高风险项
========================================
[!] main.c:59 ISR 中调用了看门狗喂狗函数
[!] main.c:104 外设写寄存器早于时钟使能调用

共 2 项 P1 风险。是否仍然继续烧录？(Y/N)
```

#### 3.5.4 注意事项

- 脚本路径不存在时**静默跳过**（不阻塞烧录），仅输出提示："未找到 code-style-check.ps1，跳过代码审查门禁"
- `-Quiet` 参数必传：避免脚本输出污染编译日志
- 审查范围与编译范围一致：扫描 .uvprojx 所在目录（含子目录）的 `.c/.h` 文件
- ESP-IDF 项目同样适用：在 esp-idf-build 技能的烧录前步骤中调用相同流程

#### 3.5.5 版本控制检查（B6 门禁精简版，警告级）

> 烧录前顺带检查版本控制纪律（完整 9 项见 embedded-dev-rules 门禁 B6）。
> 本步为**警告级**不阻塞烧录——老项目可能还没接入 git/version.h，只提醒不拦截。

**检查 1：version.h 是否存在**

```powershell
if (-not (Get-ChildItem -Path "<项目根目录>" -Recurse -Filter "version.h" | Select-Object -First 1)) {
    Write-Host '[!] 项目缺 version.h（固件版本号未嵌入）。建议添加：FW_VERSION_MAJOR/MINOR/PATCH/STRING 宏' -ForegroundColor Yellow
}
```

**检查 2：git 仓库状态**

```powershell
$inGit = Test-Path "<项目根目录>\.git"
if (-not $inGit) {
    Write-Host '[!] 项目未纳入 git 管理。烧录验证通过后建议 git init + 基线快照 commit' -ForegroundColor Yellow
} else {
    $dirty = git -C "<项目根目录>" status --short -- "*.c" "*.h" "*.uvprojx" 2>$null
    if ($dirty) {
        Write-Host "[!] 有未提交的源码改动（git status 非空）。烧录验证通过后请按格式提交：type(scope): subject" -ForegroundColor Yellow
    }
}
```

**检查 3：烧录后提示提交**（在第七步报告结果中追加一行）

```
- Git 状态：<已提交 干净> / <有 N 个未提交的 .c/.h 改动，验证通过后请 git add + commit>
- 版本号：<FW_VERSION_STRING>（来源：version.h）
```

**不与 P0/P1 门禁合并**：版本控制检查是独立的提醒维度；P0 仍然阻止烧录，P1 仍然询问确认，版本控制问题只输出黄色警告不拦截。

### 第三点九步：编译产物新鲜度检查（时间戳，强制）

> **防旧版本红线**：2026-08-20 数码管项目踩坑——复制新 main.c 后增量编译/直接烧录旧 hex，导致 PD8 LED 不亮，排查很久才发现烧的是旧版本。
> 本技能标准流程是先 `-b` 再 `-f` 保证产物最新；但用户手动烧录旧 hex、或跳过 -b 直接 -f（-f 只烧不编）时，时间戳检查是最后防线。

```powershell
# 获取源码与产物最新时间戳比较
$latestSource = Get-ChildItem -Path "<项目源码目录>" -Recurse -Include *.c,*.h |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$latestArtifact = Get-ChildItem -Path "<项目目录>" -Recurse -Include *.hex,*.axf,*.bin |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($latestArtifact -and $latestSource.LastWriteTime -gt $latestArtifact.LastWriteTime) {
    Write-Host '[X] 编译产物比源码旧，禁止烧录！请先 Rebuild All 重新编译' -ForegroundColor Red
    return  # 阻止烧录
}
Write-Host "[OK] 编译产物新鲜度正常（产物时间戳: $($latestArtifact.LastWriteTime)）" -ForegroundColor Green
```

> 判断逻辑：**产物时间戳 > 所有源码时间戳**才算新鲜；任一源码比产物新 → 说明产物是旧的 → 禁止烧录。
### 第三点九步A：-f 可能只 Load 旧 axf 不重编（必须先 -b 再 -f，强制）

> **2026-09-01 GD32F407VE LVGL 项目实测**：修改 main.c（改"实时监测中"→"数据更新中"）后直接 -f，flash_log 只显示 Load "....axf" 没有任何 compiling 行，烧进去的仍是旧固件，界面方框依旧。复查 Objects 下 axf 时间戳 < 源码修改时间，确认 -f 加载了旧 axf。

#### 现象/根因

- -f 官方定义是 **Flash Download 只烧录不编译**，直接 Load 已有 axf/hex（曾实测改代码后直接 -f，烧入旧固件，界面改动不生效）
- 后果：「改了代码 → -f → 上电没变化」≠ 代码没改对，而是**旧固件冒充新固件**
- 与第三点九步（时间戳检查）的区别：那条是手动烧旧 hex 时兜底；这条是 -f 自身偶发不重编

#### 红线规则（改代码后第一次烧录必执行）

1. **先 -b 单独编译**，确认 build_log 出现 compiling xxx.c... 行（证明源码真的被编译）
2. **核对 axf 时间戳** > 源码修改时间（可用下方 PowerShell 检查）
3. **再 -f 烧录**
4. 烧录后对怀疑的改动点做**产物特征核对**（见第三点九五步），或直接在板上看现象，避免「烧了旧固件还在改代码」

```powershell
# 改代码后：核对 axf 是否比源码新（时间戳）且含最新字符串特征
$newest = (Get-ChildItem -Path "<项目目录>" -Recurse -Include *.axf |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
$latestSrc = (Get-ChildItem -Path "<项目源码目录>" -Recurse -Include *.c,*.h |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
Write-Host "axf 时间戳: $((Get-Item $newest).LastWriteTime)  源码最新: $latestSrc"
```

#### 快速诊断

- flash_log 开头只有 Load "....axf" 且无 compiling/Compiling 行 → 就是没重编
- 改了字符串/常量后，直接用文本搜索 axf 二进制确认新字符串在不在（ASCII 编码，中文需按 UTF-8 字节匹配）

### 第三点九一步：回退/恢复源码后必须全量重编（时间戳倒退红线，强制）

> **2026-08-31 GD32F407VE LVGL 项目实测定案**：现象 = 所有固件（含纯色自检）满屏花屏，一路回退 V5.8 源码依旧花，烧历史验证过的 hex 却正常。
> 根因 = **用 Copy 旧文件覆盖"恢复"源码，时间戳倒退，欺骗了 Keil 增量编译**，链接复用了旧 .o，产出"混合固件"。

#### 机理

Keil `-b`/`-f` 是增量构建：源文件（含依赖 .h）**比 .o 新才重编**，否则复用旧 .o。

- 存档 main.c 时间戳是 8/29，Objects 里 main.o 是 8/31（现代风/自检阶段编译的）
- 用 Copy 把 8/29 的 main.c 覆盖回来 → UV4 判定"源码没变" → **跳过编译，链接 8/31 的旧 main.o**
- 结果：自以为烧 V5.8 源码，实际链接的是"现代风+自检"混合版本 → 花屏

#### 红线规则（遇"回退/恢复/替换源码"必执行）

1. **回退代码禁用 Copy 覆盖**：优先 git `checkout`/`revert`（时间戳即内容，不骗增量）；无 git 时必须全量重编兜底
2. **任何恢复操作后，第一次烧录前必须全量重编**：清空 Objects 目录再 `-b`/`-f`

   ```powershell
   # 清空增量缓存（强制全量重编）
   Remove-Item -Path "<项目目录>\Objects\*" -Force -Recurse -ErrorAction SilentlyContinue
   ```

   然后正常 `-b` 编译生成新 axf / `-f` 只烧录（-f 不重编）
3. **产物大小校验**：全量产物应与历史已知正常 hex 大小吻合；若增量产物比全量**大出明显差异**（实测大 41KB），说明混入了旧/额外代码，禁止交付

#### 常见误判提醒

- 编译通过（0 Error）+ Verify OK ≠ 固件正确 —— 混合固件编译链接全程无错
- 一路"回退无效"时，优先怀疑增量缓存，而非继续改代码或怀疑硬件
- 怀疑混合固件时：**烧历史已验证的 hex 二进制**做判别（不影响代码，一锤定音）；Keil `-f` 只烧不编（需先 -b），烧指定 hex 用 pyocd，烧指定 hex 用 pyocd（CMSIS-DAP）：`pyocd flash -t gd32f407ve <hex路径>`

### 第四步：烧录前安全校验（safe-flash）

> 本流程与 esp-idf-build 技能的安全校验流程结构一致（串口枚举 + 芯片类型匹配 + 用户确认门），差异在于 Keil 通过 SWD/JTAG 烧录而非串口。

编译通过后、执行烧录前，**必须**完成以下三重验证，防止烧录到错误的板子：

#### 4.1 串口枚举与可达性检查

```powershell
# 列出所有可用串口
$ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
if (-not $ports) {
    Write-Host '[X] 未检测到任何串口，请检查 USB 连接' -ForegroundColor Red
    return  # 不执行烧录
}
Write-Host "可用串口: $($ports -join ', ')" -ForegroundColor Cyan
```

如果只有一个串口，自动选中；如果有多个串口，列出并让用户确认目标串口。

#### 4.2 芯片类型匹配验证

读取当前板子配置（board-config），比对目标串口连接的芯片类型：

```powershell
# 读取当前板子配置
$boardName = $env:CURRENT_BOARD
if ($boardName) {
    $configPath = "$env:USERPROFILE\Tools\board-config\$boardName.ps1"
    if (Test-Path $configPath) {
        $boardConfig = & $configPath
        $expectedType = $boardConfig.Type   # 如 "GD32F407"、"STM32F103"
        $defaultPort  = $boardConfig.DefaultUart
        Write-Host "当前板子: $($boardConfig.Name) | 期望芯片: $expectedType" -ForegroundColor Yellow
    }
}
```

> Keil 项目（GD32/STM32/STC8）通过 SWD/JTAG 调试器烧录，不走串口，芯片类型由 Keil 工程配置决定。
> 此处校验主要确认 **调试器是否已连接**（CMSIS-DAP/ST-Link/J-Link）。如果之前 hardware-detection 已确认调试器在线，可跳过此步。

#### 4.3 用户确认门

```
========================================
  烧录前确认
========================================
项目：<项目名>
芯片：<芯片型号>
调试器：CMSIS-DAP / ST-Link
目标：编译 + 烧录

确认烧录？(Y/N)
```

**必须等到用户确认后才执行烧录**。如果用户选择了 `-Force` 模式或之前明确表示"烧录"可视为隐式确认。

> 也可以直接调用 safe-flash 脚本完成上述所有校验：
> ```powershell
> & "$env:USERPROFILE\Tools\safe-flash.ps1" -ListPorts   # 先列出可用串口
> & "$env:USERPROFILE\Tools\safe-flash.ps1"               # 自动校验 + 确认 + 烧录
> ```

### 第五步：执行烧录（UV4 -f）

编译通过且安全校验完成后，执行烧录，**必须 blocking: true**：

```
<UV4_PATH> -f "<.uvprojx完整路径>" -o "<项目目录>\flash_log.txt"
```

- `-f`：**只烧录不编译**（Flash Download），必须保证之前已用 `-b` 生成最新 axf
- `-o`：烧录日志输出到 flash_log.txt（**单独文件**，不覆盖编译日志）
- cwd 设为 .uvprojx 所在目录

### 第六步：读取烧录日志判断结果

```powershell
$content = [System.IO.File]::ReadAllText("<flash_log.txt路径>", [System.Text.Encoding]::GetEncoding(936))
$content -split "`n" | Where-Object { $_ -match "Verify OK|Flash Load|Erase Done|Programming Done|Error|Cannot|Failed|Time out" }
```

#### 烧录成功的完整标志

日志同时包含 `Verify OK` 和 `Flash Load finished`。

#### 烧录失败的常见关键字

| 关键字 | 可能原因 | 建议 |
|--------|----------|------|
| `Cannot access` / `No target connected` | CMSIS-DAP 未连接 | 检查 USB 线和调试器 |
| `Could not start` | 调试器未识别 | 检查驱动安装 |
| `Flash Download failed` | 烧录失败 | 检查芯片是否被保护 |
| `Error: Flash Download` | 烧录错误 | 擦除芯片后重试 |
| `Cannot erase` | 擦除失败 | 检查芯片状态 |
| `Time out` | 超时 | 检查 SWD 接线（SWDIO/SWCLK/GND/3V3） |

### 第三点九五步：烧录后固件版本特征核验（防旧固件冒充，强制）

> **SYGPAD V1 教训**：烧录日志 Verify OK 只是必要条件，不等于板上跑的就是最新行为。
> 一次实际事故：提示用户测试的结果全是旧固件行为，延误排查。烧录成功≠烧入正确固件。

烧录日志通过后、报告结果前，**必须**从 axf 提取版本特征串验证产物内容：

`powershell
# 提取 axf 中的版本特征串（banner 里的 FW_VERSION，如 "V4.2"）
 = (Get-ChildItem -Path "<项目目录>" -Recurse -Include *.axf |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
 = [System.IO.File]::ReadAllBytes()
 = [System.Text.Encoding]::ASCII.GetString()
if (-not $txt.Contains("<本版本特征串>")) {
    Write-Host '[X] axf 缺少版本特征串，禁止交付！' -ForegroundColor Red
    return
}
Write-Host "[OK] axf 固件特征核对通过（含 <本版本特征串>）" -ForegroundColor Green
`

- [ ] 向用户交付时声明：已烧录固件特征 = <FW_VERSION>（与源码一致）
- [ ] 用户上报的现象与本版特征不符时，先怀疑烧录链路再怀疑代码逻辑

### 第七步：报告结果

#### 7.1 编译成功时 —— 自动内存分析

编译通过后，从 build_log.txt 提取内存统计并分析。支持多芯片，根据项目路径推断芯片型号：

##### 芯片配置表

> 权威配置表维护在 **memory-analysis** 技能中（含 Flash/RAM 字节数、启动文件）。
> 此处仅列出推断用的路径特征关键词，具体数值请查阅 memory-analysis 的芯片配置表。

| 芯片系列 | 路径特征关键词 |
|----------|----------------|
| GD32F407x | `GD32F407`、`GD32F4xx` |
| GD32F103x | `GD32F103` |
| STM32F407x | `STM32F407` |
| STM32F103x | `STM32F103` |
| STC8H | `STC8H`、`STC8` |
| STC15 | `STC15` |

##### 内存分析脚本


## 详细参考

> 以下内容维护在 **同目录 reference.md**：芯片配置/内存统计脚本、烧录日志失败类型判断、命令示例、日志判断示例、验证记录。
> 主文件保留完整执行流程（第一步~第七步）与强制门禁，需要查表/参考脚本时打开 reference.md。

---

## 注意事项

1. **不要修改 .uvprojx/.uvoptx 工程文件**：由用户在 Keil IDE 中管理
2. **日志文件覆盖**：build_log.txt 和 flash_log.txt 每次会被覆盖，如需保留历史请提前备份
3. **UV4 命令是阻塞的**：必须 blocking: true，等待命令完成
4. **工作目录**：cwd 设为 .uvprojx 文件所在目录
5. **日志编码是 GB2312**：必须用 `[System.Text.Encoding]::GetEncoding(936)` 读取，不能用 Read 工具，不能用 `-Encoding Default`
6. **路径包含中文**：执行命令时用双引号包裹路径
7. **不靠返回码判断**：PowerShell 下 UV4 返回码不可靠，一律读日志判断
8. **日志分文件**：build_log.txt（编译）+ flash_log.txt（烧录），避免覆盖
9. **不用 Glob 找工程文件**：深中文路径下失效，改用 PowerShell `Get-ChildItem`
10. **用 Select-String 搜关键字**：避免长日志被 RunCommand 输出截断
11. **自动联动内存分析**：编译成功后自动提取 `Program Size` 信息并计算 Flash/RAM 占比
12. **自动联动硬件检测**：烧录失败时（如 CMSIS-DAP 未连接），自动调用 hardware-detection Skill 诊断


## 触发时机

- **自动触发**：每次使用 Write/Edit 工具修改 Keil 项目的源文件（.c/.h）后，主动执行烧录
- **手动触发**：用户明确要求"烧录"、"下载"、"flash"、"烧写"时执行
- **不触发**：仅查看代码、仅读取文件、修改非项目文件（如文档、配置）时不执行烧录

