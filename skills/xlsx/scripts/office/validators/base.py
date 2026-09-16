#!/usr/bin/env python3
# ──────────────────────────────────────────────────────────────────
# Foundation class for OOXML schema validation.
#
# Subclasses (DOCX, PPTX) override `validate()` and optionally
# `repair()`.  The base provides shared XSD checking, namespace
# auditing, unique-ID enforcement, relationship verification, and
# content-type validation.
# ──────────────────────────────────────────────────────────────────

import re
from pathlib import Path

import defusedxml.minidom
import lxml.etree


class BaseSchemaValidator:
    """Shared validation infrastructure for Office Open XML packages."""

    # ── patterns that we silently ignore in XSD output ──
    IGNORED_VALIDATION_ERRORS = ["hyphenationZone", "purl.org/dc/terms"]

    # tag → (attribute, scope) for uniqueness checks
    UNIQUE_ID_REQUIREMENTS = {
        "comment": ("id", "file"),
        "commentrangestart": ("id", "file"),
        "commentrangeend": ("id", "file"),
        "bookmarkstart": ("id", "file"),
        "bookmarkend": ("id", "file"),
        "sldid": ("id", "file"),
        "sldmasterid": ("id", "global"),
        "sldlayoutid": ("id", "global"),
        "cm": ("authorid", "file"),
        "sheet": ("sheetid", "file"),
        "definedname": ("id", "file"),
        "cxnsp": ("id", "file"),
        "sp": ("id", "file"),
        "pic": ("id", "file"),
        "grpsp": ("id", "file"),
    }

    EXCLUDED_ID_CONTAINERS = {"sectionlst"}

    ELEMENT_RELATIONSHIP_TYPES = {}

    SCHEMA_MAPPINGS = {
        "word": "ISO-IEC29500-4_2016/wml.xsd",
        "ppt": "ISO-IEC29500-4_2016/pml.xsd",
        "xl": "ISO-IEC29500-4_2016/sml.xsd",
        "[Content_Types].xml": "ecma/fouth-edition/opc-contentTypes.xsd",
        "app.xml": "ISO-IEC29500-4_2016/shared-documentPropertiesExtended.xsd",
        "core.xml": "ecma/fouth-edition/opc-coreProperties.xsd",
        "custom.xml": "ISO-IEC29500-4_2016/shared-documentPropertiesCustom.xsd",
        ".rels": "ecma/fouth-edition/opc-relationships.xsd",
        "people.xml": "microsoft/wml-2012.xsd",
        "commentsIds.xml": "microsoft/wml-cid-2016.xsd",
        "commentsExtensible.xml": "microsoft/wml-cex-2018.xsd",
        "commentsExtended.xml": "microsoft/wml-2012.xsd",
        "chart": "ISO-IEC29500-4_2016/dml-chart.xsd",
        "theme": "ISO-IEC29500-4_2016/dml-main.xsd",
        "drawing": "ISO-IEC29500-4_2016/dml-main.xsd",
    }

    # well-known XML / OPC / OOXML namespace URIs
    MC_NAMESPACE = "http://schemas.openxmlformats.org/markup-compatibility/2006"
    XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace"
    PACKAGE_RELATIONSHIPS_NAMESPACE = (
        "http://schemas.openxmlformats.org/package/2006/relationships"
    )
    OFFICE_RELATIONSHIPS_NAMESPACE = (
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    )
    CONTENT_TYPES_NAMESPACE = (
        "http://schemas.openxmlformats.org/package/2006/content-types"
    )

    MAIN_CONTENT_FOLDERS = {"word", "ppt", "xl"}

    OOXML_NAMESPACES = {
        "http://schemas.openxmlformats.org/officeDocument/2006/math",
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
        "http://schemas.openxmlformats.org/schemaLibrary/2006/main",
        "http://schemas.openxmlformats.org/drawingml/2006/main",
        "http://schemas.openxmlformats.org/drawingml/2006/chart",
        "http://schemas.openxmlformats.org/drawingml/2006/chartDrawing",
        "http://schemas.openxmlformats.org/drawingml/2006/diagram",
        "http://schemas.openxmlformats.org/drawingml/2006/picture",
        "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing",
        "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing",
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
        "http://schemas.openxmlformats.org/presentationml/2006/main",
        "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
        "http://schemas.openxmlformats.org/officeDocument/2006/sharedTypes",
        "http://www.w3.org/XML/1998/namespace",
    }

    # ──────────────────────────────────────────────────────────────

    def __init__(self, unpacked_dir, original_file=None, verbose=False):
        self.unpacked_dir = Path(unpacked_dir).resolve()
        self.original_file = Path(original_file) if original_file else None
        self.verbose = verbose

        self.schemas_dir = Path(__file__).parent.parent / "schemas"

        self.xml_files = [
            fp
            for glob in ("*.xml", "*.rels")
            for fp in self.unpacked_dir.rglob(glob)
        ]
        if not self.xml_files:
            print("Warning: No XML files found in {}".format(self.unpacked_dir))

    # ── abstract / default methods ──

    def validate(self):
        raise NotImplementedError("Subclasses must implement the validate method")

    def repair(self) -> int:
        return self._fix_whitespace_preservation()

    # ──────────────────────────────────────────────────────────────
    # Repair: xml:space="preserve" on <w:t> with leading/trailing ws
    # ──────────────────────────────────────────────────────────────

    def _fix_whitespace_preservation(self) -> int:
        n_fixed = 0
        for fp in self.xml_files:
            try:
                raw = fp.read_text(encoding="utf-8")
                dom = defusedxml.minidom.parseString(raw)
                touched = False

                for el in dom.getElementsByTagName("*"):
                    if not el.tagName.endswith(":t"):
                        continue
                    if el.firstChild is None:
                        continue
                    txt = el.firstChild.nodeValue
                    if not txt:
                        continue
                    has_ws = txt.startswith((' ', '\t')) or txt.endswith((' ', '\t'))
                    if has_ws and el.getAttribute("xml:space") != "preserve":
                        el.setAttribute("xml:space", "preserve")
                        preview = repr(txt[:30]) + "..." if len(txt) > 30 else repr(txt)
                        print("  Repaired: {}: Added xml:space='preserve' to {}: {}".format(
                            fp.name, el.tagName, preview
                        ))
                        n_fixed += 1
                        touched = True

                if touched:
                    fp.write_bytes(dom.toxml(encoding="UTF-8"))
            except Exception:
                pass
        return n_fixed

    # alternative name kept for backward compat
    repair_whitespace_preservation = _fix_whitespace_preservation

    # ──────────────────────────────────────────────────────────────
    # Check 1 – well-formed XML
    # ──────────────────────────────────────────────────────────────

    def validate_xml(self):
        issues = []
        for fp in self.xml_files:
            try:
                lxml.etree.parse(str(fp))
            except lxml.etree.XMLSyntaxError as exc:
                issues.append("  {}: Line {}: {}".format(
                    fp.relative_to(self.unpacked_dir), exc.lineno, exc.msg
                ))
            except Exception as exc:
                issues.append("  {}: Unexpected error: {}".format(
                    fp.relative_to(self.unpacked_dir), exc
                ))

        if issues:
            print("FAILED - Found {} XML violations:".format(len(issues)))
            for ln in issues:
                print(ln)
            return False
        if self.verbose:
            print("PASSED - All XML files are well-formed")
        return True

    # ──────────────────────────────────────────────────────────────
    # Check 2 – mc:Ignorable namespace prefixes
    # ──────────────────────────────────────────────────────────────

    def validate_namespaces(self):
        issues = []
        for fp in self.xml_files:
            try:
                root = lxml.etree.parse(str(fp)).getroot()
                declared = set(root.nsmap.keys()) - {None}

                ignorable_vals = [
                    v for k, v in root.attrib.items() if k.endswith("Ignorable")
                ]
                for val in ignorable_vals:
                    for ns in set(val.split()) - declared:
                        issues.append("  {}: Namespace '{}' in Ignorable but not declared".format(
                            fp.relative_to(self.unpacked_dir), ns
                        ))
            except lxml.etree.XMLSyntaxError:
                continue

        if issues:
            print("FAILED - {} namespace issues:".format(len(issues)))
            for ln in issues:
                print(ln)
            return False
        if self.verbose:
            print("PASSED - All namespace prefixes properly declared")
        return True

    # ──────────────────────────────────────────────────────────────
    # Check 3 – unique IDs
    # ──────────────────────────────────────────────────────────────

    def validate_unique_ids(self):
        issues = []
        g_ids = {}

        for fp in self.xml_files:
            try:
                root = lxml.etree.parse(str(fp)).getroot()
                per_file = {}

                # strip mc:AlternateContent before scanning
                for ac in root.xpath(
                    ".//mc:AlternateContent",
                    namespaces={"mc": self.MC_NAMESPACE},
                ):
                    ac.getparent().remove(ac)

                for nd in root.iter():
                    raw_tag = nd.tag
                    local = raw_tag.split("}")[-1].lower() if "}" in raw_tag else raw_tag.lower()

                    if local not in self.UNIQUE_ID_REQUIREMENTS:
                        continue

                    # skip elements inside excluded containers
                    if any(
                        anc.tag.split("}")[-1].lower() in self.EXCLUDED_ID_CONTAINERS
                        for anc in nd.iterancestors()
                    ):
                        continue

                    attr_name, scope = self.UNIQUE_ID_REQUIREMENTS[local]

                    # find the actual attribute value
                    id_val = None
                    for ak, av in nd.attrib.items():
                        a_local = ak.split("}")[-1].lower() if "}" in ak else ak.lower()
                        if a_local == attr_name:
                            id_val = av
                            break

                    if id_val is None:
                        continue

                    rel_path = fp.relative_to(self.unpacked_dir)

                    if scope == "global":
                        if id_val in g_ids:
                            pf, pl, pt = g_ids[id_val]
                            issues.append(
                                "  {}: Line {}: Global ID '{}' in <{}> "
                                "already used in {} at line {} in <{}>".format(
                                    rel_path, nd.sourceline, id_val, local, pf, pl, pt
                                )
                            )
                        else:
                            g_ids[id_val] = (rel_path, nd.sourceline, local)
                    else:
                        bucket_key = (local, attr_name)
                        if bucket_key not in per_file:
                            per_file[bucket_key] = {}
                        if id_val in per_file[bucket_key]:
                            issues.append(
                                "  {}: Line {}: Duplicate {}='{}' in <{}> "
                                "(first occurrence at line {})".format(
                                    rel_path, nd.sourceline, attr_name, id_val, local,
                                    per_file[bucket_key][id_val],
                                )
                            )
                        else:
                            per_file[bucket_key][id_val] = nd.sourceline

            except (lxml.etree.XMLSyntaxError, Exception) as exc:
                issues.append("  {}: Error: {}".format(
                    fp.relative_to(self.unpacked_dir), exc
                ))

        if issues:
            print("FAILED - Found {} ID uniqueness violations:".format(len(issues)))
            for ln in issues:
                print(ln)
            return False
        if self.verbose:
            print("PASSED - All required IDs are unique")
        return True

    # ──────────────────────────────────────────────────────────────
    # Check 4 – .rels file references
    # ──────────────────────────────────────────────────────────────

    def validate_file_references(self):
        issues = []
        rels = list(self.unpacked_dir.rglob("*.rels"))

        if not rels:
            if self.verbose:
                print("PASSED - No .rels files found")
            return True

        physical_files = [
            fp.resolve()
            for fp in self.unpacked_dir.rglob("*")
            if fp.is_file()
            and fp.name != "[Content_Types].xml"
            and not fp.name.endswith(".rels")
        ]

        all_referenced = set()
        if self.verbose:
            print("Found {} .rels files and {} target files".format(len(rels), len(physical_files)))

        for rf in rels:
            try:
                rr = lxml.etree.parse(str(rf)).getroot()
                rd = rf.parent
                referenced = set()
                broken = []

                for rel in rr.findall(
                    ".//ns:Relationship",
                    namespaces={"ns": self.PACKAGE_RELATIONSHIPS_NAMESPACE},
                ):
                    tgt = rel.get("Target")
                    if not tgt or tgt.startswith(("http", "mailto:")):
                        continue

                    if tgt.startswith("/"):
                        tp = self.unpacked_dir / tgt.lstrip("/")
                    elif rf.name == ".rels":
                        tp = self.unpacked_dir / tgt
                    else:
                        tp = rd.parent / tgt

                    try:
                        tp = tp.resolve()
                        if tp.exists() and tp.is_file():
                            referenced.add(tp)
                            all_referenced.add(tp)
                        else:
                            broken.append((tgt, rel.sourceline))
                    except (OSError, ValueError):
                        broken.append((tgt, rel.sourceline))

                if broken:
                    rp = rf.relative_to(self.unpacked_dir)
                    for ref, line in broken:
                        issues.append("  {}: Line {}: Broken reference to {}".format(rp, line, ref))

            except Exception as exc:
                issues.append("  Error parsing {}: {}".format(
                    rf.relative_to(self.unpacked_dir), exc
                ))

        orphans = set(physical_files) - all_referenced
        for orphan in sorted(orphans):
            issues.append("  Unreferenced file: {}".format(
                orphan.relative_to(self.unpacked_dir)
            ))

        if issues:
            print("FAILED - Found {} relationship validation errors:".format(len(issues)))
            for ln in issues:
                print(ln)
            print(
                "CRITICAL: These errors will cause the document to appear corrupt. "
                "Broken references MUST be fixed, "
                "and unreferenced files MUST be referenced or removed."
            )
            return False
        if self.verbose:
            print("PASSED - All references are valid and all files are properly referenced")
        return True

    # ──────────────────────────────────────────────────────────────
    # Check 5 – relationship ID cross-references
    # ──────────────────────────────────────────────────────────────

    def validate_all_relationship_ids(self):
        import lxml.etree

        issues = []
        for fp in self.xml_files:
            if fp.suffix == ".rels":
                continue

            rels_dir = fp.parent / "_rels"
            companion = rels_dir / "{}.rels".format(fp.name)
            if not companion.exists():
                continue

            try:
                rr = lxml.etree.parse(str(companion)).getroot()
                id_map = {}

                for rel in rr.findall(
                    ".//{{{}}}Relationship".format(self.PACKAGE_RELATIONSHIPS_NAMESPACE)
                ):
                    rid = rel.get("Id")
                    rtype = rel.get("Type", "")
                    if rid is None:
                        continue
                    if rid in id_map:
                        issues.append(
                            "  {}: Line {}: Duplicate relationship ID '{}' (IDs must be unique)".format(
                                companion.relative_to(self.unpacked_dir), rel.sourceline, rid
                            )
                        )
                    short_type = rtype.rsplit("/", 1)[-1] if "/" in rtype else rtype
                    id_map[rid] = short_type

                xr = lxml.etree.parse(str(fp)).getroot()
                r_ns = self.OFFICE_RELATIONSHIPS_NAMESPACE
                for nd in xr.iter():
                    for aname in ("id", "embed", "link"):
                        val = nd.get("{{{}}}{}" .format(r_ns, aname))
                        if not val:
                            continue
                        rel_p = fp.relative_to(self.unpacked_dir)
                        tag = nd.tag.split("}")[-1] if "}" in nd.tag else nd.tag

                        if val not in id_map:
                            preview = ", ".join(sorted(id_map.keys())[:5])
                            if len(id_map) > 5:
                                preview += "..."
                            issues.append(
                                "  {}: Line {}: <{}> r:{} references non-existent relationship '{}' "
                                "(valid IDs: {})".format(rel_p, nd.sourceline, tag, aname, val, preview)
                            )
                        elif aname == "id" and self.ELEMENT_RELATIONSHIP_TYPES:
                            expected = self._get_expected_relationship_type(tag)
                            if expected and expected not in id_map[val].lower():
                                issues.append(
                                    "  {}: Line {}: <{}> references '{}' which points to '{}' "
                                    "but should point to a '{}' relationship".format(
                                        rel_p, nd.sourceline, tag, val, id_map[val], expected
                                    )
                                )

            except Exception as exc:
                issues.append("  Error processing {}: {}".format(
                    fp.relative_to(self.unpacked_dir), exc
                ))

        if issues:
            print("FAILED - Found {} relationship ID reference errors:".format(len(issues)))
            for ln in issues:
                print(ln)
            print("\nThese ID mismatches will cause the document to appear corrupt!")
            return False
        if self.verbose:
            print("PASSED - All relationship ID references are valid")
        return True

    def _get_expected_relationship_type(self, elem_tag):
        lc = elem_tag.lower()
        if lc in self.ELEMENT_RELATIONSHIP_TYPES:
            return self.ELEMENT_RELATIONSHIP_TYPES[lc]
        if lc.endswith("id") and len(lc) > 2:
            stem = lc[:-2]
            if stem.endswith("master") or stem.endswith("layout"):
                return stem
            return "slide" if stem == "sld" else stem
        if lc.endswith("reference") and len(lc) > 9:
            return lc[:-9]
        return None

    # ──────────────────────────────────────────────────────────────
    # Check 6 – [Content_Types].xml completeness
    # ──────────────────────────────────────────────────────────────

    def validate_content_types(self):
        issues = []
        ct_file = self.unpacked_dir / "[Content_Types].xml"
        if not ct_file.exists():
            print("FAILED - [Content_Types].xml file not found")
            return False

        try:
            root = lxml.etree.parse(str(ct_file)).getroot()

            overrides = {
                ov.get("PartName").lstrip("/")
                for ov in root.findall(
                    ".//{{{}}}Override".format(self.CONTENT_TYPES_NAMESPACE)
                )
                if ov.get("PartName") is not None
            }

            defaults = {
                df.get("Extension").lower()
                for df in root.findall(
                    ".//{{{}}}Default".format(self.CONTENT_TYPES_NAMESPACE)
                )
                if df.get("Extension") is not None
            }

            important_roots = {
                "sld", "sldLayout", "sldMaster", "presentation",
                "document", "workbook", "worksheet", "theme",
            }

            _MEDIA_CT = {
                "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                "gif": "image/gif", "bmp": "image/bmp", "tiff": "image/tiff",
                "wmf": "image/x-wmf", "emf": "image/x-emf",
            }

            for xf in self.xml_files:
                rp = str(xf.relative_to(self.unpacked_dir)).replace("\\", "/")
                if any(skip in rp for skip in (".rels", "[Content_Types]", "docProps/", "_rels/")):
                    continue
                try:
                    tag = lxml.etree.parse(str(xf)).getroot().tag
                    root_name = tag.split("}")[-1] if "}" in tag else tag
                    if root_name in important_roots and rp not in overrides:
                        issues.append(
                            "  {}: File with <{}> root not declared in [Content_Types].xml".format(
                                rp, root_name
                            )
                        )
                except Exception:
                    continue

            all_files = [f for f in self.unpacked_dir.rglob("*") if f.is_file()]
            for fp in all_files:
                if fp.suffix.lower() in (".xml", ".rels"):
                    continue
                if fp.name == "[Content_Types].xml":
                    continue
                if "_rels" in fp.parts or "docProps" in fp.parts:
                    continue
                ext = fp.suffix.lstrip(".").lower()
                if ext and ext not in defaults and ext in _MEDIA_CT:
                    issues.append(
                        '  {}: File with extension \'{}\' not declared in [Content_Types].xml'
                        ' - should add: <Default Extension="{}" ContentType="{}"/>'.format(
                            fp.relative_to(self.unpacked_dir), ext, ext, _MEDIA_CT[ext]
                        )
                    )

        except Exception as exc:
            issues.append("  Error parsing [Content_Types].xml: {}".format(exc))

        if issues:
            print("FAILED - Found {} content type declaration errors:".format(len(issues)))
            for ln in issues:
                print(ln)
            return False
        if self.verbose:
            print("PASSED - All content files are properly declared in [Content_Types].xml")
        return True

    # ──────────────────────────────────────────────────────────────
    # XSD validation (single file + batch)
    # ──────────────────────────────────────────────────────────────

    def validate_file_against_xsd(self, xml_file, verbose=False):
        xml_file = Path(xml_file).resolve()
        base = self.unpacked_dir.resolve()

        ok, cur_errs = self._check_one_xsd(xml_file, base)

        if ok is None:
            return None, set()
        if ok:
            return True, set()

        orig_errs = self._original_xsd_errors(xml_file)

        assert cur_errs is not None
        fresh = cur_errs - orig_errs
        fresh = {
            e for e in fresh
            if not any(pat in e for pat in self.IGNORED_VALIDATION_ERRORS)
        }

        if fresh:
            if verbose:
                rp = xml_file.relative_to(base)
                print("FAILED - {}: {} new error(s)".format(rp, len(fresh)))
                for e in list(fresh)[:3]:
                    print("  - {}".format(e[:250] + "..." if len(e) > 250 else e))
            return False, fresh
        if verbose:
            print("PASSED - No new errors (original had {} errors)".format(len(cur_errs)))
        return True, set()

    def validate_against_xsd(self):
        fresh_issues = []
        n_orig_err = 0
        n_ok = 0
        n_skip = 0

        for fp in self.xml_files:
            rp = str(fp.relative_to(self.unpacked_dir))
            ok, errs = self.validate_file_against_xsd(fp, verbose=False)

            if ok is None:
                n_skip += 1
            elif ok and not errs:
                n_ok += 1
            elif ok:
                n_orig_err += 1
                n_ok += 1
            else:
                fresh_issues.append("  {}: {} new error(s)".format(rp, len(errs)))
                for e in list(errs)[:3]:
                    fresh_issues.append(
                        "    - {}".format(e[:250] + "..." if len(e) > 250 else e)
                    )

        if self.verbose:
            print("Validated {} files:".format(len(self.xml_files)))
            print("  - Valid: {}".format(n_ok))
            print("  - Skipped (no schema): {}".format(n_skip))
            if n_orig_err:
                print("  - With original errors (ignored): {}".format(n_orig_err))
            print(
                "  - With NEW errors: {}".format(
                    len(fresh_issues) > 0
                    and len([e for e in fresh_issues if not e.startswith("    ")])
                    or 0
                )
            )

        if fresh_issues:
            print("\nFAILED - Found NEW validation errors:")
            for ln in fresh_issues:
                print(ln)
            return False
        if self.verbose:
            print("\nPASSED - No new XSD validation errors introduced")
        return True

    # ── private XSD helpers ──

    def _resolve_schema(self, fp):
        if fp.name in self.SCHEMA_MAPPINGS:
            return self.schemas_dir / self.SCHEMA_MAPPINGS[fp.name]
        if fp.suffix == ".rels":
            return self.schemas_dir / self.SCHEMA_MAPPINGS[".rels"]
        if "charts/" in str(fp) and fp.name.startswith("chart"):
            return self.schemas_dir / self.SCHEMA_MAPPINGS["chart"]
        if "theme/" in str(fp) and fp.name.startswith("theme"):
            return self.schemas_dir / self.SCHEMA_MAPPINGS["theme"]
        if fp.parent.name in self.MAIN_CONTENT_FOLDERS:
            return self.schemas_dir / self.SCHEMA_MAPPINGS[fp.parent.name]
        return None

    # keep old name as alias
    _get_schema_path = _resolve_schema

    def _strip_non_ooxml_attrs(self, doc):
        """Return a cleaned ElementTree with non-OOXML attrs/elements removed."""
        s = lxml.etree.tostring(doc, encoding="unicode")
        copy = lxml.etree.fromstring(s)

        for nd in copy.iter():
            bad = [
                a for a in nd.attrib
                if "{" in a and a.split("}")[0][1:] not in self.OOXML_NAMESPACES
            ]
            for a in bad:
                del nd.attrib[a]

        self._strip_foreign_elements(copy)
        return lxml.etree.ElementTree(copy)

    # keep old name
    _clean_ignorable_namespaces = _strip_non_ooxml_attrs

    def _strip_foreign_elements(self, root):
        doomed = []
        for el in list(root):
            if not hasattr(el, "tag") or callable(el.tag):
                continue
            t = str(el.tag)
            if t.startswith("{") and t.split("}")[0][1:] not in self.OOXML_NAMESPACES:
                doomed.append(el)
                continue
            self._strip_foreign_elements(el)
        for el in doomed:
            root.remove(el)

    _remove_ignorable_elements = _strip_foreign_elements

    def _drop_mc_ignorable(self, doc):
        root = doc.getroot()
        mc_key = "{{{}}}Ignorable".format(self.MC_NAMESPACE)
        if mc_key in root.attrib:
            del root.attrib[mc_key]
        return doc

    _preprocess_for_mc_ignorable = _drop_mc_ignorable

    def _check_one_xsd(self, fp, base):
        schema_path = self._resolve_schema(fp)
        if schema_path is None:
            return None, None

        try:
            with open(schema_path, "rb") as fh:
                xsd_doc = lxml.etree.parse(fh, parser=lxml.etree.XMLParser(), base_url=str(schema_path))
                schema = lxml.etree.XMLSchema(xsd_doc)

            with open(fp, "r") as fh:
                xml_doc = lxml.etree.parse(fh)

            xml_doc, _ = self._scrub_template_tags(xml_doc)
            xml_doc = self._drop_mc_ignorable(xml_doc)

            rp = fp.relative_to(base)
            if rp.parts and rp.parts[0] in self.MAIN_CONTENT_FOLDERS:
                xml_doc = self._strip_non_ooxml_attrs(xml_doc)

            if schema.validate(xml_doc):
                return True, set()
            return False, {e.message for e in schema.error_log}

        except Exception as exc:
            return False, {str(exc)}

    _validate_single_file_xsd = _check_one_xsd

    def _original_xsd_errors(self, fp):
        if self.original_file is None:
            return set()

        import tempfile, zipfile

        fp = Path(fp).resolve()
        rp = fp.relative_to(self.unpacked_dir.resolve())

        with tempfile.TemporaryDirectory() as td:
            tp = Path(td)
            with zipfile.ZipFile(self.original_file, "r") as zr:
                zr.extractall(tp)
            orig = tp / rp
            if not orig.exists():
                return set()
            _, errs = self._check_one_xsd(orig, tp)
            return errs if errs else set()

    _get_original_file_errors = _original_xsd_errors

    def _scrub_template_tags(self, doc):
        warnings = []
        tpl_re = re.compile(r"\{\{[^}]*\}\}")

        s = lxml.etree.tostring(doc, encoding="unicode")
        copy = lxml.etree.fromstring(s)

        def _clean(txt, ctx):
            if not txt:
                return txt
            hits = list(tpl_re.finditer(txt))
            if hits:
                for h in hits:
                    warnings.append("Found template tag in {}: {}".format(ctx, h.group()))
                return tpl_re.sub("", txt)
            return txt

        for nd in copy.iter():
            if not hasattr(nd, "tag") or callable(nd.tag):
                continue
            t = str(nd.tag)
            if t.endswith("}t") or t == "t":
                continue
            nd.text = _clean(nd.text, "text content")
            nd.tail = _clean(nd.tail, "tail content")

        return lxml.etree.ElementTree(copy), warnings

    _remove_template_tags_from_text_nodes = _scrub_template_tags


if __name__ == "__main__":
    raise RuntimeError("This module should not be run directly.")
