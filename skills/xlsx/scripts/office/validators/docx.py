#!/usr/bin/env python3
# ──────────────────────────────────────────────────────────────────
# DOCX-specific schema and structural validator.
#
# Extends BaseSchemaValidator with checks for:
#   • whitespace preservation on <w:t>
#   • invalid <w:t> inside <w:del>
#   • invalid <w:delText> inside <w:ins>
#   • paraId / durableId numeric constraints
#   • comment marker pairing
#   • paragraph count comparison
# ──────────────────────────────────────────────────────────────────

import random
import re
import tempfile
import zipfile

import defusedxml.minidom
import lxml.etree

from .base import BaseSchemaValidator

_PREVIEW_LEN = 50


class DOCXSchemaValidator(BaseSchemaValidator):
    """Validator tailored to Word (.docx) documents."""

    WORD_2006_NAMESPACE = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    W14_NAMESPACE = "http://schemas.microsoft.com/office/word/2010/wordml"
    W16CID_NAMESPACE = "http://schemas.microsoft.com/office/word/2016/wordml/cid"

    ELEMENT_RELATIONSHIP_TYPES = {}

    # ── main orchestrator ──

    def validate(self):
        if not self.validate_xml():
            return False

        checks = [
            self.validate_namespaces,
            self.validate_unique_ids,
            self.validate_file_references,
            self.validate_content_types,
            self.validate_against_xsd,
            self.validate_whitespace_preservation,
            self.validate_deletions,
            self.validate_insertions,
            self.validate_all_relationship_ids,
            self.validate_id_constraints,
            self.validate_comment_markers,
        ]
        ok = True
        for chk in checks:
            if not chk():
                ok = False

        self.compare_paragraph_counts()
        return ok

    # ──────────────────────────────────────────────────────────────
    # Whitespace
    # ──────────────────────────────────────────────────────────────

    def validate_whitespace_preservation(self):
        errs = []
        wns = self.WORD_2006_NAMESPACE
        xns = self.XML_NAMESPACE

        for fp in self.xml_files:
            if fp.name != "document.xml":
                continue
            try:
                root = lxml.etree.parse(str(fp)).getroot()
                for t_el in root.iter("{{{}}}t".format(wns)):
                    txt = t_el.text
                    if not txt:
                        continue
                    if re.search(r"^[ \t\n\r]", txt) or re.search(r"[ \t\n\r]$", txt):
                        space_attr = "{{{}}}space".format(xns)
                        if t_el.attrib.get(space_attr) != "preserve":
                            preview = repr(txt)[:_PREVIEW_LEN] + "..." if len(repr(txt)) > _PREVIEW_LEN else repr(txt)
                            errs.append(
                                "  {}: Line {}: w:t element with whitespace missing "
                                "xml:space='preserve': {}".format(
                                    fp.relative_to(self.unpacked_dir), t_el.sourceline, preview
                                )
                            )
            except (lxml.etree.XMLSyntaxError, Exception) as exc:
                errs.append("  {}: Error: {}".format(fp.relative_to(self.unpacked_dir), exc))

        if errs:
            print("FAILED - Found {} whitespace preservation violations:".format(len(errs)))
            for ln in errs:
                print(ln)
            return False
        if self.verbose:
            print("PASSED - All whitespace is properly preserved")
        return True

    # ──────────────────────────────────────────────────────────────
    # Deletion integrity
    # ──────────────────────────────────────────────────────────────

    def validate_deletions(self):
        errs = []
        wns = self.WORD_2006_NAMESPACE
        ns_map = {"w": wns}

        for fp in self.xml_files:
            if fp.name != "document.xml":
                continue
            try:
                root = lxml.etree.parse(str(fp)).getroot()

                for t in root.xpath(".//w:del//w:t", namespaces=ns_map):
                    if t.text:
                        preview = repr(t.text)[:_PREVIEW_LEN] + "..." if len(repr(t.text)) > _PREVIEW_LEN else repr(t.text)
                        errs.append(
                            "  {}: Line {}: <w:t> found within <w:del>: {}".format(
                                fp.relative_to(self.unpacked_dir), t.sourceline, preview
                            )
                        )

                for instr in root.xpath(".//w:del//w:instrText", namespaces=ns_map):
                    preview = repr(instr.text or "")[:_PREVIEW_LEN] + "..." if len(repr(instr.text or "")) > _PREVIEW_LEN else repr(instr.text or "")
                    errs.append(
                        "  {}: Line {}: <w:instrText> found within <w:del> "
                        "(use <w:delInstrText>): {}".format(
                            fp.relative_to(self.unpacked_dir), instr.sourceline, preview
                        )
                    )

            except (lxml.etree.XMLSyntaxError, Exception) as exc:
                errs.append("  {}: Error: {}".format(fp.relative_to(self.unpacked_dir), exc))

        if errs:
            print("FAILED - Found {} deletion validation violations:".format(len(errs)))
            for ln in errs:
                print(ln)
            return False
        if self.verbose:
            print("PASSED - No w:t elements found within w:del elements")
        return True

    # ──────────────────────────────────────────────────────────────
    # Insertion integrity
    # ──────────────────────────────────────────────────────────────

    def validate_insertions(self):
        errs = []
        ns_map = {"w": self.WORD_2006_NAMESPACE}

        for fp in self.xml_files:
            if fp.name != "document.xml":
                continue
            try:
                root = lxml.etree.parse(str(fp)).getroot()
                bad = root.xpath(".//w:ins//w:delText[not(ancestor::w:del)]", namespaces=ns_map)
                for nd in bad:
                    preview = repr(nd.text or "")[:_PREVIEW_LEN] + "..." if len(repr(nd.text or "")) > _PREVIEW_LEN else repr(nd.text or "")
                    errs.append(
                        "  {}: Line {}: <w:delText> within <w:ins>: {}".format(
                            fp.relative_to(self.unpacked_dir), nd.sourceline, preview
                        )
                    )
            except (lxml.etree.XMLSyntaxError, Exception) as exc:
                errs.append("  {}: Error: {}".format(fp.relative_to(self.unpacked_dir), exc))

        if errs:
            print("FAILED - Found {} insertion validation violations:".format(len(errs)))
            for ln in errs:
                print(ln)
            return False
        if self.verbose:
            print("PASSED - No w:delText elements within w:ins elements")
        return True

    # ──────────────────────────────────────────────────────────────
    # Paragraph counts
    # ──────────────────────────────────────────────────────────────

    def count_paragraphs_in_unpacked(self):
        total = 0
        for fp in self.xml_files:
            if fp.name != "document.xml":
                continue
            try:
                root = lxml.etree.parse(str(fp)).getroot()
                total = len(root.findall(".//{{{}}}p".format(self.WORD_2006_NAMESPACE)))
            except Exception as exc:
                print("Error counting paragraphs in unpacked document: {}".format(exc))
        return total

    def count_paragraphs_in_original(self):
        if self.original_file is None:
            return 0
        n = 0
        try:
            with tempfile.TemporaryDirectory() as td:
                with zipfile.ZipFile(self.original_file, "r") as zf:
                    zf.extractall(td)
                root = lxml.etree.parse(td + "/word/document.xml").getroot()
                n = len(root.findall(".//{{{}}}p".format(self.WORD_2006_NAMESPACE)))
        except Exception as exc:
            print("Error counting paragraphs in original document: {}".format(exc))
        return n

    def compare_paragraph_counts(self):
        orig = self.count_paragraphs_in_original()
        cur = self.count_paragraphs_in_unpacked()
        delta = cur - orig
        sign = "+{}".format(delta) if delta > 0 else str(delta)
        print("\nParagraphs: {} \u2192 {} ({})".format(orig, cur, sign))

    # ──────────────────────────────────────────────────────────────
    # ID numeric constraints (paraId, durableId)
    # ──────────────────────────────────────────────────────────────

    def _parse_id_value(self, raw: str, base: int = 16) -> int:
        return int(raw, base)

    def validate_id_constraints(self):
        errs = []
        pid_attr = "{{{}}}paraId".format(self.W14_NAMESPACE)
        did_attr = "{{{}}}durableId".format(self.W16CID_NAMESPACE)

        _HEX_CEILING = 0x80000000
        _DUR_CEILING = 0x7FFFFFFF

        for fp in self.xml_files:
            try:
                for nd in lxml.etree.parse(str(fp)).iter():
                    pv = nd.get(pid_attr)
                    if pv is not None and self._parse_id_value(pv, 16) >= _HEX_CEILING:
                        errs.append("  {}:{}: paraId={} >= 0x80000000".format(
                            fp.name, nd.sourceline, pv
                        ))

                    dv = nd.get(did_attr)
                    if dv is not None:
                        if fp.name == "numbering.xml":
                            try:
                                if self._parse_id_value(dv, 10) >= _DUR_CEILING:
                                    errs.append("  {}:{}: durableId={} >= 0x7FFFFFFF".format(
                                        fp.name, nd.sourceline, dv
                                    ))
                            except ValueError:
                                errs.append("  {}:{}: durableId={} must be decimal in numbering.xml".format(
                                    fp.name, nd.sourceline, dv
                                ))
                        else:
                            if self._parse_id_value(dv, 16) >= _DUR_CEILING:
                                errs.append("  {}:{}: durableId={} >= 0x7FFFFFFF".format(
                                    fp.name, nd.sourceline, dv
                                ))
            except Exception:
                pass

        if errs:
            print("FAILED - {} ID constraint violations:".format(len(errs)))
            for ln in errs:
                print(ln)
        elif self.verbose:
            print("PASSED - All paraId/durableId values within constraints")
        return not bool(errs)

    # ──────────────────────────────────────────────────────────────
    # Comment marker pairing
    # ──────────────────────────────────────────────────────────────

    def validate_comment_markers(self):
        errs = []

        doc_xml = None
        cmt_xml = None
        for fp in self.xml_files:
            if fp.name == "document.xml" and "word" in str(fp):
                doc_xml = fp
            elif fp.name == "comments.xml":
                cmt_xml = fp

        if doc_xml is None:
            if self.verbose:
                print("PASSED - No document.xml found (skipping comment validation)")
            return True

        try:
            dr = lxml.etree.parse(str(doc_xml)).getroot()
            ns = {"w": self.WORD_2006_NAMESPACE}
            wid = "{{{}}}id".format(self.WORD_2006_NAMESPACE)

            starts = {el.get(wid) for el in dr.xpath(".//w:commentRangeStart", namespaces=ns)}
            ends = {el.get(wid) for el in dr.xpath(".//w:commentRangeEnd", namespaces=ns)}
            refs = {el.get(wid) for el in dr.xpath(".//w:commentReference", namespaces=ns)}

            _sort_key = lambda x: int(x) if x and x.isdigit() else 0

            for cid in sorted(ends - starts, key=_sort_key):
                errs.append('  document.xml: commentRangeEnd id="{}" has no matching commentRangeStart'.format(cid))

            for cid in sorted(starts - ends, key=_sort_key):
                errs.append('  document.xml: commentRangeStart id="{}" has no matching commentRangeEnd'.format(cid))

            if cmt_xml and cmt_xml.exists():
                cr = lxml.etree.parse(str(cmt_xml)).getroot()
                defined = {el.get(wid) for el in cr.xpath(".//w:comment", namespaces=ns)}

                for cid in sorted((starts | ends | refs) - defined, key=_sort_key):
                    if cid:
                        errs.append('  document.xml: marker id="{}" references non-existent comment'.format(cid))

        except (lxml.etree.XMLSyntaxError, Exception) as exc:
            errs.append("  Error parsing XML: {}".format(exc))

        if errs:
            print("FAILED - {} comment marker violations:".format(len(errs)))
            for ln in errs:
                print(ln)
            return False
        if self.verbose:
            print("PASSED - All comment markers properly paired")
        return True

    # ──────────────────────────────────────────────────────────────
    # Repair: durableId overflow
    # ──────────────────────────────────────────────────────────────

    def repair(self) -> int:
        n = super().repair()
        n += self._fix_durable_ids()
        return n

    def _fix_durable_ids(self) -> int:
        n_fixed = 0
        _LIMIT = 0x7FFFFFFF

        for fp in self.xml_files:
            try:
                raw = fp.read_text(encoding="utf-8")
                dom = defusedxml.minidom.parseString(raw)
                changed = False

                for el in dom.getElementsByTagName("*"):
                    if not el.hasAttribute("w16cid:durableId"):
                        continue
                    old_val = el.getAttribute("w16cid:durableId")
                    bad = False

                    if fp.name == "numbering.xml":
                        try:
                            bad = self._parse_id_value(old_val, 10) >= _LIMIT
                        except ValueError:
                            bad = True
                    else:
                        try:
                            bad = self._parse_id_value(old_val, 16) >= _LIMIT
                        except ValueError:
                            bad = True

                    if bad:
                        rv = random.randint(1, _LIMIT - 1)
                        new_val = str(rv) if fp.name == "numbering.xml" else "{:08X}".format(rv)
                        el.setAttribute("w16cid:durableId", new_val)
                        print("  Repaired: {}: durableId {} \u2192 {}".format(fp.name, old_val, new_val))
                        n_fixed += 1
                        changed = True

                if changed:
                    fp.write_bytes(dom.toxml(encoding="UTF-8"))
            except Exception:
                pass

        return n_fixed

    # keep legacy name
    repair_durableId = _fix_durable_ids


if __name__ == "__main__":
    raise RuntimeError("This module should not be run directly.")
