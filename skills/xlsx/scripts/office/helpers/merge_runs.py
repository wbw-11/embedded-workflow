#!/usr/bin/env python3
# ──────────────────────────────────────────────────────────────────
# Coalesce adjacent <w:r> elements sharing identical <w:rPr> in DOCX.
#
# Pre-processing steps that enable merging:
#   1. Strip all proofErr elements (spell/grammar markers)
#   2. Remove rsid* attributes from runs (revision metadata)
#
# After merging, adjacent <w:t> children inside the same run are
# concatenated into a single text node.
# ──────────────────────────────────────────────────────────────────

from pathlib import Path

import defusedxml.minidom


def merge_runs(input_dir: str) -> tuple[int, str]:
    """Entry point – merge runs in word/document.xml and return (count, msg)."""
    doc = Path(input_dir) / "word" / "document.xml"

    if not doc.exists():
        return 0, "Error: {} not found".format(doc)

    try:
        tree = defusedxml.minidom.parseString(doc.read_text(encoding="utf-8"))
        top = tree.documentElement

        # housekeeping
        _purge_by_tag(top, "proofErr")
        _drop_rsid_attrs(top)

        # collect unique parent containers of all <w:r>
        parents = {nd.parentNode for nd in _query_tag(top, "r")}

        merged = 0
        for p in parents:
            merged += _coalesce_in_container(p)

        doc.write_bytes(tree.toxml(encoding="UTF-8"))
        return merged, "Merged {} runs".format(merged)

    except Exception as ex:
        return 0, "Error: {}".format(ex)


# ──────────────────────────────────────────────────────────────────
# DOM traversal helpers
# ──────────────────────────────────────────────────────────────────

def _query_tag(root, local_name: str) -> list:
    """Recursively find all elements whose local name matches *local_name*."""
    hits = []

    def _walk(nd):
        if nd.nodeType != nd.ELEMENT_NODE:
            return
        tag = nd.localName or nd.tagName
        if tag == local_name or tag.endswith(":{}".format(local_name)):
            hits.append(nd)
        for ch in nd.childNodes:
            _walk(ch)

    _walk(root)
    return hits


def _child_by_tag(parent, local_name: str):
    """Return the first direct child element matching *local_name*."""
    for ch in parent.childNodes:
        if ch.nodeType != ch.ELEMENT_NODE:
            continue
        tag = ch.localName or ch.tagName
        if tag == local_name or tag.endswith(":{}".format(local_name)):
            return ch
    return None


def _children_by_tag(parent, local_name: str) -> list:
    """Return every direct child element matching *local_name*."""
    return [
        ch for ch in parent.childNodes
        if ch.nodeType == ch.ELEMENT_NODE
        and ((ch.localName or ch.tagName) == local_name
             or (ch.localName or ch.tagName).endswith(":{}".format(local_name)))
    ]


def _only_whitespace_between(a, b) -> bool:
    """True when nothing meaningful sits between siblings *a* and *b*."""
    cur = a.nextSibling
    while cur is not None:
        if cur is b:
            return True
        if cur.nodeType == cur.ELEMENT_NODE:
            return False
        if cur.nodeType == cur.TEXT_NODE and cur.data.strip():
            return False
        cur = cur.nextSibling
    return False


# ──────────────────────────────────────────────────────────────────
# Cleanup passes
# ──────────────────────────────────────────────────────────────────

def _purge_by_tag(root, local_name: str):
    """Remove every element whose local name matches *local_name*."""
    for nd in _query_tag(root, local_name):
        if nd.parentNode is not None:
            nd.parentNode.removeChild(nd)


def _drop_rsid_attrs(root):
    """Strip revision-save-ID attributes from all <w:r> elements."""
    for r in _query_tag(root, "r"):
        doomed = [a for a in r.attributes.values() if "rsid" in a.name.lower()]
        for a in doomed:
            r.removeAttribute(a.name)


# ──────────────────────────────────────────────────────────────────
# Core merging logic
# ──────────────────────────────────────────────────────────────────

def _tag_is_run(nd) -> bool:
    tag = nd.localName or nd.tagName
    return tag == "r" or tag.endswith(":r")


def _next_elem(nd):
    """Return the next element sibling (skip text/comment nodes)."""
    s = nd.nextSibling
    while s is not None:
        if s.nodeType == s.ELEMENT_NODE:
            return s
        s = s.nextSibling
    return None


def _next_run_sibling(nd):
    """Walk forward until we hit another <w:r> element."""
    s = nd.nextSibling
    while s is not None:
        if s.nodeType == s.ELEMENT_NODE and _tag_is_run(s):
            return s
        s = s.nextSibling
    return None


def _first_run_child(container):
    """Return the first child that is a run element."""
    for ch in container.childNodes:
        if ch.nodeType == ch.ELEMENT_NODE and _tag_is_run(ch):
            return ch
    return None


def _runs_compatible(a, b) -> bool:
    """Two runs are compatible when their <w:rPr> serialisations match."""
    rpr_a = _child_by_tag(a, "rPr")
    rpr_b = _child_by_tag(b, "rPr")
    if (rpr_a is None) != (rpr_b is None):
        return False
    return True if rpr_a is None else rpr_a.toxml() == rpr_b.toxml()


def _absorb_run(dst, src):
    """Move non-rPr children from *src* into *dst*."""
    for ch in list(src.childNodes):
        if ch.nodeType != ch.ELEMENT_NODE:
            continue
        tag = ch.localName or ch.tagName
        if tag == "rPr" or tag.endswith(":rPr"):
            continue
        dst.appendChild(ch)


def _squash_text_nodes(run):
    """Concatenate adjacent <w:t> children into one."""
    t_nodes = _children_by_tag(run, "t")

    idx = len(t_nodes) - 1
    while idx > 0:
        cur, prev = t_nodes[idx], t_nodes[idx - 1]

        if _only_whitespace_between(prev, cur):
            txt_prev = prev.firstChild.data if prev.firstChild else ""
            txt_cur = cur.firstChild.data if cur.firstChild else ""
            combined = txt_prev + txt_cur

            if prev.firstChild:
                prev.firstChild.data = combined
            else:
                prev.appendChild(run.ownerDocument.createTextNode(combined))

            if combined.startswith(" ") or combined.endswith(" "):
                prev.setAttribute("xml:space", "preserve")
            elif prev.hasAttribute("xml:space"):
                prev.removeAttribute("xml:space")

            run.removeChild(cur)

        idx -= 1


def _coalesce_in_container(container) -> int:
    """Merge compatible adjacent runs inside *container*."""
    count = 0
    cur = _first_run_child(container)

    while cur is not None:
        # absorb as many consecutive compatible runs as possible
        while True:
            nxt = _next_elem(cur)
            if nxt is not None and _tag_is_run(nxt) and _runs_compatible(cur, nxt):
                _absorb_run(cur, nxt)
                container.removeChild(nxt)
                count += 1
            else:
                break

        _squash_text_nodes(cur)
        cur = _next_run_sibling(cur)

    return count
