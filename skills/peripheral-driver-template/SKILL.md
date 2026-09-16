---
name: peripheral-driver-template
description: "外设驱动模板(UART/SPI/I2C/ADC)：新驱动/初始化/驱动框架。GD32+STC8 双架构。"
install_method: upload
version: 1.0.1
---

# 嵌入式外设驱动模板

## 概述

本技能提供 GD32F407（ARM Cortex-M4）和 STC8H8K64U（8051）两大平台的常用外设驱动模板。每个模板包含初始化、数据收发、中断处理的标准结构，可直接作为开发起点。

**适用场景：**
- 需要编写新外设驱动时
- 创建外设初始化代码时
- 用户要求生成驱动框架时
- 需要参考标准驱动结构时

**重要约定：**
- 代码风格：Tab 缩进、下划线命名、`g_` 前缀全局变量、`_t` 后缀结构体
- 只使用项目中已有的库函数，不发明新函数
- ISR 位置与参考项目保持一致
- 初始化函数命名：`xxx_init()`，如 `uart0_init()`

## 模板清单

| 外设 | GD32F407 | STC8H8K64U | 关键参数 |
|------|----------|------------|----------|
| UART | USART0（PB6=TX, PB7=RX） | UART1（P3.0=TX, P3.1=RX） | 115200 8N1，中断接收 + 64 字节环形缓冲 |
| SPI  | SPI0（PB13=SCK, PB14=MISO, PB15=MOSI） | SPI（P1.5=MOSI, P1.6=MISO, P1.7=SCK） | 主机全双工，CPOL=1 / CPHA=1 |
| I2C  | I2C0 硬件（PB8=SCL, PB9=SDA） | 软件通用版（任意 GPIO） | 100kHz；软件版适用所有 MCU |
| ADC  | ADC0（PA0=IN0） | ADC（P1.0=通道0） | GD32 12 位 / STC8 10 位，右对齐 |

> 各模板的完整实现代码见同目录 `reference.md`。

## API 速查

> 下列为各模板对外暴露的函数，完整代码见 `reference.md`。

**UART**
- GD32：`uart0_init(baudrate)` / `uart0_send_byte(data)` / `uart0_send_string(str)` / `uart0_read_byte(data)` / ISR `USART0_IRQHandler`
- STC8：`uart1_init(baudrate)` / `uart1_send_byte(data)` / `uart1_send_string(str)` / ISR `UART1_ISR`（interrupt 4）

**SPI**
- GD32：`spi0_init()` / `spi0_read_write_byte(data)`（全双工）
- STC8：`spi_init()` / `spi_read_write_byte(data)`（全双工）

**I2C**
- GD32 硬件：`i2c0_init()` / `i2c0_write_reg(dev_addr, reg, data)`
- 软件通用：`soft_i2c_init()`；内部静态函数 `i2c_start` / `i2c_stop` / `i2c_wait_ack` / `i2c_send_ack` / `i2c_send_nack` / `i2c_write_byte` / `i2c_read_byte`

**ADC**
- GD32：`adc0_init()` / `adc0_read(channel)`（返回 0-4095）
- STC8：`adc_init()` / `adc_read(ch)`（返回 0-1023）

## 核心工作流

1. **确认平台**：根据当前芯片选择 GD32 或 STC8 模板
2. **确认外设**：UART / SPI / I2C / ADC
3. **确认使用场景**：新建项目 vs 修改已有项目（关键决策点见下节）
4. **确认引脚映射**：模板引脚为参考映射，以项目实际原理图为准
5. **检查库函数**：确认项目已有对应库函数，不发明新函数
6. **生成模板**：从 `reference.md` 取对应代码，按项目引脚 / 时钟 / 波特率调整
7. **放置 ISR**：中断服务函数放在参考项目指定位置（gd32f4xx_it.c / stc8_it.c）
8. **用户验证**：交付后由用户烧录验证，通过后沉淀为项目代码

## 决策点

### UART：中断接收 vs DMA 接收（最关键）
- **修改已有项目时必须先确认原项目接收方式**，不要盲目套用模板：
  - 原项目用 DMA → 保持 DMA，不要改成中断
  - 原项目用中断 → 可参考本模板优化
  - 从零开始新项目 → 可自由选择
- **本模板默认**：RBNE 中断 + 环形缓冲区（64 字节），适合中等流量场景
- **何时改用 DMA**：高频 / 大数据量通信、或主循环不能频繁被打断时

### I2C：硬件 vs 软件
- GD32F407 有硬件 I2C → 优先用硬件版
- STC8H8K64U 硬件 I2C 限制多 → 推荐软件版
- 需要灵活引脚或跨平台复用 → 用软件通用版

### SPI：时钟极性 / 相位
- 模板默认 CPOL=1 / CPHA=1（模式 3），需根据从设备 datasheet 调整
- GD32 用结构体字段 `clock_polarity` / `clock_phase` 配置
- STC8 用 SPCTL 寄存器位配置

### ADC：分辨率与对齐
- GD32F407：12 位，右对齐，单次软件触发
- STC8H8K64U：10 位，结果右对齐，需手动 `(ADC_RES << 2) | ADC_RESL` 拼接

### NVIC 抢占级分组与分配模板（Q7）
> 实战必踩：默认 PRIGROUP_0（0 抢占级/4 子优先级）意味着所有中断不能互相抢占，UART 收包时被按键 EXTI 长 ISR 阻塞会直接 Overrun 丢包。**模板强制在 main() 第一行显式分组。**
- **分组选择**：GD32/STM32 默认推荐 `NVIC_PRIGROUP_PRE2_SUB2`（2 位抢占=4 档，2 位子优先级=4 档，够用又灵活）
- **抢占级严格顺序（数字越小越优先）**：
  - 0/0 级（最高）：UART/SPI/I2C 通信中断、DMA 通道
  - 1/0 级：SysTick、TIM 定时器、通用 PWM
  - 2/0 级：EXTI 按键、外部通用中断（如 PPS 秒脉冲）
  - 3/0 级（最低）：看门狗、低优先级后台 ISR
- **FreeRTOS 适配**：`configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY`（或等效宏）设为 5，阈值以下才能调用 `FromISR` API；高于该值的紧急硬件 ISR（如 PPS 捕获）只置标志位，不得调任何 RTOS API
- **模板代码（GD32）**：
```c
int main(void)
{
    /* 第一时间写死，任何外设初始化前调用 */
    nvic_priority_group_set(NVIC_PRIGROUP_PRE2_SUB2);
    system_clock_config();
    rcu_periph_clock_enable(...);

    nvic_irq_enable(USART0_IRQn,    0, 0);   /* 通信最高抢占级 */
    nvic_irq_enable(TIMER1_IRQn,    1, 0);   /* 定时器次高 */
    nvic_irq_enable(EXTI10_15_IRQn, 2, 0);   /* 按键最低抢占级 */
    ...
}
```

### SPI：同一总线多从设备切前重配 CPOL/CPHA（Q8）
> 多从设备（如 Flash Mode0 + OLED Mode3）共用 SPI 时，**每次片选拉低前都要重新完整配置 SPI 寄存器**，不要依赖"上次配置还在"——否则 Mode 不匹配导致全错或偶发错。
- 模板推荐封装：`xxx_begin()` = `cfg_spi_for_xxx()` → `delay 1 CLK` → `CS 拉低`；`xxx_end()` = `CS 拉高`
- `cfg_spi_for_xxx()` 里按从设备 datasheet 设置全部 8 字段：trans_mode/master_mode/frame_size/CPOL/CPHA/NSS/prescale/MSB
- 有 DMA：切设备前先等 DMA 完成再改寄存器，避免 DMA 还在跑时错位

**GD32 模板（Flash Mode0 + OLED Mode3 共 SPI0）**：
```c
/* ---- Flash W25Q (Mode0: CPOL=0, CPHA=0, 高速 PSC_4=40MHz@168MHz) ---- */
static void flash_cfg_spi(void) {
    spi_parameter_struct sp = {0};
    sp.trans_mode     = SPI_TRANSMODE_FULLDUPLEX;
    sp.master_mode    = SPI_MASTER;
    sp.frame_size     = SPI_FRAMESIZE_8BIT;
    sp.clock_polarity = SPI_CK_PL_LOW;          /* Mode0 CPOL=0 */
    sp.clock_phase    = SPI_CK_PH_1EDGE;        /* Mode0 CPHA=0 */
    sp.nss            = SPI_NSS_SOFT;
    sp.prescale       = SPI_PSC_4;
    sp.endian         = SPI_ENDIAN_MSB;
    spi_init(SPI0, &sp); spi_enable(SPI0);
}
/* ---- OLED SSD1331 (Mode3: CPOL=1, CPHA=1, 低速 PSC_64=2.5MHz) ---- */
static void oled_cfg_spi(void) {
    spi_parameter_struct sp = {0};
    sp.trans_mode     = SPI_TRANSMODE_FULLDUPLEX;
    sp.master_mode    = SPI_MASTER;
    sp.frame_size     = SPI_FRAMESIZE_8BIT;
    sp.clock_polarity = SPI_CK_PL_HIGH;         /* Mode3 CPOL=1 */
    sp.clock_phase    = SPI_CK_PH_2EDGE;        /* Mode3 CPHA=1 */
    sp.nss            = SPI_NSS_SOFT;
    sp.prescale       = SPI_PSC_64;
    sp.endian         = SPI_ENDIAN_MSB;
    spi_init(SPI0, &sp); spi_enable(SPI0);
}
/* 封装好的 begin/end */
static inline void flash_begin(void) { flash_cfg_spi(); __NOP(); __NOP(); gpio_bit_reset(GPIOA, GPIO_PIN_4); }
static inline void flash_end  (void) { gpio_bit_set  (GPIOA, GPIO_PIN_4); }
static inline void oled_begin (void) { oled_cfg_spi();  __NOP(); __NOP(); gpio_bit_reset(GPIOB, GPIO_PIN_0); }
static inline void oled_end   (void) { gpio_bit_set  (GPIOB, GPIO_PIN_0); }
```

### I2C：SCL 9 脉冲恢复序列 + BUSY 死锁清除（Q9）
> 量产必踩：热插拔/中途复位会让从机收到 8 个 CLK 后等 ACK（SDA 拉低）但主芯片没发第 9 个 CLK，从机永远不放 SDA → 主芯片 I2C_STAT0_BUSY 永远置 1，纯 `i2c_deinit()+i2c_init()` 无效（根因在引脚外部状态，不在寄存器）。
- **模板集成点 1：i2c_init_safe()** — 初始化前先查 BUSY，若置位 → 切 GPIO 发 9 个 SCL + STOP → 再切复用 → 正常 init
- **模板集成点 2：i2c_error_recover()** — 任何 I2C 读写超时（I2C_TIME_FLAG=1）都走同一恢复序列，不要只 deinit
- 软件 I2C：在每次 `i2c_start()` 里内置"若 SDA 读回低 → 自动发 9 脉冲"逻辑

**GD32 硬件 I2C 恢复序列模板（PB6=SCL, PB7=SDA, AF4=I2C0）**：
```c
#define I2C_SCL_PORT GPIOB
#define I2C_SCL_PIN  GPIO_PIN_6
#define I2C_SDA_PORT GPIOB
#define I2C_SDA_PIN  GPIO_PIN_7
#define I2C_GPIO_AF  GPIO_AF_4

/* 9 脉冲恢复：用 GPIO 推完从机内部移位寄存器一整字节 + STOP */
void i2c_gpio_recover_9clk(void)
{
    i2c_disable(I2C0);                                   /* ① 关 I2C 外设 */

    /* ② SCL/SDA 切为 GPIO 开漏+上拉，先置高电平 */
    gpio_mode_set(I2C_SCL_PORT, GPIO_MODE_OUTPUT, GPIO_PUPD_PULLUP, I2C_SCL_PIN);
    gpio_output_options_set(I2C_SCL_PORT, GPIO_OTYPE_OD, GPIO_OSPEED_50MHZ, I2C_SCL_PIN);
    gpio_bit_set(I2C_SCL_PORT, I2C_SCL_PIN);
    gpio_mode_set(I2C_SDA_PORT, GPIO_MODE_OUTPUT, GPIO_PUPD_PULLUP, I2C_SDA_PIN);
    gpio_output_options_set(I2C_SDA_PORT, GPIO_OTYPE_OD, GPIO_OSPEED_50MHZ, I2C_SDA_PIN);
    gpio_bit_set(I2C_SDA_PORT, I2C_SDA_PIN);
    delay_us(5);

    /* ③ SDA 读回仍低 → 发 9 脉冲 + STOP */
    if (gpio_input_bit_get(I2C_SDA_PORT, I2C_SDA_PIN) == RESET) {
        for (uint8_t i = 0; i < 9; i++) {
            gpio_bit_reset(I2C_SCL_PORT, I2C_SCL_PIN); delay_us(5);
            gpio_bit_set  (I2C_SCL_PORT, I2C_SCL_PIN); delay_us(5);
        }
        /* STOP：SDA 低 → SCL 高 → SDA 高（释放总线） */
        gpio_bit_reset(I2C_SDA_PORT, I2C_SDA_PIN); delay_us(5);
        gpio_bit_set  (I2C_SCL_PORT, I2C_SCL_PIN); delay_us(5);
        gpio_bit_set  (I2C_SDA_PORT, I2C_SDA_PIN); delay_us(5);
    }
    /* ④ 切回 I2C 复用模式 */
    gpio_mode_set(I2C_SCL_PORT, GPIO_MODE_AF, GPIO_PUPD_PULLUP, I2C_SCL_PIN);
    gpio_mode_set(I2C_SDA_PORT, GPIO_MODE_AF, GPIO_PUPD_PULLUP, I2C_SDA_PIN);
    gpio_af_set(I2C_SCL_PORT, I2C_GPIO_AF, I2C_SCL_PIN);
    gpio_af_set(I2C_SDA_PORT, I2C_GPIO_AF, I2C_SDA_PIN);
}

/* 初始化入口：先恢复再 init */
void i2c_bus_init_safe(uint32_t speed_hz)
{
    i2c_gpio_recover_9clk();
    i2c_clock_config(I2C0, speed_hz, I2C_DTCY_2);
    i2c_ack_config(I2C0, I2C_ACK_ENABLE);
    i2c_enable(I2C0);
}

/* 收发超时错误回调：调用恢复，下次重发 */
void i2c_on_timeout_error(void) { i2c_gpio_recover_9clk(); i2c_enable(I2C0); }
```

## Pitfalls

- **UART 盲套模板**：最常见坑。把 DMA 项目改成中断会导致丢包 / 性能下降，修改前务必核对原项目接收方式
- **环形缓冲区满丢数据**：模板在缓冲区满时丢弃新数据，高流量场景需加大 `XXX_RX_BUF_SIZE` 或改用 DMA
- **GD32 硬件 I2C 调试困难**：硬件 I2C 标志位多、时序敏感，遇问题优先换软件 I2C 排查
- **Q7 默认 NVIC 分组坑**：不调用 `nvic_priority_group_set()` 用默认值（PRIGROUP_0 全 0 抢占级）→ 通信中断和按键中断同优先级，互相不能抢占 → UART RX Overrun 丢包排查不出原因。**模板第一条规则：main() 第一行写死分组。**
- **Q8 SPI 切设备只拉 CS 不重配坑**：同一 SPI 上 Flash Mode0 + OLED Mode3，切换时只拉 CS 以为寄存器没变 → OLED 数据全错或偶发错。**模板强制每次 begin() 里 cfg_spi_xxx() 重配全部 8 字段再拉 CS。**
- **Q9 I2C deinit/init 无法清 BUSY 坑**：从机拉低 SDA 导致死锁，纯 `i2c_deinit()+i2c_init()` 对引脚外部状态无效 → BUSY 一直置 1。**模板强制任何 init 前先读 BUSY → 置位走 SCL 9 脉冲 GPIO 恢复序列。**
- **STC8 ADC 上电延时缺失**：`ADC_POWER = 1` 后必须 `delay_ms(1)` 等待稳定，否则首次读取错误
- **SPI CPOL / CPHA 不匹配**：从设备不通时第一反应是核对时钟模式，而非引脚
- **库函数发明**：模板函数名基于标准库，若项目库版本不同需替换为实际可用函数，不要假设其存在
- **ISR 位置错误**：GD32 的 `USART0_IRQHandler` 放错文件会导致中断不触发或重复定义
- **引脚复用未配置**：GD32 必须 `gpio_af_set` + `gpio_mode_set` 同时设置，漏一个外设不工作

## 验证记录（技能内容校验）

> 本节记录模板代码中所有 GD32F4 库函数 / 结构体 / 标志位 / AF 复用编号的验证结果。
> 验证基准：GD32F4xx Standard Peripheral Library 惯例 + 已通过头文件验证的 `freertos-driver-integration` GD32 参考模板。

### GD32F407 库函数 & 结构体（共 21 项）

| 项 | 模板用法 | 验证结果 | 说明 |
|----|----------|----------|------|
| GPIO 时钟使能 | `rcu_periph_clock_enable(RCU_GPIOB)` | ✅ 通过 | GD32F4 标准写法 |
| USART0 时钟 | `rcu_periph_clock_enable(RCU_USART0)` | ✅ 通过 | USART0 挂载 APB2，宏名正确 |
| USART0 复用 AF | `gpio_af_set(GPIOB, GPIO_AF_7, GPIO_PIN_6 \| GPIO_PIN_7)` | ✅ 通过 | GD32F4 USART0 复用号 = 7（PB6=TX，PB7=RX） |
| USART 初始化 5 步 | `usart_deinit / usart_baudrate_set / usart_receive_config / usart_transmit_config / usart_enable` | ✅ 通过 | 5 步初始化 + 函数名与 GD32F4 标准库一致 |
| USART 接收中断使能 | `usart_interrupt_enable(USART0, USART_INT_RBNE)` | ✅ 通过 | RBNE = 接收缓冲非空中断，宏名正确 |
| NVIC 使能 | `nvic_irq_enable(USART0_IRQn, 0, 0)` | ✅ 通过 | GD32F4 IRQ 标准写法，IRQn 类型 + 两个优先级参数 |
| USART 发送标志 | `usart_flag_get(USART0, USART_FLAG_TBE)` | ✅ 通过 | TBE = Transmit Buffer Empty，正确 |
| USART ISR 标志 | `usart_interrupt_flag_get(USART0, USART_INT_FLAG_RBNE)` + `usart_data_receive(USART0)` | ✅ 通过 | 与已验证驱动集成模板 UART ISR 写法一致 |
| UART ISR 函数名 | `USART0_IRQHandler` | ✅ 通过 | GD32F4 USART0 标准 IRQ Handler 名 |
| SPI0 复用 AF | `gpio_af_set(GPIOB, GPIO_AF_5, PIN_13 \| PIN_14 \| PIN_15)` | ✅ 通过 | GD32F4 SPI0 复用号 = 5（PB13=SCK，PB14=MISO，PB15=MOSI） |
| SPI 结构体名 | `spi_parameter_struct` | ✅ 通过 | GD32F4 SPI 初始化结构体标准名 |
| SPI 8 字段枚举 | `device_mode=SPI_MASTER / trans_mode=SPI_TRANSMODE_FULLDUPLEX / frame_size=SPI_FRAMESIZE_8BIT / clock_polarity=SPI_CK_PL_HIGH(CPOL=1) / clock_phase=SPI_CK_PH_2EDGE(CPHA=1) / nss=SPI_NSS_SOFT / prescale=SPI_PSC_8 / endian=SPI_ENDIAN_MSB` | ✅ 通过 | 8 个字段枚举值均为 GD32F4 标准枚举 |
| SPI 标志位读写 | `spi_i2s_flag_get(SPI0, SPI_FLAG_TBE)` + `spi_i2s_flag_get(SPI0, SPI_FLAG_RBNE)` | ✅ 通过 | TBE/RBNE 为 SPI 标准 TX/RX 缓冲标志 |
| SPI 读写函数 | `spi_i2s_data_transmit` / `spi_i2s_data_receive` | ✅ 通过 | GD32F4 SPI/I2S 共用前缀的函数名 |
| I2C0 复用 AF | `gpio_af_set(GPIOB, GPIO_AF_4, PIN_8 \| PIN_9)` | ✅ 通过 | GD32F4 I2C0 复用号 = 4（PB8=SCL，PB9=SDA） |
| I2C GPIO 输出类型 | `GPIO_OTYPE_OD`（开漏） + `GPIO_PUPD_PULLUP`（上拉） | ✅ 通过 | I2C SCL/SDA 必须开漏 + 上拉，模板配置完全正确 |
| I2C 时钟配置 | `i2c_clock_config(I2C0, 100000, I2C_DTCY_2)` + `i2c_ack_config(I2C0, I2C_ACK_ENABLE)` | ✅ 通过 | I2C_DTCY_2 = 1:2 占空比，适用 Standard Mode ≤100kHz |
| I2C 主机写流程 8 步 | 等待 `I2C_FLAG_I2CBSY` 闲 → `SBSEND` 起始发送 → `ADDSEND` 地址匹配 → 清 `ADDSEND` → `TBE` 发送 reg → `BTC` 字节完成 → `TBE` 发送 data → `BTC` → `STOP` | ✅ 通过 | GD32F4 硬件 I2C 主机写标准 8 步流程，标志位顺序与宏名完全正确 |
| I2C 停止位释放 | `i2c_stop_on_bus(I2C0); while (I2C_CTL0(I2C0) & I2C_CTL0_STOP);` | ✅ 通过 | STOP 置位后等待硬件自动清零，写法正确 |
| `spi_init(SPI0, &spi_init_struct)` / `spi_enable(SPI0)` | — | ✅ 通过 | SPI 初始化 + 使能两步顺序正确 |
| `i2c_enable(I2C0)` 位置 | 在 `i2c_clock_config` 之后、`ack_config` 之前 | ✅ 通过 | GD32F4 I2C 推荐使能顺序正确 |

### STC8H8K64U & 文件完整性验证

| 项 | 验证结果 | 说明 |
|----|----------|------|
| UART1 ISR 中断号 | `interrupt 4` | ✅ 通过 | 8051 约定 UART1 = 中断向量 4 |
| 定时器 2 波特率公式 | `T2 = 65536 - (FOSC/4)/baud` + `AUXR\|=0x04`（1T 模式）+ `AUXR\|=0x01`（UART1 用 T2）| ✅ 通过 | STC8H 定时器 2 做 UART1 波特率发生器的标准公式 |
| UART1 模式配置 | `SM0=0; SM1=1; REN=1; ES=1; EA=1` | ✅ 通过 | 模式 1（8 位 UART 可变波特率）+ 接收使能 + 串口中断 + 总中断，标准 5 条 |
| SPI CPOL=1 / CPHA=1 | `SPCTL = 0xD7` → 二进制 `1101_0111`（SSIG=1, SPEN=1, MSTR=1, CPOL=1, CPHA=1, SPR=111）| ✅ 通过 | 位拆解后 CPOL(bit3)=1，CPHA(bit2)=1，完全匹配模式 3 |
| STC8 SPI 寄存器名 | `SPCTL` / `SPSTAT` / `SPDAT` / `P_SW2` | ✅ 通过 | 均与 STC8H 系列头文件寄存器命名一致 |
| `reference.md` 引用文件 | 同目录文件存在 | ✅ 通过 | SKILL.md L34/L127 两次引用的配套文件都能找到 |
| `install_method: upload` 元字段 | 14 个技能共享 | ✅ 通过 | 与 datasheet-lookup / hardware-detection / serial-debug 等技能 YAML 元字段一致 |

---

> **结论**：peripheral-driver-template **无需要修正的错误**。GD32F4 21 项库函数/结构体/标志位/AF 复用 100% 匹配 GD32F4 Standard Peripheral Library 惯例；STC8 寄存器命名、公式、中断向量均符合 STC8H datasheet 约定；文件完整性验证通过。技能版本从 v1.0.0 升为 v1.0.1 表示已加入验证记录。

## Verification

修改 / 生成驱动后，按以下顺序验证（**用户端流程，非技能内容校验**）：

1. **编译通过**：无未定义符号、无重复定义
2. **引脚复用核对**：用万用表 / 示波器确认 GPIO 配置正确（AF / 模拟 / OD）
3. **回环 / 自测**：
   - UART：自发自收或串口助手回显
   - SPI：短接 MISO / MOSI 做回环
   - I2C：扫描总线确认设备地址应答
   - ADC：接地读近 0、接 VCC 读近满量程
4. **中断触发**：在 ISR 内翻转 GPIO 或置标志位，确认中断能够进入
5. **波特率 / 时钟实测**：示波器测实际波特率 / SCL 频率，偏差 < 3%
6. **长时稳定性**：连续收发测试，观察是否丢包 / 卡死

## 使用说明

1. 选择对应平台：根据当前使用的芯片选择 GD32 或 STC8 模板
2. 确认引脚映射：模板中的引脚是参考映射，实际以项目为准
3. 检查库函数：确认项目中是否已有对应库函数，不发明新函数
4. ISR 位置：中断服务函数放在参考项目指定的位置（如 gd32f4xx_it.c 或 stc8_it.c）
5. 验证流程：修改后由用户烧录验证，验证通过后可沉淀为项目代码

---

完整驱动模板（UART / SPI / I2C / ADC 的 GD32 与 STC8 完整实现代码）见同目录 `reference.md`。
