#!/usr/bin/env python3
# ──────────────────────────────────────────────────────────────────
# Assembles an unpacked directory back into a DOCX / PPTX / XLSX archive.
#
# Optionally validates (with auto-repair) before packing and minifies
# all XML / .rels content by stripping cosmetic whitespace.
#
#   python pack.py <src_dir> <dest_file> [--original <ref>] [--validate true|false]
# ──────────────────────────────────────────────────────────────────

import argparse
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import defusedxml.minidom

from validators import DOCXSchemaValidator, PPTXSchemaValidator, RedliningValidator

_ALLOWED_EXTENSIONS = {".docx", ".pptx", ".xlsx"}
_XML_GLOB_PATTERNS = ("*.xml", "*.rels")


def pack(
    src_dir: str,
    dest_file: str,
    ref_file: str | None = None,
    run_validation: bool = True,
    author_resolver=None,
) -> tuple[None, str]:
    """Create an Office ZIP archive from *src_dir* → *dest_file*."""
    src = Path(src_dir)
    dest = Path(dest_file)
    ext = dest.suffix.lower()

    if not src.is_dir():
        return None, "Error: {} is not a directory".format(src)

    if ext not in _ALLOWED_EXTENSIONS:
        return None, "Error: {} must be a .docx, .pptx, or .xlsx file".format(dest_file)

    # ── optional validation pass ──
    if run_validation and ref_file:
        ref = Path(ref_file)
        if ref.exists():
            ok, report = _do_validation(src, ref, ext, author_resolver)
            if report:
                print(report)
            if not ok:
                return None, "Error: Validation failed for {}".format(src)

    # ── minify XML then zip ──
    with tempfile.TemporaryDirectory() as staging:
        staging_root = Path(staging) / "content"
        shutil.copytree(src, staging_root)

        for pat in _XML_GLOB_PATTERNS:
            for xf in staging_root.rglob(pat):
                _strip_xml_whitespace(xf)

        dest.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as zf:
            for entry in staging_root.rglob("*"):
                if entry.is_file():
                    zf.write(entry, entry.relative_to(staging_root))

    return None, "Successfully packed {} to {}".format(src, dest_file)


# ──────────────────────────────────────────────────────────────────

def _do_validation(folder, original, ext, author_resolver):
    """Run format-specific validators and return (success, message|None)."""
    lines = []
    checkers = []

    if ext == ".docx":
        writer = "Claude"
        if author_resolver is not None:
            try:
                writer = author_resolver(folder, original)
            except ValueError as exc:
                print("Warning: {} Using default author 'Claude'.".format(exc), file=sys.stderr)

        checkers = [
            DOCXSchemaValidator(folder, original),
            RedliningValidator(folder, original, author=writer),
        ]
    elif ext == ".pptx":
        checkers = [PPTXSchemaValidator(folder, original)]

    if not checkers:
        return True, None

    n_repairs = sum(v.repair() for v in checkers)
    if n_repairs:
        lines.append("Auto-repaired {} issue(s)".format(n_repairs))

    passed = all(v.validate() for v in checkers)
    if passed:
        lines.append("All validations PASSED!")

    return passed, "\n".join(lines) if lines else None


def _strip_xml_whitespace(xml_path: Path) -> None:
    """Parse then re-serialise an XML file, dropping cosmetic text nodes."""
    try:
        with open(xml_path, encoding="utf-8") as fh:
            tree = defusedxml.minidom.parse(fh)

        for node in tree.getElementsByTagName("*"):
            # Preserve literal text inside <w:t>, <a:t>, etc.
            if node.tagName.endswith(":t"):
                continue
            for kid in list(node.childNodes):
                is_blank_text = (
                    kid.nodeType == kid.TEXT_NODE
                    and kid.nodeValue is not None
                    and kid.nodeValue.strip() == ""
                )
                if is_blank_text or kid.nodeType == kid.COMMENT_NODE:
                    node.removeChild(kid)

        xml_path.write_bytes(tree.toxml(encoding="UTF-8"))
    except Exception as err:
        print("ERROR: Failed to parse {}: {}".format(xml_path.name, err), file=sys.stderr)
        raise


# ──────────────────────────────────────────────────────────────────
# CLI entry-point
# ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="Pack a directory into a DOCX, PPTX, or XLSX file"
    )
    ap.add_argument("input_directory", help="Unpacked Office document directory")
    ap.add_argument("output_file", help="Output Office file (.docx/.pptx/.xlsx)")
    ap.add_argument("--original", help="Original file for validation comparison")
    ap.add_argument(
        "--validate",
        type=lambda v: v.lower() == "true",
        default=True,
        metavar="true|false",
        help="Run validation with auto-repair (default: true)",
    )
    ns = ap.parse_args()

    _, msg = pack(
        ns.input_directory,
        ns.output_file,
        ref_file=ns.original,
        run_validation=ns.validate,
    )
    print(msg)

    if "Error" in msg:
        sys.exit(1)
