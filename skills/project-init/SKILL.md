---
name: project-init
description: "嵌入式项目脚手架：按芯片自动生成 main.c/CMakeLists/Makefile。新项目、新建工程时调用。"
install_method: upload
version: 1.0.0
---

## 概述

项目脚手架 Skill 的作用是根据芯片型号和开发方式，自动生成项目骨架代码，避免从零开始。无论是 ESP32 ESP-IDF 项目、Keil ARM 项目（GD32/STM32）还是 Keil C51 项目（STC8/8051），都能快速生成标准目录结构和模板文件，让开发者专注于业务逻辑实现，减少重复性脚手架工作。

## 支持的项目类型

### ESP32 ESP-IDF 项目

- 目录结构：main/、components/、CMakeLists.txt、sdkconfig.defaults
- 生成文件：main/main.c、main/CMakeLists.txt、根 CMakeLists.txt、README.md
- 模板内容：app_main() 入口、基础日志输出、WiFi 初始化模板（可选）

### Keil ARM 项目（GD32/STM32）

- 目录结构：Firmware/、User/、Listing/、Project/
- 生成文件：User/main.c、User/main.h、Firmware/（用户复制库文件）
- 模板内容：时钟配置、GPIO 初始化、while(1) 主循环
- 注意：.uvprojx 工程文件由用户在 Keil IDE 中创建

### Keil C51 项目（STC8/8051）

- 目录结构：User/、Listing/、Output/
- 生成文件：User/main.c、User/main.h、User/config.h
- 模板内容：时钟配置、GPIO 初始化、while(1) 主循环
- 注意：.uvproj 工程文件由用户在 Keil IDE 中创建

## 使用流程

1. 确认芯片型号和开发方式（参考 user_profile.md 的新项目信息收集）
2. 选择对应模板
3. 询问用户目标目录（默认 `$env:USERPROFILE\Desktop\<芯片型号>\`）
4. 生成项目骨架
5. 给出后续操作建议（如安装 DFP、配置 Keil 工程等）

## 代码规范

- 所有生成的代码遵循 user_profile.md 中的代码风格偏好
- Tab 缩进、大括号不省略、下划线命名、模块前缀
- 中文注释、文件编码 UTF-8

## ESP-IDF 项目模板示例

main.c 最小骨架代码：

```c
#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_system.h"

static const char *TAG = "main";

void app_main(void)
{
	ESP_LOGI(TAG, "项目启动");
	ESP_LOGI(TAG, "IDF 版本: %s", esp_get_idf_version());

	while (1) {
		vTaskDelay(pdMS_TO_TICKS(1000));
	}
}
```

## Keil ARM 项目模板示例

main.c 最小骨架代码：

```c
#include "main.h"

int main(void)
{
	/* 系统初始化 */
	SystemInit();

	/* 时钟配置 */
	// RCC_Configuration();

	/* GPIO 初始化 */
	// GPIO_Configuration();

	/* 主循环 */
	while (1) {
		/* 用户代码 */
	}
}
```

## Keil C51 项目模板示例

main.c 最小骨架代码：

```c
#include "config.h"
#include "main.h"

void main(void)
{
	/* 系统初始化 */
	// System_Init();

	/* 时钟配置 */
	// CLK_Configuration();

	/* GPIO 初始化 */
	// GPIO_Configuration();

	/* 开启总中断 */
	EA = 1;

	/* 主循环 */
	while (1) {
		/* 用户代码 */
	}
}
```

## 验证

- 生成后告知用户文件列表
- 提示用户需要在 Keil IDE 中创建工程文件（如 .uvprojx）
- ESP-IDF 项目可立即 `idf.py build` 验证

## 联动工具

项目创建后，推荐使用以下工具继续完善：

| 工具 | 用途 | 调用时机 |
|------|------|----------|
| `project-stats` 技能 | 统计代码行数、注释率、模块分布 | 项目开发中期/末期了解项目规模 |
| `pin-check` 技能 | GPIO 引脚冲突检测与分配管理 | 开始分配引脚时检查可用性 |
| `board-config` 技能 | 切换和管理板子配置 | 新建项目时切换到对应开发板 |
| `$env:USERPROFILE\Tools\switch-board.ps1` | 切换当前板子配置 | 项目初始化前确认目标硬件 |

```powershell
# 项目初始化后的推荐流程
& "$env:USERPROFILE\Tools\switch-board.ps1" esp32-s3-wroom-1-n16r8   # 1. 切换到目标板子
# （使用 project-init 技能创建项目骨架）                                  # 2. 生成项目
# （使用 pin-check 技能分配引脚）                                        # 3. 引脚规划
project-stats                                                            # 4. 了解项目规模
```

