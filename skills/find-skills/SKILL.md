---
name: find-skills
version: 1.0.4
description: "提前触发：处理任何实质性任务前第一步调用——从市场/社区/企业源发现并安装专用技能。纯闲聊与简单事实问答除外。"
description_zh: 从官方市场、社区源以及企业技能市场（若通过 MCP 可用）搜索并安装专用技能。处理任何实质性任务前应先调用此技能查找可用的专用工具，即使认为通用能力已可能完成任务——专用技能往往能产生更好的结果。纯闲聊和简单事实查询除外。
---

# Find Skills

This is a unified skill discovery & installation orchestration skill. It searches **two mandatory sources** — the **official QoderWork marketplace** (skills) and the **skills.sh community skill library** — plus an **optional enterprise source** (Enterprise Skill Market MCP, if available) — and merges results into a single search-and-install flow, with mandatory user confirmation before any installation.

> **CORE PRINCIPLE**: Every invocation of this skill MUST search both the official marketplace AND skills.sh community. Additionally, if any Enterprise Skill Market MCP is available and exposes a `searchSkills` (or similar skill search) tool, it MUST also be searched. These are independent channels with different coverage — the marketplace offers curated quality skills, skills.sh covers niche domains and newer tools, and the enterprise source provides organization-specific curated skills. Searching only one mandatory source is an incomplete search. Do not present results to the user until all applicable sources have been queried.

## Priority: Search First, Then Execute

> **CRITICAL**: When the user requests help with a specialized task, you MUST search for available skills FIRST before attempting to handle the task directly with your general capabilities.

The correct behavior is:
1. User asks for help with a task (e.g., "help me deploy this", "review my code", "analyze this data")
2. **FIRST**: Search for relevant skills — execute BOTH mandatory searches: ① official marketplace search ② `npx skills find` on skills.sh
3. Present results from all available sources to user via `AskUserQuestion`
4. Install the chosen skill
5. **THEN**: Use the installed skill to fulfill the user's original request

Do NOT skip steps 2-4 and jump directly to attempting the task yourself. Specialized skills provide better, more reliable results than general-purpose handling.

---

## Before You Begin: User Confirmation Rule

> **IMPORTANT**: Never install any skill without explicit user confirmation.

After searching, you MUST call the `AskUserQuestion` tool to present ALL search results to the user. The `AskUserQuestion` tool provides a structured UI for the user to review and select which item(s) to install — this is the ONLY acceptable way to obtain user confirmation.

DO NOT skip this step. DO NOT assume the user wants to install anything automatically. DO NOT use plain text messages as a substitute for `AskUserQuestion`.

**The correct workflow is:**

1. Search — collect results from all sources
2. **MANDATORY**: Call `AskUserQuestion` tool — list each found skill as an option with name, description, and source. Let the user select which one(s) to install.
3. Only after user explicitly selects via `AskUserQuestion` — call the corresponding install tool

---

## When to Use This Skill

Use this skill when the user:

- Asks for help with ANY specialized task that might have a dedicated skill (deployment, review, analysis, testing, documentation, etc.)
- Asks "how do I do X" where X might be a common task with an existing skill
- Says "find a skill for X" or "is there a skill for X"
- Asks "can you do X" where X is a specialized capability
- Expresses interest in extending agent capabilities
- Wants to search for tools, templates, or workflows
- Mentions they wish they had help with a specific domain (design, testing, deployment, etc.)
- Asks about the skill marketplace
- Wants to browse or discover available capabilities

> **Remember**: If the user's request involves a domain-specific task and you are not sure whether a specialized skill exists, ALWAYS search first. It is better to search and find nothing than to skip searching and provide a suboptimal general-purpose response.

---

## Search Flow

When the user triggers a search, you MUST query **both mandatory sources** to provide comprehensive results.

### Keyword Extraction (Critical)

The official marketplace uses **simple substring matching** — the entire `keyword` parameter is matched as a single string against name, nameCn, description, descriptionCn. It does NOT split on spaces, does NOT support multiple keywords in one query, and does NOT support semantic search.

> **IMPORTANT**: Each search call accepts only ONE keyword. Do NOT concatenate multiple terms into a single string like `"resume CV 简历"` — this will fail because no skill contains that exact substring. Instead, pick the single most relevant keyword per call, or make multiple calls with different keywords.

Before searching, you MUST extract concise, relevant keywords from the user's intent:

| User says | ❌ Wrong (multi-term string) | ✅ Correct (one keyword per call) |
|-----------|-------------------------------|------------------------------------|
| "帮我写一份简历" | `"resume CV 简历"` | `"resume"` or `"简历"` (separate calls) |
| "help me deploy to cloud" | `"deploy cloud app"` | `"deploy"` or `"cloudflare"` |
| "can you review my PR" | `"review pull request code"` | `"review"` or `"pr"` |
| "帮我做一个PPT" | `"ppt 演示 文档"` | `"ppt"` or `"演示"` |
| "我想用AI分析这份报告" | `"AI分析报告"` | `"数据分析"` or `"report"` |

**Keyword extraction rules:**
1. **ONE keyword per search call** — the `keyword` parameter is matched as a whole string, not split by spaces
2. Pick the single most relevant domain term (e.g., `"resume"` not `"resume writing help"`)
3. If the first keyword returns no results, try an alternative keyword in a second call (e.g., try `"简历"` after `"resume"` finds nothing)
4. For bilingual coverage: make one call with English keyword, one with Chinese keyword
5. For skills.sh (`npx skills find`), use English keywords only

### Source A: Official Marketplace (via qw MCP)

Search the unified marketplace:

```
mcp__qw-builtin__qw_query({
  key: "qoderwork.settings.skills.market",
  params: {
    keyword: "<extracted-keyword>",
    category: "<optional>",
    page: <optional>
  }
})
```

All parameters are optional. `page` supports pagination, page size is fixed at 10.

**Response format:**

- Returns: `{ success, data: { skills[], totalSize, currentPage, pageSize, hasMore } }` — each skill includes `id` (skill identifier / folderName, used as `folderName` when installing), `name`, `nameCn`, `description`, `descriptionCn`, `version`, `installed`, `category`, `installCount`. 

### Source B: skills.sh Community Skill Library (EQUALLY REQUIRED)

The skills.sh community search is NOT a supplement to the marketplace — it is an independent, equally mandatory search channel. Community skills often cover niche use cases, newer tools, and specialized workflows that the curated marketplace has not yet included.

**Search method:**

Run the find command with a relevant query:

```bash
npx skills find [query]
```

This searches the community skill ecosystem at [skills.sh](https://skills.sh/).

For example:

- User asks "how do I make my React app faster?" → `npx skills find react performance`
- User asks "can you help me with PR reviews?" → `npx skills find pr review`
- User asks "I need to create a changelog" → `npx skills find changelog`

The command will return results like:

```
Install with npx skills add <owner/repo@skill>

vercel-labs/agent-skills@vercel-react-best-practices
└ https://skills.sh/vercel-labs/agent-skills/vercel-react-best-practices
```

**Browse skills at:** https://skills.sh/

### Source C: Enterprise Skill Market MCP (Optional — Auto-detected)

This source is **conditionally activated**. Before searching, you need to dynamically detect whether any enterprise MCP service with skill search capabilities exists in the current session, rather than relying on any hardcoded service name.

**Activation check (detailed steps):**

1. Call `qw_mcp_list` to view all currently available MCP tools
2. In the returned tool list, look for any tool whose name contains `searchSkill` or similar skill search functionality (e.g., `mcp__<any-mcp-name>__searchSkills`)
3. If a matching tool is found, call `qw_mcp_get` to get the tool's detailed parameter schema and confirm it accepts search parameters like `keyword`
4. If confirmed → this source is **enabled**, proceed with the search below
5. If NO matching tool found → skip this source entirely (do not error, do not warn)

> **Note**: Do not hardcode any specific MCP service name. Use the dynamic detection flow described above to automatically discover any MCP service that provides the `searchSkills` capability.

**Search method:**

Call the detected enterprise MCP's searchSkills tool (use the actually detected tool name):

```
mcp__<detected-mcp-name>__searchSkills({
  keyword: "<extracted-keyword>"
})
```

The tool returns a list of skills with fields such as `name`, `description`, `downloadUrl`, `source`, and other metadata.

**Key differences from other sources:**
- This source is **optional** — only activate when the MCP and tool are detected
- Results from this source should be tagged as **Enterprise Skill** in the presentation
- Installation uses a different method (download + extract, not marketplace API or CLI)

### Search Strategy

- **Two mandatory steps + one conditional step**: 1️⃣ Search official marketplace (required), 2️⃣ Search skills.sh (required), 3️⃣ Search Enterprise Skill Market MCP (only if available). The search is NOT complete until both mandatory steps have been executed and the conditional step has been attempted. Do not proceed to presenting results until all applicable searches are done.
- **Why all sources matter**: The marketplace has curated, high-quality skills; skills.sh has community-contributed skills covering niche domains, newer tools, and specialized workflows. They serve different purposes and have different coverage — searching only one mandatory source means missing potential solutions.
- Extract the most relevant keyword(s) from the user's request before searching.
- Combine and deduplicate results from all available sources before presenting to the user.
- If one source returns no results, still present results from the other source.

---

## Present Results and Confirm

> **IMPORTANT**: Before executing ANY installation, you MUST use `AskUserQuestion` to present search results and get explicit user authorization. Never install without user confirmation.

After collecting results from all sources, present them in a unified list using `AskUserQuestion`, clearly distinguishing the source of each result:

```
AskUserQuestion({
  questions: [{
    question: "I found the following skills matching your request. Which would you like to install?",
    header: "Install",
    options: [
      {
        label: "<skill-name> (Official Skill)",
        description: "<brief-description> — Install count: <N> — ready to install"
      },
      {
        label: "<skill-name> (Enterprise Skill)",
        description: "<brief-description> — from Enterprise Skill Market"
      },
      {
        label: "<repo@skill-name> (Community - skills.sh)",
        description: "<brief-description> — from skills.sh"
      }
    ]
  }]
})
```

**Presentation rules:**

- **Results from ALL sources MUST be presented** — never omit community results just because official results exist. The user deserves to see the full picture.
- Each option MUST be clearly tagged with its source: **Official Skill** or **Community - skills.sh**
- **Ordering**: Official marketplace results listed first, then Enterprise Skill results (if any), then community skills.sh results. This is a SORT ORDER, not a filter — all sources with results must appear.
- Include install count for official skills when available
- Include brief descriptions to help users make informed choices
- **Do NOT manually add a "don't install" or "skip" option** — `AskUserQuestion` automatically provides an "Other" option for users who want to decline or type a custom response.
- If the user chooses "Other" to decline, end gracefully and offer to help directly with the task.

**Result selection constraints (MANDATORY):**

- **Total recommendations MUST NOT exceed 4** — regardless of how many results are returned across all sources, present at most 4 options to the user via `AskUserQuestion`.
- **Prioritize diversity across sources**: pick 1-2 most relevant results from EACH source that returned matches. For example: 1-2 official marketplace results + 1 enterprise result (if available) + 1-2 community skills.sh results, with the total capped at 4.
- Allocate slots fairly: at least 1 slot for each source that returned results, so the user sees coverage from all channels.
- If one source has many more results, briefly mention in the question text: "(N more results available from skills.sh — select Other to see more)"
- Do NOT dump all results into the options list — curate the most relevant subset to keep the selection concise and actionable.

---

## Installation

After the user confirms their choice, execute the appropriate installation based on the item type.

### Official Skill Installation

> **IMPORTANT**: Always obtain user confirmation via `AskUserQuestion` before calling this tool.

The `folderName` parameter should be the skill's `id` from the search results. This `id` is the skill's folder name identifier.

```
mcp__qw-builtin__qw_action({
  key: "qoderwork.settings.skills.market",
  action: "execute",
  params: {
    operation: "install",
    folderName: "<skill-id-from-search-results>"
  }
})
```

Example: if search returns a skill with `id: "deep-research"` and `name: "deep-research"`, use `folderName: "deep-research"`.

Response: `{ success, message, data: { folderName, version, fromCache } }`

### Community Skill Installation

> **IMPORTANT**: Always obtain user confirmation via `AskUserQuestion` before calling this tool.

There are multiple approaches depending on the skill's availability:

**Approach 1: If the skill is also available in the official marketplace**, use `install_skill` for a streamlined installation.

**Approach 2: Install via CLI (npx skills):**

```bash
npx skills add <owner/repo@skill> -g -y
```

The `-g` flag installs globally to `~/.agents/skills` and `-y` skips confirmation prompts.

After installation, create links to make the skill available in QoderWork:

**For regular environments (symbolic links):**

```bash
ln -sf ~/.agents/skills/<skill-name> ~/.qoderwork/skills/<skill-name>
```

**For virtual machine environments (copy files):**

```bash
cp -r ~/.agents/skills/<skill-name> ~/.qoderwork/skills/<skill-name>
```

**Tips for skills.sh discoveries:**
- Check the skill page on skills.sh for installation instructions and configuration details
- After installation, verify the skill is available and working correctly

### Enterprise Skill Installation (Agent-Executed)

> **IMPORTANT**: Always obtain user confirmation via `AskUserQuestion` before proceeding with installation.

When the user selects a skill from the Enterprise Skill Market source, the agent performs the installation directly. The `searchSkills` result provides `downloadUrl` and `skillName` (used as folder name).

**Installation target directory:** `~/.qoderwork/skills/<skillName>/`

#### Installation Script

The `find-skills` skill ships with dedicated installation scripts located in its own `scripts/` subdirectory. These scripts encapsulate the full installation flow: downloading the ZIP package, extracting, validating `SKILL.md` presence, backing up the existing version (if any), installing to the target directory, verifying, and cleaning up temporary files.

The agent only needs to invoke the appropriate script with the skill name and download URL. No inline multi-step commands are required.

#### Platform-Specific Invocation

Detect the user's operating system first, then call the corresponding script.

**macOS / Linux (Bash/Zsh):**

```bash
bash ~/.qoderwork/skills/find-skills/scripts/install-skill.sh --name "<skillName>" --url "<downloadUrl>"
```

**Windows:**

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "$HOME\.qoderwork\skills\find-skills\scripts\install-skill.ps1" -Name "<skillName>" -Url "<downloadUrl>"
```

This command works from any shell (CMD, PowerShell, or Bash/Git Bash on Windows). The `-ExecutionPolicy Bypass` flag is already included, so no additional configuration is needed.

#### Script Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--name` / `-Name` | Yes | The skill's folder name (from `skillName` in search results) |
| `--url` / `-Url` | Yes | The download URL for the skill ZIP package (from `downloadUrl` in search results) |
| `--target-dir` / `-TargetDir` | No | Override the default install directory (`~/.qoderwork/skills`). Rarely needed. |

#### What the Script Does Internally

1. Downloads the ZIP from the provided URL (follows redirects)
2. Extracts to a temporary directory
3. Validates the package contains a `SKILL.md` file (ignores `__MACOSX` and hidden files)
4. Locates the skill root (the directory directly containing `SKILL.md`)
5. Backs up the existing version if `~/.qoderwork/skills/<skillName>` already exists
6. Installs the skill to `~/.qoderwork/skills/<skillName>/`
7. Verifies that `SKILL.md` is readable at the install path
8. Cleans up all temporary files

The script prints status messages and exits with code 0 on success or non-zero on failure.

#### Error Handling

| Error | Action |
|-------|--------|
| Download fails (network error, 404, auth required) | Inform user, suggest checking network or retrying |
| ZIP extraction fails | Inform user the package may be corrupted |
| SKILL.md not found in package | Inform user the package is invalid, not a valid skill |
| Move/copy fails (permission denied) | Inform user, suggest checking directory permissions |
| Any failure | Always clean up temporary files before reporting the error |

#### Success

After successful installation, confirm to the user:
- Skill name and install path
- The skill is immediately available for use (no session restart needed)
- Proceed to the **Post-Installation: Immediate Activation** section to invoke the skill if applicable

---

## Post-Installation: Immediate Activation

**Key point**: After installation, the skill is immediately available — no need to start a new session.

This works because QoderCLI's `GetSkill(name)` method performs a real-time disk scan on every invocation. Once the skill files are written to disk, the current session can discover and load them via the `Skill` tool.

**Follow this sequence after successful installation:**

1. If the user's original request can be served by the newly installed skill, **immediately invoke it**:
   ```
   Skill({ skill: "<installed-skill-name>" })
   ```
2. Pass the user's original request as `args` if applicable:
   ```
   Skill({ skill: "<installed-skill-name>", args: "<user-original-request>" })
   ```
3. Inform the user that the skill has been installed and is being activated now.

> **Note**: The newly installed skill will NOT appear in the `<available_skills>` list (that list is built only at session initialization). However, the `Skill` tool's runtime lookup performs a live disk scan, so it can find and load the skill regardless. Do not be confused by its absence from the available skills list.

---

## Common Skill Categories

When searching, consider these common categories to help extract better keywords:

| Category | Example Queries |
|----------|----------------|
| Web Development | react, nextjs, typescript, css, tailwind |
| Testing | testing, jest, playwright, e2e |
| DevOps | deploy, docker, kubernetes, ci-cd |
| Documentation | docs, readme, changelog, api-docs |
| Code Quality | review, lint, refactor, best-practices |
| Design | ui, ux, design-system, accessibility |
| Productivity | workflow, automation, git |
| Data Analysis | data, sql, analytics, visualization |

---

## When No Results Are Found

If all sources return no matching results:

1. Inform the user that no existing skills were found for their query
2. Offer to help with the task directly using your general capabilities
3. Suggest the user could create their own skill:

```
I searched the official marketplace and community ecosystem for "<query>" but didn't find any matches.

I can still help you with this task directly! Would you like me to proceed?

If this is something you do often, you could create your own skill:
npx skills init my-custom-skill
```

---

## Important Rules

1. **Search is a two-step mandatory checklist + one conditional step (marketplace + skills.sh + enterprise MCP if available)** — Both mandatory steps must be executed on every invocation. The enterprise MCP step is conditional — only execute if the MCP and its `searchSkills` tool are detected. A search that only covers one mandatory source is incomplete. Do not present results or proceed until all applicable searches are done.
2. **Always present results from ALL sources that returned matches** — "Official first, then Community" is sort order only, NOT filtering. If any source returned results, they MUST appear in the options.
3. **Always use AskUserQuestion before installing** — This is a mandatory step. Present results and wait for explicit user confirmation.
4. **Never install without explicit user confirmation** — Under no circumstances should you skip the confirmation step and proceed to install directly.
5. **Do NOT add a manual "skip/decline" option** — `AskUserQuestion` automatically provides "Other" for this purpose. Use all available option slots for actual search results.
6. **Immediately activate after installation** — Once installation succeeds, invoke the skill via the `Skill` tool if the user's original request can be served by it. Do not ask the user to start a new session.
7. **Handle errors gracefully** — If an installation fails, inform the user of the error, suggest alternatives (try another result, manual installation, or direct help), and do not leave the conversation in a broken state.
