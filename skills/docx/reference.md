# docx skill — reference

This file contains the detailed API, complete code examples, XML patterns, and
reference tables extracted from `SKILL.md`. The parent `SKILL.md` keeps only
the core workflows, decision points, pitfalls, and verification steps.

---

## §Markdown pipeline details

### Preferred: pandoc

```bash
python scripts/md_to_docx.py input.md output.docx \
  --reference templates/report-standard.docx \
  --toc
```

`md_to_docx.py` wraps pandoc and automatically:
- resolves relative image paths against the Markdown file's directory,
- inserts a Table of Contents field when `--toc` is passed,
- applies a reference document for styling (defaults to a clean A4 style),
- preserves fenced code blocks and tables.

### Fallback: Node renderer (no pandoc required)

```bash
node scripts/md_to_docx.mjs input.md output.docx --cjk
```

Requires the global `docx` npm package. The `--cjk` flag applies Chinese
typography defaults (see §Chinese typography preset). Supported Markdown:
headings (#–######), ordered/unordered lists (nested), tables,
bold/italic/inline-code, fenced code blocks, blockquotes, images, horizontal
rules, and links.

### After generating: validate + preview

```bash
python scripts/office/validate.py output.docx
python scripts/preview.py output.docx --pages 1,2,last  # if soffice present
```

`validate.py` passing does NOT mean the layout is visually correct. For any
multi-page or table-heavy document, render at least pages 1–2 and inspect them
for margin overflow, squeezed tables, missing fonts, or empty TOC.

---

## §Chinese typography preset

```javascript
// scripts/styles/zh-cn.js (summary)
run:  { font: { ascii: "Arial", eastAsia: "Microsoft YaHei" }, size: 24 } // 12pt
paragraph: {
  spacing: { line: 360, lineRule: "auto" },   // 1.5x line spacing
  indent:  { firstLine: 480 }                  // 2 chars first-line indent
}
// Headings keep eastAsia bold font, black color, no first-line indent
```

---

## §docx-js API reference

Produce `.docx` files via JavaScript when no template fits and the layout is
custom. Install: `npm install -g docx`.

### Bootstrap

```javascript
const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, ImageRun,
        Header, Footer, AlignmentType, PageOrientation, LevelFormat, ExternalHyperlink,
        InternalHyperlink, Bookmark, FootnoteReferenceRun, PositionalTab,
        PositionalTabAlignment, PositionalTabRelativeTo, PositionalTabLeader,
        TabStopType, TabStopPosition, Column, SectionType,
        TableOfContents, HeadingLevel, BorderStyle, WidthType, ShadingType,
        VerticalAlign, PageNumber, PageBreak } = require('docx');

const doc = new Document({ sections: [{ children: [/* content */] }] });
Packer.toBuffer(doc).then(buf => fs.writeFileSync("doc.docx", buf));
```

### Validation

```bash
python scripts/office/validate.py doc.docx
```

If the validator reports issues, unpack, repair the XML, and repackage.

### Page Dimensions

```javascript
// docx-js defaults to A4; US Letter must be set explicitly.
sections: [{
  properties: {
    page: {
      size: { width: 12240, height: 15840 },         // 8.5 × 11 in (DXA)
      margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }  // 1-inch
    }
  },
  children: [/* body content */]
}]
```

**Paper sizes (DXA; 1440 DXA = 1 inch):**

| Format | Width | Height | Usable width (1 in margins) |
|--------|-------|--------|-----------------------------|
| US Letter | 12 240 | 15 840 | 9 360 |
| A4 (default) | 11 906 | 16 838 | 9 026 |

**Landscape:** Always supply portrait dimensions — docx-js internally transposes them:

```javascript
size: {
  width: 12240,   // short edge
  height: 15840,  // long edge
  orientation: PageOrientation.LANDSCAPE
},
// Effective content width = 15840 − left − right (long edge becomes horizontal)
```

### Heading Styles

Default to Arial for broad compatibility. Keep heading text black.

```javascript
const doc = new Document({
  styles: {
    default: { document: { run: { font: "Arial", size: 24 } } },  // 12 pt base
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 32, bold: true, font: "Arial" },
        paragraph: { spacing: { before: 240, after: 240 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 28, bold: true, font: "Arial" },
        paragraph: { spacing: { before: 180, after: 180 }, outlineLevel: 1 } },
    ]
  },
  sections: [{
    children: [
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Title")] }),
    ]
  }]
});
```

### Lists (NEVER use Unicode bullet characters)

```javascript
// ❌ WRONG — literal bullet glyphs produce broken output
new Paragraph({ children: [new TextRun("• Item")] })   // BAD
new Paragraph({ children: [new TextRun("\u2022 Item")] })  // BAD

// ✅ CORRECT — use LevelFormat.BULLET via numbering configuration
const doc = new Document({
  numbering: {
    config: [
      { reference: "bullets",
        levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "numbers",
        levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
    ]
  },
  sections: [{
    children: [
      new Paragraph({ numbering: { reference: "bullets", level: 0 },
        children: [new TextRun("Bullet item")] }),
      new Paragraph({ numbering: { reference: "numbers", level: 0 },
        children: [new TextRun("Numbered item")] }),
    ]
  }]
});

// ⚠️ Same reference → continuous (1,2,3…4,5,6); different references → restart (1,2,3…1,2,3)
```

### Tables

**Both `columnWidths` on Table AND `width` on every TableCell are required.**

```javascript
const borderDef = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const allBorders = { top: borderDef, bottom: borderDef, left: borderDef, right: borderDef };

new Table({
  width: { size: 9360, type: WidthType.DXA },  // always DXA, never PERCENTAGE
  columnWidths: [4680, 4680],                   // must sum to table width
  rows: [
    new TableRow({
      children: [
        new TableCell({
          borders: allBorders,
          width: { size: 4680, type: WidthType.DXA },  // must match columnWidths entry
          shading: { fill: "D5E8F0", type: ShadingType.CLEAR },  // CLEAR, never SOLID
          margins: { top: 80, bottom: 80, left: 120, right: 120 },
          children: [new Paragraph({ children: [new TextRun("Cell")] })]
        })
      ]
    })
  ]
})
```

**Width computation:**

```javascript
// table width = Σ columnWidths = page width − both margins
// US Letter + 1 in margins: 12240 − 2880 = 9360 DXA
width: { size: 9360, type: WidthType.DXA },
columnWidths: [7000, 2360]  // must sum to 9360
```

**Table rules:**
- Always `WidthType.DXA` — `PERCENTAGE` breaks in Google Docs
- Cell `width` must equal its corresponding `columnWidths` entry
- Cell `margins` are inward padding (shrink content area, don't add to cell width)
- Full-width: set width to page width minus both lateral margins

### Images

```javascript
new Paragraph({
  children: [new ImageRun({
    type: "png",  // required; accepted: png, jpg, jpeg, gif, bmp, svg
    data: fs.readFileSync("image.png"),
    transformation: { width: 200, height: 150 },
    altText: { title: "Title", description: "Desc", name: "Name" }  // all three required
  })]
})
```

### Page Breaks

```javascript
// PageBreak MUST live inside a Paragraph
new Paragraph({ children: [new PageBreak()] })

// Alternative: pageBreakBefore
new Paragraph({ pageBreakBefore: true, children: [new TextRun("New page")] })
```

### Hyperlinks

```javascript
// External URL
new Paragraph({
  children: [new ExternalHyperlink({
    children: [new TextRun({ text: "Click here", style: "Hyperlink" })],
    link: "https://example.com",
  })]
})

// In-document cross-reference
// 1. Place bookmark at destination
new Paragraph({ heading: HeadingLevel.HEADING_1, children: [
  new Bookmark({ id: "chapter1", children: [new TextRun("Chapter 1")] }),
]})
// 2. Link to it
new Paragraph({ children: [new InternalHyperlink({
  children: [new TextRun({ text: "See Chapter 1", style: "Hyperlink" })],
  anchor: "chapter1",
})]})
```

### Footnotes

```javascript
const doc = new Document({
  footnotes: {
    1: { children: [new Paragraph("Source: Annual Report 2024")] },
    2: { children: [new Paragraph("See appendix for methodology")] },
  },
  sections: [{
    children: [new Paragraph({
      children: [
        new TextRun("Revenue grew 15%"),
        new FootnoteReferenceRun(1),
        new TextRun(" using adjusted metrics"),
        new FootnoteReferenceRun(2),
      ],
    })]
  }]
});
```

### Tab Stops

```javascript
// Right-aligned text on the same line
new Paragraph({
  children: [new TextRun("Company Name"), new TextRun("\tJanuary 2025")],
  tabStops: [{ type: TabStopType.RIGHT, position: TabStopPosition.MAX }],
})

// Dot-leader (TOC-style)
new Paragraph({
  children: [
    new TextRun("Introduction"),
    new TextRun({ children: [
      new PositionalTab({
        alignment: PositionalTabAlignment.RIGHT,
        relativeTo: PositionalTabRelativeTo.MARGIN,
        leader: PositionalTabLeader.DOT,
      }),
      "3",
    ]}),
  ],
})
```

### Multi-column Layouts

```javascript
// Evenly spaced columns
sections: [{
  properties: {
    column: { count: 2, space: 720, equalWidth: true, separate: true },
  },
  children: [/* text flows across columns automatically */]
}]

// Custom widths
sections: [{
  properties: {
    column: {
      equalWidth: false,
      children: [new Column({ width: 5400, space: 720 }), new Column({ width: 3240 })],
    },
  },
  children: [/* content */]
}]
```

Explicit column break: add a new section with `type: SectionType.NEXT_COLUMN`.

### Table of Contents

```javascript
// Headings MUST use HeadingLevel — custom paragraph styles are invisible to the TOC.
new TableOfContents("Table of Contents", { hyperlink: true, headingStyleRange: "1-3" })
```

### Headers and Footers

```javascript
sections: [{
  properties: {
    page: { margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } }
  },
  headers: {
    default: new Header({ children: [new Paragraph({ children: [new TextRun("Header")] })] })
  },
  footers: {
    default: new Footer({ children: [new Paragraph({
      children: [new TextRun("Page "), new TextRun({ children: [PageNumber.CURRENT] })]
    })] })
  },
  children: [/* body */]
}]
```

---

## §Patching existing documents — details

### Smart quote entities

| Entity | Character |
|--------|-----------|
| `&#x2018;` | ' (left single) |
| `&#x2019;` | ' (right single / apostrophe) |
| `&#x201C;` | " (left double) |
| `&#x201D;` | " (right double) |

Example:

```xml
<w:t>Here&#x2019;s a quote: &#x201C;Hello&#x201D;</w:t>
```

### comment.py — full invocation patterns

```bash
python scripts/comment.py unpacked/ 0 "Comment text with &amp; and &#x2019;"
python scripts/comment.py unpacked/ 1 "Reply text" --parent 0
python scripts/comment.py unpacked/ 0 "Text" --author "Custom Author"
```

After calling `comment.py`, wire range markers into `document.xml` (see §XML
patterns → Comments). Text must be XML-escaped.

---

## §XML patterns

### Schema Ordering

- **`<w:pPr>` child order:** `<w:pStyle>` → `<w:numPr>` → `<w:spacing>` → `<w:ind>` → `<w:jc>` → `<w:rPr>` last
- **Whitespace:** attach `xml:space="preserve"` to any `<w:t>` with leading/trailing spaces
- **RSIDs:** 8-character hexadecimal (e.g. `00AB1234`)

### Tracked Changes

**Insertion:**

```xml
<w:ins w:id="1" w:author="Claude" w:date="2025-01-01T00:00:00Z">
  <w:r><w:t>inserted text</w:t></w:r>
</w:ins>
```

**Deletion:**

```xml
<w:del w:id="2" w:author="Claude" w:date="2025-01-01T00:00:00Z">
  <w:r><w:delText>deleted text</w:delText></w:r>
</w:del>
```

Inside `<w:del>`: use `<w:delText>` instead of `<w:t>`, `<w:delInstrText>` instead of `<w:instrText>`.

**Minimal-footprint edit (change "30 days" to "60 days"):**

```xml
<w:r><w:t>The term is </w:t></w:r>
<w:del w:id="1" w:author="Claude" w:date="...">
  <w:r><w:delText>30</w:delText></w:r>
</w:del>
<w:ins w:id="2" w:author="Claude" w:date="...">
  <w:r><w:t>60</w:t></w:r>
</w:ins>
<w:r><w:t> days.</w:t></w:r>
```

**Deleting a complete paragraph** — flag the paragraph mark so the empty shell merges with the next paragraph:

```xml
<w:p>
  <w:pPr>
    <w:numPr>...</w:numPr>
    <w:rPr>
      <w:del w:id="1" w:author="Claude" w:date="2025-01-01T00:00:00Z"/>
    </w:rPr>
  </w:pPr>
  <w:del w:id="2" w:author="Claude" w:date="2025-01-01T00:00:00Z">
    <w:r><w:delText>Entire paragraph content being deleted...</w:delText></w:r>
  </w:del>
</w:p>
```

Without the `<w:del/>` in `<w:pPr><w:rPr>`, accepting leaves a blank paragraph.

**Rejecting another author's insertion:**

```xml
<w:ins w:author="Jane" w:id="5">
  <w:del w:author="Claude" w:id="10">
    <w:r><w:delText>their inserted text</w:delText></w:r>
  </w:del>
</w:ins>
```

**Restoring another author's deletion:**

```xml
<w:del w:author="Jane" w:id="5">
  <w:r><w:delText>deleted text</w:delText></w:r>
</w:del>
<w:ins w:author="Claude" w:id="10">
  <w:r><w:t>deleted text</w:t></w:r>
</w:ins>
```

### Comments

After calling `comment.py`, add range markers in document.xml. For replies, use
`--parent` and nest child markers inside the parent's range.

**Rule: `<w:commentRangeStart>` and `<w:commentRangeEnd>` are siblings of
`<w:r>` — never inside a run.**

```xml
<!-- Standalone comment -->
<w:commentRangeStart w:id="0"/>
<w:del w:id="1" w:author="Claude" w:date="2025-01-01T00:00:00Z">
  <w:r><w:delText>deleted</w:delText></w:r>
</w:del>
<w:r><w:t> more text</w:t></w:r>
<w:commentRangeEnd w:id="0"/>
<w:r><w:rPr><w:rStyle w:val="CommentReference"/></w:rPr><w:commentReference w:id="0"/></w:r>

<!-- Comment 0 with nested reply 1 -->
<w:commentRangeStart w:id="0"/>
  <w:commentRangeStart w:id="1"/>
  <w:r><w:t>text</w:t></w:r>
  <w:commentRangeEnd w:id="1"/>
<w:commentRangeEnd w:id="0"/>
<w:r><w:rPr><w:rStyle w:val="CommentReference"/></w:rPr><w:commentReference w:id="0"/></w:r>
<w:r><w:rPr><w:rStyle w:val="CommentReference"/></w:rPr><w:commentReference w:id="1"/></w:r>
```

### Images (OOXML)

1. Drop file into `word/media/`
2. Register relationship in `word/_rels/document.xml.rels`:

```xml
<Relationship Id="rId5" Type=".../image" Target="media/image1.png"/>
```

3. Declare content type in `[Content_Types].xml`:

```xml
<Default Extension="png" ContentType="image/png"/>
```

4. Reference from document.xml:

```xml
<w:drawing>
  <wp:inline>
    <wp:extent cx="914400" cy="914400"/>  <!-- EMUs: 914 400 = 1 inch -->
    <a:graphic>
      <a:graphicData uri=".../picture">
        <pic:pic>
          <pic:blipFill><a:blip r:embed="rId5"/></pic:blipFill>
        </pic:pic>
      </a:graphicData>
    </a:graphic>
  </wp:inline>
</w:drawing>
```

---

## §Common operations (reference)

```bash
# Convert legacy .doc to .docx
python scripts/office/soffice.py --headless --convert-to docx document.doc

# Extract text (Markdown preserving tracked-change info)
pandoc --track-changes=all document.docx -o output.md

# Direct XML access for fine-grained inspection
python scripts/office/unpack.py document.docx unpacked/

# Render pages as images
python scripts/office/soffice.py --headless --convert-to pdf document.docx
pdftoppm -jpeg -r 150 document.pdf page

# Accept all tracked changes (produces pristine copy; LibreOffice required)
python scripts/accept_changes.py input.docx output.docx
```

---

## §Utility scripts (full list)

High-frequency rendering & template:

- `scripts/doctor.py` — detect pandoc / node+docx / soffice / pdftoppm; print
  per-platform install hints. **Run first.**
- `scripts/md_to_docx.py` — pandoc-based Markdown→docx with image/TOC/reference
  handling. **Execute.**
- `scripts/md_to_docx.mjs` — Node fallback Markdown→docx (no pandoc). Supports
  `--cjk`. **Execute.**
- `scripts/fill_template.py` — replace `{{token}}` placeholders in a template
  docx. **Execute.**
- `scripts/preview.py` — render docx pages to JPEG for visual self-check (needs
  LibreOffice). **Execute.**
- `scripts/styles/zh-cn.js` — importable CJK typography preset. **Read/import.**

OOXML / patching / comments:

- `scripts/comment.py` — insert Word comments into an unpacked document.
- `scripts/accept_changes.py` — accept all tracked changes (LibreOffice).
- `scripts/office/unpack.py` — explode a `.docx` into pretty-printed XML.
- `scripts/office/pack.py` — repackage an unpacked tree, with auto-repair.
- `scripts/office/validate.py` — XSD-based schema validation for DOCX/PPTX.
- `scripts/office/soffice.py` — sandboxed LibreOffice wrapper.

---

## §External dependencies

- `pandoc` — preferred Markdown→docx engine (Part A).
- `node` + global `docx` package (`npm install -g docx`) — fallback renderer
  and bespoke generation (Parts A and D).
- `LibreOffice` (`soffice`) — headless conversion, accepting tracked changes,
  preview rendering.
- `pdftoppm` (Poppler) — required by `preview.py` to rasterize PDFs.
