# embedded-workflow 工具脚本

> 本目录是「嵌入式开发工作流」的工具箱：PowerShell 脚本 + 命令行包装器（.bat）。

## 结构

| 目录/文件 | 说明 |
| --- | --- |
| `*.ps1` | 各工具主脚本（动态检测路径，不硬编码） |
| `*.bat` | 命令行包装器（`%~dp0` 定位同目录 ps1，加入 PATH 后即可直接敲命令名） |
| `lib\` | 公共库：common.ps1（工具链动态检测）/ board-state.ps1 / file-lock.ps1 |
| `board-config\` | 板级配置示例（esp32-c3 / esp32-s3 / esp32-wroom-32 / gd32f407zgt6 / stc8h8k64u / stm32f407vet6） |
| `verify-code-style\` | code-style-check 回归基线（clean_code.c 全好例 / test_q10.c 全坏例） |
| `changelog.md` | 工具版本变更记录 |
| `tools_version.json` | 脚本版本登记索引（version-tools 维护） |

## 快速开始

1. 把本目录加入用户 PATH（脚本名即命令名）
2. 依赖核查：`lib\common.ps1` 必须与脚本同目录
3. 常用命令：

| 命令 | 作用 |
| --- | --- |
| `tool-guide` | 查看全部工具清单与版本 |
| `detect-chip` | 芯片型号四级确认（esp32/stm32/gd32/stc8） |
| `dev-flow` | 主流程：编译 → 静态门禁 → 时间戳核对 → 烧录 → 归档 |
| `preflight` | 开工预检（缺包自动引导安装） |
| `code-style-check` | 代码风格静态检查（overflow/defensive 等告警） |
| `build-all` | 批量编译 |
| `safe-flash` | 安全烧录（时间戳门禁） |
| `serial-debug` | 串口查看与格式化（serial-debug.py） |
| `version-tools` | 脚本版本登记（改脚本后必用） |
| `check-skills` | 技能库健康体检 |

> 路径约定：所有脚本按「环境变量 → 注册表 → 候选路径 → 搜索」动态检测工具链，不硬编码绝对路径（见 `lib\common.ps1`）。Keil / ESP-IDF / STC 工具链需自行安装。

## Windows 计划任务（可选）

- 每日 config 自检 + 备份提交：`Register-ScheduledTask`（示例见本仓库 README）
- 本地镜像备份：可选

## 约定

- 代码风格：下划线命名、单行 ≤120 字符、空格缩进、`if/else` 单行也带 `{}`
- 改 .ps1 后必做：`version-tools -Bump` 登记版本 + 更新 `changelog.md`
- 含中文的 .ps1 必须 UTF-8 with BOM（PowerShell 5.1 按 GBK 读无 BOM 文件会吞引号）