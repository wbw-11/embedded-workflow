---
name: code-migration
description: "代码移植助手：寄存器映射/库函数对照/外设差异。STC8↔GD32、GD32↔STM32、ESP32↔ARM。"
version: 1.0.0
---

## 概述

代码移植 Skill 用于在不同芯片间移植代码时，提供寄存器/库函数/外设的对照表和差异分析，避免凭记忆移植导致的错误。移植工作涉及内核架构、时钟系统、外设寄存器、库函数 API 等多方面差异，本 Skill 通过读取芯片头文件和参考手册，生成结构化对照表，确保移植准确可靠。

## 移植流程

1. 确认源芯片和目标芯片
2. 列出移植的外设模块（UART/SPI/I2C/ADC/TIMER/GPIO）
3. 对每个模块：
   a. 读取源芯片头文件，确认源代码使用的寄存器/库函数
   b. 读取目标芯片头文件，查找对应寄存器/库函数
   c. 列出差异（位定义、配置值、调用方式）
   d. 给出移植代码
4. 编译验证（参考 user_profile.md 的编译验证流程）
5. 烧录验证

## 常见移植场景

### STC8H → GD32F407
- 内核：8051 → Cortex-M4
- 时钟：内部 RC 24MHz → 外部晶振 25MHz + PLL
- GPIO：P0/P1/P2 → PA/PB/PC/PD/PE
- UART：SCON/SBUF → USART_CTL0/USART_DATA
- 开发方式：寄存器/STC库 → 寄存器/标准库/HAL
- 注意：8051 是 8 位，GD32 是 32 位，数据类型需调整（如 u8→uint8_t）

### GD32F407 → STM32F407
- 内核：Cortex-M4 → Cortex-M4（兼容）
- 库函数：gd32f4xx.h → stm32f4xx_hal.h
- 大部分寄存器地址和位定义相同
- 主要差异：HAL 库 vs 标准库、时钟树配置、中断向量表

### ARM → ESP32
- 内核：Cortex-M4 → Xtensa LX7
- 开发方式：裸机/HAL → ESP-IDF（FreeRTOS）
- GPIO：直接寄存器 → gpio_config()/gpio_set_level()
- UART：USART_DR → uart_driver_install()/uart_write_bytes()
- 注意：ESP32 是多核，需考虑任务调度

## 寄存器/库函数对照表生成

移植时按以下流程生成对照表：
1. 用 Grep 搜索源代码中所有寄存器/库函数引用
2. 读取源芯片头文件，提取寄存器定义和位定义
3. 读取目标芯片头文件，查找对应寄存器
4. 输出 Markdown 表格对照表

## Pitfalls

- **数据类型**：8051 的 u8/u16 → ARM 的 uint8_t/uint16_t
- **字节序**：8051 大端 → ARM 小端
- **中断优先级**：8051 固定 → ARM 可配置
- **时钟配置**：必须重新计算，不能直接移植
- **GPIO 驱动能力**：8051 弱 → ARM 可配置
- **DMA 通道**：8051 无 → ARM 多通道
- **浮点**：8051 软浮点 → Cortex-M4F 硬浮点

## Verification

- 移植后必须编译验证
- 烧录后逐个外设验证（UART 回显、SPI 通信、ADC 采样等）
## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| STC8H→GD32F407 移植差异（8051→Cortex-M4） | ✅ | 内核架构通用知识 |
| `gpio_config()` ESP32 GPIO 配置 API | ✅ | ESP-IDF v5.5.4 `driver/gpio.h` L71 |
| `gpio_set_level()` ESP32 GPIO 输出 API | ✅ | ESP-IDF v5.5.4 `driver/gpio.h` L141 |
| `uart_driver_install()` ESP32 UART 驱动安装 | ✅ | ESP-IDF v5.5.4 `driver/uart.h` L121 |
| `uart_write_bytes()` ESP32 UART 发送 | ✅ | ESP-IDF v5.5.4 `driver/uart.h` L533 |
| 8051 大端 → ARM 小端字节序 | ✅ | 8051 架构标准 |
| STC8H SCON/SBUF → GD32 USART_CTL0/USART_DATA | ✅ | 8051/GD32 寄存器映射 |
| GD32→STM32 库函数差异（gd32f4xx.h→stm32f4xx_hal.h） | ✅ | 厂商库标准差异 |