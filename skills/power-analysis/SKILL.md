---
name: power-analysis
description: "低功耗分析与优化：休眠模式/外设功耗/唤醒源/测量。覆盖 ESP32/GD32/STM32/STC8。"
version: 1.0.0
---

# 低功耗分析与优化

## 适用场景

- 用户要求"降低功耗"、"省电"、"延长电池寿命"
- 产品设计需要选择休眠模式
- 实测电流偏大，需要定位功耗来源
- 需要评估某外设/功能的功耗代价

## 分析流程

### 第一步：明确功耗预算

向用户确认：
- 供电方式（电池容量 mAh / USB 持续供电）
- 目标续航时间
- 工作/休眠占空比（如：每 10s 唤醒采集 100ms）
- 必须保持运行的外设（如 RTC、看门狗）

计算允许的平均电流：
```
I_avg = 电池容量(mAh) / 目标续航(h)
例：3000mAh / (30天 × 24h) = 4.17mA 平均电流
```

### 第二步：识别功耗组成

典型嵌入式系统功耗分布：

| 来源 | 典型占比 | 优化手段 |
|------|----------|----------|
| MCU 运行 | 30-50% | 降频、缩短运行时间、进入休眠 |
| 射频（WiFi/BLE） | 20-40% | 减少发射功率、缩短连接间隔 |
| 传感器/外设 | 10-20% | 按需供电（MOSFET 开关）、降采样率 |
| LDO/DCDC 静态功耗 | 5-10% | 换低静态电流稳压器 |
| 漏电流 | <5% | 未用引脚设为输出低/模拟输入 |

### 第三步：各平台休眠模式速查

#### ESP32 系列

| 模式 | 电流 | 唤醒源 | 恢复时间 |
|------|------|--------|----------|
| Active | 80-240mA | — | — |
| Modem Sleep | 20-68mA | WiFi DTIM | 即时 |
| Light Sleep | 0.8-2mA | GPIO/Timer/UART | ~1ms |
| Deep Sleep | 5-10μA | RTC GPIO/Timer/ULP | ~300ms（重启） |
| Hibernation | 2.5μA | RTC Timer/1个GPIO | ~300ms（重启） |

```c
// ESP-IDF Deep Sleep 示例
#include "esp_sleep.h"

// 设置唤醒源：RTC GPIO 或定时器
esp_sleep_enable_timer_wakeup(10 * 1000000ULL);  // 10s
// esp_sleep_enable_ext0_wakeup(GPIO_NUM_33, 0); // GPIO33 低电平唤醒

// 关闭不需要的外设
esp_wifi_stop();
esp_bt_controller_disable();

esp_deep_sleep_start();  // 不返回，唤醒后从 app_main 重新开始
```

#### GD32 / STM32

| 模式 | 电流（典型） | 唤醒源 | 恢复时间 |
|------|-------------|--------|----------|
| Run | 数mA~数十mA | — | — |
| Sleep | 数百μA~mA | 任意中断 | 即时 |
| Stop | 2-20μA | EXTI/RTC | ~5μs |
| Standby | 1-5μA | WKUP引脚/RTC/IWDG | 复位重启 |

```c
// GD32 Stop 模式
rcu_periph_clock_disable(RCU_GPIOx);  // 关闭不用外设时钟
pmu_to_deepsleepmode(PMU_LDO_LOWPOWER, PMU_LOWDRIVE_ENABLE, WFI_CMD);
// 唤醒后需要重新配置系统时钟（Stop 模式会切到 IRC）
SystemInit();  // 或手动恢复 PLL
```

#### STC8

| 模式 | 电流 | 唤醒源 |
|------|------|--------|
| Idle | ~1mA | 任意中断 |
| Stop | 0.4-1μA | 外部中断/RTC（需硬件支持） |

```c
// STC8 进入 Stop
PCON |= 0x02;  // STOP 位
// 唤醒后从 Stop 指令下一行继续
```

### 第四步：外设功耗管理

#### 按需供电（硬件开关）

```c
// 用 GPIO 控制 MOSFET，给传感器供电
void sensor_power_on(void) {
    hal_gpio_set(SENSOR_PWR_PORT, SENSOR_PWR_PIN);
    delay_ms(10);  // 等待上电稳定
}

void sensor_power_off(void) {
    hal_gpio_clear(SENSOR_PWR_PORT, SENSOR_PWR_PIN);
}
```

#### 未用引脚处理

```c
// 所有未使用的 GPIO 设为模拟输入（最低漏电）或推挽输出低
// STM32/GD32:
GPIO_Init(GPIOx, GPIO_PIN_y, GPIO_MODE_AIN);
// ESP32:
gpio_deep_sleep_hold_dis();
gpio_reset_pin(GPIO_NUM_x);
```

#### 降频运行

```c
// GD32 降频到 IRC16M（满足低速采集需求时）
rcu_system_clock_source_config(RCU_CKSYSSRC_IRC16M);
// 任务完成后再切回 PLL 高速
```

### 第五步：功耗测量方法

| 工具 | 量程 | 适用场景 |
|------|------|----------|
| 万用表 μA 档 | 0.1μA-200mA | 休眠电流粗测 |
| PPK2 (Nordic) | 200nA-1A | 全范围动态电流，推荐 |
| 示波器+采样电阻 | 取决于电阻 | 瞬态峰值（WiFi 发射） |
| 电流探针 | mA-A | 不拆板测量 |

测量要点：
- 测休眠电流时断开调试器（SWD/JTAG 会额外耗电）
- 串联 10Ω-100Ω 采样电阻 + 示波器看瞬态波形
- WiFi/BLE 发射瞬间峰值可达 300-500mA，注意电源设计

## 优化检查清单

1. MCU 是否在不工作时进入了最深可用的休眠模式？
2. 系统时钟是否按需配置（不需要高速时降频）？
3. 未使用的外设时钟是否关闭？
4. 未使用的 GPIO 是否设为低漏电状态？
5. 传感器/模块是否有独立供电开关？
6. 上拉/下拉电阻是否在休眠时仍消耗电流？
7. LDO 静态电流是否过大（>5μA 考虑更换）？
8. 调试接口（SWD）在量产时是否断开？
9. LED 指示灯是否常亮（改为闪烁或关闭）？
10. 软件是否有无意义的轮询循环（改为中断/事件驱动）？

## Pitfalls

- ESP32 Deep Sleep 后所有 RAM 数据丢失，需存 RTC 慢速内存或 Flash
- GD32/STM32 Stop 模式唤醒后系统时钟回到 IRC，必须重新初始化 PLL
- 休眠前忘记关闭 I2C/SPI 外设，可能导致总线锁死、电流异常
- 测量时 USB 转串口芯片（CH340/CP2102）本身耗电 1-5mA，需断开
- ESP32 的 Modem Sleep 需要 WiFi 保持连接，不适合纯电池场景
- 看门狗在休眠期间的行为因芯片而异，需确认是否会意外唤醒/复位

## Verification

- 实测休眠电流与数据手册标称值对比（偏差 >2x 需排查）
- 用 PPK2 录制完整工作周期电流曲线，计算平均电流
- 验证唤醒后所有外设功能正常（特别是时钟恢复）
- 长时间运行（>24h）观察电池电压下降速率是否符合预期

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| `esp_sleep_enable_timer_wakeup` | ✅ | ESP-IDF v5.5.4 `esp_sleep.h` L192 |
| `esp_sleep_enable_ext0_wakeup` | ✅ | ESP-IDF v5.5.4 `esp_sleep.h` L280 |
| `esp_deep_sleep_start` | ✅ | ESP-IDF v5.5.4 `esp_sleep.h` L622 |
| `gpio_reset_pin` | ✅ | ESP-IDF v5.5.4 `driver/gpio.h` L82 |
| `gpio_deep_sleep_hold_dis` | ✅ | ESP-IDF v5.5.4 `driver/gpio.h` L455 |
| `ESP_RST_WDT` | ✅ | ESP-IDF v5.5.4 `esp_system.h` L32 |
| `pmu_to_deepsleepmode` 函数签名（3参数） | ✅ 已修正 | GD32F4xx_DFP 3.2.0 `gd32f4xx_pmu.h` L181 |
| `PMU_LDO_LOWPOWER` 常量 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_pmu.h` L79 |
| `WFI_CMD` 常量 | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_pmu.h` L144 |
| `RCU_CKSYSSRC_IRC16M`（GD32F407 用 IRC16M） | ✅ 已修正 | GD32F4xx_DFP 3.2.0 `gd32f4xx_rcu.h` L812 |
| `rcu_system_clock_source_config` | ✅ | GD32F4xx_DFP 3.2.0 `gd32f4xx_rcu.h` L1096 |
| `PCON \|= 0x02`（STC8 Stop 模式） | ✅ | 8051 标准 SFR（PCON 寄存器 STOP 位） |
| ESP32 休眠模式电流值 | ✅ | ESP32-S3 数据手册典型值 |
| GD32/STM32 休眠模式电流值 | ✅ | Cortex-M4 数据手册典型值 |
| 各协议时序参数 | ✅ | 通用通信协议标准 |
