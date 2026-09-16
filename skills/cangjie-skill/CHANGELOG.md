# Changelog

版本口径：`cangjie.version`（根 `SKILL.md` metadata）是唯一权威版本号。
schema 各自带 `schema_version` 独立演进；宿主锁定的盲测与阈值定标是另行记录的运行时证据，
不与仓库发布版本号混为一谈。

## [2.5.0] - 2026-08-30

基于《倉頡 Skill 优化方案》v1.3.1（`docs/plans/2026-08-23-cangjie-skill-optimization-plan.md`）
的正式发布。产品目标：解决「一本书蒸馏出十几个 Skill」的安装/认知成本问题，
同时把蒸馏、编译、更新、修复和评测收敛为可复现的工程链路。

### Added

- **DeepSeek Harness v2.5.0 Bundle**：补充 `dsh-cangjie-skill-2.5.0.tgz`
  与 SHA256 校验文件；包内包含 Capability Bundle 方法论、统一 CLI、schemas、
  extractors、templates 和迁移文档，并通过临时 `DSH_HOME` 安装与配置识别验证。
- **Capability Bundle 单一事实源**（`.cangjie/capabilities/`）与全套 schema：
  `capability` / `capability-bundle` / `output-decision` / `source-manifest` /
  `change-set` / `dependency-graph` / `eval-suite` / `failure-case` /
  `contracts/source-document` / `contracts/chunk`。
- **双输出模式编译器**：`compile_single.py`（single / router 视图）、
  `compile_pack.py`（compact pack，含 destinations 不变量校验）、
  `select_output_strategy.py`（single-first-v1 auto 决策）。
- **统一 CLI `cangjie.py`**：doctor / migrate-legacy / compile / replan-output /
  update / repair / rollback / eval / benchmark。发布链路带 per-run workdir、
  写锁、staging 校验、本地手改检测（三选一保护）、原子发布与快照回滚。
- **阶段 1.6 晋级门**（`methodology/03b-stage1.6-promotion-gate.md`）：
  五判据 + 预算约束 + split-on-evidence 演化机制。
- **预处理确定性层**：`build_chunks.py`（SourceDocument + 结构化 chunk + 确定性缓存）、
  `build_index.py`（SQLite FTS5，中文 bigram）；提取器分型
  （framework/principle 全文扫描，case/counter-example/glossary 检索式 + 硬覆盖门）。
- **增量更新与修复**：`diff_sources.py`（chunk 级 diff → change-set）、
  `impact_analysis.py`（依赖图构建 + 影响分析）、`apply_skill_patch.py`
  （事务性补丁 + 自动回滚）、`update_flow.py` / `repair_flow.py`
  （九类诊断分类，语义环节交给 Agent）。
- **评测工具链**：`run_trigger_evals.py`（固定种子切分 / 盲测任务包 / 判分）、
  `run_output_evals.py`（匿名三变体 / 机械断言）、`benchmark.py`（A 类静态指标 +
  过程代理指标聚合）。
- **Registry v2**：`registry-entry.schema.json` 改为 v1/v2 `oneOf` 分发器，
  v2 新增 `output_mode` / `entrypoint_count` / `capability_count` / `router_entrypoint`；
  网站目录、卡片、安装提示按模式展示；`validate-registry.mjs` 强制 v2 不变量。
- **CI**：`pipeline-check.yml`（books 包校验、Bundle schema 校验、编译确定性冒烟）。
- **基准资产**：Naval 试点 Bundle 回填、50 条任务集（task-set-v2）、
  静态路由评测报告、正式编译产物 A 类指标（`benchmarks/naval/metrics-v2/`）。
- **官网依赖安全升级**：Astro 升级到 7.2.9、js-yaml 升级到 5.4.1，
  发布锁文件通过 `npm audit`（0 vulnerabilities）。

### Changed

- 根 `SKILL.md` 与 `methodology/` 阶段 2–5：产出对象从 SKILL.md 文件改为
  Bundle 能力卡 + 元数据，交付统一走 `cangjie.py compile`。
- 阶段 0 新增「目的」输入（通读吸收 / 高频任务），作为输出模式决策依据。

### Deprecated

- 「一书一堆平铺 Skill」（legacy pack）不再是新蒸馏的产出形态；
  已有产物继续被 registry v1 与网站兼容。迁移见
  `docs/migrations/2026-08-25-v2.0-to-v2.1.md`。
