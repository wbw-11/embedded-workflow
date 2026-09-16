# 外设驱动模板 —— 完整实现参考

> 本文件为 `SKILL.md` 的配套详细参考，包含 UART/SPI/I2C/ADC 的完整驱动代码。
> 核心工作流、决策点、Pitfalls、Verification 见 `SKILL.md`。

---
## 一、UART 驱动模板

> ⚠️ **重要提醒**：本模板使用**中断接收**模式（RBNE 中断 + 环形缓冲区）。如果修改已有项目，**必须先确认原始项目用的是 DMA 接收还是中断接收**，不要盲目套用模板，否则会破坏原有通信机制。
> 
> - 原始项目用 DMA → 保持 DMA，不要改成中断
> - 原始项目用中断 → 可以参考本模板优化
> - 从零开始新项目 → 可以自由选择

### GD32F407 版本

```c
#include "gd32f4xx.h"
#include <stdio.h>

#define UART0_RX_BUF_SIZE  64

typedef struct {
	uint8_t  buf[UART0_RX_BUF_SIZE];
	uint8_t  write;
	uint8_t  read;
	uint8_t  count;
} uart_rx_buf_t;

volatile uart_rx_buf_t g_uart0_rx;
volatile uint8_t g_uart0_rx_flag;

/*!
 * \brief UART0 初始化（PB6=TX, PB7=RX, 115200 8N1）
 */
void uart0_init(uint32_t baudrate)
{
	/* 使能时钟 */
	rcu_periph_clock_enable(RCU_GPIOB);
	rcu_periph_clock_enable(RCU_USART0);

	/* GPIO 配置：TX=AF, RX=AF */
	gpio_af_set(GPIOB, GPIO_AF_7, GPIO_PIN_6);
	gpio_af_set(GPIOB, GPIO_AF_7, GPIO_PIN_7);
	gpio_mode_set(GPIOB, GPIO_MODE_AF, GPIO_PUPD_PULLUP, GPIO_PIN_6);
	gpio_mode_set(GPIOB, GPIO_MODE_AF, GPIO_PUPD_PULLUP, GPIO_PIN_7);
	gpio_output_options_set(GPIOB, GPIO_OTYPE_PP, GPIO_OSPEED_50MHZ, GPIO_PIN_6);

	/* USART 配置 */
	usart_deinit(USART0);
	usart_baudrate_set(USART0, baudrate);
	usart_receive_config(USART0, USART_RECEIVE_ENABLE);
	usart_transmit_config(USART0, USART_TRANSMIT_ENABLE);
	usart_enable(USART0);

	/* 使能接收中断 */
	usart_interrupt_enable(USART0, USART_INT_RBNE);
	nvic_irq_enable(USART0_IRQn, 0, 0);

	/* 初始化接收缓冲区 */
	g_uart0_rx.write = 0;
	g_uart0_rx.read = 0;
	g_uart0_rx.count = 0;
	g_uart0_rx_flag = 0;
}

/*!
 * \brief UART0 发送一个字节
 */
void uart0_send_byte(uint8_t data)
{
	usart_data_transmit(USART0, data);
	while (RESET == usart_flag_get(USART0, USART_FLAG_TBE));
}

/*!
 * \brief UART0 发送字符串
 */
void uart0_send_string(const char *str)
{
	while (*str) {
		uart0_send_byte(*str++);
	}
}

/*!
 * \brief UART0 读取一个字节（非阻塞）
 * \return 0: 成功, -1: 缓冲区空
 */
int uart0_read_byte(uint8_t *data)
{
	if (g_uart0_rx.count == 0) {
		return -1;
	}
	*data = g_uart0_rx.buf[g_uart0_rx.read];
	g_uart0_rx.read = (g_uart0_rx.read + 1) % UART0_RX_BUF_SIZE;
	g_uart0_rx.count--;
	return 0;
}

/*!
 * \brief UART0 中断服务函数
 * \note 放在 gd32f4xx_it.c 中，或按参考项目位置放置
 */
void USART0_IRQHandler(void)
{
	if (usart_interrupt_flag_get(USART0, USART_INT_FLAG_RBNE)) {
		if (g_uart0_rx.count < UART0_RX_BUF_SIZE) {
			g_uart0_rx.buf[g_uart0_rx.write] = usart_data_receive(USART0);
			g_uart0_rx.write = (g_uart0_rx.write + 1) % UART0_RX_BUF_SIZE;
			g_uart0_rx.count++;
			g_uart0_rx_flag = 1;
		}
		/* 缓冲区满则丢弃新数据 */
	}
}
```

### STC8H8K64U 版本

```c
#include "stc8h.h"

#define UART1_RX_BUF_SIZE  64

typedef struct {
	uint8_t buf[UART1_RX_BUF_SIZE];
	uint8_t write;
	uint8_t read;
	uint8_t count;
} uart_rx_buf_t;

volatile uart_rx_buf_t g_uart1_rx;
volatile uint8_t g_uart1_rx_flag;

/*!
 * \brief UART1 初始化（P3.0=TX, P3.1=RX, 115200 8N1）
 * \note 使用定时器2做波特率发生器
 */
void uart1_init(uint32_t baudrate)
{
	/* 定时器2 做波特率发生器 */
	T2L = (65536UL - (FOSC / 4) / baudrate) & 0xFF;
	T2H = (65536UL - (FOSC / 4) / baudrate) >> 8;
	AUXR |= 0x04;   /* 定时器2 1T 模式 */
	AUXR |= 0x01;   /* 串口1用定时器2 */

	/* 串口1 模式1（8位UART） */
	SM0 = 0;
	SM1 = 1;

	/* 使能接收 */
	REN = 1;

	/* 使能中断 */
	ES = 1;
	EA = 1;

	/* 启动定时器2 */
	AUXR |= 0x10;

	/* 初始化缓冲区 */
	g_uart1_rx.write = 0;
	g_uart1_rx.read = 0;
	g_uart1_rx.count = 0;
	g_uart1_rx_flag = 0;
}

/*!
 * \brief UART1 发送一个字节
 */
void uart1_send_byte(uint8_t data)
{
	SBUF = data;
	while (!TI);
	TI = 0;
}

/*!
 * \brief UART1 发送字符串
 */
void uart1_send_string(const char *str)
{
	while (*str) {
		uart1_send_byte(*str++);
	}
}

/*!
 * \brief UART1 中断服务函数
 * \note 放在 stc8_it.c 中
 */
void UART1_ISR(void) interrupt 4
{
	if (RI) {
		RI = 0;
		if (g_uart1_rx.count < UART1_RX_BUF_SIZE) {
			g_uart1_rx.buf[g_uart1_rx.write] = SBUF;
			g_uart1_rx.write = (g_uart1_rx.write + 1) % UART1_RX_BUF_SIZE;
			g_uart1_rx.count++;
			g_uart1_rx_flag = 1;
		}
	}
	if (TI) {
		TI = 0;
	}
}
```

---

## 二、SPI 驱动模板

### GD32F407 版本

```c
#include "gd32f4xx.h"

/*!
 * \brief SPI0 初始化（PB13=SCK, PB14=MISO, PB15=MOSI）
 * \note 主机模式，8位数据，CPOL=1/CPHA=1
 */
void spi0_init(void)
{
	rcu_periph_clock_enable(RCU_GPIOB);
	rcu_periph_clock_enable(RCU_SPI0);

	/* GPIO: SCK/MISO/MOSI = AF */
	gpio_af_set(GPIOB, GPIO_AF_5, GPIO_PIN_13 | GPIO_PIN_14 | GPIO_PIN_15);
	gpio_mode_set(GPIOB, GPIO_MODE_AF, GPIO_PUPD_NONE, GPIO_PIN_13 | GPIO_PIN_14 | GPIO_PIN_15);
	gpio_output_options_set(GPIOB, GPIO_OTYPE_PP, GPIO_OSPEED_50MHZ, GPIO_PIN_13 | GPIO_PIN_15);

	spi_parameter_struct spi_init_struct;
	spi_init_struct.device_mode          = SPI_MASTER;
	spi_init_struct.trans_mode           = SPI_TRANSMODE_FULLDUPLEX;
	spi_init_struct.frame_size           = SPI_FRAMESIZE_8BIT;
	spi_init_struct.clock_polarity       = SPI_CK_PL_HIGH;      /* CPOL=1 */
	spi_init_struct.clock_phase          = SPI_CK_PH_2EDGE;     /* CPHA=1 */
	spi_init_struct.nss                  = SPI_NSS_SOFT;
	spi_init_struct.prescale             = SPI_PSC_8;
	spi_init_struct.endian               = SPI_ENDIAN_MSB;

	spi_init(SPI0, &spi_init_struct);
	spi_enable(SPI0);
}

/*!
 * \brief SPI0 读写一个字节（全双工）
 */
uint8_t spi0_read_write_byte(uint8_t data)
{
	while (RESET == spi_i2s_flag_get(SPI0, SPI_FLAG_TBE));
	spi_i2s_data_transmit(SPI0, data);
	while (RESET == spi_i2s_flag_get(SPI0, SPI_FLAG_RBNE));
	return spi_i2s_data_receive(SPI0);
}
```

### STC8H8K64U 版本

```c
#include "stc8h.h"

/*!
 * \brief SPI 初始化（P1.7=SCK, P1.6=MISO, P1.5=MOSI）
 * \note 主机模式，CPOL=1/CPHA=1
 */
void spi_init(void)
{
	/* 引脚配置 */
	P1M0 = 0; P1M1 = 0;
	P_SW2 = 0x04;  /* SPI 引脚选择 */

	SPCTL = 0xD7;  /* SSIG=1, SPEN=1, DORD=0, MSTR=1, CPOL=1, CPHA=1, SPR=111 */
	SPSTAT = 0xC0; /* 清除状态标志 */
}

/*!
 * \brief SPI 读写一个字节（全双工）
 */
uint8_t spi_read_write_byte(uint8_t data)
{
	SPSTAT = 0xC0;  /* 清标志 */
	SPDAT = data;
	while (!(SPSTAT & 0x80));  /* 等待完成 */
	return SPDAT;
}
```

---

## 三、I2C 驱动模板

### GD32F407 版本（硬件 I2C）

```c
#include "gd32f4xx.h"

/*!
 * \brief I2C0 初始化（PB8=SCL, PB9=SDA）
 * \note 主机模式，100kHz
 */
void i2c0_init(void)
{
	rcu_periph_clock_enable(RCU_GPIOB);
	rcu_periph_clock_enable(RCU_I2C0);

	gpio_af_set(GPIOB, GPIO_AF_4, GPIO_PIN_8 | GPIO_PIN_9);
	gpio_mode_set(GPIOB, GPIO_MODE_AF, GPIO_PUPD_PULLUP, GPIO_PIN_8 | GPIO_PIN_9);
	gpio_output_options_set(GPIOB, GPIO_OTYPE_OD, GPIO_OSPEED_50MHZ, GPIO_PIN_8 | GPIO_PIN_9);

	i2c_clock_config(I2C0, 100000, I2C_DTCY_2);
	i2c_enable(I2C0);
	i2c_ack_config(I2C0, I2C_ACK_ENABLE);
}

/*!
 * \brief I2C0 写一个字节到指定寄存器
 */
int i2c0_write_reg(uint8_t dev_addr, uint8_t reg, uint8_t data)
{
	i2c_ack_config(I2C0, I2C_ACK_ENABLE);

	/* 等待 I2C 总线空闲 */
	while (i2c_flag_get(I2C0, I2C_FLAG_I2CBSY));

	/* 发送起始条件 */
	i2c_start_on_bus(I2C0);
	while (!i2c_flag_get(I2C0, I2C_FLAG_SBSEND));

	/* 发送设备地址 + 写 */
	i2c_master_addressing(I2C0, dev_addr, I2C_TRANSMITTER);
	while (!i2c_flag_get(I2C0, I2C_FLAG_ADDSEND));
	i2c_flag_clear(I2C0, I2C_FLAG_ADDSEND);

	/* 发送寄存器地址 */
	while (!i2c_flag_get(I2C0, I2C_FLAG_TBE));
	i2c_data_transmit(I2C0, reg);
	while (!i2c_flag_get(I2C0, I2C_FLAG_BTC));

	/* 发送数据 */
	i2c_data_transmit(I2C0, data);
	while (!i2c_flag_get(I2C0, I2C_FLAG_BTC));

	/* 发送停止条件 */
	i2c_stop_on_bus(I2C0);
	while (I2C_CTL0(I2C0) & I2C_CTL0_STOP);

	return 0;
}
```

### 软件 I2C 通用版（适用所有 MCU）

```c
/* 软件 I2C —— 适用于没有硬件 I2C 或需要灵活引脚的场景 */

#define I2C_SCL_PIN  GPIO_PIN_8
#define I2C_SDA_PIN  GPIO_PIN_9
#define I2C_PORT     GPIOB
#define I2C_SCL_HIGH() gpio_bit_set(I2C_PORT, I2C_SCL_PIN)
#define I2C_SCL_LOW()  gpio_bit_reset(I2C_PORT, I2C_SCL_PIN)
#define I2C_SDA_HIGH() gpio_bit_set(I2C_PORT, I2C_SDA_PIN)
#define I2C_SDA_LOW()  gpio_bit_reset(I2C_PORT, I2C_SDA_PIN)
#define I2C_SDA_READ() gpio_input_bit_get(I2C_PORT, I2C_SDA_PIN)

/*!
 * \brief 软件 I2C 初始化
 */
void soft_i2c_init(void)
{
	rcu_periph_clock_enable(RCU_GPIOB);
	gpio_mode_set(I2C_PORT, GPIO_MODE_OUTPUT, GPIO_PUPD_PULLUP, I2C_SCL_PIN | I2C_SDA_PIN);
	gpio_output_options_set(I2C_PORT, GPIO_OTYPE_OD, GPIO_OSPEED_50MHZ, I2C_SCL_PIN | I2C_SDA_PIN);
	I2C_SCL_HIGH();
	I2C_SDA_HIGH();
}

/*!
 * \brief SDA 方向切换（输出/输入）
 */
static void i2c_sda_output(void)
{
	gpio_mode_set(I2C_PORT, GPIO_MODE_OUTPUT, GPIO_PUPD_PULLUP, I2C_SDA_PIN);
}
static void i2c_sda_input(void)
{
	gpio_mode_set(I2C_PORT, GPIO_MODE_INPUT, GPIO_PUPD_PULLUP, I2C_SDA_PIN);
}

static void i2c_delay(void)
{
	/* 根据实际时钟调整，约 5us */
	volatile uint32_t i;
	for (i = 0; i < 500; i++);
}

static void i2c_start(void)
{
	i2c_sda_output();
	I2C_SDA_HIGH();
	I2C_SCL_HIGH();
	i2c_delay();
	I2C_SDA_LOW();
	i2c_delay();
	I2C_SCL_LOW();
}

static void i2c_stop(void)
{
	i2c_sda_output();
	I2C_SCL_LOW();
	I2C_SDA_LOW();
	i2c_delay();
	I2C_SCL_HIGH();
	i2c_delay();
	I2C_SDA_HIGH();
	i2c_delay();
}

static uint8_t i2c_wait_ack(void)
{
	uint8_t timeout = 0;
	i2c_sda_input();
	I2C_SCL_HIGH();
	i2c_delay();
	while (I2C_SDA_READ() && timeout < 200) {
		timeout++;
	}
	if (timeout >= 200) {
		i2c_stop();
		return 1;  /* NACK */
	}
	I2C_SCL_LOW();
	i2c_delay();
	return 0;  /* ACK */
}

static void i2c_send_ack(void)
{
	i2c_sda_output();
	I2C_SDA_LOW();
	i2c_delay();
	I2C_SCL_HIGH();
	i2c_delay();
	I2C_SCL_LOW();
}

static void i2c_send_nack(void)
{
	i2c_sda_output();
	I2C_SDA_HIGH();
	i2c_delay();
	I2C_SCL_HIGH();
	i2c_delay();
	I2C_SCL_LOW();
}

static void i2c_write_byte(uint8_t data)
{
	uint8_t i;
	i2c_sda_output();
	for (i = 0; i < 8; i++) {
		if (data & 0x80) {
			I2C_SDA_HIGH();
		} else {
			I2C_SDA_LOW();
		}
		data <<= 1;
		i2c_delay();
		I2C_SCL_HIGH();
		i2c_delay();
		I2C_SCL_LOW();
	}
}

static uint8_t i2c_read_byte(void)
{
	uint8_t i, data = 0;
	i2c_sda_input();
	for (i = 0; i < 8; i++) {
		I2C_SCL_HIGH();
		i2c_delay();
		data <<= 1;
		if (I2C_SDA_READ()) {
			data |= 0x01;
		}
		I2C_SCL_LOW();
		i2c_delay();
	}
	return data;
}
```

---

## 四、ADC 驱动模板

### GD32F407 版本

```c
#include "gd32f4xx.h"

/*!
 * \brief ADC0 初始化（PA0 = IN0，12位分辨率）
 */
void adc0_init(void)
{
	rcu_periph_clock_enable(RCU_GPIOA);
	rcu_periph_clock_enable(RCU_ADC0);
	rcu_adc_clock_config(RCU_ADC_PRESCALER_4);

	/* PA0 = 模拟输入 */
	gpio_mode_set(GPIOA, GPIO_MODE_ANALOG, GPIO_PUPD_NONE, GPIO_PIN_0);

	adc_deinit(ADC0);
	adc_special_function_config(ADC0, ADC_CONTINUOUS_MODE, DISABLE);
	adc_special_function_config(ADC0, ADC_SCAN_MODE, DISABLE);
	adc_data_alignment_config(ADC0, ADC_DATAALIGN_RIGHT);
	adc_channel_length_config(ADC0, ADC_REGULAR_CHANNEL, 1);

	adc_external_trigger_source_config(ADC0, ADC_REGULAR_CHANNEL, ADC_EXTTRIG_REGULAR_NONE);
	adc_external_trigger_config(ADC0, ADC_REGULAR_CHANNEL, ENABLE);

	adc_enable(ADC0);
	/* ADC 校准 */
	adc_calibration_enable(ADC0);
}

/*!
 * \brief ADC0 读取指定通道
 * \param channel ADC_CHANNEL_x
 * \return 12位 ADC 值 (0-4095)
 */
uint16_t adc0_read(uint8_t channel)
{
	adc_regular_channel_config(ADC0, 0, channel, ADC_SAMPLETIME_56);
	adc_software_trigger_enable(ADC0, ADC_REGULAR_CHANNEL);
	while (!adc_flag_get(ADC0, ADC_FLAG_EOC));
	adc_flag_clear(ADC0, ADC_FLAG_EOC);
	return adc_regular_data_read(ADC0);
}
```

### STC8H8K64U 版本

```c
#include "stc8h.h"

/*!
 * \brief ADC 初始化（P1.0 = ADC 通道0）
 */
void adc_init(void)
{
	/* P1.0 设为高阻输入 */
	P1M0 |= 0x01; P1M1 |= 0x01;

	/* ADC 电源使能 */
	ADC_POWER = 1;
	/* 等待 ADC 稳定 */
	delay_ms(1);

	/* ADC 速度设置 */
	ADC_SPEED = 0b11;  /* 300Kbps */

	/* 结果右对齐 */
	ADC_RESFMT = 0;
}

/*!
 * \brief ADC 读取指定通道
 * \param ch 通道号 0-7
 * \return 10位 ADC 值 (0-1023)
 */
uint16_t adc_read(uint8_t ch)
{
	ADC_CONTR = (ADC_CONTR & 0xF0) | ch;  /* 选择通道 */
	ADC_START = 1;                         /* 启动转换 */
	while (ADC_START);                     /* 等待完成 */
	return ((uint16_t)ADC_RES << 2) | ADC_RESL;
}
```
