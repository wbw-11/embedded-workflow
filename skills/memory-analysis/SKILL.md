---
name: memory-analysis
description: "内存占用分析：解读 Keil 编译 Code/RO/RW/ZI，算 Flash/RAM 占比与预警。"
install_method: upload
version: 1.1.0
---

# 内存分析技能

## 概述

解读 Keil 编译输出中的内存统计信息，分析 Flash 和 RAM 占用情况，对比芯片限制给出预警。

**使用时机：**
- Keil 编译完成后，自动分析内存占用
- 用户问"内存够不够"、"Flash 用了多少"
- 项目越做越大，需要评估资源余量
- 优化代码前，先了解当前内存分布

**适用芯片：** 所有 Keil 编译输出的项目（GD32 / STM32 / STC8 等）。芯片限制值通过下方配置表查询，未知芯片只输出原始统计不计算百分比。

## 芯片配置表

> **权威来源说明**：Flash/RAM 容量的权威数据维护在 `board-config/*.ps1`（通过 `Get-CurrentBoard()` 读取）。下表仅包含 Keil 专用的启动文件信息，Flash/RAM 字段应与 board-config 保持一致。新增芯片时请同步更新两处。

| 芯片型号 | Flash (字节) | RAM (字节) | 启动文件 |
|----------|-------------|-----------|----------|
| GD32F407VE | 524288 (512KB) | 196608 (192KB) | startup_gd32f407_427.s |
| GD32F407VG | 1048576 (1MB) | 196608 (192KB) | startup_gd32f407_427.s |
| GD32F407ZG | 1048576 (1MB) | 196608 (192KB) | startup_gd32f407_427.s |
| GD32F103C8 | 65536 (64KB) | 20480 (20KB) | startup_gd32f10x_md.s |
| STM32F407VG | 1048576 (1MB) | 196608 (192KB) | startup_stm32f407xx.s |
| STM32F103C8 | 65536 (64KB) | 20480 (20KB) | startup_stm32f10x_md.s |
| STM32H743VI | 2097152 (2MB) | 1048576 (1MB) | startup_stm32h743xx.s |
| STC8H8K64U | 65536 (64KB) | 8192 (8KB) | - |
| STC15W4K56S4 | 57344 (56KB) | 4096 (4KB) | - |
| STC89C52RC | 8192 (8KB) | 512 (512B) | - |

## 芯片推断流程（三步法）

```
1. 优先从用户消息提取芯片型号（如"这是 STM32F103 项目"）
   - 正则：/(GD32|STM32|STC)[A-Z0-9]+/i
2. 从项目路径推断（如路径含 "GD32F4xx" → GD32F407VE）
3. 都失败时：只输出原始统计，不计算百分比，提示用户告知芯片型号
```

```powershell
# 芯片配置表（Flash/RAM 同步自 board-config，启动文件为 Keil 专用字段）
# 新增芯片时请同步更新 board-config/<芯片>.ps1
$chipConfig = @{
    "GD32F407VE"   = @{ Flash = 524288;   RAM = 196608; Startup = "startup_gd32f407_427.s" }
    "GD32F407VG"   = @{ Flash = 1048576;  RAM = 196608; Startup = "startup_gd32f407_427.s" }
    "GD32F407ZG"   = @{ Flash = 1048576;  RAM = 196608; Startup = "startup_gd32f407_427.s" }
    "GD32F103C8"   = @{ Flash = 65536;    RAM = 20480;  Startup = "startup_gd32f10x_md.s" }
    "STM32F407VG"  = @{ Flash = 1048576;  RAM = 196608; Startup = "startup_stm32f407xx.s" }
    "STM32F103C8"  = @{ Flash = 65536;    RAM = 20480;  Startup = "startup_stm32f10x_md.s" }
    "STM32H743VI"  = @{ Flash = 2097152;  RAM = 1048576; Startup = "startup_stm32h743xx.s" }
    "STC8H8K64U"   = @{ Flash = 65536;    RAM = 8192;   Startup = "" }
    "STC15W4K56S4" = @{ Flash = 57344;    RAM = 4096;   Startup = "" }
    "STC89C52RC"   = @{ Flash = 8192;     RAM = 512;    Startup = "" }
}

# 三步推断芯片型号
$chipModel = $null

# 步骤1：从用户消息提取
if ($userMessage -match "((?:GD32|STM32|STC)[A-Z0-9]+)") {
    $chipModel = $matches[1]
}

# 步骤2：从项目路径推断
if (-not $chipModel) {
    if ($projectPath -match "GD32F4xx") { $chipModel = "GD32F407VE" }
    elseif ($projectPath -match "STM32F1") { $chipModel = "STM32F103C8" }
    elseif ($projectPath -match "STM32F4") { $chipModel = "STM32F407VG" }
    elseif ($projectPath -match "STM32H7") { $chipModel = "STM32H743VI" }
    elseif ($projectPath -match "STC8H") { $chipModel = "STC8H8K64U" }
    elseif ($projectPath -match "STC15") { $chipModel = "STC15W4K56S4" }
    elseif ($projectPath -match "STC89") { $chipModel = "STC89C52RC" }
}

# 步骤3：未知芯片处理
if (-not $chipModel -or -not $chipConfig.ContainsKey($chipModel)) {
    Write-Output "⚠️ 未知芯片型号，只输出原始统计，不计算百分比"
    Write-Output "   请告知芯片型号以获取占用百分比（支持：$($chipConfig.Keys -join ', '))"
    # 只输出原始统计，跳过百分比计算
    return
}
```

## 编译输出解读

### Keil 编译输出格式

```
Program Size: Code=12345 RO-data=678 RW-data=90 ZI-data=1234
```

### 各段含义

| 段名 | 全称 | 存储位置 | 含义 |
|------|------|----------|------|
| **Code** | 代码段 | Flash | 程序指令（.text），编译后的机器码 |
| **RO-data** | 只读数据 | Flash | 常量数据（const 变量、字符串字面量、查找表）|
| **RW-data** | 可读可写数据 | Flash + RAM | 已初始化的全局/静态变量（.data），启动时从 Flash 复制到 RAM |
| **ZI-data** | 零初始化数据 | RAM | 未初始化的全局/静态变量（.bss），启动时清零 |

### 占用计算

```
Flash 占用 = Code + RO-data + RW-data
RAM 占用   = RW-data + ZI-data
```

## 分析流程

### 第一步：提取编译输出

从 build_log.txt 中提取内存统计行：

```powershell
$content = [System.IO.File]::ReadAllText("<build_log.txt>", [System.Text.Encoding]::GetEncoding(936))
if ($content -match "Program Size: Code=(\d+) RO-data=(\d+) RW-data=(\d+) ZI-data=(\d+)") {
    $code = [int]$matches[1]
    $rodata = [int]$matches[2]
    $rwdata = [int]$matches[3]
    $zidata = [int]$matches[4]
}
```

### 第二步：计算占用

```powershell
$flashUsed = $code + $rodata + $rwdata
$ramUsed = $rwdata + $zidata

# 从芯片配置表获取限制值（不硬编码）
$flashLimit = $chipConfig[$chipModel].Flash
$ramLimit = $chipConfig[$chipModel].RAM

$flashPercent = ($flashUsed / $flashLimit) * 100
$ramPercent = ($ramUsed / $ramLimit) * 100
```

### 第三步：输出分析报告

#### 已知芯片报告格式

```
【内存分析报告】

芯片：GD32F407VE（推断来源：项目路径）

Flash 占用：
  - Code:     12,345 字节 (指令)
  - RO-data:    678 字节 (常量)
  - RW-data:     90 字节 (已初始化变量)
  - 总计:     13,113 字节 / 524,288 字节 (512KB)
  - 占比:      2.5%  ✅ 充裕

RAM 占用：
  - RW-data:     90 字节 (已初始化变量)
  - ZI-data:  1,234 字节 (未初始化变量)
  - 总计:      1,324 字节 / 196,608 字节 (192KB)
  - 占比:      0.7%  ✅ 充裕

Flash 剩余：511,175 字节 (97.5%)
RAM 剩余：  195,284 字节 (99.3%)
```

#### 未知芯片报告格式（只输出原始统计）

```
【内存分析报告】

⚠️ 未知芯片型号，只输出原始统计，不计算百分比

Flash 占用（原始统计）：
  - Code:     12,345 字节
  - RO-data:    678 字节
  - RW-data:     90 字节
  - 总计:     13,113 字节

RAM 占用（原始统计）：
  - RW-data:     90 字节
  - ZI-data:  1,234 字节
  - 总计:      1,324 字节

提示：请告知芯片型号（如 GD32F407VE、STM32F103C8、STC8H8K64U 等）以获取占用百分比
```

## 预警阈值

| 占用比例 | 状态 | 建议 |
|----------|------|------|
| < 50% | ✅ 充裕 | 继续开发，无需担心 |
| 50~70% | ⚠️ 注意 | 正常范围，但新增大功能时需留意 |
| 70~85% | ⚠️ 紧张 | 建议优化，检查是否有大数组/大常量表 |
| 85~95% | ❌ 危险 | 必须优化，可能需要用外部存储或裁剪功能 |
| > 95% | ❌ 溢出风险 | 无法编译通过，必须大幅优化 |

## 常见优化方向

### Flash 优化

| 问题 | 优化方法 |
|------|----------|
| Code 过大 | 开编译器优化 `-O2` 或 `-Os`，去掉未使用的函数 |
| RO-data 过大 | 压缩常量表、用算法代替查表、去掉未使用的字符串 |
| RW-data 过大 | 把已初始化变量改为未初始化（ZI-data 不占 Flash）|

### RAM 优化

| 问题 | 优化方法 |
|------|----------|
| RW-data 过大 | 把全局变量改为 const（挪到 RO-data）|
| ZI-data 过大 | 减小数组/缓冲区大小、用动态分配（谨慎）|
| 栈溢出 | 减小局部数组、避免递归、增加栈大小（启动文件）|

## 栈大小估算

栈大小在启动文件中定义（ARM Cortex-M 系列），不同芯片启动文件名不同：

```asm
/* GD32F407：startup_gd32f407_427.s */
/* STM32F407：startup_stm32f407xx.s */
/* STM32F103：startup_stm32f10x_md.s */
Stack_Size      EQU     0x00010000    ; 栈大小（按实际芯片调整）
```

**估算方法：**
```
栈需求 ≈ 最大中断嵌套深度 × ISR 栈使用 + 最深函数调用链 × 函数栈使用

保守估算：栈大小 ≥ 最大任务栈使用 × 2
```

**如果栈溢出特征：**
- 程序运行一段时间后随机死机
- HardFault 时 SP 值异常接近栈底
- 修改代码后（增加局部变量）才出现

> 注：8051 内核（STC8H/STC15/STC89）使用固定栈区，无独立启动文件，栈大小由硬件决定。

## 与其他 Skill 联动

### 与 keil-auto-flash 联动

编译成功后自动调用内存分析，输出报告：
```
【01_GD32F407_PB2_PD8】编译+烧录+内存分析
- 编译：✅ 成功（0 错误，0 警告）
- 烧录：✅ 成功
- 芯片：GD32F407VE（推断来源：项目路径）
- Flash：2.5%  ✅ 充裕
- RAM：0.7%  ✅ 充裕
```

### 与 hardfault-diagnosis 联动

如果内存占用接近 100%，HardFault 可能是栈溢出导致。
## LVGL 内部池专项检查（2026-09-01 实测补充）

> **触发场景**：项目使用 LVGL（GD32/STM32 等），界面突然"定格 + 触摸失灵 + 时间/数据不刷新"，且无任何日志输出。
> **根因**：LVGL 内部池 `LV_MEM_SIZE`（lv_conf.h）耗尽，`LV_ASSERT_MALLOC=1` + `LV_ASSERT_HANDLER while(1)` 直接永久死循环——无打印、无 HardFault、界面停在首帧。

### 现象特征速查

| 现象 | 含义 |
|------|------|
| 界面定格首帧（如时间停 00:00） | LVGL 创建 UI 中途 `while(1)` |
| 触摸/滑动完全失灵 | LVGL 事件循环不再运行 |
| 无串口日志、无 FATAL | 死在 LV_ASSERT_HANDLER，不是任务崩溃 |
| 改了 UI（加对象/字体/图标）后出现 | 对象+字形缓存撑爆内部池 |

### LVGL 池内存估算（改 UI 前必做）

`
消耗 ≈ 对象数 × 200B + 中文字形缓存 + 图标字形缓存
- 每个 lv_obj/label/btn 约 150~250B
- 中文字体每个字形位图约 0.5~2KB（按字体字号），几十个汉字就去掉 10~30KB
- 大字号数字字体（如 40px）每个数字字形可达 1~3KB
`

### 检查与修复步骤

1. 编译后看 `Program Size` 的 **ZI-data**，确认 RAM 余量（LV_MEM_SIZE 是静态数组，计入 ZI-data）
2. 估算本次 UI 新增对象数量，与当前 `LV_MEM_SIZE` 对比
3. 池大小调整经验（GD32F407VE 实测）：
   - 简单 UI：32KB 足够
   - 现代风多卡多环 UI（表盘×3 影子 + 运动/心率/设置页）：需 48KB（32KB 耗尽死机）
   - 上限约束：主 SRAM 128KB（GD32F407VE IRAM 0x20000000,0x020000），80KB 池会导致 L6406E 链接失败
   - 若 RAM 紧张：启用分区刷新、减少表盘影子 UI、缩减中文字符集

**实测记录（2026-09-01 GD32F407VE LVGL 手表项目，48KB 池运行时 lv_mem_monitor 打印）：**
- 池总大小 49,152B；完整多页 UI 存活占用 ~30.8KB（used 63%）；峰值 max_used 15,891B；空闲 ~18.3KB（37% 余量）
- 推论：32KB 池之所以死机，是因完整 UI（表盘×3 影子 + 运动/心率/设置全部对象+字形）存活占用已近 90%+，遇分片/动画临时分配即触发 while(1)
- 48KB 余量 37% 为稳妥值；RAM 足够时宁大勿小

**运行时余量检查方法（不靠猜）：**
1. 在 debug/info 任务加 lv_mem_monitor_t mm; lv_mem_monitor(&mm); 并 printf free_size/max_used/used_pct
2. 烧录后从串口读该行（当前项目已内置于 debug_task，每 2s 一打）
3. 遍历所有页面/触发所有动画后看峰值，即为真实余量参考
4. 临时诊断兜底：把 LV_ASSERT_HANDLER 改为打印后 while(1)，或开 LV_USE_LOG=1 看 No more memory


### 预防规则

- 改 UI（新增页面/控件/字体）后、烧录前，必须重新检查 LV_MEM_SIZE 余量
- LVGL 池耗尽症状（定格+失灵+无日志）≠ 硬件问题，先查内存再查硬件
- 大字体字形缓存是隐形消耗：中文字体优先用裁剪字库（只含用到的汉字）

## 触发时机

- **自动触发**：keil-auto-flash 编译成功后，自动分析内存
- **手动触发**：用户问"内存用了多少"、"Flash 够不够"时

## 注意事项

1. **ZI-data 不占 Flash**：未初始化变量只在 RAM 中，不占用 Flash 空间
2. **RW-data 既占 Flash 又占 RAM**：启动代码把初值从 Flash 复制到 RAM
3. **Code 优化级别影响大小**：`-O0`（不优化）> `-O2`（平衡）> `-Os`（最小代码）
4. **不同芯片限制不同**：必须通过配置表查询，不能硬编码（如 GD32F407VE 是 512KB，GD32F407VG 是 1MB）
5. **未知芯片不计算百分比**：避免用错误限制值算出误导性百分比（如把 STC89C52 的 8KB Flash 项目算成 0.2%）
6. **8051 与 ARM 编译输出格式相同**：Keil C51 和 ARMCC 都输出 Program Size 行，分析流程一致
7. **Flash/RAM 同步**：芯片配置表的 Flash/RAM 值应与 board-config 保持一致，新增芯片时两处都需更新