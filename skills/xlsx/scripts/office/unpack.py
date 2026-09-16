#!/usr/bin/env python3
# ──────────────────────────────────────────────────────────────────
# Extract Office archives (DOCX / PPTX / XLSX) into an editable tree.
#
# After extraction, XML is pretty-printed for readability. For DOCX
# files two optional post-processing passes are available:
#   • run-merging   – coalesce adjacent <w:r> with matching properties
#   • redline-simplification – coalesce adjacent <w:ins>/<w:del> tags
#
# CLI:
#   python unpack.py <office_file> <out_dir> [--merge-runs true|false]
#                                             [--simplify-redlines true|false]
# ──────────────────────────────────────────────────────────────────

import argparse
import sys
import zipfile
from pathlib import Path

import defusedxml.minidom

from helpers.merge_runs import merge_runs as _coalesce_runs
from helpers.simplify_redlines import simplify_redlines as _coalesce_redlines

# Unicode curly-quote → XML entity mapping
_CURLY_QUOTES = {
    "\u201c": "&#x201C;",
    "\u201d": "&#x201D;",
    "\u2018": "&#x2018;",
    "\u2019": "&#x2019;",
}

_OFFICE_SUFFIXES = {".docx", ".pptx", ".xlsx"}


def unpack(
    src_file: str,
    out_dir: str,
    coalesce_runs: bool = True,
    coalesce_redlines: bool = True,
) -> tuple[None, str]:
    """Extract *src_file* into *out_dir* and post-process XML."""
    src = Path(src_file)
    dest = Path(out_dir)
    ext = src.suffix.lower()

    if not src.exists():
        return None, "Error: {} does not exist".format(src_file)

    if ext not in _OFFICE_SUFFIXES:
        return None, "Error: {} must be a .docx, .pptx, or .xlsx file".format(src_file)

    try:
        dest.mkdir(parents=True, exist_ok=True)

        with zipfile.ZipFile(src, "r") as archive:
            archive.extractall(dest)

        xml_paths = [
            p for p in list(dest.rglob("*.xml")) + list(dest.rglob("*.rels"))
        ]

        for xp in xml_paths:
            _reformat_xml(xp)

        info = "Unpacked {} ({} XML files)".format(src_file, len(xml_paths))

        # DOCX-specific post-processing
        if ext == ".docx":
            if coalesce_redlines:
                n, _ = _coalesce_redlines(str(dest))
                info += ", simplified {} tracked changes".format(n)
            if coalesce_runs:
                n, _ = _coalesce_runs(str(dest))
                info += ", merged {} runs".format(n)

        for xp in xml_paths:
            _encode_curly_quotes(xp)

        return None, info

    except zipfile.BadZipFile:
        return None, "Error: {} is not a valid Office file".format(src_file)
    except Exception as exc:
        return None, "Error unpacking: {}".format(exc)


# ──────────────────────────────────────────────────────────────────

def _reformat_xml(fp: Path) -> None:
    """Pretty-print an XML file in-place (2-space indent)."""
    try:
        raw = fp.read_text(encoding="utf-8")
        doc = defusedxml.minidom.parseString(raw)
        fp.write_bytes(doc.toprettyxml(indent="  ", encoding="utf-8"))
    except Exception:
        pass


def _encode_curly_quotes(fp: Path) -> None:
    """Replace curly quotes with their XML entity equivalents."""
    try:
        data = fp.read_text(encoding="utf-8")
        for ch, ent in _CURLY_QUOTES.items():
            data = data.replace(ch, ent)
        fp.write_text(data, encoding="utf-8")
    except Exception:
        pass


# ──────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="Unpack an Office file (DOCX, PPTX, XLSX) for editing"
    )
    ap.add_argument("input_file", help="Office file to unpack")
    ap.add_argument("output_directory", help="Output directory")
    ap.add_argument(
        "--merge-runs",
        type=lambda x: x.lower() == "true",
        default=True,
        metavar="true|false",
        help="Merge adjacent runs with identical formatting (DOCX only, default: true)",
    )
    ap.add_argument(
        "--simplify-redlines",
        type=lambda x: x.lower() == "true",
        default=True,
        metavar="true|false",
        help="Merge adjacent tracked changes from same author (DOCX only, default: true)",
    )
    ns = ap.parse_args()

    _, msg = unpack(
        ns.input_file,
        ns.output_directory,
        coalesce_runs=ns.merge_runs,
        coalesce_redlines=ns.simplify_redlines,
    )
    print(msg)

    if "Error" in msg:
        sys.exit(1)
