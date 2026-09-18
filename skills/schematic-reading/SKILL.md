---
name: schematic-reading
description: "原理图阅读：确认引脚连接/电源域/外设关系并映射 GPIO 配置。提供原理图时调用。"
version: 1.0.0
---

# 原理图辅助阅读

## 适用场景

- 用户提供原理图截图或 PDF，需要解读
- 用户问"某个引脚接了什么"、"某个外设怎么连的"
- 根据原理图编写引脚定义头文件（board.h / pins.h）
- 排查硬件连接问题（"为什么 I2C 不通"）
- 新项目拿到硬件设计后，梳理外设资源分配

## 解读流程

### 第一步：识别原理图结构

典型嵌入式项目原理图分页：
1. **MCU 最小系统**：芯片、晶振、复位、去耦电容、Boot 配置
2. **电源部分**：LDO/DCDC、电池管理、电压域划分
3. **通信接口**：UART、USB、CAN、以太网
4. **传感器/外设**：I2C/SPI 设备、ADC 输入
5. **人机交互**：LED、按键、蜂鸣器、显示屏
6. **射频/天线**（如有）：WiFi/BLE/LoRa 匹配网络

### 第二步：提取关键信息

从原理图中需要提取：

#### 引脚分配表

| 网络标号 | MCU 引脚 | 功能 | 连接目标 | 备注 |
|----------|----------|------|----------|------|
| UART0_TX | PA9 | USART0_TX | CH340 RXD | 调试串口 |
| UART0_RX | PA10 | USART0_RX | CH340 TXD | 调试串口 |
| I2C1_SCL | PB6 | I2C1_SCL | BMP280 SCL, 4.7kΩ上拉 | 传感器总线 |
| I2C1_SDA | PB7 | I2C1_SDA | BMP280 SDA, 4.7kΩ上拉 | 传感器总线 |
| SPI1_CLK | PA5 | SPI1_SCK | W25Q128 CLK | Flash |
| SPI1_CS | PA4 | GPIO | W25Q128 CS | 软件片选 |
| LED_STATUS | PC13 | GPIO | LED1 (低有效) | 状态指示 |

#### 电源域

```
VBAT (3.7V 锂电池)
  └── DCDC → 3.3V (主供电)
        ├── VDD_MCU
        ├── VDD_SENSOR (可通过 MOSFET 关断)
        └── VDD_RF
  └── LDO → 1.8V (DDR/Flash IO，如有)
```

#### 特殊电路

- 复位电路：RC 延时 / 专用复位芯片
- Boot 配置：跳线/电阻选择启动模式
- 晶振：负载电容值（CL1、CL2）
- 上拉/下拉：I2C 上拉值、UART 默认电平

### 第三步：生成引脚定义代码

根据提取的信息，生成 board.h：

```c
// board.h - 根据原理图 Rev 1.2 生成
#ifndef __BOARD_H
#define __BOARD_H

// ===== 调试串口 (UART0 → CH340) =====
#define DEBUG_UART          USART0
#define DEBUG_UART_TX_PORT  GPIOA
#define DEBUG_UART_TX_PIN   GPIO_PIN_9
#define DEBUG_UART_RX_PORT  GPIOA
#define DEBUG_UART_RX_PIN   GPIO_PIN_10
#define DEBUG_UART_BAUD     115200

// ===== I2C1 传感器总线 =====
#define SENSOR_I2C          I2C1
#define SENSOR_I2C_SCL_PORT GPIOB
#define SENSOR_I2C_SCL_PIN  GPIO_PIN_6
#define SENSOR_I2C_SDA_PORT GPIOB
#define SENSOR_I2C_SDA_PIN  GPIO_PIN_7
#define SENSOR_I2C_PULLUP   4700  // 4.7kΩ

// ===== SPI1 外部 Flash (W25Q128) =====
#define FLASH_SPI           SPI1
#define FLASH_SPI_CLK_PORT  GPIOA
#define FLASH_SPI_CLK_PIN   GPIO_PIN_5
#define FLASH_SPI_MOSI_PORT GPIOA
#define FLASH_SPI_MOSI_PIN  GPIO_PIN_7
#define FLASH_SPI_MISO_PORT GPIOA
#define FLASH_SPI_MISO_PIN  GPIO_PIN_6
#define FLASH_SPI_CS_PORT   GPIOA
#define FLASH_SPI_CS_PIN    GPIO_PIN_4  // GPIO 软件控制

// ===== LED (低电平点亮) =====
#define LED_PORT            GPIOC
#define LED_PIN             GPIO_PIN_13
#define LED_ON()            gpio_bit_reset(LED_PORT, LED_PIN)
#define LED_OFF()           gpio_bit_set(LED_PORT, LED_PIN)

// ===== 传感器电源控制 =====
#define SENSOR_PWR_PORT     GPIOB
#define SENSOR_PWR_PIN      GPIO_PIN_0
#define SENSOR_PWR_ON()     gpio_bit_set(SENSOR_PWR_PORT, SENSOR_PWR_PIN)
#define SENSOR_PWR_OFF()    gpio_bit_reset(SENSOR_PWR_PORT, SENSOR_PWR_PIN)

#endif
```

### 第四步：交叉验证

将原理图信息与以下来源交叉对比：
- 数据手册引脚复用表（确认该引脚确实支持所需功能）
- 代码中的实际配置（是否一致）
- PCB 实物（网络标号是否对应）

## 原理图符号速查

| 符号/标注 | 含义 |
|-----------|------|
| VCC/VDD | 正电源 |
| GND/VSS | 地 |
| NC | 未连接 (No Connect) |
| 网络标号（如 UART0_TX） | 跨页连接，同名标号电气相连 |
| 上拉电阻标注（4.7kΩ to 3.3V） | I2C/开漏输出上拉 |
| 电容标注（100nF） | 去耦电容，靠近引脚放置 |
| 三角形/箭头 | 信号方向 |
| 圆圈+叉 | 测试点 (Test Point) |

## 常见问题排查

### "I2C 设备不响应"

从原理图检查：
1. SDA/SCL 是否有上拉电阻？阻值多少？
2. 上拉到哪个电压域？（必须与 MCU IO 电压一致）
3. 设备地址引脚（ADDR）接高还是接低？→ 决定 7 位地址
4. 设备供电是否经过使能开关？
5. 是否有其他设备共用地址？

### "SPI Flash 读不出数据"

从原理图检查：
1. CS 引脚是 GPIO 还是硬件 NSS？
2. WP（写保护）和 HOLD 引脚是否接高？
3. VCC 和 GND 是否连接？去耦电容有无？
4. CLK/MOSI/MISO 是否接反？

### "UART 乱码"

从原理图检查：
1. TX 和 RX 是否交叉连接（MCU TX → 对端 RX）？
2. 两端电平标准是否一致（3.3V vs 5V）？
3. 是否有电平转换芯片？方向对不对？
4. GND 是否共地？

## 处理原理图截图/PDF

当用户提供图片时：
1. 使用 Read 工具查看图片
2. 识别元器件标号（U1、R1、C1 等）
3. 追踪网络标号和连线
4. 提取引脚分配关系
5. 输出结构化的引脚表

当用户提供 PDF 时：
1. 读取 PDF（提取文本/表格）
2. 逐页分析，识别各功能模块
3. 汇总为完整的硬件资源表

## Pitfalls

- 原理图版本要与 PCB 一致，注意 Rev 标注
- 网络标号相同 = 电气连接，不需要画线连过去
- "低有效"信号注意上划线或 # 后缀（如 RESET#、CS_N）
- 同一引脚可能有多个功能复用，以原理图实际连接为准
- 去耦电容（100nF）在原理图中可能省略不画，但 PCB 上必须有
- 注意区分模拟地和数字地（AGND/DGND），单点连接

## Verification

- 生成的 board.h 中每个引脚都能在原理图上找到对应连接
- 用 datasheet-lookup 技能确认引脚复用功能正确
- 与用户确认关键信号（特别是电源使能、复位）的逻辑极性

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| `gpio_bit_set(port, pin)` 函数 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L396 |
| `gpio_bit_reset(port, pin)` 函数 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L407 |
| `GPIO_PIN_9` / `GPIO_PIN_13` 等引脚宏 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_gpio.h` L114-L141 |
| `GPIOA` / `GPIOB` / `GPIOC` 端口宏 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx.h` |
| `USART0` / `I2C1` / `SPI1` 外设宏 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx.h` |
| LED 低有效模式（`gpio_bit_reset` = ON） | ✅ | 通用硬件设计：NPN/PMOS 驱动常用低有效 |
| I2C 上拉电阻 4.7kΩ 典型值 | ✅ | I2C 标准推荐（Fast Mode ≤400kHz） |
| 原理图符号含义（VCC/GND/NC/网络标号） | ✅ | 通用电子设计标准符号 |
| W25Q128 Flash SPI 连接（CS/CLK/MOSI/MISO/WP/HOLD） | ✅ | W25Q128 数据手册标准引脚定义 |
| board.h 宏命名风格（全大写+模块前缀） | ✅ | user_profile.md 宏定义命名规范 |
| 低有效信号命名约定（RESET#、CS_N 后缀） | ✅ | 通用硬件设计规范 |
| 去耦电容 100nF 典型值 | ✅ | 数字电路电源去耦标准推荐值 |
| 交叉验证流程（原理图→数据手册→代码→PCB） | ✅ | 嵌入式硬件开发通用流程 |
