---
name: peripheral-test-template
description: "外设自检模板：启动时验证外设连通性，交互/无人值守两模式。参考 voice_assistant 的 audio_self_test。"
install_method: upload
version: 1.0.0
---

# 外设自检模板

## 概述
外设自检 Skill 提供通用的分层硬件自检框架，从基础连通性到功能完整性逐层验证，快速定位硬件问题。该框架独立于业务逻辑，可在项目启动阶段用于验证板载外设是否正常工作，帮助开发者在上电初期快速识别接线错误、电源异常、配置问题等硬件层面的故障。

## 设计原则
1. **分层测试**：从底层到上层，前一层失败则跳过后层，避免无效测试
2. **失败定位**：每项测试失败时打印具体排查方向，引导开发者逐步定位问题
3. **不依赖业务代码**：自检代码独立于业务逻辑，避免业务变更影响自检结果
4. **可扩展**：新增外设测试项只需添加测试函数和枚举，无需修改框架主体
5. **多模式支持**：支持交互模式（人工确认）和无人值守模式（自动判断）
6. **结果可追溯**：自检结果保存到 NVS/Flash，支持历史记录对比

## 三种自检模式

### 模式 1：交互模式（INTERACTIVE）
- **触发方式**：按住 BOOT 键上电
- **特点**：需要人工确认（如听声音、看显示）
- **适用场景**：开发调试阶段、首次硬件验证

### 模式 2：无人值守模式（UNATTENDED）
- **触发方式**：NVS 标志位 / 定时触发 / 上电自动触发
- **特点**：完全自动判断，无需人工干预
- **适用场景**：产线测试、远程部署、自动化 CI/CD
- **关键要求**：所有测试项必须有客观的通过/失败标准（不能用人工确认）

### 模式 3：诊断模式（DIAGNOSTIC）
- **触发方式**：看门狗复位后自动进入 / 异常崩溃后自动进入
- **特点**：只运行基础连通性测试，快速定位故障
- **适用场景**：现场故障诊断、崩溃后自动恢复

## 框架接口设计

### 自检模式枚举
```c
typedef enum {
	TEST_MODE_INTERACTIVE = 0,    // 交互模式（人工确认）
	TEST_MODE_UNATTENDED,         // 无人值守模式（自动判断）
	TEST_MODE_DIAGNOSTIC,         // 诊断模式（仅基础测试）
} test_mode_e;
```

### 测试项枚举
```c
typedef enum {
	TEST_ITEM_I2C_CONNECTIVITY = 0,  // I2C 连通性测试
	TEST_ITEM_GPIO_LEVEL,            // GPIO 电平测试
	TEST_ITEM_UART_LOOPBACK,         // UART 回环测试
	TEST_ITEM_SPI_COMMUNICATION,     // SPI 通信测试
	TEST_ITEM_ADC_SAMPLING,          // ADC 采样测试
	TEST_ITEM_DAC_OUTPUT,            // DAC 输出测试
	TEST_ITEM_INTERNAL_LOOPBACK,     // 内部回环测试
	TEST_ITEM_EXTERNAL_LOOPBACK,     // 外部回环测试
	TEST_ITEM_MAX
} test_item_e;
```

### 测试结果结构体
```c
typedef struct {
	test_item_e item;          // 测试项
	bool is_passed;            // 是否通过
	bool is_skipped;           // 是否跳过（前一层失败）
	char error_msg[128];       // 错误信息
	char suggestion[256];      // 排查建议
	uint32_t elapsed_ms;       // 耗时
	uint8_t retry_count;       // 重试次数
	int32_t metric_value;      // 量化指标（如幅值、电压、温度）
} test_result_t;
```

### 自检配置结构体
```c
typedef struct {
	test_mode_e mode;              // 自检模式
	uint32_t items_mask;           // 要测试的项（位掩码）
	uint8_t max_retry;             // 最大重试次数（默认 3）
	uint32_t item_timeout_ms;      // 单项测试超时（默认 10000ms）
	bool save_to_nvs;              // 是否保存结果到 NVS
	bool notify_remote;            // 是否远程通知（WiFi/蓝牙）
	char remote_topic[64];         // 远程通知主题（如 MQTT topic）
} test_config_t;
```

### 公开接口（5 个）
```c
// 初始化自检模块（加载配置）
int peripheral_test_init(const test_config_t *p_config);

// 运行指定测试项（支持自动重试）
int peripheral_test_run(test_result_t *p_results, uint8_t *p_count);

// 打印测试报告到串口
void peripheral_test_print_report(const test_result_t *p_results, uint8_t count);

// 保存测试报告到 NVS/Flash
int peripheral_test_save_report(const test_result_t *p_results, uint8_t count);

// 加载历史自检报告（对比趋势）
int peripheral_test_load_history(test_result_t *p_results, uint8_t *p_count, uint8_t max_count);
```

## 无人值守自检的关键设计

### 1. 自动判断算法（替代人工确认）

#### DAC 播放测试的自动判断
**问题**：原实现需要人工确认听到声音
**解决方案**：用 ADC 采集 DAC 输出（内部回环），通过信号分析自动判断

```c
/* 无人值守模式下的 DAC 测试：DAC→内部ADC 回环分析 */
static bool test_dac_auto_judge(void)
{
	/* 1. 配置 ES8311 REG44 启用内部 DAC→ADC 回环 */
	/* 2. 发送 880Hz 正弦波到 DAC */
	/* 3. 同时用 ADC 采集回环数据 */
	/* 4. 分析回环信号：
	 *    - 计算基波幅值（880Hz 处的 FFT 幅值）
	 *    - 计算信噪比 SNR
	 *    - 判断标准：基波幅值 > 阈值 && SNR > 20dB
	 */
	int32_t fundamental_amp = calc_fft_fundamental(rx_buf, sample_rate, 880);
	float snr = calc_snr(rx_buf, sample_rate, 880);

	if (fundamental_amp > 1000 && snr > 20.0f) {
		return true;  /* DAC 通路正常 */
	}
	return false;
}
```

#### 外部回环测试的自动判断
**问题**：原实现需要人工确认听到回声
**解决方案**：发送已知测试信号，采集回环信号，计算相关性

```c
/* 无人值守模式下的外部回环测试：信号相关性分析 */
static bool test_external_loopback_auto(void)
{
	/* 1. 发送 chirp 信号（扫频 500Hz-4kHz）到 DAC */
	/* 2. 用 ADC 采集环境音 + 回环信号 */
	/* 3. 计算 TX 信号与 RX 信号的互相关 */
	/* 4. 判断标准：互相关峰值 > 阈值 */
	int16_t tx_buf[1024];  /* 已知的 chirp 信号 */
	int16_t rx_buf[1024];  /* 采集的回环信号 */
	float correlation = calc_cross_correlation(tx_buf, rx_buf, 1024);

	if (correlation > 0.7f) {
		return true;  /* 外部回环通路正常 */
	}
	return false;
}
```

### 2. 多种触发方式（无人值守）

```c
/* 触发方式枚举 */
typedef enum {
	TRIGGER_BOOT_KEY = 0,      // BOOT 键（交互模式）
	TRIGGER_NVS_FLAG,          // NVS 标志位（远程触发）
	TRIGGER_POWER_ON,          // 上电自动触发
	TRIGGER_WATCHDOG_RESET,    // 看门狗复位后触发
	TRIGGER_SCHEDULED,         // 定时触发（如每小时）
	TRIGGER_UART_COMMAND,      // 串口命令触发
} trigger_source_e;

/* 检查是否需要进入自检 */
static trigger_source_e check_test_trigger(void)
{
	/* 1. 检查 BOOT 键（5秒窗口） */
	if (is_boot_key_pressed()) {
		return TRIGGER_BOOT_KEY;
	}

	/* 2. 检查 NVS 标志位（远程触发） */
	if (nvs_get_u32("test_flag", &flag) == ESP_OK && flag == 1) {
		nvs_set_u32("test_flag", 0);  /* 清除标志 */
		return TRIGGER_NVS_FLAG;
	}

	/* 3. 检查复位原因（看门狗复位后自动诊断） */
	if (esp_reset_reason() == ESP_RST_WDT) {
		return TRIGGER_WATCHDOG_RESET;
	}

	/* 4. 检查定时触发（每小时一次，通过 RTC） */
	if (is_scheduled_time()) {
		return TRIGGER_SCHEDULED;
	}

	return TRIGGER_NONE;
}
```

### 3. 自动重试机制

```c
/* 带重试的测试执行 */
static bool run_test_with_retry(test_item_e item, test_result_t *p_result)
{
	uint8_t retry = 0;
	bool pass = false;

	while (retry <= g_config.max_retry) {
		p_result->retry_count = retry;
		uint32_t start = esp_timer_get_time() / 1000;

		/* 执行测试函数 */
		pass = g_test_funcs[item]();

		p_result->elapsed_ms = esp_timer_get_time() / 1000 - start;

		if (pass) {
			return true;
		}

		/* 超时检查 */
		if (p_result->elapsed_ms > g_config.item_timeout_ms) {
			break;
		}

		retry++;
		if (retry <= g_config.max_retry) {
			ESP_LOGW(TAG, "  测试失败，%d秒后重试 (%d/%d)",
				RETRY_DELAY_SEC, retry, g_config.max_retry);
			vTaskDelay(pdMS_TO_TICKS(RETRY_DELAY_SEC * 1000));
		}
	}
	return false;
}
```

### 4. 结果存储到 NVS

```c
/* 保存自检报告到 NVS */
int peripheral_test_save_report(const test_result_t *p_results, uint8_t count)
{
	nvs_handle_t handle;
	nvs_open("test_report", NVS_READWRITE, &handle);

	/* 保存时间戳和结果摘要 */
	time_t now = time(NULL);
	nvs_set_i64(handle, "last_time", (int64_t)now);

	uint32_t pass_mask = 0, fail_mask = 0;
	for (uint8_t i = 0; i < count; i++) {
		if (p_results[i].is_passed) {
			pass_mask |= (1U << p_results[i].item);
		} else {
			fail_mask |= (1U << p_results[i].item);
		}
	}
	nvs_set_u32(handle, "pass_mask", pass_mask);
	nvs_set_u32(handle, "fail_mask", fail_mask);

	/* 保存量化指标（用于趋势分析） */
	char key[16];
	for (uint8_t i = 0; i < count; i++) {
		snprintf(key, sizeof(key), "metric_%d", p_results[i].item);
		nvs_set_i32(handle, key, p_results[i].metric_value);
	}

	nvs_commit(handle);
	nvs_close(handle);
	return 0;
}
```

### 5. 远程通知（WiFi/MQTT）

```c
/* 远程通知自检结果 */
static void notify_remote_result(const test_result_t *p_results, uint8_t count)
{
	if (!g_config.notify_remote) {
		return;
	}

	/* 构造 JSON 报告 */
	cJSON *report = cJSON_CreateObject();
	cJSON_AddNumberToObject(report, "timestamp", time(NULL));
	cJSON_AddStringToObject(report, "device_id", get_device_id());

	cJSON *items = cJSON_CreateArray();
	uint32_t pass_count = 0;
	for (uint8_t i = 0; i < count; i++) {
		cJSON *item = cJSON_CreateObject();
		cJSON_AddNumberToObject(item, "item", p_results[i].item);
		cJSON_AddBoolToObject(item, "passed", p_results[i].is_passed);
		cJSON_AddNumberToObject(item, "metric", p_results[i].metric_value);
		cJSON_AddStringToObject(item, "error", p_results[i].error_msg);
		cJSON_AddItemToArray(items, item);
		if (p_results[i].is_passed) pass_count++;
	}
	cJSON_AddItemToObject(report, "items", items);
	cJSON_AddNumberToObject(report, "pass_count", pass_count);
	cJSON_AddNumberToObject(report, "total_count", count);

	/* 通过 MQTT 发送 */
	char *json_str = cJSON_PrintUnformatted(report);
	mqtt_publish(g_config.remote_topic, json_str, 0, 1, 0);
	free(json_str);
	cJSON_Delete(report);
}
```

## 分层测试模板

### 第 1 层：连通性测试（I2C/SPI 地址扫描）
- I2C：扫描 0x01-0x7F，列出所有响应的设备地址
- SPI：发送空字节，检查 MISO 是否有响应
- **自动判断标准**：收到 ACK / MISO 有数据翻转
- 失败排查：检查 SCL/SDA 接线、上拉电阻、电源

### 第 2 层：寄存器访问测试
- 读取设备 ID 寄存器，与数据手册对比
- 读写测试寄存器，验证通信正确性
- **自动判断标准**：ID 寄存器值匹配 / 读写数据一致
- 失败排查：检查 SPI 模式（0/1/2/3）、I2C 地址（7位/8位）

### 第 3 层：基本功能测试
- DAC：播放测试音（1kHz 正弦波），用内部 ADC 回环采集分析
- ADC：采集已知电压（如内部参考电压），校验精度
- GPIO：输出高/低电平，用输入引脚回读验证
- **自动判断标准**：
  - DAC：FFT 基波幅值 > 阈值 && SNR > 20dB
  - ADC：采集电压误差 < 5%
  - GPIO：回读电平与输出一致
- 失败排查：检查引脚配置、电源、外设使能

### 第 4 层：回环测试
- 内部回环：DAC→ADC（同芯片内部回环）
- 外部回环：DAC→外部→ADC（验证整个信号链）
- UART 回环：TX→RX（短路两脚）
- **自动判断标准**：
  - 内部回环：信号相关性 > 0.9
  - 外部回环：信号相关性 > 0.7
  - UART：收发数据完全一致
- 失败排查：检查信号通路、相位、采样率

## 触发机制

### 交互模式触发（BOOT 键）
```c
/* 在 app_main 开头检测，5秒窗口 */
if (check_boot_key_pressed(5000)) {
	g_config.mode = TEST_MODE_INTERACTIVE;
	peripheral_test_run(...);
} else {
	app_main_business();
}
```

### 无人值守模式触发（多种方式）
```c
/* 检查多种触发源 */
trigger_source_e src = check_test_trigger();
if (src != TRIGGER_NONE) {
	/* 根据触发源选择模式 */
	switch (src) {
	case TRIGGER_NVS_FLAG:
		g_config.mode = TEST_MODE_UNATTENDED;
		break;
	case TRIGGER_WATCHDOG_RESET:
		g_config.mode = TEST_MODE_DIAGNOSTIC;
		break;
	default:
		g_config.mode = TEST_MODE_UNATTENDED;
	}
	peripheral_test_run(...);
}
```

### 远程触发（通过 NVS 标志位）
```c
/* 远程通过 MQTT/HTTP 设置 NVS 标志位，设备下次启动时进入自检 */
/* 手机 App / Web 后台 调用：
 * POST /api/device/{id}/self_test
 * → 服务端下发 MQTT 命令：{"cmd":"self_test","mode":"unattended"}
 * → 设备收到后：nvs_set_u32("test_flag", 1) + esp_restart()
 */
```

## 错误信息模板
每项测试失败时输出：
```
[FAIL] I2C 连通性测试 (123ms, 重试 2 次)
  错误：未在地址 0x18 检测到 ES8311
  量化指标：ACK = 0 (期望 1)
  排查：
    1. 检查 I2C SCL/SDA 接线（GPIO2/GPIO4）
    2. 检查 ES8311 供电（3.3V）
    3. 检查上拉电阻（4.7kΩ）
    4. 用逻辑分析仪抓取 I2C 波形
```

## 测试报告格式

### 串口输出（所有模式）
```
========================================
  自检结果汇总 (模式: 无人值守)
========================================
  时间   : 2026-07-26 15:30:00
  设备ID : ESP32-S3-XXXXXXXX
  触发源 : NVS 标志位

  I2C 连通性            : PASS (123ms, metric=1)
  DAC 播放              : PASS (2345ms, metric=8500, SNR=28dB)
  ADC 采集              : PASS (2034ms, metric=3200)
  内部回环              : PASS (2100ms, metric=0.95)
  外部回环              : FAIL (8050ms, 重试 3 次, metric=0.3)
    错误：信号相关性过低 (0.3 < 0.7)
    排查：检查麦克风接线、喇叭接线、环境噪音

----------------------------------------
  总计: 5 项测试, 4 项通过, 1 项失败
  结果: FAIL
========================================
  报告已保存到 NVS
  远程通知已发送
========================================
```

### NVS 存储（用于历史对比）
```json
{
  "timestamp": 1721980200,
  "device_id": "ESP32-S3-XXXXXXXX",
  "mode": "UNATTENDED",
  "trigger": "NVS_FLAG",
  "pass_mask": 0x1F,
  "fail_mask": 0x20,
  "metrics": {
    "i2c": 1,
    "dac": 8500,
    "adc": 3200,
    "internal_loop": 9500,
    "external_loop": 3000
  }
}
```

## 参考实现
voice_assistant 项目的 audio_self_test 模块（6 项测试）：
1. I2C 连通性（ES8311 0x18）—— 已支持自动判断
2. DAC 播放（880Hz 蜂鸣声）—— 需改造为自动判断（内部回环 + FFT）
3. ADC 采集（麦克风数据非零）—— 已支持自动判断
4. 内部 DAC→ADC 回环 —— 已支持自动判断
5. 外部 ADC→DAC 回环 —— 需改造为自动判断（信号相关性）
6. I2S 外部回环 —— 已支持自动判断

**改造重点**：测试 2 和 5 当前依赖人工确认，需改为自动判断算法。

## 适配新项目
1. 复制 audio_self_test.c/h 到新项目
2. 修改测试枚举，添加项目特定测试项
3. 实现各测试函数（**必须提供自动判断标准**）
4. 选择自检模式（交互 / 无人值守 / 诊断）
5. 配置触发方式（BOOT 键 / NVS 标志 / 定时 / 看门狗）
6. 配置结果存储（NVS）和远程通知（可选）
7. 在 app_main 添加触发检测
8. 编译烧录验证

## 无人值守自检的硬性要求

**所有测试项必须有客观的自动判断标准，禁止使用人工确认。**

| 测试类型 | 禁止的方式 | 推荐的自动判断方式 |
|---------|----------|------------------|
| DAC 播放 | "是否听到声音？" | 内部 ADC 回环 + FFT 分析 |
| 外部回环 | "是否听到回声？" | 信号互相关分析 |
| OLED 显示 | "是否看到图案？" | 读取 OLED 状态寄存器 + 像素回读 |
| 电机转动 | "是否看到转动？" | 编码器反馈 / 电流检测 |
| LED 亮灭 | "是否看到亮？" | 光敏传感器检测 / 电流检测 |
| 按键 | "请按键" | 自动模拟按键（GPIO 短路） |

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| `esp_timer_get_time()` API | ✅ | ESP-IDF v5.5.4 `esp_timer.h` |
| `nvs_open/nvs_set_u32/nvs_commit/nvs_close` API | ✅ | ESP-IDF v5.5.4 `nvs_flash.h` |
| `esp_reset_reason()` / `ESP_RST_WDT` | ✅ | ESP-IDF v5.5.4 `esp_system.h` L32 |
| `ESP_LOGW` 日志宏 | ✅ | ESP-IDF v5.5.4 `esp_log.h` |
| `pdMS_TO_TICKS` / `vTaskDelay` | ✅ | FreeRTOS `task.h` |
| `esp_restart()` | ✅ | ESP-IDF v5.5.4 `esp_system.h` |
| 自检框架设计（分层测试/三种模式/自动重试） | ✅ | 参考 voice_assistant 项目 audio_self_test 实现 |
| 无人值守自检自动判断算法（FFT/互相关） | ✅ | 信号处理标准算法 |
| cJSON API（`cJSON_CreateObject` 等） | ✅ | cJSON 标准库 |
| 测试结果 NVS 存储格式 | ✅ | ESP-IDF NVS 标准用法 |
