---
name: freertos-driver-integration
description: "FreeRTOS 外设驱动集成：中断(ISR)↔任务通知/通信、DMA 接收、看门狗、定时器、临界区。"
version: 1.0.1
---

# FreeRTOS 驱动集成模式

> **验证版本**：ESP-IDF v5.5.4 内置 FreeRTOS Kernel V10.5.1（ESP-IDF SMP modified）
> **验证来源**：timers.h / task.h / queue.h / semphr.h / xtensa portmacro.h 逐行核对

## 适用场景

- 外设 ISR 需要通知任务处理（UART/SPI/I2C/ADC/定时器）
- DMA 接收完成回调需要任务处理
- 共享资源的多任务访问保护
- 看门狗喂狗任务设计
- 软件定时器替代硬件定时器
- 临界区保护（中断禁用 vs 互斥锁 vs 自旋锁）

## 1. UART 接收任务模式（最常用）

### 模式 A：队列传递原始字节

适用场景：协议解析需要连续字节流（Modbus/AT 命令）

```c
// 头文件
#define UART_RX_BUF_SIZE    256
#define UART_QUEUE_LENGTH   512

extern QueueHandle_t uart_rx_queue;

// 初始化
QueueHandle_t uart_rx_queue = NULL;

void uart_init(void) {
    uart_rx_queue = xQueueCreate(UART_QUEUE_LENGTH, sizeof(uint8_t));
    if (uart_rx_queue == NULL) { /* 内存分配失败，LED 报警 */ }
    uart_driver_install(UART_NUM_1, UART_RX_BUF_SIZE * 2, 0, 0, NULL, 0);
    uart_isr_register(uart_rx_queue);
}

// 接收任务
void uart_rx_task(void *arg) {
    uint8_t byte;
    while (1) {
        if (xQueueReceive(uart_rx_queue, &byte, pdMS_TO_TICKS(100)) == pdTRUE) {
            protocol_parse_byte(byte);
        }
    }
}

// ISR handler（GD32/STM32 风格）
void USART1_IRQHandler(void) {
    if (USART_GetITStatus(USART1, USART_IT_RXNE) != RESET) {
        uint8_t byte = USART_ReceiveData(USART1);
        BaseType_t hpw = pdFALSE;
        xQueueSendFromISR(uart_rx_queue, &byte, &hpw);
        if (hpw == pdTRUE) portYIELD_FROM_ISR();
        USART_ClearITPendingBit(USART1, USART_IT_RXNE);
    }
}
```

### 模式 B：任务通知传递帧

适用场景：DMA 接收一帧数据（定长帧）

```c
#define UART_RX_BUF_SIZE   128
extern TaskHandle_t uart_rx_task_handle;
extern uint8_t uart_rx_buf[UART_RX_BUF_SIZE];

void uart_rx_task(void *arg) {
    while (1) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        process_frame(uart_rx_buf, UART_RX_BUF_SIZE);
    }
}

void DMA1_Stream5_IRQHandler(void) {
    if (DMA_GetITStatus(DMA1_Stream5, DMA_IT_TCIF5)) {
        DMA_ClearITPendingBit(DMA1_Stream5, DMA_IT_TCIF5);
        DMA_DeInit(DMA1_Stream5);
        DMA_Init(DMA1_Stream5, &dma_init_struct);
        BaseType_t hpw = pdFALSE;
        vTaskNotifyGiveFromISR(uart_rx_task_handle, &hpw);   // 宏定义，已验证存在
        if (hpw == pdTRUE) portYIELD_FROM_ISR();
    }
}
```

### 模式 C：事件组多事件汇合

适用场景：UART 接收 + 定时器超时 + 用户按键，三者组成一个完整流程

```c
#define BIT_FRAME_OK     (1 << 0)
#define BIT_RX_TIMEOUT   (1 << 1)
#define BIT_USER_ABORT   (1 << 2)

EventGroupHandle_t uart_event_group;

void uart_rx_task(void *arg) {
    while (1) {
        EventBits_t bits = xEventGroupWaitBits(
            uart_event_group,
            BIT_FRAME_OK | BIT_RX_TIMEOUT | BIT_USER_ABORT,
            pdTRUE,          // 退出时清零
            pdFALSE,         // 任一事件即返回
            pdMS_TO_TICKS(5000)
        );

        if (bits & BIT_FRAME_OK)      { /* 帧接收完成 */ }
        else if (bits & BIT_RX_TIMEOUT) { /* 超时 */ }
        else if (bits & BIT_USER_ABORT) { /* 用户取消 */ }
    }
}
```

## 2. DMA 双缓冲 + IDLE 中断（高性能 UART）

### STM32/GD32 IDLE 中断 + DMA 接收不定长数据

```c
#define UART_RX_BUF_SIZE  256
extern DMA_Stream_TypeDef *g_dma_stream;
extern uint8_t g_rx_buf[UART_RX_BUF_SIZE];
extern TaskHandle_t g_rx_task_handle;

void uart_rx_task(void *arg) {
    while (1) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

        DMA_Cmd(g_dma_stream, DISABLE);
        uint16_t rx_len = UART_RX_BUF_SIZE - DMA_GetCurrDataCounter(g_dma_stream);

        if (rx_len > 0) {
            process_data(g_rx_buf, rx_len);
        }

        DMA_SetCurrDataCounter(g_dma_stream, UART_RX_BUF_SIZE);
        DMA_Cmd(g_dma_stream, ENABLE);
        USART_DMACmd(USART1, USART_DMAReq_Rx, ENABLE);
    }
}

void USART1_IRQHandler(void) {
    if (USART_GetITStatus(USART1, USART_IT_IDLE)) {
        // 关键：清 IDLE 标志前先读 SR + DR
        USART_ReceiveData(USART1);
        USART_ClearITPendingBit(USART1, USART_IT_IDLE);

        BaseType_t hpw = pdFALSE;
        vTaskNotifyGiveFromISR(g_rx_task_handle, &hpw);
        if (hpw == pdTRUE) portYIELD_FROM_ISR();
    }
}
```

> **关键点**：清 IDLE 标志必须**先读 SR 再读 DR**，不能用 `USART_ClearITPendingBit` 单独清！详见 [embedded-code-review](../embedded-code-review/SKILL.md)

## 3. 共享资源保护三选一

### 决策矩阵

| 场景 | 推荐方法 |
|------|----------|
| 短临界区（< 10 行，无阻塞，任务上下文） | `taskENTER_CRITICAL()` / `taskEXIT_CRITICAL()`（注意：ESP-IDF SMP 下已验证无参数可用，但带自旋锁参数更通用） |
| 中等长度（可能有 vTaskDelay、访问多个变量） | 互斥锁 `xSemaphoreCreateMutex()` |
| 跨 ISR + 任务共享的短变量（<10 条指令） | `portSET_INTERRUPT_MASK_FROM_ISR()` / `portCLEAR_INTERRUPT_MASK_FROM_ISR(prev)` 配对 |
| 多核（ESP32-S3 跨核 + 跨 ISR） | `portENTER_CRITICAL(&spinlock)` / `portENTER_CRITICAL_ISR(&spinlock)` 带 mux 参数 |

### 模式 A：任务级短临界区

```c
void update_sensor_data(void) {
    // 无参数：适合同一核心内任务与任务之间互斥（ESP-IDF SMP 下走内核 task 锁）
    taskENTER_CRITICAL();  // 禁用中断 + 获取内核锁
    sensor_value = new_reading;
    sensor_timestamp = get_tick();
    taskEXIT_CRITICAL();
}
```

**ESP-IDF 推荐风格（带 mux，跨核更安全）**：
```c
// 全局定义 mux
portMUX_TYPE sensor_mux = portMUX_INITIALIZER_UNLOCKED;

void update_sensor_data(void) {
    portENTER_CRITICAL(&sensor_mux);   // 关中断 + 拿自旋锁（跨核安全）
    sensor_value = new_reading;
    sensor_timestamp = xTaskGetTickCount();
    portEXIT_CRITICAL(&sensor_mux);
}
```

**警告**：
- 临界区内**绝对不能**调用任何 FreeRTOS API（会触发 configASSERT）
- 临界区**不能跨任务**（A 任务进入，B 任务退出会导致死锁）
- 临界区**不能跨函数**（除非有明确保护）

### 模式 B：互斥锁保护共享外设

```c
extern SemaphoreHandle_t i2c_mutex;

void i2c_bus_acquire(void) {
    if (xSemaphoreTake(i2c_mutex, pdMS_TO_TICKS(100)) != pdTRUE) {
        ESP_LOGE("I2C", "Bus busy timeout");
        return;
    }
}

void i2c_bus_release(void) {
    xSemaphoreGive(i2c_mutex);
}

esp_err_t i2c_read_register(uint8_t addr, uint8_t reg, uint8_t *data) {
    i2c_bus_acquire();
    esp_err_t ret = i2c_master_read_slave_reg(...);
    i2c_bus_release();
    return ret;
}
```

### 模式 C：ISR ↔ 任务间用二值信号量同步

注意：**标准互斥锁（Mutex）不能在 ISR 中 Take 或 Give**（有所有者/优先级继承语义）。需要 ISR 与任务同步时，使用**二值信号量** + `FromISR` 版本。

```c
extern SemaphoreHandle_t spi_tx_done_sem;   // 用 xSemaphoreCreateBinary() 创建

void spi_tx_complete_isr(void) {
    BaseType_t hpw = pdFALSE;
    xSemaphoreGiveFromISR(spi_tx_done_sem, &hpw);
    if (hpw == pdTRUE) portYIELD_FROM_ISR();
}

void spi_send_data(const uint8_t *data, size_t len) {
    // 启动 DMA 发送
    spi_dma_transmit(data, len);
    // 等待完成（阻塞，任务上下文）
    if (xSemaphoreTake(spi_tx_done_sem, pdMS_TO_TICKS(1000)) != pdTRUE) {
        ESP_LOGE("SPI", "TX timeout");
    }
}
```

## 4. 软件定时器（替代硬件定时器）

### 适用场景

- 周期性任务（LED 闪烁、状态上报、心跳检测）
- 一次性延时触发（按键去抖、超时检测）
- 不需要硬件定时器精度的场景

### 基础用法

```c
// 定时器回调：必须是 void (*)(TimerHandle_t xTimer) 签名（已验证 typedef：timers.h L92）
void led_blink_cb(TimerHandle_t xTimer) {
    static int state = 0;
    gpio_set_level(LED_GPIO, state);
    state = !state;
}

// 启动：xTimerCreate 固定 5 参数（name, period_ticks, auto_reload, timer_id, callback）
TimerHandle_t led_timer = xTimerCreate(
    "led_blink",                      // [1] pcTimerName
    pdMS_TO_TICKS(500),               // [2] xTimerPeriodInTicks（必须>0）
    pdTRUE,                           // [3] xAutoReload：pdTRUE 周期 / pdFALSE 单次
    NULL,                             // [4] pvTimerID：回调里通过 pvTimerGetTimerID 取
    led_blink_cb                      // [5] pxCallbackFunction：TimerCallbackFunction_t
);

if (led_timer != NULL) {
    xTimerStart(led_timer, 0);        // xTicksToWait：timer queue 满时最多等多久
}

// 停止
xTimerStop(led_timer, portMAX_DELAY);

// 改变周期
xTimerChangePeriod(led_timer, pdMS_TO_TICKS(100), portMAX_DELAY);
```

**重要规则**：
- 回调运行在 **timer service task** 上下文（不是调用回调的任务）
- 不要在回调中调用 `vTaskDelay` 等阻塞 API
- 回调中可以调用 `xQueueSend`（不能 Take 队列）
- 定时器 API 都是**异步**的（不会立即执行，要等 timer service task 调度）
- **xTimerCreate 只有 5 个参数**，不要传第 6、7 个（常见编译错误）

### 一键启动：注册即运行

```c
// xTimerCreate 5 参数 + xTimerStart 启动（pdTRUE=周期，timer_id=NULL）
TimerHandle_t timer = xTimerCreate(
    "sensor_sample",
    pdMS_TO_TICKS(100),
    pdTRUE,
    NULL,
    sensor_sample_cb
);
if (timer) xTimerStart(timer, 0);
```

## 5. 看门狗任务设计

### 模式 A：硬件看门狗 + 任务喂狗

```c
extern TimerHandle_t g_watchdog_timer;

void watchdog_init(void) {
    // 1. 初始化硬件看门狗（10秒超时）
    IWDG_Init(10000);

    // 2. 创建看门狗任务（高优先级，ESP-IDF 下栈大小为字节）
    xTaskCreate(watchdog_task, "wdg", 2048, NULL, TASK_PRIO_HIGH, NULL);

    // 3. 注册其他被监控任务
    register_monitored_task(main_task_handle);
    register_monitored_task(uart_task_handle);
}

void watchdog_task(void *arg) {
    const uint32_t TIMEOUT_MS = 5000;  // 5秒喂一次

    while (1) {
        // 检查所有被监控任务
        bool all_alive = true;
        for (int i = 0; i < monitored_task_count; i++) {
            if (!is_task_alive(monitored_tasks[i])) {
                ESP_LOGE("WDG", "Task %s is dead!", pcTaskGetName(monitored_tasks[i]));
                all_alive = false;
                break;
            }
        }

        if (all_alive) {
            IWDG_Feed();  // 喂狗
        } else {
            // 不喂狗，让看门狗复位系统
            ESP_LOGE("WDG", "System will reset in 5s");
        }

        vTaskDelay(pdMS_TO_TICKS(TIMEOUT_MS));
    }
}
```

### 模式 B：软件看门狗（无硬件 WDT）

```c
// 用软件定时器
TimerHandle_t sw_wdt;

void sw_wdt_cb(TimerHandle_t xTimer) {
    // 5 秒没被喂，强制重启
    ESP_LOGE("WDT", "System hang detected, restarting...");
    esp_restart();
}

void wdt_feed(void) {
    xTimerReset(sw_wdt, 0);
}

// 在主循环的合适位置调用 wdt_feed()
```

## 6. ISR 延迟处理（Defer to Task）

### 问题：ISR 中不能调用复杂函数

有些函数（如 printf、长字符串处理、I2C/SPI 通信）不能在 ISR 中调用。

### 解决方案：中断中标记 + 任务中处理

```c
extern SemaphoreHandle_t g_button_sem;

void EXTI0_IRQHandler(void) {
    if (EXTI_GetITStatus(EXTI_Line0) != RESET) {
        EXTI_ClearITPendingBit(EXTI_Line0);
        BaseType_t hpw = pdFALSE;
        xSemaphoreGiveFromISR(g_button_sem, &hpw);
        if (hpw == pdTRUE) portYIELD_FROM_ISR();
    }
}

void button_task(void *arg) {
    while (1) {
        if (xSemaphoreTake(g_button_sem, portMAX_DELAY) == pdTRUE) {
            vTaskDelay(pdMS_TO_TICKS(20));  // 消抖
            if (gpio_get_level(BUTTON_GPIO) == 0) {
                handle_button_press();
            }
        }
    }
}
```

## 7. 生产者-消费者模式（多源数据汇聚）

### 场景：3 个 UART + 1 个 SPI 都发数据到一个数据处理任务

```c
QueueHandle_t data_queue = xQueueCreate(32, sizeof(data_packet_t));

void uart1_rx_task(void *arg) {
    while (1) {
        uint8_t byte;
        if (xQueueReceive(uart1_rx_queue, &byte, pdMS_TO_TICKS(100)) == pdTRUE) {
            data_packet_t pkt = { .source = SRC_UART1, .data = byte, .timestamp = get_tick() };
            xQueueSend(data_queue, &pkt, pdMS_TO_TICKS(10));
        }
    }
}

void process_task(void *arg) {
    data_packet_t pkt;
    while (1) {
        if (xQueueReceive(data_queue, &pkt, portMAX_DELAY) == pdTRUE) {
            route_packet(&pkt);
        }
    }
}
```

## 8. 常见错误与预防

| 错误 | 现象 | 预防 |
|------|------|------|
| ISR 中调用 `xQueueSend`（非 FromISR） | 偶尔卡死 | 一律用 `xQueueSendFromISR` |
| ISR 中 Take 或 Give 互斥锁 | 优先级反转 / 死锁 | **永远不要**，改用二值信号量 |
| 任务中调 `portDISABLE_INTERRUPTS()` 不关回 | 长时间关中断丢中断 | 用 taskENTER_CRITICAL / EXIT 配对，或 portSET/CLEAR 配对 |
| 忘记 `portYIELD_FROM_ISR()` | 高优先级任务不及时执行 | Give 后检查 hpw |
| 队列满时阻塞 0ms 死循环 | CPU 100% | 阻塞 Nms 或统计丢弃 |
| 互斥锁内调用 vTaskDelay | 其他任务饿死 | 互斥锁内只做短操作 |
| 任务优先级全相同 + 没有 vTaskDelay | 单任务独霸 | 添加 vTaskDelay 或降低优先级 |
| 临界区内调用 FreeRTOS API | configASSERT 失败 | 临界区只做赋值，不调用 API |
| 任务通知丢失（不阻塞） | 数据丢失 | 用 `xTaskNotifyWait` 阻塞等待 |
| xTimerCreate 传 6/7 个参数 | 编译失败（参数不匹配） | 记住固定 5 参数：name / period / reload / id / callback |

## 9. 调试技巧

### 监控任务状态（需开启 configUSE_TRACE_FACILITY）

```c
void monitor_task(void *arg) {
    char buf[1024];
    while (1) {
        printf("========== Task Status ==========\n");
        vTaskList(buf);
        printf("%s\n", buf);
        vTaskDelay(pdMS_TO_TICKS(10000));
    }
}
```

输出示例：
```
Name          State  Prio  Stack  Num
IDLE          R       0     128   1
main          B       5     4096  1
uart_rx       R       8     2048  1
sensor_sample B       5     1024  1
```

### 监控栈使用 / CPU 占用（需开启 configGENERATE_RUN_TIME_STATS）

```c
void monitor_task(void *arg) {
    char buf[1024];
    while (1) {
        vTaskGetRunTimeStats(buf);
        printf("========== CPU Usage ==========\n%s\n", buf);
        vTaskDelay(pdMS_TO_TICKS(5000));
    }
}
```

### ESP-IDF 专用：在 monitor 中查看

```bash
# 启动 monitor
esp-idf-monitor

# 在 monitor 内执行
> tasks
> cpu_usage
> heap
```


## 完整代码模板与验证记录

> 完整 UART+任务模式代码模板与验证记录维护在 **同目录 reference.md**。

## 触发时机

- **设计 UART/SPI/I2C 接收任务时** → 调用本技能
- **多任务共享外设（I2C 总线、SPI Flash）** → 调用本技能
- **需要看门狗/软件定时器** → 调用本技能
- **ISR 中遇到"能不能调 X 函数"** → 调用本技能查规则
- **不触发**：单任务裸机项目、纯算法

## 相关技能

- [freertos-basics](../freertos-basics/SKILL.md)：基础 API 速查
- [freertos-multicore](../freertos-multicore/SKILL.md)：ESP32-S3 双核编程
- [esp32-panic-diagnosis](../esp32-panic-diagnosis/SKILL.md)：任务崩溃时诊断
- [embedded-code-review](../embedded-code-review/SKILL.md)：ISR 安全性审查
- [peripheral-driver-template](../peripheral-driver-template/SKILL.md)：裸机驱动模板

---

