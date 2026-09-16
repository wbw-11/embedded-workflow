---
name: git-workflow
description: "嵌入式项目 Git 工作流与固件版本：commit 规范/分支策略/版本号/tag/追溯。提交、建分支、打 tag 时调用。"
version: 1.0.0
---

# Git 工作流与固件版本管理

## 适用场景

- 用户提交代码、要求写 commit message
- 用户创建/切换/合并分支
- 用户打 tag、发布固件版本
- 用户询问"这个版本对应哪次提交"
- 多人协作需要规范工作流

## 分支策略

采用简化的 Git Flow，适合嵌入式小团队：

```
main          ← 稳定版本，只接受 release 分支合入
develop       ← 日常开发主线
feature/xxx   ← 功能分支，从 develop 拉，完成后合回 develop
hotfix/xxx    ← 紧急修复，从 main 拉，修完同时合入 main 和 develop
release/vX.Y.Z ← 发布准备，从 develop 拉，只做 bugfix 和版本号修改
```

### 分支命名规则

- feature/uart-driver、feature/ble-pairing
- hotfix/watchdog-reset
- release/v1.2.0

## Commit Message 规范

格式：`<type>(<scope>): <subject>`

### Type 取值

| type | 含义 |
|------|------|
| feat | 新功能 |
| fix | 修复 bug |
| refactor | 重构（不改功能） |
| perf | 性能优化 |
| docs | 文档 |
| style | 格式调整（不影响逻辑） |
| test | 测试相关 |
| build | 构建系统/工具链变更 |
| chore | 杂项 |

### Scope 示例

uart, spi, i2c, adc, gpio, ble, wifi, ota, power, bsp, hal, app

### 示例

```
feat(uart): 添加 DMA 接收模式，支持不定长数据
fix(watchdog): 修复低功耗唤醒后看门狗未喂导致复位
build(cmake): ESP-IDF 5.2 适配，更新 CMakeLists 最低版本
```

### 规则

- subject 用中文或英文均可，但同一项目保持一致
- subject 不超过 72 字符
- body 说明 why，不重复 what
- 涉及硬件变更时在 body 注明影响范围

## 固件版本号规则

采用语义化版本 `vMAJOR.MINOR.PATCH`：

- MAJOR：不兼容的协议/接口变更（如通信协议大改）
- MINOR：新增功能，向后兼容
- PATCH：bug 修复

### 打 Tag 流程

```bash
# 1. 确保在 release 分支或 main 上
git checkout main

# 2. 打前先过发布门禁 B6（见 embedded-dev-rules 技能）：version.h 与 tag 一致、无未提交改动、commit 格式正确

# 3. 打带注释的 tag
git tag -a v1.2.0 -m "Release v1.2.0: 新增 BLE 配网，修复 UART 丢包"

# 4. 推送 tag
git push origin v1.2.0

# 5. 自动生成 changelog（release-notes 技能）
#    从 git log v1.1.0..v1.2.0 提取变更，按 feat/fix/refactor 分类生成 CHANGELOG.md
```

### 打 Tag 后联动 release-notes（流程钩子）

打完 tag 后**自动调用 release-notes 技能**生成 changelog，无需用户点名：

1. `git log v上一个版本..v1.2.0 --oneline` 提取本次版本的全部 commit
2. 按 type 分类汇总：feat 新功能 / fix 修复 / refactor 重构 / perf 性能 / build 构建
3. 生成 `CHANGELOG.md`（追加到文件顶部，保留历史版本）
4. 配合 gh-cli 发布到 GitHub Release：

```bash
gh release create v1.2.0 ./build/firmware.bin --title "v1.2.0" --notes-file CHANGELOG.md
```

### 与 embedded-dev-rules 门禁 B6 的关系

- **B6 是发布门禁**：9 项检查（version.h 一致、无未提交、tag 已打、bin 含版本串等），全部通过才允许打 tag 交付
- **本技能是操作视角**：B6 定义了"检查什么"，本技能提供"怎么执行"的命令
- 执行顺序：B6 检查通过 → 本技能打 tag → release-notes 生成 changelog → 交付
- 基线快照（V0 通过后）的 commit 使用格式：`feat(v0): baseline passed, [V0方式]`

### 版本号存放位置

**Keil/裸机项目**：项目根目录 `version.h`

- 格式示例：
```c
#define FW_VERSION_MAJOR  1
#define FW_VERSION_MINOR  2
#define FW_VERSION_PATCH  0
#define FW_VERSION_STRING "v1.2.0"
```

**ESP-IDF 项目**：无需 version.h，版本号写在根 CMakeLists.txt 的 project() 声明里，编译时自动注入固件头 `esp_app_desc_t`

```cmake
# CMakeLists.txt
project(firmware VERSION 1.2.0)
```

- 代码中读取：`esp_app_get_description()->version`
- 烧录后核对：`python -m esptool image_info build/firmware.bin` → `Application version: 1.2.0`
- 若未声明 VERSION，ESP-IDF 回退用 `git describe` 生成（无 git 仓库则版本号缺失，务必显式声明）
- 三处一致性：CMakeLists.txt VERSION = git tag = 固件头 Application version

## 常用操作速查

### 提交代码

```bash
git add <具体文件>
git commit -m "feat(spi): 添加 W25Q128 驱动初始化"
```

### 创建功能分支

```bash
git checkout develop
git pull origin develop
git checkout -b feature/adc-multichannel
```

### 合并功能分支

```bash
git checkout develop
git merge --no-ff feature/adc-multichannel
git branch -d feature/adc-multichannel
```

### 查看某版本对应的代码

```bash
git log v1.2.0 --oneline -1
git diff v1.1.0..v1.2.0 --stat
```

### 回溯某次固件对应的源码

```bash
# 如果固件 bin 文件里嵌入了版本号字符串
git log --all --grep="v1.2.0" --oneline
```

## 与 gh-cli 联动

```bash
# 创建 release（配合 release-notes 技能）
gh release create v1.2.0 ./build/firmware.bin --title "v1.2.0" --notes-file CHANGELOG.md
```

## Pitfalls

- 不要在 main 上直接开发，始终从 develop 或 feature 分支工作
- 打 tag 前确认 version.h 中的版本号与 tag 一致
- 合并时用 --no-ff 保留分支历史，方便回溯
- 固件 bin 文件不要提交到 git（用 .gitignore 排除 build/ 目录），通过 GitHub Release 附件分发
- 涉及芯片选型变更、引脚重分配等重大硬件改动，commit body 必须注明

## Verification

- `git log --oneline -5` 确认 commit 格式正确
- `git tag -l "v*"` 确认 tag 列表完整
- `git branch -a` 确认无残留的已合并分支
