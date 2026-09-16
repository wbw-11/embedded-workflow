# 参与贡献（Contributing）

欢迎参与完善这个工作流！本仓库开源的目的之一就是**大家一起把流程打磨得更好**——你踩过的坑、你补充的技能、你改进的脚本，都可能帮助下一个嵌入式开发者。

## 一、以什么形式参与

| 方式 | 适用场景 | 操作 |
| --- | --- | --- |
| **提 Issue** | 报告脚本 bug、提出流程改进建议、申请新技能 | 点 GitHub 右上角 `Issues` |
| **提 PR** | 直接改了代码/技能/文档，想让改动进入仓库 | Fork → 改 → Pull Request |
| **Discussions** | 讨论流程设计、经验交流、提问 | 点 GitHub 右上角 `Discussions` |
| **写经验分享** | 在 TRAE 社区 / B 站分享使用经验 | 仓库 + 社区互链即可 |

> 不会写代码也没关系：提 Issue 描述"你想要什么、现在的痛点是啥"就够了，开发者会帮忙实现。

## 二、贡献的几类内容

### 1. 新增 Skill 技能
技能是 `skills/<技能名>/SKILL.md`，遵循：
- frontmatter 必须含 `name` / `description` / `version`（`check-skills` 会体检，缺了报 P1）
- 内容：触发词 + 核心知识 + 步骤 + 不适用场景（参考现有技能的结构）
- 提交前跑：`tools\check-skills.ps1 -Path skills\<技能名>` 应无 P0/P1

### 2. 完善流程规则（docs / embedded-dev-rules）
- 通用规则（换芯片也成立）→ `docs/`
- 芯片系列规则 → `skills/chip-rules/rules/`（如 `arm_cortex_m.md`）
- 分级原则：**通用规则 L1 > 芯片系列 L2 > 项目级 L3**，避免把单项目经验写成通用规则

### 3. 改进工具脚本（tools/）
- 遵循代码风格：空格缩进（禁用 Tab）、下划线命名、单行 ≤120 字符
- 改完 `.ps1` 必做三步：
  ```
  version-tools -Bump -Name <脚本> -How patch -Message "说明"   # 登记版本
  check-bom -Quiet                                                # 编码检查
  version-tools -Validate                                         # 版本齐全
  ```
- 改了 `code-style-check.ps1` 必须跑三步回归：`tools\verify-code-style\verify-check.ps1`（clean 0 告警 + 坏例命中 + 基线对比）

### 4. 修正文档
直接改 README / docs，或提 Issue 指出问题位置即可。

## 三、PR 流程约定

1. **小步提交**：一个 PR 解决一件事，标题写清"修了什么"
2. **版本号三处一致**（涉及固件时）：代码 `printf` / 产物文件名 / 运行日志
3. **commit message**：中文，`fix:` / `feat:` / `docs:` 前缀（例：`docs: 补充 xxx`）
4. **合并前**：本地用 `verify-code-style\verify-check.ps1` 确认没破坏 baseline

## 四、找不到主题？先看这些

- [ ] 仓库 `docs/` 有没有过时/错误
- [ ] 某个脚本在本机运行报错（提 Issue 附错误截图 + 环境）
- [ ] 缺某种常见芯片的规则（8051 / ARM / ESP32 之外的）
- [ ] Skills 里某个技能的触发词不全、很难被 AI 正确调用
- [ ] README 的部署指南有一步跑不通

## License 说明

本仓库 MIT 协议；你的贡献默认以同一协议发布。