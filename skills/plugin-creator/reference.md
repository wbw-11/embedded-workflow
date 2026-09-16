# Plugin Creator — 完整参考文档

本文件是 SKILL.md 的详细参考文档，包含插件结构规范、完整示例、模板内容、格式规范等。核心工作流与决策点见同目录 SKILL.md。

## 目录

- [Plugin Directory Structure](#plugin-directory-structure)
- [plugin.json Schema](#pluginjson-schema)
- [.mcp.json Format](#mcpjson-format)
- [SKILL.md Format](#skillmd-format)
- [Skill Content Guidelines](#skill-content-guidelines)
- [Plugin Modes](#plugin-modes)
- [External Tool Integration (MCP Configuration)](#external-tool-integration-mcp-configuration)
- [README Template](#readme-template)
- [CONNECTORS.md Template](#connectorsmd-template)
- [Command .md Format (Legacy)](#command-md-format-legacy)

---

## Plugin Directory Structure

```
{plugin-name}/
├── .qoder-plugin/
│   └── plugin.json          # Plugin metadata (required)
├── .mcp.json                 # Guided-setup MCP declarations (optional)
├── CONNECTORS.md             # Human-readable setup guide (REQUIRED when external tools are mentioned)
├── skills/                   # Skills directory
│   ├── skill-a/
│   │   ├── SKILL.md          # Core instruction file
│   │   └── references/       # Reference materials (templates, examples, docs)
│   │       ├── template.md
│   │       └── examples.md
│   └── skill-b/
│       └── SKILL.md
└── README.md                 # Usage documentation (optional but recommended)
```

Compatibility: Always use `.qoder-plugin/` for new plugins. The system also reads `.claude-plugin/plugin.json` for third-party plugin imports, but prefer `.qoder-plugin/` when creating.

---

## plugin.json Schema

```json
{
  "name": "my-plugin",
  "displayName": "My Plugin",
  "version": "1.0.0",
  "description": "English description of the plugin",
  "descriptionZh": "插件的中文描述",
  "author": {
    "name": "Author Name",
    "url": "https://example.com"
  },
  "category": "marketing",
  "tags": ["social-media", "content"],
  "skills": [
    "skills/skill-a",
    "skills/skill-b"
  ]
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Technical identifier, kebab-case (e.g., `marketing-toolkit`) |
| `displayName` | Yes | Display name shown in UI, supports localized text |
| `version` | Yes | Semantic version (e.g., `1.0.0`) |
| `description` | Yes | English description |
| `descriptionZh` | No | Chinese description |
| `author` | No | Author info with `name` and optional `url` |
| `category` | No | Category: marketing, finance, legal, engineering, etc. |
| `customizedFrom` | No | Only set when customized from a built-in plugin — use the original plugin's `displayName`. Do NOT set for brand-new plugins |
| `tags` | No | Array of tags for search/filter |
| `skills` | No | Array of relative paths to skill directories |
| `commands` | No | Array of relative paths to command files |

---

## .mcp.json Format

Place `.mcp.json` in the plugin root only for MCP services that the plugin runtime can load directly or guide the user to configure. For newly created plugins, use `guided-setup` for third-party MCP services requiring per-user credentials.

Do not generate marker-only connector declarations; plugin `.mcp.json` configs are loaded as actual MCP server configs, so placeholder connector markers will not resolve to market/native connector configs. Native/market connectors are product-level capabilities: document them in `CONNECTORS.md` and tell users to enable them from Connector settings.

Do not generate legacy direct server entries like `type: "http"`, `type: "streamable-http"`, or hardcoded personal MCP URLs for market/native services. Existing old plugins may contain those formats, but new plugins should use `guided-setup` for user-specific MCP services so installation remains portable.

### `guided-setup` (for third-party MCP services requiring per-user credentials)

Use this when the MCP service setup is user-specific (e.g., DingTalk, Feishu). The server `url` field is omitted — users configure it after installation via the plugin detail page. `_setup.url` is only the public setup/configuration page, not the user's personal MCP endpoint.

```json
{
  "mcpServers": {
    "钉钉文档": {
      "type": "guided-setup",
      "_setup": {
        "url": "https://aihub.dingtalk.com/#/mcp",
        "description": "1. Open [DingTalk AI Hub](https://aihub.dingtalk.com/#/mcp)\n2. Find **DingTalk Documents MCP**\n3. Click to generate your personal configuration\n4. Copy the JSON and paste it into the input box below",
        "descriptionZh": "1. 打开[钉钉 AI 能力中心](https://aihub.dingtalk.com/#/mcp)\n2. 找到 **钉钉文档 MCP**\n3. 点击生成个人专属配置\n4. 复制 JSON 配置并粘贴到下方输入框"
      }
    }
  }
}
```

| `_setup` Field | Required | Description |
|----------------|----------|-------------|
| `url` | Yes | Configuration page URL — where users go to get their credentials |
| `description` | Yes | English setup guide (supports markdown) |
| `descriptionZh` | No | Chinese setup guide (supports markdown) |

### Multiple Guided Setup Entries

A plugin can declare multiple third-party MCP services that need guided setup:

```json
{
  "mcpServers": {
    "钉钉文档": {
      "type": "guided-setup",
      "_setup": {
        "url": "https://aihub.dingtalk.com/#/mcp",
        "description": "1. Open [DingTalk AI Hub](https://aihub.dingtalk.com/#/mcp)\n2. Find the MCP service\n3. Generate your config and paste below",
        "descriptionZh": "1. 打开[钉钉 AI 能力中心](https://aihub.dingtalk.com/#/mcp)\n2. 找到对应 MCP 服务\n3. 生成配置并粘贴到下方"
      }
    },
    "飞书文档": {
      "type": "guided-setup",
      "_setup": {
        "url": "https://applink.feishu.cn/client/ai/ai_mcp",
        "description": "1. Open Feishu MCP settings\n2. Find the document MCP service\n3. Generate your config and paste below",
        "descriptionZh": "1. 打开飞书 MCP 设置\n2. 找到文档 MCP 服务\n3. 生成配置并粘贴到下方"
      }
    }
  }
}
```

---

## SKILL.md Format

> 详细的 SKILL.md 编写指南（描述编写原则、核心规范、常见模式、反模式等）见 **create-skill** 技能。本节仅列出插件 context 下所需的 frontmatter 格式。

Each skill is a directory under `skills/` containing a `SKILL.md` with frontmatter:

```markdown
---
name: my-skill-name
version: 1.0.0
description: What this skill does in English
description_zh: 这个技能做什么的中文描述
user-invocable: true
argument-hint: Brief hint of expected input
---

# Skill Title

Detailed instructions for the AI agent...
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | Yes | - | Skill identifier |
| `version` | No | - | Version number for tracking iterations |
| `description` | Yes | - | English description |
| `description_zh` | No | - | Chinese description |
| `user-invocable` | No | `true` | Set to `false` for internal knowledge-base skills that are only referenced by other skills, hidden from the user menu |
| `argument-hint` | No | - | Hint shown in the mention menu (e.g., "Upload a contract file or paste contract text") |

---

## Skill Content Guidelines

The body of SKILL.md is the core — it determines how well AI performs with this Skill.

### Write What AI Doesn't Already Know

AI has broad general knowledge. A Skill's value is the **incremental, domain-specific information** it injects: your industry standards, your template formats, your workflow rules, your quality criteria.

Avoid vague instructions like "analyze carefully" or "ensure high quality" — these add nothing. Be specific: which framework to use, which dimensions to evaluate, what output format to follow, what constitutes pass/fail.

### Progressive Loading with references/

Keep SKILL.md under 500 lines. For extensive reference materials (templates, examples, knowledge bases, regulatory docs), use the `references/` directory. AI loads only SKILL.md at startup and reads reference files on demand via markdown links.

Example structure:

```
skills/write-prd/
├── SKILL.md                     # Main instructions: workflow, rules, format
└── references/
    ├── prd-template.md          # PRD template
    ├── good-example.md          # Example of a good PRD
    └── review-checklist.md      # Quality checklist
```

Reference in SKILL.md via links:
```markdown
Follow the structure in [PRD Template](references/prd-template.md).
After drafting, verify against the [Quality Checklist](references/review-checklist.md).
```

Rule of thumb:
- **SKILL.md**: Execution flow, decision rules, output format definitions, conditional branches
- **references/**: Full templates, detailed examples, domain knowledge docs, regulatory text, checklists

### Flexibility Over Rigidity

Good skills handle varied inputs and scenarios:

- Use conditional branches for different cases: if input is X → path A; if input is Y → path B
- Define clearly but don't over-constrain: specify "output must contain these 5 sections" but don't dictate sentence counts
- Provide fallback logic: what AI should do when information is incomplete or the scenario is unexpected

### Connector Integration in Skills

Every Skill must work **standalone** — without any connectors. Connectors are enhancements, not requirements.

When a Skill benefits from external tools, add a **"If Connectors Available"** section at the end of the Skill's SKILL.md. Use category placeholders (not hardcoded tool names) so the Skill works with any tool in that category:

```markdown
## If Connectors Available

If **文档平台** is connected:
- 完成后自动发布为文档，无需手动复制

If **任务工具** is connected:
- 自动创建待办事项并关联到对应项目

If no connectors available:
- Output to local file / display in chat (default behavior)
```

**Rules for connector references in Skills:**
- Use **category names** (文档平台, 任务工具, 沟通工具, 设计工具), not specific tool names (钉钉, Notion, Figma)
- Always state the **default behavior** when no connector is available
- Place the "If Connectors Available" section at the **end** of SKILL.md, not the beginning
- Each enhancement should describe the **user-visible outcome** ("自动发布为文档"), not the technical mechanism ("调用 mcp__钉钉文档__create_document")

### Internal Knowledge-Base Skills

For knowledge-intensive domains (legal, medical, finance), create internal skills with `user-invocable: false` to hold domain knowledge. Other skills reference them at runtime, but users don't see them in the menu:

```
skills/legal-knowledge/          # user-invocable: false — hidden from users
├── SKILL.md                     # Index and usage notes
└── references/
    ├── contract-law-essentials.md
    └── common-clauses.md

skills/draft-contract/           # user-invocable: true — references legal-knowledge
skills/review-contract/          # user-invocable: true — references legal-knowledge
```

---

## Plugin Modes

Two typical patterns based on task complexity. **Default to Simple Tool Mode** — only suggest Orchestration Mode when the project-mode signals are clearly met. When in doubt, choose simple.

### Mode 1: Simple Tool Mode (default)

Skills are independent; users invoke whichever they need. Suitable for most scenarios.

```
marketing-plugin/
├── skills/
│   ├── write-copy/SKILL.md        # Write marketing copy
│   ├── analyze-data/SKILL.md      # Analyze campaign data
│   └── plan-campaign/SKILL.md     # Plan marketing campaign
```

Use when: Skills have no strong dependencies, no fixed execution order, no shared state across skills.

### Mode 2: Project Orchestration Mode

When the task involves multiple dependent stages and requires progress tracking, add an **orchestrator skill** to manage the workflow. Suitable for legal cases, investment projects, product launch processes, etc.

```
legal-case-plugin/
├── skills/
│   ├── case-orchestrator/          # Orchestrator: manages the full workflow
│   │   ├── SKILL.md
│   │   └── references/
│   │       └── workflow-stages.md  # Stage definitions and dependencies
│   ├── case-analysis/SKILL.md      # Stage: case analysis
│   ├── evidence-organizer/SKILL.md # Stage: evidence organization
│   ├── defense-brief/SKILL.md      # Stage: defense brief
│   └── legal-knowledge/            # Internal knowledge base (user-invocable: false)
│       ├── SKILL.md
│       └── references/
```

The orchestrator skill is responsible for:
- Maintaining project state (a progress file in the working directory tracking each stage's status, outputs, and timestamps)
- Guiding the user to the next step, specifying what prerequisite outputs are needed
- Ensuring downstream stages can locate and reference upstream outputs
- Optionally syncing status to external tools if the user has connected relevant MCP services (e.g., DingTalk tasks, Feishu projects)

Use when: Stages have sequential dependencies (B requires A to complete), overall progress needs tracking, outputs need to be passed between stages. Note: multiple stages that are independent of each other (e.g., 5 parallel analysis tasks) should still use Simple Tool Mode.

When you determine Orchestration Mode is appropriate, explain it to the user:

> "Your scenario involves multiple work stages with dependencies between them. I recommend adding a project management Skill to coordinate the workflow — it will automatically track progress after each stage, and you can check the overall status at any time. Would you like this design?"

---

## External Tool Integration (MCP Configuration)

A plugin that connects external tools is far more useful than one that runs in isolation. **Users rarely add MCP on their own after installation** — if you don't proactively configure it during creation, it likely never gets added.

### Timing in the Workflow

1. **Step 2–3 (Tool Collection + MCP Resolution)**: Identify MCP needs from the user's confirmed tool ecosystem. Tell the user to prepare setup info for non-native services while you write the Skills.
2. **Step 5 (Build)**: Write Skills first. After Skills are done, generate `.mcp.json` only for confirmed non-native MCP services that need guided setup. Ask for a setup page URL only when the service is non-native and there is no known default URL; never ask for or store the user's personal credential JSON in `.mcp.json`.

### Identifying What to Connect

Based on each Skill's function and **the user's confirmed tool ecosystem**, recommend connectors. **Only recommend tools the user has indicated they use** — do not assume any platform:
- Skill outputs documents/reports → document platform (Notion, Google Docs, 钉钉文档, 飞书文档)
- Skill manages tasks/progress → task tool (Linear, Todoist, 钉钉待办, 飞书任务)
- Skill reads design files → design tool (Figma, Canva)
- Skill sends notifications → communication platform (Slack, 钉钉, 飞书)
- Skill reads/writes structured data → table tool (Google Sheets, Notion, 钉钉AI表格, 飞书多维表格)

### Approach: Determine Connector Type

When you identify an MCP dependency, first determine whether it's already a native connector in the current product:

**How to check**: Call `mcp__builtin_qoderwork__query` with key `qoderwork.settings.connector.market` to get the current product's market/native connector list. Treat the query result as the source of truth for native/product connectors, but do not write native connectors into `.mcp.json`. If needed, also query `qoderwork.settings.connector.custom` to understand what the current user already added, but do not treat user-specific custom servers as portable for all plugin installers.

**Native/market connector** (found in `qoderwork.settings.connector.market`): Do not add it to `.mcp.json`. Mention it in `CONNECTORS.md` as a product-level connector users can enable from Connector settings. No setup URL needed.

**Not in market list** (e.g., DingTalk, Feishu, or any service not found in the query result): These require per-user setup. Use `guided-setup` type with a configuration page URL and markdown setup instructions.

### Decision Flow

1. Identify the external tool the Skill needs
2. Query `qoderwork.settings.connector.market` to check if it exists as a native/market connector
   - **Found** → Do not add it to `.mcp.json`; document it in `CONNECTORS.md` as a native/product connector.
   - **Not found** → Use a known default setup URL when available; otherwise ask the user for the configuration page URL, then generate a `guided-setup` entry.
3. If the user already has the service as a custom connector, you may mention it works for them locally, but plugin distribution still needs `guided-setup` when a public setup URL exists. If no setup URL is available, document it in `CONNECTORS.md` as a local prerequisite instead of writing a placeholder `.mcp.json` entry.

### Common Non-Native MCP Configuration URLs

Use these as defaults when the user confirms the tool but doesn't know the exact URL:

| MCP Service | Config URL |
|-------------|-----------|
| 钉钉文档 / 钉钉待办 / 钉钉日志 / 钉钉AI表格 / 钉钉日历 / 钉钉OA审批 | `https://aihub.dingtalk.com/#/mcp` |
| 飞书文档 / 飞书多维表格 / 飞书日历 | Feishu Open Platform MCP page (ask user for URL) |

### How to Record in Skills

Each Skill that benefits from external tools should include a standardized "If Connectors Available" section at the end (see "Connector Integration in Skills" under Skill Content Guidelines). Use category names, not specific tool names.

### If User Declines

If the user doesn't want to add MCP or doesn't know the config URL, skip `.mcp.json` creation. It does not block plugin creation — it can always be added later.

---

## README Template

When creating the README.md, follow this structure as the **default template** (adapt as needed for the user's specific case):

```markdown
# {Plugin Display Name}

{One paragraph summary: what this plugin does, which scenarios it covers, what methodologies/standards are built in.}

> **Disclaimer:** {Appropriate disclaimer for the domain — e.g., "This plugin assists professional workflows and does not replace professional advice. All outputs should be reviewed by qualified professionals before use in decision-making."}

## Target Roles

- **{Role A}** — {how this plugin helps them}
- **{Role B}** — {how this plugin helps them}
- ...

## Quick Commands

| Command | Description |
|---------|-------------|
| `/{skill-name}` | {what it does, key input} |
| ... | ... |

## Skills

| Skill | Description |
|-------|-------------|
| {Skill Name} | {detailed description: what it does + key methodology/framework built in} |
| ... | ... |

## Connectors (Optional Enhancement)

| What You Can Do | Standalone | Supercharged With |
|-----------------|-----------|-------------------|
| {技能1} | {无连接器时的能力} | {连上XX后的增强能力} |
| {技能2} | {无连接器时的能力} | {连上XX后的增强能力} |

> All skills work fully without connectors. See CONNECTORS.md for setup details.
```

Key principles for the README:
- The summary paragraph should be dense and specific — mention the exact number of scenarios, key methodologies, and built-in standards
- "Target Roles" shows who benefits and how, reinforcing the "role-oriented toolkit" positioning
- "Quick Commands" gives users an instant-use reference — include typical input examples where helpful
- "Skills" table should describe not just WHAT but HOW (the methodology/framework inside)
- "Connectors" section is optional — only include if the user mentioned external tools. Always note that the plugin works without connectors
- This is the default template. If the user has specific preferences for README format, adapt accordingly.

---

## CONNECTORS.md Template

If external tools/connectors are mentioned, **always** create `CONNECTORS.md` as a **category-to-tool mapping reference**. Native/product connectors may appear only in `CONNECTORS.md`; `.mcp.json` is generated only for guided setup entries. Format:

```markdown
# Connectors

本插件使用品类占位符引用外部工具。实际使用时，对应品类连上任意一个工具即可。

| 品类 | 连上后能做什么 | 支持的工具 | 配置方式 |
|------|---------------|-----------|----------|
| 文档平台 | 结果自动发布为文档 | 钉钉文档, Notion, 飞书文档 | 钉钉/飞书：去配置页生成；Notion：设置页一键开启 |
| 任务工具 | 自动创建待办跟进 | 钉钉待办, Linear, Todoist | ... |

> 所有技能在没有连接器的情况下均可正常使用，连接后体验升级。
```

This is the user-facing reference document. `.mcp.json` is the machine-readable declaration for guided setup entries only; it is optional when all connectors are native/product-level connectors.

---

## Command .md Format (Legacy)

New plugins should prefer `skills/` with `user-invocable` and `argument-hint`. The `commands/` directory is still supported for backward compatibility.

```markdown
---
description: What this command does in English
description_zh: 这个指令做什么的中文描述
---

# Command Content

Content injected when the user invokes this command via /command-name...
```
