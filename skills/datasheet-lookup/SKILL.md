---
name: datasheet-lookup
description: "数据手册查阅：写寄存器前查项目头文件/Keil 系统头文件/PDF/官网确认定义。杜绝凭记忆。"
version: 1.1.0
install_method: upload
---

# 数据手册查阅技能

## 概述

写寄存器配置或调用库函数前，按规范流程查阅资料，确认寄存器名称、位定义、库函数名。杜绝凭记忆写代码导致的拼写错误和配置错误。

**使用时机：**
- 写新外设驱动前（需要确认寄存器配置）
- 调用不熟悉的库函数前（需要确认函数名和参数）
- 移植代码到新芯片时（需要确认寄存器兼容性）
- 编译报错"undefined identifier"时（可能是寄存器名写错）

**核心原则：**
> **不凭记忆写寄存器配置** —— 写寄存器地址、位定义、配置值前，必须先查头文件或 datasheet 确认。不同芯片（如 STC8H vs STC15）寄存器名称可能完全不同。

## 查阅优先级

按以下顺序逐级查询，找到即停：

```
1. 项目头文件（最高优先级，最可靠）
2. Keil 系统头文件（次高优先级）
3. PDF 数据手册（权威来源）
4. 官方网页版手册（补充来源）
5. GitHub/Gitee 开源项目（参考实现）
```

## 第一步：搜索项目头文件

### 1.1 定位头文件目录

在项目目录下搜索芯片头文件：

```powershell
# 搜索 GD32F4xx 头文件
Get-ChildItem -Path "<项目根目录>" -Recurse -Filter "gd32f4xx*.h" | Select-Object FullName

# 搜索外设头文件
Get-ChildItem -Path "<项目根目录>" -Recurse -Filter "gd32f4xx_usart*.h" | Select-Object FullName
Get-ChildItem -Path "<项目根目录>" -Recurse -Filter "gd32f4xx_gpio*.h" | Select-Object FullName
```

### 1.2 用 Grep 搜索寄存器/函数名

```powershell
# 搜索寄存器定义
Select-String -Path "<项目头文件目录>\*.h" -Pattern "USART_CTL0|USART_BAUD|GPIO_MODE_AF"

# 搜索库函数
Select-String -Path "<项目头文件目录>\*.h" -Pattern "usart_baudrate_set|gpio_mode_set"

# 搜索位定义
Select-String -Path "<项目头文件目录>\*.h" -Pattern "USART_CTL0_UEN|GPIO_MODE_AF"
```

**示例：确认 USART 波特率设置函数**
```powershell
Select-String -Path "d:\...\Firmware\GD32F4xx_standard_peripheral\Include\gd32f4xx_usart.h" -Pattern "baudrate"

# 输出：
# void usart_baudrate_set(uint32_t usart_periph, uint32_t baudval);
```

### 1.3 用 Read 工具读取头文件确认

找到相关头文件后，用 Read 工具读取并确认：
- 寄存器名称拼写
- 位定义值
- 函数参数类型和顺序

## 第二步：搜索 Keil 系统头文件

### 2.1 ARM 芯片头文件路径

不同厂商的 DFP 安装在不同子目录下，需根据芯片厂商动态查找：

```
# GD32：<KEIL_ROOT>\ARM\PACK\GigaDevice\GD32F4xx_DFP\<版本>\Device\Include\
# STM32：<KEIL_ROOT>\ARM\PACK\Keil\STM32F1xx_DFP\<版本>\Include\
#       <KEIL_ROOT>\ARM\PACK\Keil\STM32F4xx_DFP\<版本>\Include\
# 通用查找方式（不硬编码厂商和版本）：
```

```powershell
# 自动检测 Keil 安装路径
$keilRoot = @("C:\Keil_v5", "<KEIL_ROOT>", "E:\Keil_v5") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $keilRoot) {
    $reg = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Keil\Products\MDK" -ErrorAction SilentlyContinue
    if ($reg) { $keilRoot = $reg.Path }
}

# 动态查找所有已安装的 ARM DFP 头文件目录
Get-ChildItem -Path "$keilRoot\ARM\PACK" -Recurse -Filter "*.h" -Directory |
    Select-Object -ExpandProperty FullName
```

### 2.2 8051 芯片头文件路径

```
<KEIL_ROOT>\C51\INC\STC\STC8H.H
<KEIL_ROOT>\C51\INC\STC\STC15.H
```

### 2.3 搜索方法

```powershell
# ARM 芯片（通配符查找所有已安装的 DFP，不硬编码厂商）
Select-String -Path "$keilRoot\ARM\PACK\*\*\*\Device\Include\*.h" -Pattern "寄存器名"
# 或按芯片厂商缩小范围：
# Select-String -Path "$keilRoot\ARM\PACK\GigaDevice\*\*\Device\Include\*.h" -Pattern "寄存器名"
# Select-String -Path "$keilRoot\ARM\PACK\Keil\STM32*\*\Include\*.h" -Pattern "寄存器名"

# 8051 芯片
Select-String -Path "$keilRoot\C51\INC\STC\*.h" -Pattern "寄存器名"
```

## 第三步：读取 PDF 数据手册

### 3.0 PDF 读取工具选择策略

| 场景 | 工具 | 说明 |
|------|------|------|
| 快速提取 PDF 文本（查寄存器/函数名） | `mcp_pdf-reader-mcp` 的 `read_pdf` | 轻量，直接返回文本，适合查阅 datasheet 某一段 |
| 扫描件 PDF（图片型，文本提取为空） | `pdf` skill 的 OCR 功能 | 能识别图片中的文字 |
| 合并/拆分/加水印等复杂操作 | `pdf` skill | 全功能 PDF 处理 |

> **默认策略**：查寄存器配置时优先用 `mcp_pdf-reader-mcp`（快），文本提取为空再切换到 `pdf` skill 的 OCR。

### 3.1 使用 PDF Reader MCP

如果头文件中没有或不确定，用 PDF Reader MCP 读取数据手册：

```
# 搜索项目目录下的 PDF
Get-ChildItem -Path "<项目根目录>" -Recurse -Filter "*.pdf" | Select-Object Name

# 读取数据手册中的寄存器章节
# 重点关注：Register Description 章节
```

### 3.2 常见 PDF 手册位置

| 芯片 | 手册名称 | 关键章节 |
|------|----------|----------|
| GD32F407 | GD32F4xx_User_Manual_EN.pdf | Chapter 17 USART, Chapter 8 GPIO |
| GD32F407 | GD32F4xx_Datasheet_EN.pdf | Pinout, Electrical Characteristics |
| STC8H8K64U | STC8H 数据手册.pdf | 寄存器定义、时序参数 |

## 第四步：抓取官方网页版手册

### 4.1 使用 WebFetch MCP

```
# 兆易创新官网
https://www.gigadevice.com.cn/product/mcu/arm-cortex-m4/gd32f407vet6

# STC 官网
http://www.stcmcudata.com/
```

### 4.2 搜索寄存器定义

在网页手册中搜索寄存器名称，确认：
- 寄存器地址
- 位定义
- 复位值
- 读写属性

## 第五步：搜索开源项目参考

### 5.1 使用 GitHub/Gitee MCP

```
# 搜索同芯片的开源项目
search_repositories "GD32F407 USART DMA"
search_repositories "STC8H I2C"
```

### 5.2 参考实现注意事项

- 仅作为参考，不直接复制
- 确认与自己项目的库版本一致
- 注意不同版本的 API 差异

## 查询输出格式

```
【数据手册查阅结果】
查询项：USART 波特率设置函数

1. 项目头文件：✅ 找到
   - 文件：gd32f4xx_usart.h
   - 函数：void usart_baudrate_set(uint32_t usart_periph, uint32_t baudval);
   - 参数：usart_periph = USART0/1/2...，baudval = 波特率数值

2. Keil 系统头文件：✅ 一致
3. PDF 手册：✅ 一致

结论：函数名和参数确认无误，可以安全使用。
```

## 常见查询场景

### 场景1：确认 DMA 函数名

**问题**：凭记忆写了 `dma_struct_para_init()`，编译报错 undefined。

**查询流程**：
```powershell
# 1. 项目头文件搜索
Select-String -Path "*.h" -Pattern "dma.*init"

# 2. 找到正确函数名：dma_single_data_para_struct_init()
# 3. 读取头文件确认参数
```

### 场景2：确认 GPIO 复用配置

**问题**：不确定 USART0 TX 是配 AF 还是 OUTPUT。

**查询流程**：
```powershell
# 1. 项目头文件搜索
Select-String -Path "gd32f4xx_gpio.h" -Pattern "GPIO_MODE_AF|GPIO_MODE_OUTPUT"

# 2. 确认：TX 必须配 GPIO_MODE_AF
# 3. 确认复用号：AF7 = USART0
```

### 场景3：移植到不同芯片

**问题**：STC8H 的 ADC 寄存器和 STC15 是否相同？

**查询流程**：
```powershell
# 1. 搜索 STC8H 头文件
Select-String -Path "$keilRoot\C51\INC\STC\STC8H.H" -Pattern "ADC"

# 2. 搜索 STC15 头文件
Select-String -Path "$keilRoot\C51\INC\STC\STC15.H" -Pattern "ADC"

# 3. 对比发现：寄存器名称完全不同！不能直接复制代码
```

## 触发时机

- **自动触发**：写不熟悉的寄存器配置或库函数调用时
- **手动触发**：用户问"这个寄存器怎么配"、"这个函数叫什么"时
- **被动触发**：编译报错"undefined identifier"时

## 注意事项

1. **头文件优先**：项目头文件是最可靠的来源，因为与项目使用的库版本一致
2. **PDF 是权威**：头文件和 PDF 冲突时，以 PDF 为准（可能是库版本问题）
3. **不同版本差异大**：GD32F4xx 标准库 V3.2 和 V2.x 的函数名可能不同
4. **8051 和 ARM 完全不同**：STC8H 和 GD32F407 的寄存器命名规则差异巨大
5. **查不到时明确告知**：如果所有来源都查不到，明确告诉用户"无法确认，需您提供资料"

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| 查阅优先级流程（项目→Keil→PDF→网页→开源） | ✅ | 与 user_profile 中"寄存器验证流程"一致 |
| STC8H.H 头文件存在 | ✅ | `<KEIL_ROOT>\C51\INC\STC\STC8H.H` |
| STC15.H 头文件存在 | ✅ | `<KEIL_ROOT>\C51\INC\STC\STC15.H` |
| Keil 安装路径动态检测（环境变量→注册表→候选列表） | ✅ | 与 user_profile 中工具链路径一致 |
| GD32 DFP 头文件路径 | ✅ | `<KEIL_ROOT>\ARM\GigaDevice\GD32F4xx_DFP\3.2.0\` |
| 注意：DFP 安装在 ARM\ 下而非 ARM\PACK\ | ⚠️ | 本机 PACK 目录仅有 .Download/.Web，DFP 在 ARM\GigaDevice\ |
| `usart_baudrate_set` 函数示例 | ✅ | GD32F4xx_DFP `gd32f4xx_usart.h` |
| `dma_single_data_para_struct_init` 踩坑记录 | ✅ | GD32F4xx_DFP `gd32f4xx_dma.h` L360 |
