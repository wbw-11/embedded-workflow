---
name: pin-check
description: "GPIO 引脚冲突检测与分配：新外设分配/查占用/改配置。引脚表从 board-config 加载。"
version: 2.0.0
---

# GPIO 引脚冲突检测

## 适用场景

- 用户要为新外设选引脚，问"GPIO X 能不能用"
- 用户修改了引脚分配，需要检查冲突
- 用户问"还有哪些引脚可用"
- 编写驱动代码时确认引脚分配

## 脚本位置

`$env:USERPROFILE\Tools\pin-check.ps1`

## 前置条件

脚本从 board-config 动态加载引脚保留表，使用前必须确保已切换到正确的板子：

```powershell
# 查看可用板子
switch-board -List

# 切换到 ESP32-S3
switch-board esp32-s3-wroom-1-n16r8
```

如果未配置板子，脚本会提示并退出。

## 使用方法

### 检查单个引脚

```powershell
pin-check -Pin 18        # 检查 GPIO18 是否可用
```

输出状态：
- `[OK]` 绿色 → 可安全使用
- `[!]` 黄色 → 已分配给其他功能，可能冲突
- `[X]` 红色 → 模组内部占用（SPI Flash/PSRAM），绝对不可用

### 列出所有引脚状态

```powershell
pin-check -List
```

输出三个分类：
1. 已占用（模组内部，绝对不可用）：从 board-config 动态加载
2. 已分配（项目使用中）：从 project_memory.md 加载
3. 可使用：未分配的可用引脚

### 分配引脚并同步更新

```powershell
pin-check -Allocate 18 "LED控制" -AutoUpdate
```

`-AutoUpdate` 会自动更新 `project_memory.md` 的引脚分配表。

### 去除重复记录

```powershell
pin-check -Dedup
```

## 引脚数据来源（三层优先级）

1. **board-config**（权威来源）：模组保留引脚（ReservedPins/ReservedDesc/AvailablePins），通过 `Get-CurrentBoard` 动态加载
2. **project_memory.md**（动态加载）：当前项目的引脚分配表
3. ~~脚本硬编码默认分配~~（v2.0 已删除，避免与 project_memory.md 不一致）

## 与 AI 的协作流程

当用户问引脚相关问题时：

1. **先运行脚本获取最新状态**：
```powershell
cd <项目目录>
pin-check -List
```

2. **解读结果**：
   - 告诉用户哪些引脚可用
   - 如果用户要分配的引脚冲突了，建议替代方案
   - 分配后用 `-AutoUpdate` 同步 project_memory.md

3. **生成驱动代码时使用分配的引脚号**

## Pitfalls

- 运行前必须在项目目录下（脚本从当前目录加载 project_memory.md）
- 运行前必须已通过 `switch-board` 切换板子，否则脚本会报错退出
- `-AutoUpdate` 会覆盖 project_memory.md，建议先 git commit
- GPIO 0 在 BOOT 模式下有特殊行为，不要在上电初始化时使用
- GPIO 20/21 如果用作 USB CDC，不能同时用作普通 GPIO
- 新增板子时只需在 board-config 目录添加 .ps1 配置文件，pin-check 自动适配

## Verification

- `pin-check -List` 确认所有引脚状态与 board-config + project_memory.md 一致
- 分配新引脚后检查驱动代码中的引脚号是否同步更新
- 切换板子后 `pin-check -List` 应显示新板子的保留引脚

## 验证记录

| 验证项 | 状态 | 来源 |
|--------|------|------|
| 从 board-config 动态加载 ReservedPins | ✅ | `Get-CurrentBoard()` in common.ps1 |
| 从 project_memory.md 动态加载已分配引脚 | ✅ | `Load-PinAllocationFromMemory()` |
| `-List/-Pin/-Allocate/-Dedup` 命令参数 | ✅ | pin-check.ps1 脚本参数 |
| 无板子配置时报错提示 | ✅ | pin-check.ps1 L33-38 |
| 删除硬编码默认 ALLOCATED_PINS | ✅ | v2.0 变更，改为只从 project_memory.md 加载 |
