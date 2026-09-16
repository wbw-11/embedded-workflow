---
name: esp-idf-build
description: "ESP-IDF 编译烧录：自动初始化环境，idf.py build/flash/monitor，错误诊断与内存联动。适用 ESP32 全系列。"
version: 2.1.0
---

# ESP-IDF 编译烧录技能

> 一键闭环可直接用 Tools\dev-flow.ps1 -ProjectDir <项目>（含时间戳/版本门禁与固件自动归档）；本技能保留完整手动流程与踩坑记录。

## 概述

自动完成 ESP-IDF 环境初始化、编译、烧录、串口监控全流程。改完代码后一键完成所有操作，并自动分析编译错误和内存占用。

**使用时机：**
- 改完 ESP32 代码后需要编译验证
- 编译成功后需要烧录到开发板
- 烧录后需要查看串口输出
- 需要清理构建目录重新编译

**支持的芯片：** ESP32、ESP32-S2、ESP32-S3、ESP32-C3、ESP32-C6、ESP32-H2 等所有 ESP-IDF 支持的芯片

## 环境配置

### 安装路径（自动检测）

首次使用时自动检测 ESP-IDF 安装位置，不要假设固定路径：

```powershell
# 优先使用环境变量
$idfPath = $env:IDF_PATH

# 其次搜索常见安装位置
if (-not $idfPath) {
    $candidates = @(
        "$env:USERPROFILE\esp\esp-idf",
        "$env:USERPROFILE\esp\v5.5.4\esp-idf",
        "C:\Espressif\frameworks\esp-idf-v5.5.4",
        "<ESP_IDF_ROOT>",
        "D:\Espressif\frameworks\esp-idf-v5.5.4"
    )
    $idfPath = $candidates | Where-Object { Test-Path "$_\export.ps1" } | Select-Object -First 1
}

# 最后手段：搜索 export.ps1
if (-not $idfPath) {
    $idfPath = (Get-ChildItem -Path C:\,D:\ -Recurse -Filter "export.ps1" -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match "esp-idf" } | Select-Object -First 1).DirectoryName
}
```

检测到后记为 `$IDF_PATH`，工具链在其同级 `..\tools`，Python 虚拟环境在 `..\python_env`。

### 初始化环境

> 如果用户已配置 PowerShell Profile 自动加载，进入项目目录即可自动初始化。

```powershell
# 方式1：自动加载（推荐）— 进入项目目录时 PowerShell Profile 自动触发
cd <ESP-IDF 项目目录>

# 方式2：手动加载（搜索用户自定义的环境脚本）
$envScript = @(
    "$env:USERPROFILE\Tools\esp-idf-env.ps1",
    "$IDF_PATH\export.ps1"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
. $envScript

# 方式3：加载并验证工具
. $envScript -Check

# 方式4：直接使用 esp-burn 工具（自动加载环境 + 编译 + 烧录 + 监控 + 重试）
esp-burn -Mode build-flash-monitor -ProjectDir <项目目录>
```

### 从 QoderWork Bash 调用（重要）

QoderWork 的 Bash 工具运行在 MSYS/Git Bash 兼容环境中，ESP-IDF 的 `idf.py` 会检测 `MSYSTEM` 环境变量并误判当前为 MSys 环境，导致报错或行为异常。**每次调用前必须清除以下变量：**

```powershell
$env:MSYSTEM = $null
$env:MSYS = $null
$env:CHERE_INVOKING = $null
```

此外，工具链路径中的版本号**不能硬编码**（不同安装环境版本不同），需先检测实际安装的版本再构建 PATH：

```powershell
# 自动检测工具链版本（$toolsDir 根据实际 IDF 安装位置调整）
$toolsDir = "$IDF_PATH\..\tools"
$cmakeVer = (Get-ChildItem "$toolsDir\cmake" -Directory | Select-Object -First 1).Name
$ninjaVer = (Get-ChildItem "$toolsDir\ninja" -Directory | Select-Object -First 1).Name
$xtensaDir = (Get-ChildItem "$toolsDir" -Directory -Filter "xtensa-esp*-elf" | Select-Object -First 1).Name
$xtensaVer = (Get-ChildItem "$toolsDir\$xtensaDir" -Directory | Select-Object -First 1).Name

# 构建 PATH（示例）
$env:PATH = "$pythonEnv\Scripts;$toolsDir\cmake\$cmakeVer\bin;$toolsDir\ninja\$ninjaVer;$toolsDir\$xtensaDir\$xtensaVer\bin;$env:PATH"
```

> **常见错误对照：**
> - 硬编码 `cmake\3.30.5` 但实际安装的是 `3.30.2` → 找不到 cmake
> - 硬编码 `xtensa-esp32s3-elf` 但实际目录名为 `xtensa-esp-elf` → 找不到编译器

## 执行流程

### 第一步：确认项目和目标芯片

在执行编译前，确认以下信息：
1. **项目路径**：包含 `CMakeLists.txt` 和 `main/` 目录的项目根目录
2. **目标芯片**：`esp32` / `esp32s3` / `esp32c3` / `esp32c6` 等
   - 如果项目已配置过，可从 `sdkconfig` 文件的 `CONFIG_IDF_TARGET` 读取
3. **串口号**：`COM3` / `COM5` 等（烧录和监控需要）

```powershell
# 读取已配置的目标芯片
$sdkconfig = Get-Content "<项目路径>\sdkconfig" -ErrorAction SilentlyContinue
$target = ($sdkconfig | Select-String "CONFIG_IDF_TARGET=").Line.Replace("CONFIG_IDF_TARGET=", "")
Write-Output "当前目标芯片：$target"
```

### 第二步：编译（idf.py build）

```powershell
# 进入项目目录
Set-Location "<项目路径>"

# 编译
idf.py build 2>&1 | Tee-Object -FilePath "build_log.txt"

# 检查编译结果
if ($LASTEXITCODE -eq 0) {
    Write-Output "编译成功"
} else {
    Write-Output "编译失败，查看 build_log.txt"
}
```

**编译输出解读：**
```
Project build complete. To flash, run:
   idf.py -p COM5 flash
```

### 第二点五步：代码审查门禁（烧录前强制，2026-09-03 强化）

> **强制要求：烧录前必须执行本节全部检查，缺一不可**（V8.2f 教训：未过门禁烧录，审查时才发现 CSRF 漏洞已存在于已上板固件）。
> 与 keil-auto-flash 技能的审查门禁流程一致。

#### 2.5.0 本次改动人工快查三项（每次烧录前必过）

按"本次改了什么"核对，与脚本互补（脚本漏人工项）：

| 类别 | 快查内容 | 例子（voice_motor 实锤） |
|---|---|---|
| 安全 | 新 HTTP 接口/表单/Cookie：越权、CSRF、明文密钥 | Set-Cookie 必须带 SameSite=Strict；受保护接口前置鉴权 |
| 并发 | 跨任务共享变量：标记 volatile；队列/锁正确 | OTA 进度、busy 标志多任务读写需 volatile |
| 缓冲区 | 新数组/解析：长度用 sizeof，边界校验；禁 strcpy/sprintf | cookie/token/form 解析定长 + 截断校验 |

#### 2.5.1 定位检测脚本

```powershell
$csc = @(
    "$PWD\code-style-check.ps1",
    "$env:USERPROFILE\Tools\code-style-check.ps1"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
```

#### 2.5.2 执行检测

扫描项目 `main/` 和 `components/` 目录下的 `.c/.h` 文件：

```powershell
# 扫描 main 目录（ESP-IDF 项目源码通常在 main/ 下）
$result = & powershell -ExecutionPolicy Bypass -File $csc -Path "<项目目录>\main" -Checks "overflow,defensive" -Quiet 2>&1
$exitCode = $LASTEXITCODE
# 如果有 components 目录也扫一遍
if (Test-Path "<项目目录>\components") {
    & powershell -ExecutionPolicy Bypass -File $csc -Path "<项目目录>\components" -Checks "overflow,defensive" -Quiet 2>&1
}
```

#### 2.5.3 根据退出码决定是否放行

| 退出码 | 含义 | 处理 |
|--------|------|------|
| 0 | 全部通过 | ✅ 放行，继续烧录 |
| 1 | 仅低级规范问题 | ✅ 放行，告知用户问题数 |
| 2 | P1 级问题 | ⚠️ 警告用户，列出问题摘要，**询问是否继续烧录** |
| 3 | **P0 致命级问题** | ❌ **阻止烧录**，列出全部 P0 项，要求修复后重试 |

#### 2.5.4 注意事项

- 脚本不存在时**静默跳过**，仅输出提示
- `-Quiet` 参数必传
- ESP-IDF 项目源码在 `main/` 和 `components/` 下，不是项目根目录
- 增量模式可用：加 `-ChangedOnly` 参数只扫 git diff 改动文件

#### 2.5.5 版本控制检查（B6 门禁 ESP-IDF 版，警告级）

> ESP-IDF 的固件版本机制与 Keil 不同：**版本号存在 CMakeLists.txt 的 project() 声明里**，
> 编译时自动注入到固件头部 `esp_app_desc_t`，无需手写 version.h。
> 本步为**警告级**不阻塞烧录，与 keil-auto-flash 3.5.5 同级。

**检查 1：CMakeLists.txt 是否声明版本号**

```powershell
$cmake = Get-ChildItem -Path "<项目根目录>" -Filter "CMakeLists.txt" | Select-Object -First 1
if ($cmake) {
    $content = Get-Content $cmake.FullName -Raw
    if ($content -notmatch "project\(\s*\w+\s+VERSION\s+\d+\.\d+\.\d+") {
        Write-Host '[!] CMakeLists.txt 的 project() 未声明 VERSION。建议：project(firmware VERSION 1.2.0)' -ForegroundColor Yellow
    }
} else {
    Write-Host '[!] 未找到 CMakeLists.txt' -ForegroundColor Yellow
}
```

**检查 2：git 仓库状态**

```powershell
if (-not (Test-Path "<项目根目录>\.git")) {
    Write-Host '[!] 项目未纳入 git 管理。ESP-IDF 默认用 git describe 生成版本号（project 未声明 VERSION 时），无 git 则版本号缺失' -ForegroundColor Yellow
} else {
    $dirty = git -C "<项目根目录>" status --short -- "*.c" "*.h" "CMakeLists.txt" "*.cmake" 2>$null
    if ($dirty) {
        Write-Host '[!] 有未提交的源码改动。验证通过后请 commit：type(scope): subject' -ForegroundColor Yellow
    }
}
```

**检查 3：烧录后核对固件内版本**（在报告结果中追加）

```powershell
# 从固件头读取版本（esptool 自带，无需手写解析）
python -m esptool image_info "<项目目录>\build\firmware.bin"
# 应输出 Application version: 1.2.0，与 CMakeLists.txt 的 project VERSION 一致
# 不一致说明烧的固件与源码版本不符
```

**版本号三处一致性要求**：

| 位置 | 内容 | 必须一致 |
|------|------|----------|
| CMakeLists.txt | `project(<name> VERSION X.Y.Z)` | ✅ 权威来源 |
| git tag | `vX.Y.Z` | ✅ 发布时打 |
| 固件头 esp_app_desc | Application version: X.Y.Z | ✅ 烧录后核对 |

### 第三步：烧录前安全校验（safe-flash）

编译成功后、执行烧录前，**必须**完成以下验证，防止烧录到错误的板子：

#### 3.0 编译产物新鲜度检查（时间戳，强制）

> **防旧版本红线**：2026-08-20 数码管项目踩坑——复制新源码后直接烧录旧产物导致功能不生效。`idf.py flash` 默认只做增量检查（未改文件不重编），若 build/ 产物时间戳早于 main/ 源码，必须先 `idf.py build` 再烧录。

```powershell
$latestSource = Get-ChildItem -Path "<项目目录>\main" -Recurse -Include *.c,*.h |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$bin = Get-ChildItem -Path "<项目目录>\build" -Recurse -Include *.bin |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($bin -and $latestSource.LastWriteTime -gt $bin.LastWriteTime) {
    Write-Host '[X] 编译产物比源码旧，请先 idf.py build 重新编译' -ForegroundColor Red
    return  # 阻止烧录
}
Write-Host "[OK] 编译产物新鲜度正常（产物时间戳: $($bin.LastWriteTime)）" -ForegroundColor Green
```

> 判断逻辑：**产物时间戳 > 所有源码时间戳**才算新鲜；任一源码比产物新 → 说明产物是旧的 → 禁止烧录。

#### 3.1 串口枚举与可达性检查

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

#### 3.2 芯片类型匹配验证

读取当前板子配置（board-config），比对目标串口连接的芯片类型：

```powershell
# 读取当前板子配置
$boardName = $env:CURRENT_BOARD
if ($boardName) {
    $configPath = "$env:USERPROFILE\Tools\board-config\$boardName.ps1"
    if (Test-Path $configPath) {
        $boardConfig = & $configPath
        $expectedType = $boardConfig.Type   # 如 "ESP32-S3"
        $defaultPort  = $boardConfig.DefaultUart
        Write-Host "当前板子: $($boardConfig.Name) | 期望芯片: $expectedType | 默认串口: $defaultPort" -ForegroundColor Yellow
    }
}

# 对比目标芯片（从 sdkconfig 读取）
$sdkconfig = Get-Content "<项目路径>\sdkconfig" -ErrorAction SilentlyContinue
$target = ($sdkconfig | Select-String "CONFIG_IDF_TARGET=").Line.Replace("CONFIG_IDF_TARGET=", "")
Write-Host "项目目标芯片: $target" -ForegroundColor Yellow
```

如果 board-config 的 `Type` 与 sdkconfig 的 `CONFIG_IDF_TARGET` 不一致（例如板子是 ESP32-S3 但项目配置为 ESP32），**警告用户并暂停烧录**。

#### 3.3 用户确认门

```
========================================
  烧录前确认
========================================
项目：<项目名>
芯片：ESP32-S3（来自 sdkconfig）
板子：ESP32-S3-WROOM-1-N16R8（来自 board-config）
串口：COM8
目标：编译 + 烧录 + 监控

确认烧录？(Y/N)
```

**必须等到用户确认后才执行烧录**。如果用户之前明确说"烧录"可视为隐式确认。

> 也可以直接调用 safe-flash 脚本完成上述所有校验：
> ```powershell
> & "$env:USERPROFILE\Tools\safe-flash.ps1" -ListPorts   # 先列出可用串口和芯片类型
> & "$env:USERPROFILE\Tools\safe-flash.ps1" -Port COM8    # 指定串口，自动校验 + 确认 + 烧录
> ```

### 第四步：烧录（idf.py flash）

```powershell
# 指定串口号烧录
idf.py -p COM5 flash 2>&1 | Tee-Object -FilePath "flash_log.txt"

# 检查烧录结果
if ($LASTEXITCODE -eq 0) {
    Write-Output "烧录成功"
} else {
    Write-Output "烧录失败，查看 flash_log.txt"
}
```

### 第五步：监控（idf.py monitor，可选）

```powershell
# 串口监控（Ctrl+] 退出）
# 注意：监控是持续输出，需要用 blocking: false 启动
idf.py -p COM5 monitor
```

### 一键编译+烧录+监控

```powershell
# 三条命令合并执行
idf.py -p COM5 build flash monitor
```

## 芯片配置切换

```powershell
# 查看当前目标芯片
idf.py fullclean   # 清理构建目录（切换芯片前必须清理）
idf.py set-target esp32s3   # 切换到 ESP32-S3
idf.py menuconfig           # 图形化配置
```

## 内存分析（编译后自动提取）

ESP-IDF 编译输出中包含内存占用信息：

```
Total sizes:
Used static DRAM:  xx bytes ( xx available, xx percent used)
Used static IRAM:  xx bytes ( xx available, xx percent used)
Flash image:  xxx bytes
```

从编译日志中提取：
```powershell
$log = Get-Content "build_log.txt" -Raw

# 提取 DRAM 占用
if ($log -match "Used static DRAM:\s+(\d+)\s+bytes.*?(\d+\.\d+)\s+percent used") {
    $dramUsed = [int]$matches[1]
    $dramPercent = [double]$matches[2]
    Write-Output "DRAM：$dramUsed 字节 ($dramPercent%)"
}

# 提取 IRAM 占用
if ($log -match "Used static IRAM:\s+(\d+)\s+bytes.*?(\d+\.\d+)\s+percent used") {
    $iramUsed = [int]$matches[1]
    $iramPercent = [double]$matches[2]
    Write-Output "IRAM：$iramUsed 字节 ($iramPercent%)"
}

# 提取 Flash 镜像大小
if ($log -match "Flash image:\s+(\d+)\s+bytes") {
    $flashSize = [int]$matches[1]
    Write-Output "Flash 镜像：$flashSize 字节"
}
```

## 常见错误排查、命令速查与验证记录

> 常见错误排查表、常用命令速查、验证记录维护在 **同目录 reference.md**；踩坑记录保留在主文件（高频防坑经验）。

---

## 与其他 Skill 联动

### 与 serial-debug 联动

烧录后可用 serial-debug 技能监听串口输出：
- 简单监听：用 `serial-debug` 的 `list` 和监听功能
- 详细监控：用 `idf.py monitor`（支持异常解码、颜色输出）

### 与 esp32-panic-diagnosis 联动

如果监控输出中出现 `Guru Meditation Error`，自动调用 panic 诊断技能分析崩溃原因。

### 与 hardware-detection 联动

烧录失败时，检测 USB 串口连接状态（注意：ESP32 用 USB 串口，不是 ST-Link/J-Link）。

### 与 esp-burn 工具联动

推荐使用 `esp-burn` 工具替代手动执行 idf.py 命令：
- 自动扫描串口，识别 ESP32 设备
- 烧录失败自动重试（最多 3 次）
- 根据错误信息自动给出排查建议
- 支持 bin 直接烧录和项目编译+烧录+监控一条龙

```powershell
# 编译 + 烧录 + 监控（推荐）
esp-burn -Mode build-flash-monitor -ProjectDir <项目目录>

# 仅烧录 bin 文件
esp-burn -Mode flash -Firmware <bin 文件路径>
```

## 触发时机

- **自动触发**：用户改完 ESP32 代码后说"编译一下"、"烧录"、"跑一下"
- **手动触发**：用户明确要求"编译 ESP32"、"烧录 ESP32"
- **不触发**：GD32/STM32/STC8 等非 ESP32 项目

## 踩坑记录

### 安装踩坑（重要）

1. **GitHub 下载不通**：`dl.espressif.com` 在国内可能不通，必须改用 `dl.espressif.cn`
   ```powershell
   $env:IDF_GITHUB_ASSETS = "dl.espressif.cn/github_assets"
   ```

2. **PowerShell 执行策略**：默认禁止运行脚本，需要绕过
   ```powershell
   powershell -ExecutionPolicy Bypass -File "$IDF_PATH\install.ps1" all
   ```

3. **沙箱限制**：AI 可能无法操作工具链目录创建虚拟环境，需要用户手动运行 install 脚本

4. **Python 版本**（已解决）：系统 Python 版本决定虚拟环境名称，export.ps1 默认找 `py3.10_env`。已通过环境脚本的多版本回退检测解决

5. **环境会话一致性**（已优化）：PowerShell Profile 进入项目目录自动加载环境，无需手动初始化

6. **切换芯片前必须 fullclean**：否则可能出现奇怪的编译错误

7. **烧录时可能需要按 BOOT 键**：部分开发板需要手动进入下载模式

8. **监控退出快捷键**：`Ctrl + ]` 退出 monitor

9. **MSYS 环境误判**：从 QoderWork bash（Git Bash 内核）运行 idf.py 时，若存在 `MSYSTEM`/`MSYS`/`CHERE_INVOKING` 环境变量，ESP-IDF 会误判为 MSys 环境并报错。解决：每次调用前置 `$null`（见「从 QoderWork Bash 调用」一节）

10. **工具链版本号不能硬编码**：`tools/` 下的目录名包含版本号（如 `cmake/3.30.2`、`xtensa-esp-elf/14.2.0_20241119`），不同机器/不同时间安装的版本不同。必须先 `ls` 检测实际目录名再拼接 PATH，否则报"找不到 cmake/ninja/gcc"

## 注意事项

1. **ESP-IDF 使用自己的 Python venv**：不要用系统 Python 直接运行 idf.py
2. **文件编码**：ESP-IDF 源码推荐 UTF-8，和 GD32 一致
3. **ESP32-S3 是双核**：注意看崩溃发生在哪个核，Core 0 通常跑 WiFi/蓝牙，Core 1 跑应用

