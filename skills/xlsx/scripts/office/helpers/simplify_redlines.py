#!/usr/bin/env python3
# ──────────────────────────────────────────────────────────────────
# Merge adjacent tracked-change wrappers (<w:ins> / <w:del>) when they
# share the same author.  Reduces visual clutter in heavily-redlined
# DOCX documents without altering semantics.
#
# Constraints:
#   • Only merges elements of the *same* tag (ins↔ins, del↔del)
#   • Author must match (timestamps are ignored)
#   • Only merges truly adjacent elements (whitespace-only gap allowed)
# ──────────────────────────────────────────────────────────────────

import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

import defusedxml.minidom

_WML_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"


def simplify_redlines(input_dir: str) -> tuple[int, str]:
    """Merge adjacent tracked changes in word/document.xml."""
    doc = Path(input_dir) / "word" / "document.xml"

    if not doc.exists():
        return 0, "Error: {} not found".format(doc)

    try:
        tree = defusedxml.minidom.parseString(doc.read_text(encoding="utf-8"))
        top = tree.documentElement

        total = 0
        for box in _collect_elements(top, "p") + _collect_elements(top, "tc"):
            total += _coalesce_tracked(box, "ins")
            total += _coalesce_tracked(box, "del")

        doc.write_bytes(tree.toxml(encoding="UTF-8"))
        return total, "Simplified {} tracked changes".format(total)

    except Exception as ex:
        return 0, "Error: {}".format(ex)


# ──────────────────────────────────────────────────────────────────
# Internal helpers
# ──────────────────────────────────────────────────────────────────

def _coalesce_tracked(container, kind: str) -> int:
    """Merge adjacent <w:ins> or <w:del> elements inside *container*."""
    nodes = [
        ch for ch in container.childNodes
        if ch.nodeType == ch.ELEMENT_NODE and _matches_tag(ch, kind)
    ]
    if len(nodes) < 2:
        return 0

    merged = 0
    pos = 0
    while pos < len(nodes) - 1:
        this, that = nodes[pos], nodes[pos + 1]
        if _same_author_adjacent(this, that):
            _move_children(this, that)
            container.removeChild(that)
            nodes.pop(pos + 1)
            merged += 1
        else:
            pos += 1

    return merged


def _matches_tag(nd, local: str) -> bool:
    tag = nd.localName or nd.tagName
    return tag == local or tag.endswith(":{}".format(local))


def _author_of(elem) -> str:
    """Extract the w:author attribute value from a tracked-change element."""
    val = elem.getAttribute("w:author")
    if val:
        return val
    for attr in elem.attributes.values():
        if attr.localName == "author" or attr.name.endswith(":author"):
            return attr.value
    return ""


def _same_author_adjacent(a, b) -> bool:
    """True when *a* and *b* share an author and have no elements between them."""
    if _author_of(a) != _author_of(b):
        return False
    cur = a.nextSibling
    while cur is not None and cur is not b:
        if cur.nodeType == cur.ELEMENT_NODE:
            return False
        if cur.nodeType == cur.TEXT_NODE and cur.data.strip():
            return False
        cur = cur.nextSibling
    return True


def _move_children(dst, src):
    """Transplant every child of *src* into *dst*."""
    while src.firstChild is not None:
        kid = src.firstChild
        src.removeChild(kid)
        dst.appendChild(kid)


def _collect_elements(root, local: str) -> list:
    """Depth-first collection of elements matching *local*."""
    out = []

    def _dfs(nd):
        if nd.nodeType == nd.ELEMENT_NODE:
            tag = nd.localName or nd.tagName
            if tag == local or tag.endswith(":{}".format(local)):
                out.append(nd)
            for ch in nd.childNodes:
                _dfs(ch)

    _dfs(root)
    return out


# ──────────────────────────────────────────────────────────────────
# Author-analysis utilities (used by pack.py / infer_author)
# ──────────────────────────────────────────────────────────────────

def get_tracked_change_authors(xml_path: Path) -> dict[str, int]:
    """Count tracked-change occurrences per author in an XML file."""
    if not xml_path.exists():
        return {}
    try:
        parsed = ET.parse(xml_path)
    except ET.ParseError:
        return {}

    ns = {"w": _WML_NS}
    attr_key = "{{{}}}author".format(_WML_NS)

    counts: dict[str, int] = {}
    for tag in ("ins", "del"):
        for el in parsed.getroot().findall(".//w:{}".format(tag), ns):
            who = el.get(attr_key)
            if who:
                counts[who] = counts.get(who, 0) + 1
    return counts


def _get_authors_from_docx(docx: Path) -> dict[str, int]:
    """Extract author counts from a packed .docx without full unpacking."""
    try:
        with zipfile.ZipFile(docx, "r") as zf:
            if "word/document.xml" not in zf.namelist():
                return {}
            with zf.open("word/document.xml") as fh:
                parsed = ET.parse(fh)
                ns = {"w": _WML_NS}
                attr_key = "{{{}}}author".format(_WML_NS)
                counts: dict[str, int] = {}
                for tag in ("ins", "del"):
                    for el in parsed.getroot().findall(".//w:{}".format(tag), ns):
                        who = el.get(attr_key)
                        if who:
                            counts[who] = counts.get(who, 0) + 1
                return counts
    except (zipfile.BadZipFile, ET.ParseError):
        return {}


def infer_author(modified_dir: Path, original_docx: Path, default: str = "Claude") -> str:
    """Guess which author introduced new tracked changes."""
    mod_xml = modified_dir / "word" / "document.xml"
    mod_counts = get_tracked_change_authors(mod_xml)

    if not mod_counts:
        return default

    orig_counts = _get_authors_from_docx(original_docx)

    delta: dict[str, int] = {}
    for who, n in mod_counts.items():
        diff = n - orig_counts.get(who, 0)
        if diff > 0:
            delta[who] = diff

    if not delta:
        return default

    if len(delta) == 1:
        return next(iter(delta))

    raise ValueError(
        "Multiple authors added new changes: {}. "
        "Cannot infer which author to validate.".format(delta)
    )
