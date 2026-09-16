---
name: board-config
description: "板级配置管理：芯片型号/Flash/PSRAM/保留引脚/串口/调试器。切板/看配置/新建板配置时调用。"
version: 1.0.0
---

# 板级配置管理

## 适用场景

- 用户切换开发板（从 ESP32-S3 切到 GD32F407）
- 查看当前连接的板子硬件参数
- 新建一块开发板的配置文件
- 其他工具需要读取当前板子信息

## 核心概念

板级配置是整个工具体系的**中心抽象**。几乎所有工具（safe-flash、pin-check、debug-esp32、watch-board 等）都通过 `$env:CURRENT_BOARD` 环境变量读取当前板子配置。

### 配置文件位置

```
$env:USERPROFILE\Tools\board-config\
├── esp32-s3-wroom-1-n16r8.ps1
├── esp32-c3-wroom-02.ps1
├── esp32-wroom-32.ps1
├── gd32f407zgt6.ps1
├── stm32f407vet6.ps1
└── stc8h8k64u.ps1
```

### 配置结构（HashTable）

```powershell
@{
    Name = 'ESP32-S3-WROOM-1-N16R8'      # 板子名称
    Type = 'ESP32-S3'                     # 芯片类型
    FlashSize = '16MB'                    # Flash 容量
    PsramSize = '8MB'                     # PSRAM 容量（可选）
    CrystalFreq = '40MHz'                 # 晶振频率
    ReservedPins = @(26, 27, ...)         # 模组内部保留引脚
    ReservedDesc = @{ 26 = 'SPI Flash CLK' ... }  # 保留引脚说明
    AvailablePins = @(0, 1, 2, ...)       # 可用引脚
    DefaultUart = 'COM8'                  # 默认串口
    OpenOcdConfig = 'board/esp32s3-builtin.cfg'  # OpenOCD 配置
    GdbTarget = 'xtensa-esp32s3-elf-gdb.exe'     # GDB 目标
}
```

## 脚本位置

| 脚本 | 用途 |
|------|------|
| `$env:USERPROFILE\Tools\switch-board.ps1` | 切换/查看当前板子 |
| `$env:USERPROFILE\Tools\new-board-config.ps1` | 创建新板子配置 |
| `$env:USERPROFILE\Tools\watch-board.ps1` | USB 热插拔自动切换 |

## 使用方法

### 切换板子

```powershell
# 切换到 ESP32-S3
switch-board esp32-s3-wroom-1-n16r8

# 切换到 GD32
switch-board gd32f407zgt6

# 查看所有可用板子
switch-board -List

# 查看当前板子
switch-board -Current
```

### 创建新板子配置

```powershell
# 交互式创建
new-board-config

# 带参数创建
new-board-config -Name "my-board" -Type "ESP32-S3" -Flash "8MB" -Uart "COM5"
```

### 自动检测（热插拔）

```powershell
# 后台监控 USB 设备变化，自动切换板子
watch-board
```

## 状态持久化

当前板子名称保存在：
```
%LOCALAPPDATA%\trae-tools\current-board.txt
```

同时设置环境变量 `$env:CURRENT_BOARD`，所有工具通过此变量读取配置。

## 与其他技能的联动

| 工具 | 如何读取 board-config |
|------|----------------------|
| pin-check | 读取 ReservedPins、AvailablePins 做引脚检测 |
| safe-flash | 读取 Type、DefaultUart 做烧录前验证 |
| debug-esp32 | 读取 OpenOcdConfig、GdbTarget 启动调试 |
| esp-burn | 读取 DefaultUart 确定烧录串口 |
| esp-monitor | 读取 DefaultUart 确定监控串口 |
| hardware-detection | 读取 Type 确定检测方式 |

## 与 AI 的协作流程

当用户开始新的硬件项目或切换开发板时：

1. **查看可用板子**：
```powershell
switch-board -List
```

2. **切换板子**：
```powershell
switch-board <板子名>
```

3. **确认配置**：
```powershell
switch-board -Current
```

4. **后续工具自动使用**：编译、烧录、调试、引脚检测都会自动读取当前板子配置

## Pitfalls

- 切换板子后需要重新加载 ESP-IDF 环境（如果从 ESP32 切到 ARM 或反过来）
- board-config 的 `DefaultUart` 可能与实际串口号不同，用 `detect-chip` 确认
- 新建板子配置时 ReservedPins 需要根据模组型号查数据手册确认
- `$env:CURRENT_BOARD` 只在当前 PowerShell 会话中有效，重启后从文件恢复
- Keil 项目（GD32/STM32/STC8）的板子配置没有 OpenOcdConfig 和 GdbTarget 字段

## Verification

- `switch-board -Current` 显示正确的板子信息
- `$env:CURRENT_BOARD` 与状态文件内容一致
- pin-check 能正确读取当前板子的保留引脚

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| `board-config` 目录存在 | ✅ | `<USERPROFILE>\Tools\board-config\` |
| 6 个板子配置文件存在 | ✅ | esp32-s3/esp32-c3/esp32-wroom/gd32f407/stm32f407/stc8h8k64u |
| `switch-board.ps1` 脚本存在 | ✅ | `<USERPROFILE>\Tools\switch-board.ps1` |
| `new-board-config.ps1` 脚本存在 | ✅ | `<USERPROFILE>\Tools\new-board-config.ps1` |
| 配置结构字段（Name/Type/FlashSize/DefaultUart 等） | ✅ | `esp32-s3-wroom-1-n16r8.ps1` 实际内容 |
| ESP32-S3 配置：Flash=16MB, PSRAM=8MB, COM8 | ✅ | 与 user_profile 中设备信息一致 |
| ReservedPins = @(26-33, 11-17) | ✅ | `esp32-s3-wroom-1-n16r8.ps1` L7 |
| OpenOcdConfig = 'board/esp32s3-builtin.cfg' | ✅ | `esp32-s3-wroom-1-n16r8.ps1` L27 |
| GdbTarget = 'xtensa-esp32s3-elf-gdb.exe' | ✅ | `esp32-s3-wroom-1-n16r8.ps1` L28 |
| 注意：ReservedDesc 中 GPIO 26-33 标注为 "SPI Flash" | ⚠️ | 实际含 PSRAM 引脚，标签不够精确 |