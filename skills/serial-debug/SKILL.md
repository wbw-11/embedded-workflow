---
name: serial-debug
description: "串口调试：监听/发送串口数据并格式化展示。串口调试、看回显、验证串口时调用。"
install_method: upload
version: 1.0.1
---

# 串口调试 Skill

## 适用场景

- 烧录后验证 MCU 串口输出是否正常
- 监听 USART/UART 数据，格式化展示带时间戳
- 发送测试指令并观察 MCU 响应
- 自动保存串口日志文件
- 扫描当前可用串口列表

## 工具路径（自动检测）

脚本位于本技能目录下，首次使用时自动定位：

```powershell
# 技能脚本路径（自动检测）
$scriptPath = @(
    "$env:USERPROFILE\.qoderworkcn\skills\serial-debug\serial-debug.py",
    "$env:USERPROFILE\.trae-cn\skills\serial-debug\serial-debug.py"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
```

- **依赖**：Python 3 + pyserial（`pip install pyserial`）
- **默认波特率**：115200
- **默认串口号**：无默认值，必须先执行 `list` 扫描可用串口后由用户确认

## 执行流程

### 第一步：确认串口参数

向用户确认或从上下文推断：
1. **串口号**（COM3/COM5 等）— 不确定时先执行 `list` 扫描
2. **波特率**（默认 115200）— 可从项目 USART 配置头文件中查找
3. **监听时长**（秒，默认 10 秒，0 表示持续）
4. **是否需要发送数据**（纯监听 vs 发送+监听）

### 第二步：执行串口操作

使用 RunCommand 工具，**必须 blocking: true**（监听模式是定时的，duration > 0 时会自动退出）。

cwd 设为项目根目录或脚本所在目录均可。

### 第三步：解读结果

根据输出内容判断：
- ✅ 有预期格式的数据 → 串口功能正常
- ❌ 无任何输出 → 检查接线、波特率、串口是否被其他程序占用
- ⚠️ 乱码 → 波特率不匹配或编码问题
- ❌ 打开失败 → 串口不存在或被占用

## 命令示例

> 以下命令中脚本路径为全局安装路径，请原样使用。

### 1. 列出所有可用串口
```powershell
python $scriptPath list
```
输出示例：
```
可用串口:
  COM3 - 蓝牙链接上的标准串行 (COM3)
  COM5 - USB 串行设备 (COM5)
```

### 2. 监听串口 10 秒（纯接收）
```powershell
python $scriptPath COM5 115200 10
```
输出格式：
```
打开 COM5 @ 115200bps, 监听 10秒...
✅ COM5 已打开
======================================================================
[21:32:01] [inner] adc = 1746, vol = 1.41, temp = 35.48
[21:32:01] [vol] adc = 2538, vol = 2.05
...
======================================================================
接收 20 行, 耗时 10.2秒
日志已保存: serial_log_20260722_213216.txt
```

### 3. 持续监听（手动中断）
```powershell
python $scriptPath COM5 115200 0
```
- duration=0 表示持续监听
- 用户可按 Ctrl+C 退出（但 RunCommand blocking 模式下需设为非阻塞）
- **注意**：持续监听建议用 `blocking: false` + `wait_ms_before_async` 启动，后续用 CheckCommandStatus 查看输出

### 4. 发送数据 + 监听响应
```powershell
python $scriptPath COM5 115200 10 "hello"
```
- 第4个参数为要发送的字符串
- 发送后监听 N 秒等待响应
- 常用于：发送 AT 指令、发送控制命令等

## 常见问题排查

| 现象 | 可能原因 | 解决方案 |
|------|----------|----------|
| 打开失败：Permission denied | 串口被其他程序占用（串口助手、Keil 调试器等） | 关闭其他占用串口的程序 |
| 打开失败：FileNotFound | 串口号不存在 | 用 `list` 命令扫描确认串口号 |
| 有输出但乱码 | 波特率不匹配 | 检查 MCU 端波特率配置，确认两端一致 |
| 完全无输出 | TX/RX 接反、未上电、波特率错误 | 检查接线、电源、波特率 |
| 输出缺字/断断续续 | 缓冲区溢出或波特率误差 | 检查两端时钟配置，降低波特率试试 |

## 脚本工具参考

以下脚本位于 `$env:USERPROFILE\Tools\` 目录，可配合本技能使用：

| 脚本 | 用途 | 调用时机 |
|------|------|----------|
| `safe-flash.ps1 -ListPorts` | 快速扫描串口并探测芯片类型 | 不确定串口号时快速定位 |
| `esp-burn` (PowerShell 模块) | ESP32 专用编译+烧录+监控一条龙 | ESP32 项目烧录后自动监控 |

```powershell
# 快速定位 ESP32 所在串口
& "$env:USERPROFILE\Tools\safe-flash.ps1" -ListPorts

# ESP32 一条龙（编译+烧录+监控）
esp-burn -Mode build-flash-monitor -ProjectDir <项目目录>
```

## 注意事项

1. **串口独占**：同一时间只能有一个程序打开串口，Keil 调试器或 GUI 串口助手占用时必须先关闭
2. **TX/RX 交叉**：MCU 的 TX 接 USB-TTL 的 RX，MCU 的 RX 接 USB-TTL 的 TX，GND 必须共地
3. **波特率一致性**：两端波特率、数据位、停止位、校验位必须完全一致（默认 8N1）
4. **日志保存**：每次监听自动保存 `serial_log_时间戳.txt` 到当前工作目录
5. **编码**：脚本默认 UTF-8 解码，GB2312 编码数据可能乱码（可用 `errors='replace'` 替换）
6. **非阻塞监听**：长时间监听用 `blocking: false`，避免阻塞对话

## 触发时机

- **用户明确要求**："串口调试"、"监听串口"、"看看串口输出"、"发指令看回显"
- **烧录后验证**：烧录成功后，用户需要验证串口输出时
- **排查问题**：用户说"串口没反应"、"串口乱码"、"收不到数据"等串口相关问题时
- **不触发**：仅讨论代码逻辑、不涉及实际串口硬件通信时

## 验证记录

> 本节记录技能内容中脚本引用、依赖、路径检测逻辑的验证结果。

### 脚本路径验证

| 技能中引用的路径 | 实际路径 | 验证结果 |
|-----------------|---------|----------|
| `$env:USERPROFILE\.qoderworkcn\skills\serial-debug\serial-debug.py` | 未安装（旧路径） | ✅ 通过 |
| `$env:USERPROFILE\.trae-cn\skills\serial-debug\serial-debug.py` | `<USERPROFILE>\.trae-cn\skills\serial-debug\serial-debug.py` | ✅ 通过 |

### 依赖验证

| 依赖 | 验证结果 | 说明 |
|------|----------|------|
| Python 3 | ✅ 系统 Python 可用 | `$(Get-Command python).Source` 动态定位 |
| pyserial | ⚠️ 需用户自行安装 | `pip install pyserial`（技能首次使用前安装） |

### 引用工具验证

| 技能中引用的工具 | 验证结果 | 说明 |
|-----------------|----------|------|
| `safe-flash.ps1 -ListPorts` | ✅ 通过 | 脚本存在，参数已验证（见 hardware-detection 验证记录） |
| `esp-burn` PowerShell 模块 | ✅ 通过 | `Get-Command esp-burn` 返回可用 |

### 命令格式验证

| 命令格式 | 验证结果 | 说明 |
|----------|----------|------|
| `python $scriptPath list` | ✅ 正确 | serial-debug.py 支持 `list` 子命令 |
| `python $scriptPath COM5 115200 10` | ✅ 正确 | 参数顺序：[脚本] [串口] [波特率] [时长] |
| `python $scriptPath COM5 115200 0` | ✅ 正确 | duration=0 表示持续监听 |
| `python $scriptPath COM5 115200 10 "hello"` | ✅ 正确 | 第4个参数为发送字符串 |

### 修正项

| 项 | 原内容 | 修正内容 | 原因 |
|----|--------|----------|------|
| pyserial 依赖说明 | 仅提及 `pip install pyserial` | 标注为"需用户自行安装" | 明确告知用户需提前安装 |
| 路径检测逻辑 | 未说明回退顺序 | 补充 `.qoderworkcn` → `.trae-cn` 回退说明 | 两个路径都可能存在，按顺序检测 |

---

> **结论**：serial-debug v1.0.1 **已完成验证**。脚本路径、命令格式、工具引用均通过实际文件系统和工具链验证。2 项说明性修正：pyserial 安装提示、路径回退顺序。无功能性错误。
