# ESP32 / Xtensa 系列规则（L2 芯片系列层）

> 适用范围：ESP32、ESP32-S3（Xtensa LX7）；ESP32-C3 为 RISC-V 内核但工具链/框架相同，内核差异见下方注意事项。型号级约束以各项目 `project_memory.md`（L3）为准。

## 工具链

- 开发框架：ESP-IDF（动态检测路径，优先环境变量 `ESP_IDF_ROOT` → 候选路径列表；当前验证版本 v5.5.4，路径 D:\ESP32\Espressif\frameworks\esp-idf-v5.5.4）
- 环境：`esp-idf-env.ps1`（自动检测 Python 虚拟环境），进入项目目录自动加载
- 构建/烧录/监控：`idf.py build/flash/monitor`，或 `esp-burn` / `esp-monitor` 脚本
- 检测：`esptool`（新项目必须先检测确认芯片型号/Flash/PSRAM）
- 版本归档：编译通过后自动复制 `bin + elf + map` 到 `<项目根>/Firmware_Build/Vxx/`，命名 `<芯片>_Vxx.<后缀>`（如 ESP32S3_V08.bin）。**目录名允许 VM/项目前缀（如 VM_V7_0）；含点号的目录名用下划线规避 PowerShell `md` 点号目录坑**（2026-09-01 Voice_motor 归档验证）。详细规则见 user_profile「固件版本管理」章节（L1 强制，全局通用）

## 时钟

- 时钟树由 IDF 自动配置（40MHz 晶振 → PLL），一般无需手动改时钟宏
- 低功耗/深度睡眠时注意时钟源切换与唤醒源配置

## 中断（FreeRTOS）

- 基于 FreeRTOS，任务调度而非裸机前后台
- ISR 中避免耗时操作，用队列/信号量/任务通知与任务通信
- 多核（ESP32-S3 双核）需考虑任务核心亲和性、跨核通信（队列/信号量/自旋锁）

## 内存

- 堆管理：`heap_caps_malloc` 等 API，可指定内部/PSRAM
- 长运行注意内存泄漏：用 heap_caps API 监控内存水位（见 memory-leak-detection）
- NVS / flash 分区表：NVS 有写入寿命，频繁写请用磨损均衡方案

## 寄存器与 API

- **优先用 IDF API**（`gpio_config`、`uart_driver_install` 等），避免直接操作寄存器
- API 名以 ESP-IDF v5.x 头文件为准（`driver/gpio.h`、`driver/uart.h` 等）
- 引脚分配用 `pin-check` 检查冲突（模组内部保留引脚如 Flash/PSRAM 不可用）

## 系列踩坑

- ESP32-C3 是 RISC-V 内核，不是 Xtensa，裸机汇编/特殊指令不通用
- 双核 FreeRTOS：关键代码跨核需自旋锁，ISR 跨核通信有专门模式
- WiFi/BT 开启后功耗显著上升，低功耗项目需合理休眠
- 新项目启动前必须 esptool 检测芯片型号，与声明型号对比
- **通用驱动防坑规则**（底层优先验证 / 官方例程基线对照 / 不改官方库源码 / 3 版本止损红线）见 user_profile.md「嵌入式驱动开发防坑规则」章节（L1 全局强制，对 ESP-IDF 组件同样适用）

## 与 L3 的关系

- 型号级约束（引脚表、特定外设配置）在对应项目 `project_memory.md`
- L3 与本文冲突时以 L3 为准

## 项目目录结构（2026-08-27 用户指定，L2 强制）
- ESP-IDF 项目**必须遵循官方结构**：main\\（应用 ≈ User）、components\\（自定义组件/驱动 ≈ Library+bsp）、CMakeLists.txt、sdkconfig、partitions 等
- 六目录仅作内容归位映射，另建 **Doc\\**（项目文档）、**Hardware\\**（板级信息）、**Firmware_Build\\**（bin/elf/map + 快照）、**Logs\\**
- **禁止把 IDF 项目改成 Keil 式六目录物理形状**（构建系统不识别）
- 完整标准见 user_profile「新项目目录结构标准」（L1）

## ESP32 音频播放/ES8311 出声三件套（2026-09-01 voice_motor V7.0 实锤）

> 适用：ESP32 + ES8311 codec 播放无声/音效没声音。按顺序检查，缺一不可。

1. **REG44 出厂默认回环**：ES8311 复位默认 REG44=0x58（含 DAC→ADC 内部回环 bit6=0x40），组件 open 不改 → DAC 输出被回环、喇叭功放收不到。`codec open 后必须 esp_codec_dev_write_reg(0x44, reg & ~0x40)` 清成 0x18，播放内幂等保底。
2. **PA_EN/EN 引脚语义**：原理图 PA_EN=GPIO3 → ES8311 EN，**active high（+5V 上拉）恒高常开**（拉低会关掉整个 codec，采集/唤醒全废）；组件 `es8311_cfg.pa_pin 必须=-1`（组件会配成开漏 OD 破坏 EN 电平）；静音/播放用 REG31 out_mute（esp_codec_dev_set_out_mute 只写 REG31，不碰 GPIO——已看源码确认）。
3. **音效合成用查表**：动态 `sinf()` 浮点合成链路曾实测输出恒零（PSRAM/普通 malloc 均如此）→ 用 **256 点静态正弦表(sine_lut.h) + 整数相位步进** 合成（sine_lut 见 voice_motor 归档 Firmware_Build/VM_V7_0/）。
4. **排查工具**：play/生成数据 `max|x|` 双探针（gen max/play max）一次定位数据源；mic 检到 880Hz 可能是板内电耦合假信号，须人耳/万用表交叉确认。