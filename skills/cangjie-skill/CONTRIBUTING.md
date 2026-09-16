# 参与仓颉 Skill 共建

仓颉 Skill 使用 GitHub Pull Request 作为公开的投稿和审核流程。你不需要注册额外账号，也不需要把内容提交到私有后台。

## 两种收录方式

### 1. 已经有公开 GitHub 仓库（推荐）

只需新增一个 Registry 条目：

```text
registry/<your-slug>/entry.yaml
```

这个文件指向你的公开仓库，Skill 源文件继续由你维护。可以在官网的「提交 Skill」页面填写信息并自动生成文件。

### 2. 暂时没有公开仓库

将内容和 Registry 条目一起放入：

```text
registry/<your-slug>/
├── entry.yaml
└── skill/
    ├── README.md
    └── <atomic-skill>/
        └── SKILL.md
```

官网投稿页可以检查本地文件夹并生成符合此结构的 ZIP。文件检查完全发生在浏览器本地。

请不要提交版权受限的原始书籍、课程、视频、音频、大型二进制文件、API Key、`.env` 或其他隐私信息。

## Registry 字段

每个 `entry.yaml` 必须符合 [`schemas/registry-entry.schema.json`](./schemas/registry-entry.schema.json)。最小示例：

```yaml
schema_version: 1
slug: example-decision-skill
name: 示例决策 Skill
summary: 一套用于识别关键假设和复盘复杂决策的工作方法。
source_type: github
source_url: https://github.com/example/example-decision-skill
skill_count: 3
domains: [决策, 管理]
language: [zh-CN]
status: active
quality: community
featured: false
use_cases:
  - 检查重要决策的隐含假设
  - 复盘行动结果
```

质量字段由审核流程维护：新投稿默认使用 `community`；维护者在验证内容和结构后可调整为 `verified`。

## 本地检查

```bash
cd website
npm ci
npm run verify
```

该命令会依次校验 Registry、运行单元测试、执行 Astro 类型检查并构建整站。

## 审核标准

维护者主要检查：

- 来源与授权是否清晰；
- 使用场景是否具体，是否真正形成可执行方法；
- `SKILL.md` 是否包含明确触发条件、输入、步骤和输出；
- 是否含敏感信息、恶意脚本或不必要的大文件；
- Registry 信息是否准确且没有夸大描述；
- 是否与现有 Skill 高度重复。

自动检查通过不代表一定合并。审核意见、修改过程和最终结果都会保留在 Pull Request 中。

## 官网开发

官网位于 `website/`，使用 Astro 生成静态站点；`registry/` 是唯一的数据源。

```bash
cd website
npm install
npm run dev
```

本地地址默认为 `http://localhost:4321`。向 `main` 分支合并后，GitHub Actions 会重新构建并部署 GitHub Pages。
