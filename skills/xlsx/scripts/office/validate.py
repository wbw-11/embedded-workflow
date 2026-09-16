#!/usr/bin/env python3
# ──────────────────────────────────────────────────────────────────
# Standalone CLI for validating unpacked Office XML against XSD schemas
# and checking tracked-change consistency.
#
# Accepts either an unpacked directory or a packed .docx/.pptx/.xlsx
# (the latter is extracted to a temp dir automatically).
#
# Auto-repair capabilities:
#   • paraId / durableId values exceeding OOXML limits
#   • Missing xml:space="preserve" on <w:t> elements with whitespace
# ──────────────────────────────────────────────────────────────────

import argparse
import sys
import tempfile
import zipfile
from pathlib import Path

from validators import DOCXSchemaValidator, PPTXSchemaValidator, RedliningValidator

_VALID_SUFFIXES = [".docx", ".pptx", ".xlsx"]


def main():
    ap = argparse.ArgumentParser(description="Validate Office document XML files")
    ap.add_argument(
        "path",
        help="Path to unpacked directory or packed Office file (.docx/.pptx/.xlsx)",
    )
    ap.add_argument(
        "--original", required=False, default=None,
        help=(
            "Path to original file (.docx/.pptx/.xlsx). "
            "If omitted, all XSD errors are reported and redlining validation is skipped."
        ),
    )
    ap.add_argument("-v", "--verbose", action="store_true", help="Enable verbose output")
    ap.add_argument(
        "--auto-repair", action="store_true",
        help="Automatically repair common issues (hex IDs, whitespace preservation)",
    )
    ap.add_argument(
        "--author", default="Claude",
        help="Author name for redlining validation (default: Claude)",
    )
    opts = ap.parse_args()

    target = Path(opts.path)
    assert target.exists(), "Error: {} does not exist".format(target)

    orig = None
    if opts.original is not None:
        orig = Path(opts.original)
        assert orig.is_file(), "Error: {} is not a file".format(orig)
        assert orig.suffix.lower() in _VALID_SUFFIXES, (
            "Error: {} must be a .docx, .pptx, or .xlsx file".format(orig)
        )

    detected_ext = (orig or target).suffix.lower()
    assert detected_ext in _VALID_SUFFIXES, (
        "Error: Cannot determine file type from {}. "
        "Use --original or provide a .docx/.pptx/.xlsx file.".format(target)
    )

    # Auto-extract packed files into a temp directory
    if target.is_file() and target.suffix.lower() in _VALID_SUFFIXES:
        tmp = tempfile.mkdtemp()
        with zipfile.ZipFile(target, "r") as zf:
            zf.extractall(tmp)
        work_dir = Path(tmp)
    else:
        assert target.is_dir(), "Error: {} is not a directory or Office file".format(target)
        work_dir = target

    # Build the appropriate validator chain
    match detected_ext:
        case ".docx":
            checkers = [
                DOCXSchemaValidator(work_dir, orig, verbose=opts.verbose),
            ]
            if orig is not None:
                checkers.append(
                    RedliningValidator(work_dir, orig, verbose=opts.verbose, author=opts.author)
                )
        case ".pptx":
            checkers = [
                PPTXSchemaValidator(work_dir, orig, verbose=opts.verbose),
            ]
        case _:
            print("Error: Validation not supported for file type {}".format(detected_ext))
            sys.exit(1)

    if opts.auto_repair:
        n_fixed = sum(c.repair() for c in checkers)
        if n_fixed:
            print("Auto-repaired {} issue(s)".format(n_fixed))

    ok = all(c.validate() for c in checkers)

    if ok:
        print("All validations PASSED!")

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
