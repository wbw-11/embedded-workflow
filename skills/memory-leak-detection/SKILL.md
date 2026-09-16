---
name: memory-leak-detection
description: "ESP32 内存泄漏/堆耗尽检测：heap_caps 监控水位/追踪泄漏/查堆完整性。运行后死机、内存下降时调用。"
version: 1.0.0
triggers:
  - "内存泄漏"
  - "内存不足"
  - "堆溢出"
  - "OOM"
  - "out of memory"
  - "内存水位"
  - "heap"
  - "内存耗尽"
  - "内存检测"
---

# ESP32 内存泄漏与堆耗尽检测

> **验证来源**：所有 API 签名和常量均来自 ESP-IDF v5.5.4 实际头文件 `components/heap/include/esp_heap_caps.h` 和 `components/heap/include/esp_heap_trace.h`，FreeRTOS API 来自 `components/freertos/FreeRTOS-Kernel/include/freertos/task.h`。

## 1. ESP32 内存架构

ESP32-S3 有两类内存区域：

| 区域 | 容量 | 能力标志 | 用途 |
|------|------|----------|------|
| 内部 DRAM | 约 390KB | MALLOC_CAP_INTERNAL \| MALLOC_CAP_8BIT \| MALLOC_CAP_DMA | 关键数据、DMA 缓冲区 |
| PSRAM (SPIRAM) | 8MB | MALLOC_CAP_SPIRAM \| MALLOC_CAP_8BIT | 大缓冲区（图像/音频） |

## 2. MALLOC_CAP 能力标志

> 来源：`esp_heap_caps.h` L29-L51

```c
#define MALLOC_CAP_EXEC             (1<<0)  // 可执行代码
#define MALLOC_CAP_32BIT            (1<<1)  // 32 位对齐访问
#define MALLOC_CAP_8BIT             (1<<2)  // 8/16 位访问
#define MALLOC_CAP_DMA              (1<<3)  // DMA 可访问
#define MALLOC_CAP_SPIRAM           (1<<10) // 必须在 PSRAM
#define MALLOC_CAP_INTERNAL         (1<<11) // 必须在内部 RAM
#define MALLOC_CAP_DEFAULT          (1<<12) // malloc()/calloc() 可返回
#define MALLOC_CAP_IRAM_8BIT        (1<<13) // IRAM 中且允许非对齐访问
```

## 3. 堆状态查询 API

> 来源：`esp_heap_caps.h` L200-L436，所有函数签名已逐行对照

### 3.1 基础查询

```c
/* 获取指定能力堆的总空闲大小（字节）
 * 来源：esp_heap_caps.h L216 */
size_t heap_caps_get_free_size(uint32_t caps);

/* 获取指定能力堆的最大可分配连续块大小（字节）
 * 来源：esp_heap_caps.h L246 */
size_t heap_caps_get_largest_free_block(uint32_t caps);

/* 获取指定能力堆的历史最低空闲内存（字节）——水位线
 * 来源：esp_heap_caps.h L234 */
size_t heap_caps_get_minimum_free_size(uint32_t caps);

/* 获取指定能力堆的总大小（字节）
 * 来源：esp_heap_caps.h L200 */
size_t heap_caps_get_total_size(uint32_t caps);
```

### 3.2 详细信息

```c
/* 获取堆聚合信息（含 total/free/minimum_free/allocated_blocks/free_blocks 等）
 * 来源：esp_heap_caps.h L283 */
void heap_caps_get_info(multi_heap_info_t *info, uint32_t caps);

/* 打印指定能力堆的摘要信息（两行格式）
 * 来源：esp_heap_caps.h L296 */
void heap_caps_print_heap_info(uint32_t caps);

/* 输出匹配堆的完整结构（每个块地址/大小/下一块指针）
 * 来源：esp_heap_caps.h L426 */
void heap_caps_dump(uint32_t caps);

/* 输出所有堆的完整结构
 * 来源：esp_heap_caps.h L436 */
void heap_caps_dump_all(void);
```

### 3.3 局部水位监控

```c
/* 从此刻开始监控最低空闲内存（而非从启动开始）
 * 来源：esp_heap_caps.h L258 */
esp_err_t heap_caps_monitor_local_minimum_free_size_start(void);

/* 停止局部监控，恢复到从启动开始的全局水位
 * 来源：esp_heap_caps.h L268 */
esp_err_t heap_caps_monitor_local_minimum_free_size_stop(void);
```

### 3.4 堆完整性检查

```c
/* 检查指定能力堆的完整性
 * 来源：esp_heap_caps.h L334 */
bool heap_caps_check_integrity(uint32_t caps, bool print_errors);

/* 检查所有堆的完整性
 * 来源：esp_heap_caps.h L313 */
bool heap_caps_check_integrity_all(bool print_errors);

/* 检查包含指定地址的堆区域的完整性
 * 来源：esp_heap_caps.h L357 */
bool heap_caps_check_integrity_addr(intptr_t addr, bool print_errors);

/* 获取指定指针的分配大小
 * 来源：esp_heap_caps.h L449 */
size_t heap_caps_get_allocated_size(void *ptr);
```

> **注意**：PSRAM 启用时，完整性检查耗时较长，需增大 `CONFIG_ESP_INT_WDT_TIMEOUT_MS`。

## 4. 堆追踪 API（内存泄漏检测核心工具）

> 来源：`esp_heap_trace.h` L22-L197，所有函数签名已逐行对照

### 4.1 追踪模式

```c
/* 来源：esp_heap_trace.h L22-L25 */
typedef enum {
    HEAP_TRACE_ALL,    // 追踪所有分配和释放
    HEAP_TRACE_LEAKS,  // 仅追踪疑似泄漏（释放时移除记录）
} heap_trace_mode_t;
```

### 4.2 追踪记录结构

```c
/* 来源：esp_heap_trace.h L30-L43 */
typedef struct heap_trace_record_t {
    uint32_t ccount;    // 分配时的 CPU CCOUNT（LSB 为 CPU 编号）
    void *address;      // 分配地址（NULL 表示空记录）
    size_t size;        // 分配大小
    bool freed;         // 是否已释放
    void *alloced_by[CONFIG_HEAP_TRACING_STACK_DEPTH]; // 分配调用栈
    void *freed_by[CONFIG_HEAP_TRACING_STACK_DEPTH];   // 释放调用栈
} heap_trace_record_t;
```

### 4.3 追踪摘要

```c
/* 来源：esp_heap_trace.h L48-L60 */
typedef struct {
    heap_trace_mode_t mode;     // 追踪模式
    size_t total_allocations;   // 总分配次数
    size_t total_frees;         // 总释放次数
    size_t count;               // 当前记录数
    size_t capacity;            // 缓冲区容量
    size_t high_water_mark;     // 记录数峰值
    size_t has_overflowed;      // 缓冲区是否溢出
} heap_trace_summary_t;
```

### 4.4 追踪控制 API

```c
/* 初始化 standalone 模式追踪
 * 来源：esp_heap_trace.h L77 */
esp_err_t heap_trace_init_standalone(heap_trace_record_t *record_buffer, size_t num_records);

/* 初始化 host-based 模式追踪
 * 来源：esp_heap_trace.h L88 */
esp_err_t heap_trace_init_tohost(void);

/* 启动堆追踪
 * 来源：esp_heap_trace.h L105 */
esp_err_t heap_trace_start(heap_trace_mode_t mode);

/* 停止堆追踪
 * 来源：esp_heap_trace.h L115 */
esp_err_t heap_trace_stop(void);

/* 暂停分配追踪（释放仍记录）
 * 来源：esp_heap_trace.h L130 */
esp_err_t heap_trace_alloc_pause(void);

/* 恢复分配追踪
 * 来源：esp_heap_trace.h L146 */
esp_err_t heap_trace_resume(void);

/* 获取当前记录数
 * 来源：esp_heap_trace.h L153 */
size_t heap_trace_get_count(void);

/* 获取指定索引的记录
 * 来源：esp_heap_trace.h L170 */
esp_err_t heap_trace_get(size_t index, heap_trace_record_t *record);

/* 输出追踪记录到 stdout
 * 来源：esp_heap_trace.h L179 */
void heap_trace_dump(void);

/* 输出指定能力内存的追踪记录
 * 来源：esp_heap_trace.h L189 */
void heap_trace_dump_caps(const uint32_t caps);

/* 获取追踪摘要
 * 来源：esp_heap_trace.h L196 */
esp_err_t heap_trace_summary(heap_trace_summary_t *summary);
```

## 5. 任务栈水位检测

> 来源：`freertos/FreeRTOS-Kernel/include/freertos/task.h` L1513, L1538

```c
/* 获取任务栈的高水位线（单位：字，即字节/4）
 * 来源：task.h L1513
 * INCLUDE_uxTaskGetStackHighWaterMark = 1（FreeRTOSConfig.h L219） */
UBaseType_t uxTaskGetStackHighWaterMark(TaskHandle_t xTask);

/* 获取任务栈的高水位线（单位：字节）
 * 来源：task.h L1538
 * INCLUDE_uxTaskGetStackHighWaterMark2 = 1（xtensa FreeRTOSConfig_arch.h L103） */
configSTACK_DEPTH_TYPE uxTaskGetStackHighWaterMark2(TaskHandle_t xTask);
```

> **注意**：`uxTaskGetStackHighWaterMark` 返回的是**字数**（ESP32 上 1 字 = 4 字节），`uxTaskGetStackHighWaterMark2` 返回**字节数**。推荐使用 `uxTaskGetStackHighWaterMark2`。

## 6. 实战使用模式

### 模式一：周期性内存水位打印（快速排查）

```c
#include "esp_heap_caps.h"
#include "freertos/task.h"

/* 内存监控任务 */
void memory_monitor_task(void *pvParameters)
{
	while (1) {
		ESP_LOGI("MEM", "内堆 free: %u, 最大块: %u, 水位: %u",
			heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
			heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL),
			heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL));

		ESP_LOGI("MEM", "PSRAM free: %u, 最大块: %u, 水位: %u",
			heap_caps_get_free_size(MALLOC_CAP_SPIRAM),
			heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM),
			heap_caps_get_minimum_free_size(MALLOC_CAP_SPIRAM));

		vTaskDelay(pdMS_TO_TICKS(5000));
	}
}
```

### 模式二：堆追踪检测泄漏（精确定位）

**menuconfig 配置**：
```
Component Config → Heap Memory Debugging → Comprehensive
Component Config → Heap Memory Debugging → Record allocation call stack（设深度 4-8）
```

```c
#include "esp_heap_trace.h"

#define TRACE_RECORDS  100

static heap_trace_record_t s_trace_record[TRACE_RECORDS];

void test_memory_leak(void)
{
	/* 1. 初始化追踪 */
	ESP_ERROR_CHECK(heap_trace_init_standalone(s_trace_record, TRACE_RECORD));

	/* 2. 开始追踪（仅记录泄漏） */
	ESP_ERROR_CHECK(heap_trace_start(HEAP_TRACE_LEAKS));

	/* 3. 执行被测功能 */
	suspect_function();

	/* 4. 停止追踪 */
	ESP_ERROR_CHECK(heap_trace_stop());

	/* 5. 输出结果 */
	heap_trace_dump();

	/* 6. 获取摘要 */
	heap_trace_summary_t summary;
	heap_trace_summary(&summary);
	ESP_LOGI("LEAK", "分配: %u, 释放: %u, 未释放: %u",
		summary.total_allocations, summary.total_frees, summary.count);
}
```

### 模式三：任务栈溢出检测

```c
#include "freertos/task.h"

void check_task_stack(TaskHandle_t task_handle, const char *name)
{
	/* 使用 uxTaskGetStackHighWaterMark2 获取字节数 */
	configSTACK_DEPTH_TYPE hwm = uxTaskGetStackHighWaterMark2(task_handle);
	ESP_LOGI("STACK", "任务 [%s] 栈剩余: %u 字节", name, hwm);
	if (hwm < 256) {
		ESP_LOGW("STACK", "任务 [%s] 栈空间不足！剩余 < 256 字节", name);
	}
}
```

### 模式四：堆完整性检查

```c
#include "esp_heap_caps.h"

void periodic_heap_check(void)
{
	/* 检查所有堆 */
	if (!heap_caps_check_integrity_all(true)) {
		ESP_LOGE("HEAP", "堆损坏！");
	}

	/* 仅检查内部堆 */
	if (!heap_caps_check_integrity(MALLOC_CAP_INTERNAL, true)) {
		ESP_LOGE("HEAP", "内部堆损坏！");
	}
}
```

### 模式五：局部水位监控（定位特定操作导致的内存下降）

```c
void monitor_specific_operation(void)
{
	/* 从此刻开始记录最低水位 */
	heap_caps_monitor_local_minimum_free_size_start();

	/* 执行可疑操作 */
	suspect_operation();

	/* 查看此期间的最低水位 */
	size_t local_min = heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL);
	ESP_LOGI("MEM", "操作期间内堆最低: %u 字节", local_min);

	/* 恢复全局水位监控 */
	heap_caps_monitor_local_minimum_free_size_stop();
}
```

## 7. 诊断决策树

```
内存问题
├── OOM 崩溃（malloc 返回 NULL）
│   ├── heap_caps_get_free_size() 持续下降 → 内存泄漏 → 用模式二追踪
│   ├── heap_caps_get_largest_free_block() 远小于 free_size → 碎片化 → 考虑 psram
│   └── 总内存就不够 → 增大 PSRAM 分配或优化数据结构
│
├── 堆损坏（heap_caps_check_integrity 返回 false）
│   ├── 数组越界写入 → 用 heap_caps_check_integrity_addr 定位
│   ├── 使用已释放指针（use-after-free）→ 开启 heap poisoning
│   └── 多线程竞争 → 检查是否有无锁共享堆操作
│
├── 栈溢出（uxTaskGetStackHighWaterMark2 < 256）
│   ├── 增大任务栈（xTaskCreate 的 stackSize 参数）
│   └── 减少栈上大数组 → 改为堆分配
│
└── 运行缓慢/卡顿
    ├── 频繁 malloc/free → 考虑内存池或静态分配
    └── PSRAM 访问慢 → 热数据放内部 RAM，冷数据放 PSRAM
```

## 8. menuconfig 关键配置

| 配置项 | 路径 | 调试值 | 生产值 |
|--------|------|--------|--------|
| 堆调试级别 | Component Config → Heap Memory Debugging | Comprehensive | Basic |
| 追踪调用栈深度 | Component Config → Heap Tracing | 4-8 | 0 |
| 堆中毒 | Component Config → Heap Poisoning | Light / Full | Disable |
| 看门狗超时 | Component Config → Task WDT | 15s | 5s |

## 9. 与其他技能配合

| 技能 | 场景 |
|------|------|
| esp32-panic-diagnosis | OOM 导致的 abort/assert 崩溃分析 |
| live-debug-workflow | 在 GDB 中实时查看内存变量 |
| freertos-basics | 任务栈配置和创建 |
| freertos-driver-integration | DMA 缓冲区分配策略（内部 vs PSRAM） |

## 10. 验证记录

| 内容 | 验证来源 | 状态 |
|------|----------|------|
| MALLOC_CAP_* 常量（17 个） | `esp_heap_caps.h` L29-L51 实际读取 | ✅ 已验证 |
| heap_caps_get_free_size 签名 | `esp_heap_caps.h` L216 | ✅ 已验证 |
| heap_caps_get_largest_free_block 签名 | `esp_heap_caps.h` L246 | ✅ 已验证 |
| heap_caps_get_minimum_free_size 签名 | `esp_heap_caps.h` L234 | ✅ 已验证 |
| heap_caps_print_heap_info 签名 | `esp_heap_caps.h` L296 | ✅ 已验证 |
| heap_caps_dump 签名 | `esp_heap_caps.h` L426 | ✅ 已验证 |
| heap_caps_dump_all 签名 | `esp_heap_caps.h` L436 | ✅ 已验证 |
| heap_caps_check_integrity 签名 | `esp_heap_caps.h` L334 | ✅ 已验证 |
| heap_caps_check_integrity_all 签名 | `esp_heap_caps.h` L313 | ✅ 已验证 |
| heap_caps_check_integrity_addr 签名 | `esp_heap_caps.h` L357 | ✅ 已验证 |
| heap_caps_get_allocated_size 签名 | `esp_heap_caps.h` L449 | ✅ 已验证 |
| heap_caps_monitor_local_minimum_free_size_start 签名 | `esp_heap_caps.h` L258 | ✅ 已验证 |
| heap_caps_monitor_local_minimum_free_size_stop 签名 | `esp_heap_caps.h` L268 | ✅ 已验证 |
| heap_trace_mode_t 枚举 | `esp_heap_trace.h` L22-L25 | ✅ 已验证 |
| heap_trace_init_standalone 签名 | `esp_heap_trace.h` L77 | ✅ 已验证 |
| heap_trace_start/stop 签名 | `esp_heap_trace.h` L105, L115 | ✅ 已验证 |
| heap_trace_dump/dump_caps 签名 | `esp_heap_trace.h` L179, L189 | ✅ 已验证 |
| heap_trace_summary 签名 | `esp_heap_trace.h` L196 | ✅ 已验证 |
| uxTaskGetStackHighWaterMark 签名 | `task.h` L1513 | ✅ 已验证 |
| uxTaskGetStackHighWaterMark2 签名 | `task.h` L1538 | ✅ 已验证 |
| INCLUDE_uxTaskGetStackHighWaterMark = 1 | `FreeRTOSConfig.h` L219 | ✅ 已验证 |
| INCLUDE_uxTaskGetStackHighWaterMark2 = 1 (xtensa) | `FreeRTOSConfig_arch.h` L103 | ✅ 已验证 |
