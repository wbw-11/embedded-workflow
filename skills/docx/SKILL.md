---
name: docx
version: 2.0.0
description: "Word(.docx) 文档处理：生成/读取/编辑/套模板，Markdown 转 Word，中文排版，修订/批注/OOXML。触发：Word 文档、报告、备忘录、信函、合同、会议纪要、md 转 docx、tracked changes。PDF/Excel/纯代码任务勿用。"
description_zh: "全功能 Word(.docx) 技能：端到端创建、读取、编辑和操作 Word 文档。覆盖 Markdown/结构化文本转 Word、模板套用（{{token}} 或 reference-doc 两种）、正确的中文排版默认值、用 docx-js 从零定制文档、以及 OOXML 底层修补（含修订标记、批注）。触发词：'Word 文档'、'.docx'、'报告/备忘录/信函/合同/会议纪要'、'Markdown 转 Word'、'md 转 docx'、'套模板生成 Word'、'中文 Word 报告'、'修订标记'、'Word 批注'、'OOXML'，以及插入/替换图片、查找替换、把内容转为精美 Word 文档等请求。不适用于 PDF、电子表格、Google Docs 或与文档生成无关的编程任务。"
license: Proprietary
---

# docx-pro: Complete Word document skill

Single self-contained skill for everything related to `.docx` files —
high-frequency Markdown/template workflows on top, full docx-js generation in
the middle, and low-level OOXML patching at the bottom.

A `.docx` file is a ZIP container holding a tree of XML files conforming to the
OOXML standard. This skill works at every layer: composing Markdown and
rendering with pandoc, generating from scratch with docx-js, and unpacking the
archive to edit XML directly.

---

## ⚠️ Golden Rule: Compose first, render second

**The user's request/spec is NOT your Markdown input.** You must:

1. **Read and understand** the user's requirements (content, structure, data).
2. **Compose** a clean, publication-ready Markdown file containing ONLY the
   final document content — no meta-instructions, no "排版要求" sections, no
   "用表格呈现：" directives, no formatting instructions.
3. **Then** feed that composed Markdown to the renderer.

```
❌ WRONG:  python scripts/md_to_docx.py 需求.md output.docx        # BAD!  (piping spec)
✅ CORRECT: python scripts/md_to_docx.py content.md output.docx    # GOOD  (your composed file)
```

If the user explicitly says "把这个 Markdown 文件原样转成 Word" (convert this
exact Markdown as-is), only then may you skip the composition step.

**Self-check before rendering:** Open your composed `.md` and ask: "Would I
hand this text directly to a client/boss as the document body?" If it contains
anything a reader shouldn't see (instructions, meta-commentary, formatting
directives, section labels like "排版要求"), remove it before rendering.

---

## Decision Matrix

| Goal | Pathway |
|------|---------|
| User gives a brief/spec → produce a Word doc | §Standard workflow → §Markdown pipeline |
| User has a finished Markdown file → format as Word | §Markdown pipeline (skip composition) |
| Fill a reusable template with placeholder values | §Template fill |
| Chinese-language doc with correct CJK typography | §Chinese typography |
| Build a fully custom doc from scratch | §Generating from scratch with docx-js |
| Modify an existing `.docx` file | §Patching existing documents |
| Inspect / extract text | `pandoc` or §Patching → unpack to browse raw XML |
| Tracked changes, comments, paragraph-level XML | §XML patterns + §Patching existing documents |

---

## Standard workflow (requirement → docx)

When the user gives you a task description, brief, or specification — NOT a
finished Markdown file they want converted as-is — follow these steps in order:

1. **Understand the requirement** — identify: document type, target audience,
   required content (specific data, tables, lists), and formatting preferences
   (Chinese/English, font, layout).
2. **Choose a template** — pick the closest match from `templates/`. If none
   fits, use `report-standard.docx` as a general-purpose default.
3. **Compose the Markdown** — write a NEW `.md` file with ONLY the final
   document content a reader would see (headings, prose, pipe tables, lists).
   **NO** "排版要求", "用表格呈现：", "用有序列表：", or any instructional/meta
   text from the spec.
4. **Run doctor** — `python scripts/doctor.py` (once per session) to choose the
   rendering engine.
5. **Render** — call `md_to_docx.py` (pandoc) or `md_to_docx.mjs` (Node
   fallback) on your **composed** file — never on the original spec file.
6. **Validate + preview** — run `validate.py` and (if available) `preview.py`.

---

## First step: environment check

Always run the doctor once per task before generating:

```bash
python scripts/doctor.py
```

Engine selection based on results:

- **pandoc available** → preferred for Markdown→docx (fastest, template-aware).
- **pandoc missing, node available** → use `scripts/md_to_docx.mjs` (covers
  headings, lists, tables, bold/italic, code, images, blockquotes).
- **soffice available** → enables `scripts/preview.py` self-check screenshots.
- All missing → tell the user which dependency to install (doctor prints the
  per-platform command).

---

# Part A: Markdown pipeline

Convert a Markdown file (or content you wrote to a temp `.md`) into `.docx`.

> **Important:** The input `.md` must contain publication-ready content only.
> If working from a user's requirement spec, first compose a clean content
> file (see §Standard workflow) — never feed a spec/brief directly to renderer.

**Preferred (pandoc):**

```bash
python scripts/md_to_docx.py input.md output.docx \
  --reference templates/report-standard.docx --toc
```

**Fallback (Node, no pandoc):**

```bash
node scripts/md_to_docx.mjs input.md output.docx --cjk
```

**After generating — validate + preview:**

```bash
python scripts/office/validate.py output.docx
python scripts/preview.py output.docx --pages 1,2,last  # if soffice present
```

> `validate.py` passing does NOT mean the layout is visually correct. For
> multi-page or table-heavy docs, render pages 1–2 and inspect for margin
> overflow, squeezed tables, missing fonts, or empty TOC.
>
> Detailed engine behavior: see [reference.md](reference.md) §Markdown pipeline details.

---

# Part B: Template fill

Generate a standard document by filling a template instead of building from
scratch. Templates live in `templates/`:

| File | Use for |
|------|---------|
| `report-standard.docx` | A4 report: cover, TOC, H1–H3, header/footer, page numbers |
| `memo.docx` | Memo with To / From / Subject / Date header block |
| `letter.docx` | Business letter with letterhead and signature block |
| `contract.docx` | Contract skeleton with numbered clauses and signature area |
| `meeting-minutes.docx` | Meeting minutes: attendees, agenda, decisions table |

> The shipped templates are minimal style references. If a template file is
> missing or you need a richer one, build it once with §Generating from scratch
> and drop it into `templates/` for reuse.

**Reference-document workflow** (render Markdown body against a template):

```bash
python scripts/md_to_docx.py body.md output.docx --reference templates/memo.docx
```

**Placeholder workflow** (`{{token}}` replacement, safe across split runs):

```bash
python scripts/fill_template.py templates/contract.docx output.docx \
  --set title="服务采购合同" --set party_a="甲方公司" --set date="2026-06-17"
```

`fill_template.py` always writes a new output file and never edits the template
in place.

---

# Part C: Chinese typography

Western-only fonts (e.g. Arial) trigger Word's font fallback for CJK text,
producing inconsistent rendering across macOS / Windows / WPS. When the
document is primarily Chinese, apply the CJK preset.

- **Node renderer:** pass `--cjk` to `md_to_docx.mjs`.
- **Custom docx-js code:** import the preset from `scripts/styles/zh-cn.js`.

Rules for Chinese documents:

- Always declare `eastAsia` explicitly; never rely on `ascii` font alone.
- Body text: 1.5 line spacing, 2-character first-line indent.
- Headings: no first-line indent, bold, black.
- Default heading font: `Microsoft YaHei`; body can use `SimSun`/`宋体` if the
  user prefers a print look — ask if unsure.

> Full preset code (font, spacing, indent values): see [reference.md](reference.md) §Chinese typography preset.

---

# Part D: Generating from scratch with docx-js

Produce `.docx` files via JavaScript when no template fits and the layout is
custom. Install: `npm install -g docx`. After generating, validate with
`python scripts/office/validate.py doc.docx`. If the validator reports issues,
unpack, repair the XML, and repackage.

## Essential docx-js Rules (Pitfalls)

- **Page size:** defaults to A4; US Letter = 12 240 × 15 840 DXA
- **Landscape:** supply portrait dimensions + `PageOrientation.LANDSCAPE`
- **No `\n`:** create separate Paragraph objects
- **No Unicode bullets:** use `LevelFormat.BULLET` via numbering API
- **PageBreak inside Paragraph only**
- **ImageRun requires `type`**
- **Table `width` must use DXA** — `PERCENTAGE` breaks in Google Docs
- **Dual-width rule:** set `columnWidths` on table AND `width` on every cell
- **Table width = Σ columnWidths**
- **Cell margins:** `{ top: 80, bottom: 80, left: 120, right: 120 }` for readable padding
- **Use `ShadingType.CLEAR`** — never SOLID for cell fills
- **Avoid tables as dividers:** use border on Paragraph instead; for side-by-side footer content use tab stops
- **TOC only with HeadingLevel**
- **Override styles by ID:** "Heading1", "Heading2", etc.
- **Provide `outlineLevel`** for TOC (0 = H1, 1 = H2 …)

> Complete code templates for every docx-js feature (bootstrap, page setup,
> headings, lists, tables, images, hyperlinks, footnotes, tab stops,
> multi-column, TOC, headers/footers): see [reference.md](reference.md) §docx-js API reference.

---

# Part E: Patching existing documents

Execute all three stages in order.

**Stage 1 — Unpack:**

```bash
python scripts/office/unpack.py document.docx unpacked/
```

Inflates the archive, pretty-prints XML, coalesces adjacent runs, and encodes
typographic quotes as XML entities. Pass `--merge-runs false` to skip run
coalescing.

**Stage 2 — Edit the XML** — work inside `unpacked/word/`. Refer to §XML
patterns in [reference.md](reference.md).

- **Use "Claude" as the author** for tracked changes and comments, unless the
  user specifies otherwise.
- **Use the Edit tool for string replacements — do not write Python scripts.**
  The Edit tool makes every replacement visible and auditable.
- **Use typographic (smart) quotes** for new text (e.g. `&#x2019;`, `&#x201C;`,
  `&#x201D;`). Full entity table in [reference.md](reference.md).
- **Inserting comments** — `comment.py` handles the multi-file boilerplate:

```bash
python scripts/comment.py unpacked/ 0 "Comment text with &amp; and &#x2019;"
python scripts/comment.py unpacked/ 1 "Reply text" --parent 0
```

**Stage 3 — Repack:**

```bash
python scripts/office/pack.py unpacked/ output.docx --original document.docx
```

Validates with automatic repair, condenses XML, produces the final DOCX. Pass
`--validate false` to bypass.

**Auto-repair corrects:** `durableId` values ≥ 0x7FFFFFFF; missing
`xml:space="preserve"` on `<w:t>` with leading/trailing whitespace.
**Does NOT fix:** malformed XML, illegal nesting, broken relationships, schema
violations.

**Gotchas:**
- **Swap whole `<w:r>` blocks:** when introducing tracked changes, replace the
  entire run — never splice change-tracking tags inside an existing run.
- **Carry forward `<w:rPr>`:** copy original formatting properties into new
  tracked-change runs.

---

# Part F: XML patterns

For tracked changes, comments, image insertion, and full schema ordering rules,
see [reference.md](reference.md) §XML patterns. Key reminders:

- **`<w:pPr>` child order:** `<w:pStyle>` → `<w:numPr>` → `<w:spacing>` → `<w:ind>` → `<w:jc>` → `<w:rPr>` last
- **Whitespace:** attach `xml:space="preserve"` to any `<w:t>` with leading/trailing spaces
- **RSIDs:** 8-character hexadecimal (e.g. `00AB1234`)
- Inside `<w:del>`: use `<w:delText>` instead of `<w:t>`, `<w:delInstrText>` instead of `<w:instrText>`.
- `<w:commentRangeStart>` and `<w:commentRangeEnd>` are siblings of `<w:r>` — never inside a run.

---

## Verification

Every docx task ends with one or more of:

1. **`python scripts/office/validate.py output.docx`** — schema validation passes.
2. **`python scripts/preview.py output.docx --pages 1,2,last`** — visual self-check
   (needs LibreOffice): margins OK, tables fit, fonts present, TOC populated.
3. **Open the file** (or the rendered preview images) and confirm the content
   matches the user's intent — no leftover meta-instructions, no missing
   sections, placeholder tokens all resolved.

For multi-page or table-heavy docs, **preview is mandatory** — `validate.py`
passing does not guarantee visual correctness.

---

## Additional resources

- For deeper Markdown→docx mapping and edge cases, see [reference/pipeline.md](reference/pipeline.md).
- For template authoring and placeholder conventions, see [reference/templates.md](reference/templates.md).
- Utility scripts, external dependencies, and common operations: see [reference.md](reference.md).
- **完整参考文档见同目录 [reference.md](reference.md)**（详细 API、完整代码示例、XML 模式、模板内容）。
