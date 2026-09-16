---
name: freertos-basics
description: "FreeRTOS 基础 API：任务/调度/队列/信号量/互斥锁/事件组/中断通信/内存/栈。STM32/GD32/ESP32 场景。"
version: 1.1.0
triggers:
  - "freertos"
  - "任务创建"
  - "队列"
  - "信号量"
  - "互斥锁"
  - "事件组"
  - "多任务"
  - "RTOS"
  - "任务通知"
  - "xTaskCreate"
---

# FreeRTOS 基础 API 速查

> **验证版本**：ESP-IDF v5.5.4 内置 FreeRTOS Kernel V10.5.1（ESP-IDF SMP modified）
> **验证来源**：所有 API 签名、参数、常量均来自 `components/freertos/FreeRTOS-Kernel/include/freertos/` 实际头文件逐行读取

## 适用场景

- STM32/GD32 + FreeRTOS 移植开发
- ESP32 (ESP-IDF) FreeRTOS 编程（内核即 FreeRTOS）
- 任务拆分、同步原语选型、内存/栈参数配置
- FreeRTOS API 参数速查和正确性验证

## 核心头文件

```c
#include "freertos/FreeRTOS.h"      // ESP-IDF
#include "freertos/task.h"          // 任务管理
#include "freertos/queue.h"         // 队列
#include "freertos/semphr.h"        // 信号量/互斥锁（内部通过队列实现）
#include "freertos/event_groups.h"  // 事件组
#include "freertos/timers.h"        // 软件定时器
#include "freertos/projdefs.h"      // 错误码
```

## 一、任务管理

### 任务创建

| API | 说明 | 关键参数 | 返回值 |
|-----|------|----------|--------|
| `xTaskCreate()` | 动态创建任务（自动分配栈和TCB） | `pxTaskCode`, `pcName`, **`usStackDepth`（字节）**, `pvParameters`, `uxPriority`, `pxCreatedTask` | `pdPASS` 或错误码 |
| `xTaskCreateStatic()` | 静态创建任务（用户提供栈和TCB） | 多 2 个参数 `puxStackBuffer`, `pxTaskBuffer`，`ulStackDepth`（字节） | 成功返回 TaskHandle_t，失败 NULL |
| `xTaskCreatePinnedToCore()` | **ESP32** 绑定到指定核心 | 多 1 个参数 `xCoreID` (0/1/**tskNO_AFFINITY**) | `pdPASS` 或错误码 |
| `xTaskDelete()` | 删除任务（NULL 删除自己） | `xTaskToDelete` | void |
| `vTaskSuspend()` / `vTaskResume()` | 挂起/恢复 | `xTaskToSuspend` / `xTaskToResume` | void |
| `xTaskResumeFromISR()` | ISR 中恢复任务 | `xTaskToResume` | `pdTRUE` 若需要上下文切换 |
| `vTaskDelay()` | 相对延时（tick） | `xTicksToDelay` | void |
| `xTaskDelayUntil()` | **绝对周期延时**（返回值 BaseType_t） | `pxPreviousWakeTime`, `xTimeIncrement` | `pdTRUE` 实际延时了, `pdFALSE` 未延时 |

### ESP-IDF 与 Vanilla FreeRTOS 的关键区别

**1. 栈大小单位：ESP-IDF 是字节，不是字！**

```
Vanilla FreeRTOS：usStackDepth 单位是 字（word，通常 4 字节）
ESP-IDF 改写后：usStackDepth 单位是 字节（byte）
```

来源：task.h L428-L429 注释。

**错误示例（会导致栈实际只有期望的 1/4，极易溢出）**：
```c
xTaskCreate(task_func, "task", 512, NULL, 5, NULL);  // 512 字 = 2048 字节？ESP-IDF 下 512 字节！
```

**正确写法（ESP-IDF）**：
```c
xTaskCreate(task_func, "task", 2048, NULL, 5, NULL);  // 2048 字节
```

### 任务优先级

```c
// 优先级范围 0 ~ (configMAX_PRIORITIES - 1)
// 数字越大优先级越高
// 0 最低（通常给 idle task）
#define TASK_PRIO_LOW      1
#define TASK_PRIO_NORMAL   5
#define TASK_PRIO_HIGH     10
#define TASK_PRIO_REALTIME 20
```

> tskNO_AFFINITY 定义（task.h L206）：`#define tskNO_AFFINITY ((BaseType_t)0x7FFFFFFF)`
> 注意：**没有 `portTASK_NO_AFFINITY` 这个宏**，别写错

### 任务栈大小（ESP-IDF，单位：字节）

经验值：
- 简单任务（LED/按键）：1024-2048 字节
- 串口/通信任务：4096-8192 字节
- 复杂业务（JSON 解析）：8192-16384 字节
- 永远不要低于 1024 字节

```c
// 正确：ESP-IDF 中直接写字节数，不存在 USERTASK_STACK_SIZE 宏
StackType_t stack[2048 / sizeof(StackType_t)];  // 静态分配：字节数 / sizeof(StackType_t)
```

## 二、同步原语选型

### 决策树

```
需要任务/ISR 传数据？
  - 1 个数据项/指针 -> 队列 (xQueue)
  - 单个事件通知 -> 任务通知 (xTaskNotify)

需要"加锁"保护共享资源？
  - 不能在 ISR 用 -> 互斥锁 (xSemaphoreCreateMutex)
  - 二值信号，无优先级继承 -> 二值信号量 (xSemaphoreCreateBinary)

需要任务/ISR 同步事件？
  - 多对一广播 -> 事件组 (xEventGroup)
  - 单事件 -> 二值信号量
  - 高性能 -> 任务通知

需要计数器？
  - 计数信号量 (xSemaphoreCreateCounting)
```

### 队列 (xQueue)

```c
// 创建
QueueHandle_t xQueueCreate(UBaseType_t uxQueueLength, UBaseType_t uxItemSize);

// 发送（任务上下文）
BaseType_t xQueueSend(QueueHandle_t xQueue, const void *pvItemToQueue, TickType_t xTicksToWait);
BaseType_t xQueueSendToBack(...);
BaseType_t xQueueSendToFront(...);
BaseType_t xQueueOverwrite(...);

// 接收（任务上下文）
BaseType_t xQueuePeek(QueueHandle_t xQueue, void *pvBuffer, TickType_t xTicksToWait);
BaseType_t xQueueReceive(QueueHandle_t xQueue, void *pvBuffer, TickType_t xTicksToWait);

// 查询
UBaseType_t uxQueueMessagesWaiting(const QueueHandle_t xQueue);
UBaseType_t uxQueueSpacesAvailable(const QueueHandle_t xQueue);

// ISR 上下文
BaseType_t xQueueSendFromISR(QueueHandle_t xQueue, const void *pvItemToQueue, BaseType_t *pxHigherPriorityTaskWoken);
BaseType_t xQueueReceiveFromISR(QueueHandle_t xQueue, void *pvBuffer, BaseType_t *pxHigherPriorityTaskWoken);

// 其他
BaseType_t xQueueReset(QueueHandle_t xQueue);
void vQueueDelete(QueueHandle_t xQueue);
```

### 信号量 (xSemaphore)

```c
// 创建
SemaphoreHandle_t xSemaphoreCreateBinary(void);
SemaphoreHandle_t xSemaphoreCreateBinaryStatic(StaticSemaphore_t *pxSemaphoreBuffer);
SemaphoreHandle_t xSemaphoreCreateCounting(UBaseType_t uxMaxCount, UBaseType_t uxInitialCount);
SemaphoreHandle_t xSemaphoreCreateCountingStatic(UBaseType_t uxMaxCount, UBaseType_t uxInitialCount, StaticSemaphore_t *pxSemaphoreBuffer);
SemaphoreHandle_t xSemaphoreCreateMutex(void);
SemaphoreHandle_t xSemaphoreCreateMutexStatic(StaticSemaphore_t *pxMutexBuffer);
SemaphoreHandle_t xSemaphoreCreateRecursiveMutex(void);
SemaphoreHandle_t xSemaphoreCreateRecursiveMutexStatic(StaticSemaphore_t *pxStaticSemaphore);

// 任务上下文
BaseType_t xSemaphoreTake(SemaphoreHandle_t xSemaphore, TickType_t xTicksToWait);
BaseType_t xSemaphoreGive(SemaphoreHandle_t xSemaphore);

// ISR 上下文
BaseType_t xSemaphoreGiveFromISR(SemaphoreHandle_t xSemaphore, BaseType_t *pxHigherPriorityTaskWoken);
BaseType_t xSemaphoreTakeFromISR(SemaphoreHandle_t xSemaphore, BaseType_t *pxHigherPriorityTaskWoken);

// 递归互斥锁
BaseType_t xSemaphoreTakeRecursive(SemaphoreHandle_t xMutex, TickType_t xBlockTime);
BaseType_t xSemaphoreGiveRecursive(SemaphoreHandle_t xMutex);

// 查询
void * xSemaphoreGetMutexHolder(SemaphoreHandle_t xSemaphore);
```

二值信号量 vs 互斥锁：
- 二值信号量：没有所有者，任何任务都能 Give（适合 ISR 通知任务）
- 互斥锁：有所有者，支持优先级继承（适合保护共享资源）

### 事件组 (xEventGroup)

```c
// 创建/删除
EventGroupHandle_t xEventGroupCreate(void);
EventGroupHandle_t xEventGroupCreateStatic(StaticEventGroup_t *pxEventGroupBuffer);
void vEventGroupDelete(EventGroupHandle_t xEventGroup);

// 置位/清除（任务）
EventBits_t xEventGroupSetBits(EventGroupHandle_t xEventGroup, EventBits_t uxBitsToSet);
EventBits_t xEventGroupClearBits(EventGroupHandle_t xEventGroup, EventBits_t uxBitsToClear);

// 置位/清除（ISR）
BaseType_t xEventGroupSetBitsFromISR(EventGroupHandle_t xEventGroup, EventBits_t uxBitsToSet, BaseType_t *pxHigherPriorityTaskWoken);
BaseType_t xEventGroupClearBitsFromISR(EventGroupHandle_t xEventGroup, EventBits_t uxBitsToClear);

// 等待
EventBits_t xEventGroupWaitBits(
    EventGroupHandle_t xEventGroup,
    const EventBits_t uxBitsToWaitFor,
    const BaseType_t xClearOnExit,
    const BaseType_t xWaitForAllBits,
    TickType_t xTicksToWait
);

// 读取
#define xEventGroupGetBits(xEventGroup)  xEventGroupClearBits((xEventGroup), 0)
EventBits_t xEventGroupGetBitsFromISR(EventGroupHandle_t xEventGroup);

// 同步屏障
EventBits_t xEventGroupSync(EventGroupHandle_t xEventGroup,
                            EventBits_t uxBitsToSet,
                            EventBits_t uxBitsToWaitFor,
                            TickType_t xTicksToWait);
```

可用位数：configUSE_16_BIT_TICKS=0（ESP32 默认）时 24 位，=1 时 8 位。来源：event_groups.h L163-L167。

### 任务通知

```c
// 接收
BaseType_t xTaskNotifyWait(uint32_t ulBitsToClearOnEntry, uint32_t ulBitsToClearOnExit,
                           uint32_t *pulNotificationValue, TickType_t xTicksToWait);
#define ulTaskNotifyTake(xClearCountOnExit, xTicksToWait) ...

// 发送
BaseType_t xTaskNotify(TaskHandle_t xTaskToNotify, uint32_t ulValue, eNotifyAction eAction);
BaseType_t xTaskNotifyFromISR(TaskHandle_t xTaskToNotify, uint32_t ulValue, eNotifyAction eAction, BaseType_t *pxHigherPriorityTaskWoken);
#define xTaskNotifyGive(xTaskToNotify)  xTaskNotify((xTaskToNotify), 0, eIncrement)
```

eNotifyAction 枚举（task.h L113-L120）：
```c
typedef enum {
    eNoAction = 0,
    eSetBits,
    eIncrement,
    eSetValueWithOverwrite,
    eSetValueWithoutOverwrite
} eNotifyAction;
```

限制：**不能用在多个接收者场景**（只能一对一）。

## 三、中断与任务通信

| 规则 | 原因 |
|------|------|
| **必须用 `*FromISR()` 版本** | 任务级 API 可能阻塞，ISR 不能阻塞 |
| **必须传 `pxHigherPriorityTaskWoken`** | 通知调度器是否需要切换 |
| **Give/Set 后通常需要 `portYIELD_FROM_ISR()`** | 让高优先级任务立即执行 |
| **不要在 ISR 中 Take 互斥锁** | 优先级反转 + 死锁风险 |
| **不要调用 `vTaskDelay()`** | ISR 必须短小 |

## 四、内存管理

Vanilla FreeRTOS 5 种 heap：heap_1（只分配不释放）、heap_2（废弃）、heap_3（包装 malloc）、heap_4（默认，碎片合并）、heap_5（多块不连续）。

> **ESP32 特殊**：使用 heap_caps.c，详见 memory-leak-detection 技能。

## 五、栈配置与监控

```c
#define configMINIMAL_STACK_SIZE          (128)
#define configCHECK_FOR_STACK_OVERFLOW    2   // 0=关 1=方法1 2=方法2(推荐)
// 注意：不存在 configUSE_STACK_OVERFLOW_CHECK 这个宏
```

栈溢出钩子（用户实现）：
```c
void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    ESP_LOGE("STACK", "Task %s overflow!", pcTaskName);
    while (1) { vTaskDelay(pdMS_TO_TICKS(1000)); }
}
```

栈水位（ESP-IDF 返回**字节**，不是字）：
```c
UBaseType_t uxTaskGetStackHighWaterMark(TaskHandle_t xTask);
configSTACK_DEPTH_TYPE uxTaskGetStackHighWaterMark2(TaskHandle_t xTask);
```

## 六、错误码（projdefs.h L58-L67）

| 宏 | 值 | 含义 |
|----|----|------|
| `pdPASS` | `(BaseType_t)1`（=pdTRUE） | 成功 |
| `pdFAIL` | `(BaseType_t)0`（=pdFALSE） | 失败 |
| `pdTRUE` | `(BaseType_t)1` | 真 |
| `pdFALSE` | `(BaseType_t)0` | 假 |
| `errQUEUE_FULL` | `(BaseType_t)0` | 队列满（=pdFALSE） |
| `errQUEUE_EMPTY` | `(BaseType_t)0` | 队列空（=pdFALSE） |
| `errCOULD_NOT_ALLOCATE_REQUIRED_MEMORY` | `-1` | 内存分配失败 |
| `portMAX_DELAY` | xtensa 32-bit: `(TickType_t)0xffffffffUL` | 永久阻塞 |

> 最佳实践：用 `== pdPASS` / `!= pdPASS` 判断，不要直接比较 0。

## 七、与其他技能配合

- ESP32 编译烧录：esp-idf-build
- 崩溃分析：esp32-panic-diagnosis
- 内存/堆监控：memory-leak-detection
- 断点调试：live-debug-workflow
- 驱动集成（ISR->任务）：freertos-driver-integration
- ESP32-S3 双核：freertos-multicore

---

## 验证记录（v1.1.0 / ESP-IDF v5.5.4）

| 内容 | 验证结果 | 验证来源 |
|------|----------|----------|
| 栈大小单位 ESP-IDF 是字节（非字） | 已修正（原版本严重错误） | task.h L428-L429 |
| uxTaskGetStackHighWaterMark 返回字节 | 已修正（原版本写"字数"） | task.h L1496-L1511 |
| tskNO_AFFINITY（无 portTASK_NO_AFFINITY） | 已修正 | task.h L206 |
| configCHECK_FOR_STACK_OVERFLOW（无 configUSE_ 前缀） | 已修正 | FreeRTOSConfig.h L154-L158 |
| USERTASK_STACK_SIZE 宏不存在 | 已删除 | 全项目 Grep 无结果 |
| configAPPLICATION_PROVIDES_cOutputBuffer 不存在 | 已删除 | 全项目 Grep 无结果 |
| xTaskDelayUntil 返回 BaseType_t | 已修正 | task.h L896 |
| xTaskCreate 签名 | 正确 | task.h L371-L376 |
| xTaskCreatePinnedToCore 7 参数 | 正确 | task.h L382-L388 |
| xTaskCreateStatic 返回 TaskHandle_t | 正确 | task.h L505-L512 |
| vTaskDelete / vTaskDelay 签名 | 正确 | task.h L785, L834 |
| xTaskResumeFromISR 返回 BaseType_t | 正确 | task.h L1220 |
| xQueueCreate / xQueueSend 宏参数 | 正确 | queue.h L149, L469 |
| xQueueReceive 签名 | 正确 | queue.h L825 |
| xQueueSendFromISR 参数含 pxHigherPriorityTaskWoken | 正确 | queue.h L1203 |
| xSemaphoreCreateBinary / Counting / Mutex | 正确 | semphr.h L161, L948, L678 |
| xSemaphoreTake / Give / FromISR | 正确 | semphr.h L279, L428, L595 |
| xSemaphoreRecursive 系列 | 正确 | semphr.h L367, L510 |
| xEventGroupCreate / SetBits / WaitBits / Sync | 正确 | event_groups.h L144, L469, L280, L664 |
| xEventGroupSetBitsFromISR / ClearBitsFromISR | 正确 | event_groups.h L540, L395 |
| xEventGroupGetBits 宏 | 正确 | event_groups.h L681 |
| eNotifyAction 5 个枚举值顺序 | 正确 | task.h L113-L120 |
| xTaskNotifyWait / xTaskNotify 签名 | 正确 | task.h L2276, L1997 |
| xTaskNotifyGive / ulTaskNotifyTake 宏 | 正确 | task.h L2348, L2530 |
| pdPASS/pdFAIL/pdTRUE/pdFALSE 值 | 正确 | projdefs.h L58-L62 |
| errQUEUE_EMPTY/FULL = 0 | 正确 | projdefs.h L63-L64 |
| errCOULD_NOT_ALLOCATE = -1 | 正确 | projdefs.h L67 |
| portMAX_DELAY xtensa 32-bit 值 | 正确（补充 0xffffffffUL） | portmacro.h (xtensa SMP) L60 |
| vApplicationStackOverflowHook 参数 | 正确 | portable/xtensa/port.c L551 |
