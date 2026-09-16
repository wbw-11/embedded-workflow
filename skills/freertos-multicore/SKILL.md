---
name: freertos-multicore
description: "ESP32-S3 双核编程：核亲和/自旋锁/跨核通信/关键代码。仅 S3/S2/C6。"
version: 1.0.1
---

# ESP32-S3 双核 FreeRTOS 编程

> **验证版本**：ESP-IDF v5.5.4 内置 FreeRTOS Kernel V10.5.1（ESP-IDF SMP modified）
> **验证来源**：task.h / esp_pm.h / esp_heap_caps.h / xtensa portmacro.h / soc/esp32s3/soc.h / idf_additions.h / esp_attr.h

## 适用场景

- ESP32-S3 双核项目（CPU 0 = PRO CPU，CPU 1 = APP CPU）
- 计算密集型任务需要分核优化
- 高实时性任务（电机控制、音频）需要独占核心
- 双核间数据共享和同步

> **重要**：本项目使用 **ESP32-S3-WROOM-1-N16R8**（双核 Xtensa LX7，详情见 [pin-check](../pin-check/SKILL.md)）

## 1. 核心编号与默认任务

| 核心 | 名称 | 用途 |
|------|------|------|
| 0 | PRO CPU | 协议处理器，默认运行 ESP-IDF 系统任务 |
| 1 | APP CPU | 应用处理器，默认 idle |

```c
// 核心常量（已验证：soc/esp32s3/soc.h L17-L18）
#define PRO_CPU_NUM    0
#define APP_CPU_NUM    1
#define CORE_ID_0      0
#define CORE_ID_1      1
#define CORE_NO_AFFINITY  tskNO_AFFINITY   // 任意核心
```

## 2. 任务核心亲和性

### 基础 API

```c
// task.h L382-L388，已验证 7 参数；usStackDepth 在 ESP-IDF 下单位是字节
BaseType_t xTaskCreatePinnedToCore(
    TaskFunction_t pvTaskCode,
    const char *const pcName,
    const configSTACK_DEPTH_TYPE usStackDepth,  // 字节（ESP-IDF SMP）
    void *const pvParameters,
    UBaseType_t uxPriority,
    TaskHandle_t *const pxCreatedTask,
    const BaseType_t xCoreID    // 0 / 1 / tskNO_AFFINITY
);
```

### 任务分配策略

```c
// 通信/网络任务：绑核心 0（PRO CPU，靠近协议栈）
xTaskCreatePinnedToCore(
    wifi_task, "wifi", 8192, NULL, 5, NULL, 0);  // 栈 8192 字节

// 实时控制/音频任务：绑核心 1（APP CPU，避免与系统任务冲突）
xTaskCreatePinnedToCore(
    motor_control_task, "motor", 4096, NULL, 10, NULL, 1);

// 普通 UI/逻辑任务：不指定（任一核心调度）
xTaskCreate(ui_task, "ui", 4096, NULL, 3, NULL);  // 不带 Pinned
```

### 运行时修改核心

```c
// 不支持直接修改任务亲和性，但可用 vTaskDelete + xTaskCreatePinnedToCore 重启
// ESP-IDF 内部用 task pinning 实现
void set_task_core(TaskHandle_t *handle, TaskFunction_t fn, BaseType_t core) {
    if (*handle != NULL) vTaskDelete(*handle);
    xTaskCreatePinnedToCore(fn, "renamed", 4096, NULL, 5, handle, core);
}
```

### 获取当前在哪个核心

```c
// 任务中
BaseType_t core_id = xPortGetCoreID();   // portmacro.h L282，返回 BaseType_t
printf("Running on core %d\n", (int)core_id);

// ISR 中（用更具体的 API，返回 int）
int core_id_2 = esp_cpu_get_core_id();   // esp_cpu.h L128，已验证存在
```

## 3. 跨核通信

### 跨核队列

```c
QueueHandle_t cross_core_queue;

void app_main(void) {
    // 创建队列（任何核心都能访问，FreeRTOS SMP 队列内部自旋锁保护）
    cross_core_queue = xQueueCreate(10, sizeof(int));

    // 创建双核任务
    xTaskCreatePinnedToCore(producer_task, "producer", 4096, NULL, 5, NULL, 0);
    xTaskCreatePinnedToCore(consumer_task, "consumer", 4096, NULL, 5, NULL, 1);
}

void producer_task(void *arg) {
    int value = 0;
    while (1) {
        value++;
        // 当前在核心 0，发送到队列
        xQueueSend(cross_core_queue, &value, pdMS_TO_TICKS(100));
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

void consumer_task(void *arg) {
    int value;
    while (1) {
        // 当前在核心 1，从队列接收
        if (xQueueReceive(cross_core_queue, &value, pdMS_TO_TICKS(100)) == pdTRUE) {
            printf("[Core 1] received: %d\n", value);
        }
    }
}
```

### 跨核信号量

```c
SemaphoreHandle_t cross_core_sem;

void setup(void) {
    cross_core_sem = xSemaphoreCreateBinary();

    // 核心 1 等待，核心 0 释放
    xTaskCreatePinnedToCore(worker_task, "worker", 4096, NULL, 5, NULL, 1);

    vTaskDelay(pdMS_TO_TICKS(100));
    xSemaphoreGive(cross_core_sem);  // 释放信号量（核心 0）
}

void worker_task(void *arg) {
    xSemaphoreTake(cross_core_sem, portMAX_DELAY);
    // ...
}
```

### 跨核任务通知

```c
TaskHandle_t core1_task_handle;

void setup(void) {
    xTaskCreatePinnedToCore(core1_task, "core1", 4096, NULL, 5, &core1_task_handle, 1);
}

void core0_task(void *arg) {
    // 通知核心 1 任务（一对一通知，跨核也能用）
    xTaskNotify(core1_task_handle, 0x01, eSetBits);
}

void core1_task(void *arg) {
    uint32_t value;
    xTaskNotifyWait(0, 0xFFFFFFFF, &value, portMAX_DELAY);
    // 处理
}
```

## 4. 自旋锁（Spinlock）

### 什么是自旋锁

普通互斥锁只能在任务上下文做"同一核心或多核 + 阻塞切换"保护；**自旋锁**提供**关中断 + 跨核忙等互斥**，专门用于双核场景下的短临界区（包括跨核 ISR 安全访问）。

```c
// 创建自旋锁。portMUX_TYPE = spinlock_t（已验证 portmacro.h L85）
portMUX_TYPE my_spinlock = portMUX_INITIALIZER_UNLOCKED;   // L86

// 任务上下文：进入临界区
portENTER_CRITICAL(&my_spinlock);
// 受保护代码（短小，不能阻塞，不能调 FreeRTOS API）
portEXIT_CRITICAL(&my_spinlock);

// ISR 安全版本（已验证 portmacro.h L350-L351 宏存在）
portENTER_CRITICAL_ISR(&my_spinlock);
// ISR 中受保护代码
portEXIT_CRITICAL_ISR(&my_spinlock);
```

### 使用规则

| 规则 | 原因 |
|------|------|
| **临界区必须短小**（<1us 或 <20 条指令） | 拿锁期间另一个核会自旋等待（空耗 CPU） |
| **临界区内不能有阻塞调用**（vTaskDelay / xSemaphoreTake / malloc） | 阻塞时关中断 + 另一核忙等 → 死锁或丢中断 |
| **同一线程/ISR 不可递归拿同一锁** | 自旋锁没有"持有计数"，递归会直接死锁 |
| **不同核的任务/ISR 可以拿同一把锁** | ✅ 这正是自旋锁的设计目的（跨核互斥），不要反过来限制 |

### 跨核共享外设保护

```c
static portMUX_TYPE g_i2c_spinlock = portMUX_INITIALIZER_UNLOCKED;

void i2c_driver_write(uint8_t addr, uint8_t reg, uint8_t data) {
    portENTER_CRITICAL(&g_i2c_spinlock);
    // 访问 I2C 寄存器（必须短、快、无阻塞）
    i2c_master_write_byte(addr);
    i2c_master_write_byte(reg);
    i2c_master_write_byte(data);
    portEXIT_CRITICAL(&g_i2c_spinlock);
}
```

## 5. 内存分配策略（PSRAM 优化）

ESP32-S3 有 8MB PSRAM（项目配置），适合大块数据分配。

```c
// 头文件：#include "esp_heap_caps.h"

// 内部 RAM 分配（快，约 320KB，MALLOC_CAP_INTERNAL esp_heap_caps.h L40）
void *fast_buf = heap_caps_malloc(1024, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
//                                            L31 (1<<2)        L40 (1<<11)

// PSRAM 分配（慢但大，8MB，MALLOC_CAP_SPIRAM L39 = 1<<10）
void *large_buf = heap_caps_malloc(1024 * 1024, MALLOC_CAP_SPIRAM);

// 8bit 数据可 DMA 到 LCD / Camera（像素缓冲）
uint8_t *pixels = heap_caps_malloc(WIDTH * HEIGHT * 2, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);

// DMA 兼容（必须内部 RAM，MALLOC_CAP_DMA L32 = 1<<3）
uint8_t *dma_buf = heap_caps_malloc(4096, MALLOC_CAP_DMA);

// 释放（free(p) 也能，ESP-IDF free 就是 heap_caps_free）
heap_caps_free(fast_buf);   // esp_heap_caps.h L111
```

### 跨核共享内存

```c
// 在哪个核分配？
// 内部 RAM：任何核访问都很快（cache 一致性由硬件保证）
// PSRAM：任何核访问速度都慢（但容量大）

// 跨核写共享内存必须加自旋锁（读不用，只要写是原子的）
static portMUX_TYPE data_spinlock = portMUX_INITIALIZER_UNLOCKED;

portENTER_CRITICAL(&data_spinlock);
memcpy(shared_data, new_data, len);
portEXIT_CRITICAL(&data_spinlock);
```

## 6. ISR 跨核处理

### 哪个 ISR 在哪个核？

| 外设 | 运行核心 |
|------|----------|
| WiFi | 核心 0（PRO CPU）|
| BLE | 核心 0（PRO CPU）|
| 定时器中断 | 中断发生的核心（取决于定时器绑核） |
| GPIO 中断 | 由安装中断时的 core_id 参数决定（默认任意核） |
| UART 中断 | 由安装中断时的 core_id 参数决定 |

### 跨核 ISR 通知任务

```c
TaskHandle_t worker_task_handle = NULL;

// IRAM_ATTR 宏（已验证 esp_attr.h L23）强制函数放内部 RAM，PSRAM cache
// 关掉时也能执行（ISR 必须）
void IRAM_ATTR gpio_isr_handler(void *arg) {
    // 当前在某个核，调用 FreeRTOS FromISR API
    BaseType_t hpw = pdFALSE;
    vTaskNotifyGiveFromISR(worker_task_handle, &hpw);   // 已验证存在
    if (hpw == pdTRUE) portYIELD_FROM_ISR();
}

void worker_task(void *arg) {
    // 创建到核心 1
    while (1) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        // 处理（无论 ISR 来自哪个核，跨核通知 FreeRTOS SMP 已保证安全）
    }
}
```

## 7. 关键设计模式

### 模式 A：核心分工

```c
// 核心 0：通信任务（WiFi/蓝牙/网络）
// 核心 1：实时控制（电机/音频/PWM）

void app_main(void) {
    // 核心 0：系统任务（自动）
    // 用户任务
    xTaskCreatePinnedToCore(wifi_task, "wifi", 8192, NULL, 5, NULL, 0);
    xTaskCreatePinnedToCore(mqtt_task, "mqtt", 8192, NULL, 4, NULL, 0);

    // 核心 1：实时任务
    xTaskCreatePinnedToCore(motor_task, "motor", 4096, NULL, 10, NULL, 1);
    xTaskCreatePinnedToCore(audio_task, "audio", 8192, NULL, 8, NULL, 1);
}
```

### 模式 B：核心间生产者-消费者

```c
// 核心 0 采集传感器数据
// 核心 1 处理后上报

QueueHandle_t sensor_queue = NULL;

void core0_sensor_task(void *arg) {
    while (1) {
        sensor_data_t data = read_sensor();
        xQueueSend(sensor_queue, &data, portMAX_DELAY);
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

void core1_process_task(void *arg) {
    sensor_data_t data;
    while (1) {
        if (xQueueReceive(sensor_queue, &data, portMAX_DELAY) == pdTRUE) {
            processed_t result = process(data);
            upload_to_cloud(result);
        }
    }
}
```

### 模式 C：单例任务调度器

```c
// 某些操作必须在同一核心完成（如 I2C 设备实例）
portMUX_TYPE g_i2c_lock = portMUX_INITIALIZER_UNLOCKED;
TaskHandle_t g_i2c_task = NULL;

void i2c_request(i2c_op_t *op) {
    // 任何核调用此函数都会被串行化（自旋锁保证跨核互斥）
    portENTER_CRITICAL(&g_i2c_lock);
    perform_i2c_op(op);
    portEXIT_CRITICAL(&g_i2c_lock);
}
```

## 8. 常见错误与排查

| 错误 | 现象 | 解决方案 |
|------|------|----------|
| 跨核共享变量没保护 | 数据竞争、偶发崩溃、读到撕裂值 | 写用自旋锁/队列；读也要看数据宽度是否原子（>4 字节必须锁） |
| 自旋锁内调用阻塞 API | 另一个核 100% 卡死、中断全丢 | 临界区只做寄存器/内存读写 |
| 自旋锁递归调用 | 直接死锁（当前核心拿锁再拿 = 自己忙等自己） | 改为单层或用计数语义包装 |
| 跨核 ISR 访问未同步变量 | 数据损坏 | ISR 中用 FromISR API + portENTER_CRITICAL_ISR |
| 任务未绑定核心，性能差 | 高优先级任务在两个核间跳来跳去 cache miss | 用 Pinned 明确分工 |
| PSRAM 频繁小对象 malloc/free | 性能低 + 外部 RAM 碎片 | 内部 RAM 缓存小对象，大块放 PSRAM |
| 跨核 malloc 分配/释放 | 正常安全（heap_caps 内部已锁） | ✅ ESP-IDF heap_caps 线程/核安全，不用额外锁 |
| 任务优先级和核心亲和性冲突 | 调度异常 | 高优先级任务绑专用核心 |
| esp_pm_config_xtal_freq_t 未定义 | **编译直接失败** | **用 esp_pm_config_t（通用名）或 esp_pm_config_esp32s3_t（deprecated 别名）** |

## 9. 调试技巧

### 查看任务所在核心

```c
// xTaskGetAffinity = ESP-IDF 扩展（非 Vanilla FreeRTOS），需 #include "freertos/idf_additions.h"
void print_task_core(const char *task_name) {
    TaskHandle_t handle = xTaskGetHandle(task_name);  // INCLUDE_xTaskGetHandle=1，已开启
    if (handle) {
        BaseType_t core = xTaskGetAffinity(handle);    // idf_additions.h L639
        char *name = pcTaskGetName(handle);             // task.h L1452
        UBaseType_t prio = uxTaskPriorityGet(handle);   // INCLUDE_uxTaskPriorityGet=1，已开启
        printf("Task %s on core %d, prio %d\n", name, (int)core, (int)prio);
    }
}
```

### 监控跨核同步

```c
// 用性能计数器（拿锁计数，调试用）
static portMUX_TYPE perf_lock = portMUX_INITIALIZER_UNLOCKED;
static uint64_t core0_ticks = 0, core1_ticks = 0;

void record_core0_work(void) {
    portENTER_CRITICAL(&perf_lock);
    core0_ticks++;
    portEXIT_CRITICAL(&perf_lock);
}
```

### ESP-IDF 调试命令

```bash
# 在 monitor 中
> tasks
# 输出会显示任务所在核心（Core 列）

> heap
# 显示各区域 heap 使用情况
```

## 10. ESP32-S3 性能优化建议

### CPU 频率

```c
// 头文件 #include "esp_pm.h"
// 需要 CONFIG_PM_ENABLE=y（sdkconfig）
// esp_pm_config_t 结构体验证：esp_pm.h L22-L26

esp_pm_config_t pm_cfg = {
    .max_freq_mhz = 240,
    .min_freq_mhz = 80,
    .light_sleep_enable = false
};
esp_err_t err = esp_pm_configure(&pm_cfg);   // esp_pm.h L70
if (err != ESP_OK) { ESP_LOGE("PM", "esp_pm_configure failed: %s", esp_err_to_name(err)); }
```

### 内存优化

```c
// 启动时打印内存状态（heap_caps 已验证 esp_heap_caps.h L200/L216）
void print_mem_info(void) {
    printf("Internal: %u / %u bytes free\n",
           (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
           (unsigned)heap_caps_get_total_size(MALLOC_CAP_INTERNAL));
    printf("PSRAM:    %u / %u bytes free\n",
           (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM),
           (unsigned)heap_caps_get_total_size(MALLOC_CAP_SPIRAM));
}
```


## 完整双核示例与验证记录

> 完整双核示例（传感器采集 + 网络上报）与验证记录维护在 **同目录 reference.md**。

## 触发时机

- **ESP32-S3 项目需要分核优化** → 调用本技能
- **实时任务（电机/音频）需要独占核心** → 调用本技能
- **跨核数据共享** → 调用本技能
- **不触发**：单核 ESP32-C3、ESP8266；纯串口透传项目

## 相关技能

- [freertos-basics](../freertos-basics/SKILL.md)：FreeRTOS 基础 API
- [freertos-driver-integration](../freertos-driver-integration/SKILL.md)：驱动集成模式
- [esp32-panic-diagnosis](../esp32-panic-diagnosis/SKILL.md)：双核崩溃诊断
- [pin-check](../pin-check/SKILL.md)：本项目 ESP32-S3 设备信息
- [memory-leak-detection](../memory-leak-detection/SKILL.md)：heap_caps / PSRAM 监控

---

