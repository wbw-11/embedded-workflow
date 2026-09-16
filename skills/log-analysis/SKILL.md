---
name: log-analysis
description: "日志分析：解析编译输出/运行日志定位错误。Keil/ESP-IDF 编译错、ESP32 Panic、HardFault。"
version: 1.0.0
---

## 概述

日志分析 Skill 用于自动解析编译输出和运行日志，定位错误位置，给出修复建议。该 Skill 覆盖嵌入式开发中常见的日志场景，包括 Keil C51 / ARMCC 编译日志、ESP-IDF (GCC) 编译日志、Makefile 构建日志，以及 ESP32 Panic、ARM HardFault 等运行时崩溃日志。

通过结构化解析日志内容，提取错误码、文件路径、行号等关键信息，并结合源码上下文给出针对性修复建议，帮助开发者快速定位和解决问题。

## 支持的日志类型

### 编译日志
- **Keil C51**：error Cxxx、warning Cxxx、Lxxx 链接错误
- **Keil ARM (ARMCC)**：error: #xxx、warning: #xxx、L6xxx 链接错误
- **ESP-IDF (GCC)**：error:、warning:、undefined reference to
- **Makefile**：No rule to make target、recipe for target failed

### 运行日志
- **ESP32 Panic**：Guru Meditation Error、Watchdog Timeout、Stack overflow
- **ARM HardFault**：HardFault_Handler、寄存器转储
- **通用 RTT/串口日志**：模块标签、错误等级、时间戳

## 编译错误分析流程
1. 提取所有 error: 和 warning: 行
2. 解析文件路径、行号、错误代码、错误消息
3. 对每个错误：
   a. 读取对应文件和行号
   b. 分析错误原因（语法错误、未定义符号、类型不匹配等）
   c. 给出修复建议
4. 输出修复清单（按优先级排序）

## 常见编译错误对照表

### Keil C51 错误代码
| 错误码 | 含义 | 常见原因 |
|-------|------|---------|
| C202 | 未定义标识符 | 拼写错误、头文件未包含 |
| C206 | 缺少分号 | 上一行末尾缺分号 |
| C129 | 缺少分号 | 语法错误 |
| L107 | 地址溢出 | RAM 超出芯片容量 |
| L121 | 重复定义 | 同一变量多处定义 |

### ARMCC 错误代码
| 错误码 | 含义 | 常见原因 |
|-------|------|---------|
| #20 | 标识符未声明 | 头文件未包含、拼写错误 |
| #5 | 无法打开源文件 | 路径错误、文件不存在 |
| #18 | 重复定义 | 同一变量多处定义 |
| #159 | 函数声明在 return 之后 | 函数声明必须在函数外 |
| L6406 | 链接范围溢出 | Flash/RAM 超出芯片容量 |

### ESP-IDF (GCC) 错误
| 错误模式 | 含义 | 常见原因 |
|---------|------|---------|
| undefined reference to | 未定义引用 | 函数未实现、库未链接 |
| conflicting types for | 类型冲突 | 函数声明与实现不一致 |
| expected ';' before | 缺少分号 | 语法错误 |
| No rule to make target | Make 规则缺失 | 文件名错误、路径错误 |

## 运行日志分析

### ESP32 Panic 分析
触发条件：日志中出现 "Guru Meditation Error"、"Watchdog Timeout"、"Stack overflow"
→ 识别到 Panic 日志后，直接调用 **esp32-panic-diagnosis** 技能进行完整诊断（backtrace 解析、崩溃定位）。

### ARM HardFault 分析
触发条件：进入 HardFault_Handler 或打印寄存器转储
→ 识别到 HardFault 日志后，直接调用 **hardfault-diagnosis** 技能进行完整诊断（寄存器解析、Fault Status 分析、崩溃定位）。

## 日志格式化
解析日志时按以下规则格式化：
- 时间戳：[HH:MM:SS.mmm]
- 模块标签：[MODULE]
- 等级：[E]/[W]/[I]/[D]/[V]
- 消息：原始内容

## 输出格式
分析完成后输出：
```
=========================================
  日志分析报告
=========================================
日志类型：ESP-IDF 编译日志
错误数：3，警告数：5

【错误清单】
1. [ERROR] main.c:45:5: 'foo' was not declared in this scope
   原因：函数 foo 未声明
   建议：检查头文件是否包含 foo 的声明

2. [ERROR] ...
```

## 联动其他 Skill
- 编译错误 → 查 datasheet-lookup 确认寄存器
- Panic → 调用 esp32-panic-diagnosis
- HardFault → 调用 hardfault-diagnosis
- 内存溢出 → 调用 memory-analysis

## 编译警告自动匹配（warning-db 工具）

编译日志分析后，可调用 `warning-db` 工具自动匹配已知警告模式并给出解决方案：

```powershell
# 自动解析编译输出，匹配已知警告/错误
warning-db -Parse build_log.txt

# 按关键词搜索已知警告
warning-db -Search "未定义"

# 按平台过滤
warning-db -Platform c51      # Keil C51
warning-db -Platform armcc    # Keil ARM
warning-db -Platform gcc      # ESP-IDF/GCC
warning-db -Platform linker   # 链接器错误

# 查看特定警告详情
warning-db -Detail c51-c202
```

**数据库位置**：`$env:USERPROFILE\Tools\warning-db.json`（15 条已知警告/错误，覆盖 C51/ARMCC/GCC/Linker 四个平台）

**严重等级**：critical（严重）→ high（高）→ medium（中）→ low（低）

**工作流**：编译失败时先手动分析错误，再用 `warning-db -Parse` 自动匹配已知模式，获得更详细的原因和解决方案。
