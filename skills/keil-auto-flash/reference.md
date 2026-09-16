# Keil 自动编译烧录 - 详细参考

> 本文件为 keil-auto-flash 技能的辅助脚本与示例（自 SKILL.md 拆分）。SKILL.md 保留完整执行流程。

---

```powershell
# 芯片配置（权威数据维护在 memory-analysis 技能中，此处为运行时副本）
# 新增芯片时请同步更新 memory-analysis 的配置表
$projectPath = "<项目根目录>"
$chipConfig = @{
    "GD32F407VE" = @{ Flash = 524288; RAM = 196608 }
    "GD32F407VG" = @{ Flash = 1048576; RAM = 196608 }
    "GD32F103C8" = @{ Flash = 65536; RAM = 20480 }
    "STM32F407VG" = @{ Flash = 1048576; RAM = 196608 }
    "STM32F103C8" = @{ Flash = 65536; RAM = 20480 }
    "STC8H8K64U" = @{ Flash = 65536; RAM = 8192 }
    "STC15W4K56S4" = @{ Flash = 57344; RAM = 4096 }
}

# 推断芯片（根据路径关键词匹配）
$chip = $null
foreach ($key in $chipConfig.Keys) {
    if ($projectPath -match $key -or $projectPath -match $key.Replace("GD32", "GD32").Replace("STM32", "STM32").Replace("STC8H", "STC8H")) {
        $chip = $key
        break
    }
}

# 提取内存统计（所有芯片通用）
$content = [System.IO.File]::ReadAllText("<build_log.txt路径>", [System.Text.Encoding]::GetEncoding(936))
if ($content -match "Program Size: Code=(\d+) RO-data=(\d+) RW-data=(\d+) ZI-data=(\d+)") {
    $code = [int]$matches[1]; $ro = [int]$matches[2]; $rw = [int]$matches[3]; $zi = [int]$matches[4]
    $flash = $code + $ro + $rw; $ram = $rw + $zi
    
    # 如果推断出芯片型号，计算百分比
    if ($chip -ne $null) {
        $flashLimit = $chipConfig[$chip].Flash
        $ramLimit = $chipConfig[$chip].RAM
        $flashPct = [math]::Round(($flash / $flashLimit) * 100, 1)
        $ramPct  = [math]::Round(($ram / $ramLimit) * 100, 1)
        Write-Output "芯片：$chip | Flash: $flash 字节 ($flashPct%) | RAM: $ram 字节 ($ramPct%)"
    } else {
        # 推断不出时，只输出原始统计，不计算百分比（避免误导）
        Write-Output "Flash: $flash 字节 (Code=$code, RO=$ro, RW=$rw) | RAM: $ram 字节 (RW=$rw, ZI=$zi)"
        Write-Output "⚠️ 无法推断芯片型号，未计算百分比。请告诉我芯片型号以便准确分析。"
    }
}
```

#### 7.2 烧录失败时 —— 自动硬件检测

如果烧录日志含 `Cannot access`、`No target connected`、`Flash Download failed` 等关键字，**自动调用 hardware-detection Skill**：

```powershell
# 读取烧录日志判断失败类型
$flashContent = [System.IO.File]::ReadAllText("<flash_log.txt路径>", [System.Text.Encoding]::GetEncoding(936))
if ($flashContent -match "Cannot access|No target connected|Flash Download failed") {
    # 自动执行硬件检测
    # 1. 检测调试器是否存在
    # 2. 读取芯片电压/Device ID
    # 3. 输出硬件检测报告
}
```

#### 单项目烧录结果
```
【项目名称】编译+烧录结果
- 编译：✅ 成功（0 错误，X 警告）/ ❌ 失败（X 错误）
- 烧录：✅ 成功 / ❌ 失败（原因：xxx）
- Flash 占用：xx,xxx 字节 / 512KB (x.x%)  ✅/⚠️/❌
- RAM 占用：  xx,xxx 字节 / 192KB (x.x%)  ✅/⚠️/❌
- Git 状态：已提交 干净 / 有 N 个未提交改动（验证通过后请 commit）
- 版本号：<FW_VERSION_STRING>（来源 version.h；缺 version.h 时提示添加）
- 编译日志：<build_log.txt路径>
- 烧录日志：<flash_log.txt路径>
- 验证建议：<根据项目功能给出具体验证步骤>
```

#### 多项目批量结果
如果本次修改涉及多个项目：
1. 按项目目录名字母顺序依次处理
2. 每个项目独立执行完整流程
3. 某个项目编译失败时停止该项目，可继续下一个
4. 某个项目烧录失败时停止该项目，可继续下一个
5. 全部完成后汇总：

```
【批量烧录汇总】
| 项目 | 编译 | 烧录 | 状态 |
|------|------|------|------|
| 01_LED188 | ✅ | ✅ | 完成 |
| 02_ADKey | ✅ | ❌ | 失败：CMSIS-DAP 未连接 |
```

## 命令示例

### 定位工程文件（PowerShell）
```powershell
Get-ChildItem -Path "<项目根目录>\01_GD32F407_PB2_PD8" -Recurse -Filter "*.uvprojx" | ForEach-Object { $_.FullName }
```

### 第一步：编译验证
```
命令：<UV4_PATH> -b "<项目目录>\GD32F407.uvprojx" -o "<项目目录>\build_log.txt"
cwd：<项目目录>
blocking: true
```

### 第二步：读编译日志（GB2312 + 搜关键字）
```powershell
$content = [System.IO.File]::ReadAllText("<项目根目录>\Project\build_log.txt", [System.Text.Encoding]::GetEncoding(936))
$content -split "`n" | Where-Object { $_ -match "Error\(s\)|Warning\(s\)|error:" }
```

### 第三步：烧录
```
命令：<UV4_PATH> -f "<项目目录>\GD32F407.uvprojx" -o "<项目目录>\flash_log.txt"
cwd：<项目目录>
blocking: true
```

### 第四步：读烧录日志（GB2312 + 搜关键字）
```powershell
$content = [System.IO.File]::ReadAllText("<项目根目录>\Project\flash_log.txt", [System.Text.Encoding]::GetEncoding(936))
$content -split "`n" | Where-Object { $_ -match "Verify OK|Flash Load|Erase Done|Programming Done|Error|Cannot|Failed|Time out" }
```

## 日志判断示例

### 编译+烧录都成功
**build_log.txt** 关键行：
```
".\Objects\GD32F407.axf" - 0 Error(s), 0 Warning(s).
Build Time Elapsed:  00:00:08
```
**flash_log.txt** 关键行：
```
Erase Done.
Programming Done.
Verify OK.
Application running ...
Flash Load finished at 21:18:29
```

### 编译失败（停止，不烧录）
**build_log.txt** 关键行：
```
main.c(15): error: #20: identifier "gpio_mode" is undefined
".\Objects\GD32F407.axf" - 1 Error(s), 0 Warning(s).
```
→ 日志含 `1 Error(s)`，停止，不执行烧录，报告 `main.c(15): error: #20`

### 烧录失败
**flash_log.txt** 关键行：
```
Error: Flash Download failed - "Cortex-M4"
```
→ 日志含 `Flash Download failed`，报告 CMSIS-DAP 或芯片连接问题

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| UV4.exe 路径 `<KEIL_ROOT>\UV4\UV4.exe` | ✅ | 文件存在已确认 |
| `-b` 仅编译 / `-f` 仅烧录(Flash Download) / `-o` 日志输出 | ✅ | UV4 命令行标准参数（-f 不编译，需先 -b） |
| 注册表路径 `HKLM:\SOFTWARE\WOW6432Node\Keil\Products\MDK` | ✅ | 返回 `<KEIL_ROOT>\ARM` |
| GB2312 编码（代码页 936）读取日志 | ✅ | Keil 日志为 GB2312 编码 |
| ARMCC 编译器路径 `<KEIL_ROOT>\ARM\ARMCC\bin\armcc.exe` | ✅ | 文件存在已确认 |
| ARMCLANG 编译器目录 `<KEIL_ROOT>\ARM\ARMCLANG\Bin` | ✅ | 目录存在已确认 |
| 芯片配置表（Flash/RAM 字节数） | ✅ | 与 memory-analysis 技能一致 |
| `Program Size: Code=xx RO-data=xx RW-data=xx ZI-data=xx` 格式 | ✅ | Keil ARMCC 标准编译输出 |
