# FreeRTOS 驱动集成 - 参考

> 本文件为 freertos-driver-integration 技能的完整模板与验证记录（自 SKILL.md 拆分）。

---

## 10. 完整 UART+任务模式代码模板（GD32F407）

```c
// ====== uart_driver.h ======
#ifndef __UART_DRIVER_H
#define __UART_DRIVER_H

#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"

#define USART1_RX_BUF_SIZE  256
#define USART1_QUEUE_LEN    128

typedef struct {
    uint8_t data;
    uint32_t timestamp;
} uart_rx_item_t;

extern QueueHandle_t usart1_rx_queue;
extern TaskHandle_t  usart1_rx_task_handle;

void usart1_driver_init(void);
void usart1_rx_task(void *arg);
void USART1_IRQHandler(void);

#endif
```

```c
// ====== uart_driver.c ======
#include "uart_driver.h"
#include "gd32f4xx_usart.h"
#include "gd32f4xx_dma.h"

QueueHandle_t usart1_rx_queue = NULL;
TaskHandle_t  usart1_rx_task_handle = NULL;

void usart1_driver_init(void) {
    usart1_rx_queue = xQueueCreate(USART1_QUEUE_LEN, sizeof(uart_rx_item_t));
    configASSERT(usart1_rx_queue);   // 要求 configASSERT 定义

    rcu_periph_clock_enable(RCU_GPIOA);
    gpio_af_set(GPIOA, GPIO_AF_7, GPIO_PIN_9 | GPIO_PIN_10);
    gpio_mode_set(GPIOA, GPIO_MODE_AF, GPIO_PUPD_PULLUP, GPIO_PIN_9 | GPIO_PIN_10);
    gpio_output_options_set(GPIOA, GPIO_OTYPE_PP, GPIO_OSPEED_50MHZ, GPIO_PIN_9);

    rcu_periph_clock_enable(RCU_USART1);
    usart_deinit(USART1);
    usart_baudrate_set(USART1, 115200U);
    usart_receive_config(USART1, USART_RECEIVE_ENABLE);
    usart_transmit_config(USART1, USART_TRANSMIT_ENABLE);
    usart_enable(USART1);

    usart_interrupt_enable(USART1, USART_INT_RBNE);
    nvic_irq_enable(USART1_IRQn, 5, 0);

    // 栈大小 1024 字 = 4096 字节（GD32/STM32 Vanilla FreeRTOS 栈单位是字，与 ESP-IDF 不同！）
    xTaskCreate(usart1_rx_task, "uart1_rx", 1024, NULL, 8, &usart1_rx_task_handle);
}

void usart1_rx_task(void *arg) {
    uart_rx_item_t item;
    while (1) {
        if (xQueueReceive(usart1_rx_queue, &item, pdMS_TO_TICKS(100)) == pdTRUE) {
            protocol_parse(item.data, item.timestamp);
        }
    }
}

void USART1_IRQHandler(void) {
    if (usart_interrupt_flag_get(USART1, USART_INT_FLAG_RBNE) != RESET) {
        uint8_t byte = usart_data_receive(USART1);
        uart_rx_item_t item = { .data = byte, .timestamp = xTaskGetTickCountFromISR() };
        BaseType_t hpw = pdFALSE;
        xQueueSendFromISR(usart1_rx_queue, &item, &hpw);
        if (hpw == pdTRUE) portYIELD_FROM_ISR();
    }
}
```

## 验证记录（v1.0.1 / ESP-IDF v5.5.4）

| 内容 | 验证结果 | 验证来源 |
|------|----------|----------|
| xTimerCreate 是 5 参数（非 6/7 参数） | **已修正（原版本 L284 传 6 参数编译不通过）** | timers.h L234-L238 |
| TimerCallbackFunction_t = void (*)(TimerHandle_t xTimer) | 正确（回调签名验证） | timers.h L92 |
| xTimerStart / Stop / ChangePeriod / Reset 宏签名 | 正确 | timers.h L500/L542/L620/L782 |
| xTimerStartFromISR / ResetFromISR 带 pxHigherPriorityTaskWoken | 正确 | timers.h L867/L1085 |
| 模式 C 小标题改为"ISR↔任务间二值信号量" | 已修正（原为"ISR 安全互斥锁"误导） | semphr.h 互斥锁无 FromISR Take |
| vTaskNotifyGiveFromISR 宏存在 | 正确（不是假 API） | task.h L2430 宏定义 |
| xTaskGetTickCountFromISR 存在 | 正确 | task.h L1431 |
| pcTaskGetName(xTask) 存在 | 正确（WDG 里用了） | task.h L1452 |
| vTaskList 存在（需 configUSE_TRACE_FACILITY） | 正确（已补条件说明） | task.h L1798 |
| vTaskGetRunTimeStats（需 configGENERATE_RUN_TIME_STATS） | 正确（已补条件说明） | task.h L1849 |
| portSET_INTERRUPT_MASK_FROM_ISR / CLEAR 配对 | 补充（原决策矩阵未覆盖） | xtensa portmacro.h L168/L189 |
| taskENTER_CRITICAL() 无参数 ESP32 SMP 可用 | 正确（走 portENTER_CRITICAL_SMP → vTaskEnterCritical） | xtensa portmacro.h L210-L219 |
| portENTER_CRITICAL(&mux) ESP-IDF 风格 | 补充（跨核安全） | xtensa portmacro.h L85 portMUX_TYPE |
| portMUX_INITIALIZER_UNLOCKED | 正确 | xtensa portmacro.h L86 |
| portYIELD_FROM_ISR(...) SMP 下 VA_ARGS（CHECK/NO_CHECK） | 正确，无参/带 hpw 都能用 | xtensa portmacro.h L227-L233 |
| xQueueSendFromISR / ReceiveFromISR 签名 | 正确 | queue.h L1133/L1288 |
| xQueueIsQueueEmptyFromISR / FullFromISR 存在（未用但验证） | 正确 | queue.h L1298/L1306 |
| 看门狗任务栈大小：GD32=字，ESP32=字节 | 补充注释区分 | basics 技能已验证 |
| configASSERT 宏（默认 FreeRTOS.h 提供） | 正确（若用户未定义则用默认） | FreeRTOS.h L730-L750 条件定义 |
