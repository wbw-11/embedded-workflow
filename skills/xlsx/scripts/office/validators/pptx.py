#!/usr/bin/env python3
# ──────────────────────────────────────────────────────────────────
# PPTX-specific schema and structural validator.
#
# Extends BaseSchemaValidator with checks for:
#   • UUID format validation on ID attributes
#   • Slide-layout ↔ slide-master relationship integrity
#   • Notes-slide reference uniqueness
#   • Duplicate slideLayout relationship detection
# ──────────────────────────────────────────────────────────────────

import re

from .base import BaseSchemaValidator

_UUID_RE = re.compile(
    r"^[\{\(]?[0-9A-Fa-f]{8}-?[0-9A-Fa-f]{4}-?[0-9A-Fa-f]{4}"
    r"-?[0-9A-Fa-f]{4}-?[0-9A-Fa-f]{12}[\}\)]?$"
)


class PPTXSchemaValidator(BaseSchemaValidator):
    """Validator tailored to PowerPoint (.pptx) presentations."""

    PRESENTATIONML_NAMESPACE = (
        "http://schemas.openxmlformats.org/presentationml/2006/main"
    )

    ELEMENT_RELATIONSHIP_TYPES = {
        "sldid": "slide",
        "sldmasterid": "slidemaster",
        "notesmasterid": "notesmaster",
        "sldlayoutid": "slidelayout",
        "themeid": "theme",
        "tablestyleid": "tablestyles",
    }

    # ── orchestrator ──

    def validate(self):
        if not self.validate_xml():
            return False

        ok = True
        for chk in (
            self.validate_namespaces,
            self.validate_unique_ids,
            self.validate_uuid_ids,
            self.validate_file_references,
            self.validate_slide_layout_ids,
            self.validate_content_types,
            self.validate_against_xsd,
            self.validate_notes_slide_references,
            self.validate_all_relationship_ids,
            self.validate_no_duplicate_slide_layouts,
        ):
            if not chk():
                ok = False
        return ok

    # ──────────────────────────────────────────────────────────────
    # UUID-format IDs
    # ──────────────────────────────────────────────────────────────

    def validate_uuid_ids(self):
        import lxml.etree

        errs = []
        for fp in self.xml_files:
            try:
                root = lxml.etree.parse(str(fp)).getroot()
                for nd in root.iter():
                    for attr_key, attr_val in nd.attrib.items():
                        aname = attr_key.split("}")[-1].lower()
                        if aname != "id" and not aname.endswith("id"):
                            continue
                        if self._resembles_uuid(attr_val) and not _UUID_RE.match(attr_val):
                            errs.append(
                                "  {}: Line {}: ID '{}' appears to be a UUID "
                                "but contains invalid hex characters".format(
                                    fp.relative_to(self.unpacked_dir), nd.sourceline, attr_val
                                )
                            )
            except (lxml.etree.XMLSyntaxError, Exception) as exc:
                errs.append("  {}: Error: {}".format(fp.relative_to(self.unpacked_dir), exc))

        if errs:
            print("FAILED - Found {} UUID ID validation errors:".format(len(errs)))
            for ln in errs:
                print(ln)
            return False
        if self.verbose:
            print("PASSED - All UUID-like IDs contain valid hex values")
        return True

    @staticmethod
    def _resembles_uuid(val):
        stripped = val.strip("{}()").replace("-", "")
        return len(stripped) == 32 and stripped.isalnum()

    # ──────────────────────────────────────────────────────────────
    # Slide-layout IDs ↔ relationships
    # ──────────────────────────────────────────────────────────────

    def validate_slide_layout_ids(self):
        import lxml.etree

        errs = []
        masters = list(self.unpacked_dir.glob("ppt/slideMasters/*.xml"))

        if not masters:
            if self.verbose:
                print("PASSED - No slide masters found")
            return True

        for sm in masters:
            try:
                root = lxml.etree.parse(str(sm)).getroot()
                rels_path = sm.parent / "_rels" / "{}.rels".format(sm.name)

                if not rels_path.exists():
                    errs.append("  {}: Missing relationships file: {}".format(
                        sm.relative_to(self.unpacked_dir),
                        rels_path.relative_to(self.unpacked_dir),
                    ))
                    continue

                rroot = lxml.etree.parse(str(rels_path)).getroot()
                valid_rids = {
                    r.get("Id")
                    for r in rroot.findall(
                        ".//{{{}}}Relationship".format(self.PACKAGE_RELATIONSHIPS_NAMESPACE)
                    )
                    if "slideLayout" in r.get("Type", "")
                }

                pml = self.PRESENTATIONML_NAMESPACE
                for lid in root.findall(".//{{{}}}sldLayoutId".format(pml)):
                    rid = lid.get("{{{}}}id".format(self.OFFICE_RELATIONSHIPS_NAMESPACE))
                    layout_id = lid.get("id")
                    if rid and rid not in valid_rids:
                        errs.append(
                            "  {}: Line {}: sldLayoutId with id='{}' "
                            "references r:id='{}' which is not found in slide layout relationships".format(
                                sm.relative_to(self.unpacked_dir), lid.sourceline, layout_id, rid
                            )
                        )
            except (lxml.etree.XMLSyntaxError, Exception) as exc:
                errs.append("  {}: Error: {}".format(sm.relative_to(self.unpacked_dir), exc))

        if errs:
            print("FAILED - Found {} slide layout ID validation errors:".format(len(errs)))
            for ln in errs:
                print(ln)
            print("Remove invalid references or add missing slide layouts to the relationships file.")
            return False
        if self.verbose:
            print("PASSED - All slide layout IDs reference valid slide layouts")
        return True

    # ──────────────────────────────────────────────────────────────
    # Duplicate slideLayout refs per slide
    # ──────────────────────────────────────────────────────────────

    def validate_no_duplicate_slide_layouts(self):
        import lxml.etree

        errs = []
        for rf in self.unpacked_dir.glob("ppt/slides/_rels/*.xml.rels"):
            try:
                root = lxml.etree.parse(str(rf)).getroot()
                layouts = [
                    r for r in root.findall(
                        ".//{{{}}}Relationship".format(self.PACKAGE_RELATIONSHIPS_NAMESPACE)
                    )
                    if "slideLayout" in r.get("Type", "")
                ]
                if len(layouts) > 1:
                    errs.append("  {}: has {} slideLayout references".format(
                        rf.relative_to(self.unpacked_dir), len(layouts)
                    ))
            except Exception as exc:
                errs.append("  {}: Error: {}".format(rf.relative_to(self.unpacked_dir), exc))

        if errs:
            print("FAILED - Found slides with duplicate slideLayout references:")
            for ln in errs:
                print(ln)
            return False
        if self.verbose:
            print("PASSED - All slides have exactly one slideLayout reference")
        return True

    # ──────────────────────────────────────────────────────────────
    # Notes-slide reference uniqueness
    # ──────────────────────────────────────────────────────────────

    def validate_notes_slide_references(self):
        import lxml.etree

        errs = []
        target_map = {}

        slide_rels = list(self.unpacked_dir.glob("ppt/slides/_rels/*.xml.rels"))
        if not slide_rels:
            if self.verbose:
                print("PASSED - No slide relationship files found")
            return True

        for rf in slide_rels:
            try:
                root = lxml.etree.parse(str(rf)).getroot()
                for rel in root.findall(
                    ".//{{{}}}Relationship".format(self.PACKAGE_RELATIONSHIPS_NAMESPACE)
                ):
                    if "notesSlide" not in rel.get("Type", ""):
                        continue
                    tgt = rel.get("Target", "")
                    if not tgt:
                        continue
                    norm = tgt.replace("../", "")
                    slide = rf.stem.replace(".xml", "")
                    target_map.setdefault(norm, []).append((slide, rf))

            except (lxml.etree.XMLSyntaxError, Exception) as exc:
                errs.append("  {}: Error: {}".format(rf.relative_to(self.unpacked_dir), exc))

        for tgt, refs in target_map.items():
            if len(refs) > 1:
                names = [r[0] for r in refs]
                errs.append("  Notes slide '{}' is referenced by multiple slides: {}".format(
                    tgt, ", ".join(names)
                ))
                for name, rfile in refs:
                    errs.append("    - {}".format(rfile.relative_to(self.unpacked_dir)))

        if errs:
            top_errs = [e for e in errs if not e.startswith("    ")]
            print("FAILED - Found {} notes slide reference validation errors:".format(len(top_errs)))
            for ln in errs:
                print(ln)
            print("Each slide may optionally have its own slide file.")
            return False
        if self.verbose:
            print("PASSED - All notes slide references are unique")
        return True


if __name__ == "__main__":
    raise RuntimeError("This module should not be run directly.")
