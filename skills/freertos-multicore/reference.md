# FreeRTOS 双核编程 - 参考

> 本文件为 freertos-multicore 技能的完整示例与验证记录（自 SKILL.md 拆分）。

---

## 11. 完整双核示例：传感器采集 + 网络上报

```c
// app_main.c
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_log.h"

static const char *TAG = "DUAL_CORE";

typedef struct {
    float temperature;
    float humidity;
    uint32_t timestamp;
} sensor_data_t;

static QueueHandle_t sensor_queue = NULL;

// 核心 0：传感器采集（1ms 周期）
void sensor_task(void *arg) {
    ESP_LOGI(TAG, "Sensor task on core %d", (int)xPortGetCoreID());
    sensor_data_t data;
    while (1) {
        // 模拟读取传感器
        data.temperature = 25.0 + (esp_random() % 100) / 10.0;
        data.humidity = 60.0 + (esp_random() % 200) / 10.0;
        data.timestamp = xTaskGetTickCount();

        if (xQueueSend(sensor_queue, &data, pdMS_TO_TICKS(10)) != pdTRUE) {
            ESP_LOGE(TAG, "Queue full, dropping data");
        }
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

// 核心 1：网络上报（5s 周期 + 平均）
void network_task(void *arg) {
    ESP_LOGI(TAG, "Network task on core %d", (int)xPortGetCoreID());
    sensor_data_t data;
    float temp_sum = 0, hum_sum = 0;
    int count = 0;

    while (1) {
        // 阻塞等待传感器数据
        if (xQueueReceive(sensor_queue, &data, portMAX_DELAY) == pdTRUE) {
            temp_sum += data.temperature;
            hum_sum += data.humidity;
            count++;

            // 每 5 秒上报一次
            if (count >= 5) {
                ESP_LOGI(TAG, "Avg: T=%.1f H=%.1f (n=%d)",
                         temp_sum / count, hum_sum / count, count);
                // 调用网络上报 API
                // mqtt_publish(...)
                temp_sum = hum_sum = 0;
                count = 0;
            }
        }
    }
}

void app_main(void) {
    ESP_LOGI(TAG, "app_main on core %d", (int)xPortGetCoreID());

    // 创建跨核队列
    sensor_queue = xQueueCreate(10, sizeof(sensor_data_t));

    // 启动双核任务（栈大小 = 字节）
    xTaskCreatePinnedToCore(sensor_task, "sensor", 4096, NULL, 5, NULL, 0);
    xTaskCreatePinnedToCore(network_task, "network", 8192, NULL, 4, NULL, 1);
}
```

## 验证记录（v1.0.1 / ESP-IDF v5.5.4）

| 内容 | 验证结果 | 验证来源 |
|------|----------|----------|
| **esp_pm_config_xtal_freq_t 不存在，改 esp_pm_config_t** | **已修正（原 L402 编不过）** | esp_pm.h L22-L26；旧芯片别名 L32-L37 deprecated |
| 自旋锁规则："同一锁必须同一核"为错误规则 | **已修正（删除，改为跨核设计目的 + 不可递归）** | portMUX_TYPE 设计 + FreeRTOS SMP 文档 |
| PRO_CPU_NUM = 0，APP_CPU_NUM = 1 | 正确 | soc/esp32s3/include/soc/soc.h L17-L18 |
| xTaskCreatePinnedToCore 7 参数签名 | 正确 | task.h L382-L388 |
| xPortGetCoreID() 返回 BaseType_t | 正确 | xtensa portmacro.h L282-L285 |
| esp_cpu_get_core_id() 返回 int | 正确 | esp_hw_support/include/esp_cpu.h L128 |
| xTaskGetHandle / uxTaskPriorityGet 默认开启 | 正确 | FreeRTOSConfig.h L211/L218 均 =1 |
| xTaskGetAffinity(TaskHandle_t) 为 ESP-IDF 扩展 | 正确，补充头文件 | idf_additions.h L639（需 #include "freertos/idf_additions.h"） |
| pcTaskGetName(xTask) 存在 | 正确 | task.h L1452 |
| portMUX_TYPE = spinlock_t typedef | 正确 | xtensa portmacro.h L85 |
| portMUX_INITIALIZER_UNLOCKED 存在 | 正确 | xtensa portmacro.h L86 |
| portENTER_CRITICAL(&mux) / portEXIT_CRITICAL(&mux) SMP 下 VA_ARGS 宏 | 正确（带 mux 走 portENTER_CRITICAL_IDF） | xtensa portmacro.h L213-L219 |
| portENTER_CRITICAL_ISR / portEXIT_CRITICAL_ISR 宏存在 | 正确（= vPortEnterCriticalIDF / Exit） | xtensa portmacro.h L350-L351 |
| IRAM_ATTR 宏存在 | 正确（= _SECTION_ATTR_IMPL ".iram1"） | esp_common/include/esp_attr.h L23 |
| heap_caps_malloc / heap_caps_free | 正确 | heap/heap_caps.c L82 / heap_caps_base.c L64 |
| MALLOC_CAP_8BIT (1<<2) / DMA (1<<3) / SPIRAM (1<<10) / INTERNAL (1<<11) | 值全部正确 | esp_heap_caps.h L31-L40 |
| heap_caps_get_free_size / get_total_size | 正确 | esp_heap_caps.h L216/L200 |
| vTaskNotifyGiveFromISR / portYIELD_FROM_ISR | 正确（同 basics/driver-integration 已验证） | task.h L2430 / portmacro.h L227-L233 |
| esp_pm_configure 签名 + 结构体 3 字段（max/min MHz + light_sleep_enable） | 正确（原版本字段名都对，只有结构体名错） | esp_pm.h L22-L26, L70 |
