---
name: live-debug-workflow
description: "ESP32 在线调试(OpenOCD+GDB)：断点/单步/查看变量。实时调试而非 panic 分析。"
version: 1.0.0
triggers:
  - "实时调试"
  - "断点调试"
  - "JTAG 调试"
  - "GDB 调试"
  - "单步执行"
  - "在线调试"
  - "live debug"
  - "断点"
---

# ESP32 在线调试工作流

> **验证来源**：所有命令和配置均来自 ESP-IDF v5.5.4 官方文档 `docs/en/api-guides/jtag-debugging/` 及 `tools/openocd-esp32/v0.12.0-esp32-20251215/` 实际 cfg 文件。

## 1. 前置条件

| 条件 | 说明 |
|------|------|
| 编译模式 | 项目必须以 `OPTIMIZE_LEVEL=O0` 或 `-Og` 编译，否则变量可能被优化掉 |
| 调试信息 | `CONFIG_COMPILER_DEBUG_OPTIMIZATION` 设为 `-Og`（menuconfig） |
| 看门狗 | 调试时建议关闭 Task Watchdog 或增大超时：`CONFIG_ESP_TASK_WDT_TIMEOUT_S=15` |
| OpenOCD | ESP-IDF 工具链自带，版本 v0.12.0-esp32-20251215 |
| GDB | `xtensa-esp32s3-elf-gdb`（ESP-IDF 工具链自带） |

## 2. ESP32-S3 JTAG 连接方式

### 方式 A：USB Serial JTAG（内置，推荐）

ESP32-S3 内置 USB JTAG 电路，仅需一根 USB 线。

| 引脚 | USB 信号 |
|------|----------|
| GPIO19 | D- |
| GPIO20 | D+ |
| 5V | V_BUS |
| GND | Ground |

> **Windows 驱动**：如遇 `LIBUSB_ERROR_NOT_FOUND`，需安装 Espressif WinUSB 驱动（ESP-IDF 安装器中勾选，或用 `idf-env driver install --espressif`）。

**OpenOCD 配置文件**（已验证存在于 `tools/openocd-esp32/.../scripts/board/`）：
```
board/esp32s3-builtin.cfg
```

### 方式 B：外部 JTAG（ESP-Prog / FT2232H）

**OpenOCD 配置文件**（已验证存在）：
```
board/esp32s3-ftdi.cfg
```

### 方式 C：JTAG 桥接

```
board/esp32s3-bridge.cfg
```

## 3. 调试启动流程

### 方式一：idf.py 一键启动（推荐）

```bash
# 终端 1：启动 OpenOCD
idf.py openocd

# 终端 2：启动 GDB（TUI 模式）
idf.py gdbtui

# 或一步到位：OpenOCD + GDB GUI + 串口监控
idf.py openocd gdbgui monitor
```

**idf.py 支持的调试命令**（来自官方文档 using-debugger.rst L209-L246）：

| 命令 | 说明 |
|------|------|
| `idf.py openocd` | 启动 OpenOCD，默认配置来自 `build/project_description.json` 的 `debug_arguments_openocd` |
| `idf.py gdb` | 启动 GDB（命令行模式） |
| `idf.py gdbtui` | 启动 GDB（TUI 源码视图模式） |
| `idf.py gdbgui` | 启动 GDB GUI（浏览器前端） |
| `idf.py openocd gdbgui monitor` | 组合：后台 OpenOCD + 浏览器 GDB + 串口监控 |

### 方式二：手动分步启动

```bash
# 步骤 1：启动 OpenOCD
openocd -f board/esp32s3-builtin.cfg

# 步骤 2：启动 GDB（来自官方文档 using-debugger.rst L168-L173）
xtensa-esp32s3-elf-gdb -q \
    -x build/gdbinit/symbols \
    -x build/gdbinit/prefix_map \
    -x build/gdbinit/connect \
    build/<project>.elf
```

**gdbinit 脚本说明**：
| 脚本 | 作用 |
|------|------|
| `build/gdbinit/symbols` | 加载 ELF 符号表（含 bootloader 和 ROM ELF） |
| `build/gdbinit/prefix_map` | 修正源码路径映射 |
| `build/gdbinit/connect` | 建立与目标设备的连接，在 `app_main()` 设临时断点 |

## 4. GDB 常用调试命令

### 断点管理

```gdb
# 设置断点
break main.c:42          # 在 main.c 第 42 行设断点
break app_main           # 在 app_main 函数入口设断点
break task_handler       # 在任务处理函数设断点

# 条件断点
break uart_event_task:50 if event.size > 100

# 临时断点（触发一次后自动删除）
tbreak init_peripheral

# 查看和删除断点
info breakpoints
delete 1                 # 删除 1 号断点
disable 2                # 禁用 2 号断点
enable 2                 # 启用 2 号断点
```

### 执行控制

```gdb
continue                 # 继续运行
step                     # 单步进入（进入函数内部）
next                     # 单步跳过（不进入函数）
finish                   # 执行到当前函数返回
until 55                 # 执行到第 55 行
```

### 查看变量和内存

```gdb
# 打印变量
print rx_buffer          # 打印变量值
print/x status           # 十六进制打印
print buf[0]@10          # 打印 buf[0] 到 buf[9]

# 查看内存
x/10bx 0x3FFB0000       # 查看内存地址（10 个字节，十六进制）

# 查看寄存器
info registers           # 查看所有寄存器
print $pc                # 查看程序计数器

# 查看调用栈
backtrace                # 或简写 bt
backtrace full           # 含局部变量的调用栈

# 查看线程/任务
info threads             # 查看所有 FreeRTOS 任务
thread 2                 # 切换到任务 2
```

### 观察点（硬件资源有限，通常仅 2 个）

```gdb
watch global_flag        # 写观察点：变量被修改时暂停
rwatch rx_count          # 读观察点
awatch state_var         # 读/写观察点
```

## 5. ESP32-S3 双核调试

ESP32-S3 有两个 CPU 核心，GDB 支持切换：

```gdb
info threads             # 查看两个核心的任务
thread apply all backtrace  # 所有线程的调用栈
```

**注意事项**：
- OpenOCD 对双核断点有数量限制（每核约 2 个硬件断点）
- 优先用软件断点（`break`），硬件断点（`hbreak`）仅用于 Flash 中的代码
- 调试时两个核心都会暂停

## 6. 常见问题排查

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `LIBUSB_ERROR_NOT_FOUND` | Windows 缺 USB 驱动 | 安装 Espressif WinUSB 驱动 |
| JTAG `...all ones/zeroes` | JTAG 连接问题 | 检查 USB 线、确认引脚无冲突、检查供电 |
| `Cannot read register` | OpenOCD 未连上目标 | 重启 OpenOCD，确认 cfg 文件正确 |
| 变量被优化掉 | 编译优化级别太高 | menuconfig 设 `CONFIG_COMPILER_DEBUG_OPTIMIZATION=-Og` |
| 看门狗复位 | 调试暂停触发看门狗 | 增大 `CONFIG_ESP_TASK_WDT_TIMEOUT_S` 或关闭看门狗 |
| 找不到源码 | 路径映射问题 | 检查 `build/gdbinit/prefix_map` 是否正确 |

## 7. 与其他技能配合

| 技能 | 场景 |
|------|------|
| esp32-panic-diagnosis | 崩溃后先分析 backtrace，再决定是否需要实时调试 |
| esp32-live-debug | 此技能是 esp32-live-debug 的详细工作流扩展 |
| freertos-basics | 调试 FreeRTOS 任务时配合使用 |
| freertos-multicore | 双核调试时查看任务核心亲和性 |

## 8. 验证记录

| 内容 | 验证来源 | 状态 |
|------|----------|------|
| OpenOCD cfg 文件 | `tools/openocd-esp32/v0.12.0-esp32-20251215/.../scripts/board/` 实际读取 | ✅ 已验证 |
| esp32s3-builtin.cfg | 实际读取，内容为 `source [find interface/esp_usb_jtag.cfg]` + `source [find target/esp32s3.cfg]` | ✅ 已验证 |
| esp32s3-ftdi.cfg | 实际读取，内容为 `source [find interface/ftdi/esp_ftdi.cfg]` + `source [find target/esp32s3.cfg]` | ✅ 已验证 |
| idf.py 调试命令 | `docs/en/api-guides/jtag-debugging/using-debugger.rst` L209-L246 | ✅ 已验证 |
| GDB 启动命令 | `docs/en/api-guides/jtag-debugging/using-debugger.rst` L168-L173 | ✅ 已验证 |
| ESP32-S3 USB JTAG 引脚 | `docs/en/api-guides/jtag-debugging/configure-builtin-jtag.rst` L11-L12 | ✅ 已验证 |
