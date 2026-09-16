#!/usr/bin/env python3
# ──────────────────────────────────────────────────────────────────
# Tracked-change (redlining) consistency validator for DOCX.
#
# Verifies that the textual content of the modified document matches
# the original *after* stripping out all tracked changes attributed
# to the specified author.  If there's a mismatch, a word-level diff
# is produced via `git diff --word-diff`.
# ──────────────────────────────────────────────────────────────────

import subprocess
import tempfile
import zipfile
from pathlib import Path

_W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"


class RedliningValidator:
    """Ensure that an author's changes are fully tracked in the DOCX XML."""

    def __init__(self, unpacked_dir, original_docx, verbose=False, author="Claude"):
        self.work_dir = Path(unpacked_dir)
        self.ref_docx = Path(original_docx)
        self.verbose = verbose
        self.author = author
        self._ns = {"w": _W_NS}

    # kept for interface compat
    @property
    def unpacked_dir(self):
        return self.work_dir

    @property
    def original_docx(self):
        return self.ref_docx

    @property
    def namespaces(self):
        return self._ns

    def repair(self) -> int:
        return 0

    # ──────────────────────────────────────────────────────────────

    def validate(self):
        mod_xml = self.work_dir / "word" / "document.xml"
        if not mod_xml.exists():
            print("FAILED - Modified document.xml not found at {}".format(mod_xml))
            return False

        # Quick check: any tracked changes by this author?
        try:
            import xml.etree.ElementTree as ET

            tree = ET.parse(mod_xml)
            root = tree.getroot()

            w_author = "{{{}}}author".format(_W_NS)
            del_by_author = [
                e for e in root.findall(".//w:del", self._ns)
                if e.get(w_author) == self.author
            ]
            ins_by_author = [
                e for e in root.findall(".//w:ins", self._ns)
                if e.get(w_author) == self.author
            ]
            if not del_by_author and not ins_by_author:
                if self.verbose:
                    print("PASSED - No tracked changes by {} found.".format(self.author))
                return True
        except Exception:
            pass

        # Full comparison
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)

            try:
                with zipfile.ZipFile(self.ref_docx, "r") as zf:
                    zf.extractall(tmp)
            except Exception as exc:
                print("FAILED - Error unpacking original docx: {}".format(exc))
                return False

            orig_xml = tmp / "word" / "document.xml"
            if not orig_xml.exists():
                print("FAILED - Original document.xml not found in {}".format(self.ref_docx))
                return False

            try:
                import xml.etree.ElementTree as ET

                mod_root = ET.parse(mod_xml).getroot()
                orig_root = ET.parse(orig_xml).getroot()
            except ET.ParseError as exc:
                print("FAILED - Error parsing XML files: {}".format(exc))
                return False

            self._strip_author_changes(orig_root)
            self._strip_author_changes(mod_root)

            txt_mod = self._body_text(mod_root)
            txt_orig = self._body_text(orig_root)

            if txt_mod != txt_orig:
                print(self._build_diff_report(txt_orig, txt_mod))
                return False

        if self.verbose:
            print("PASSED - All changes by {} are properly tracked".format(self.author))
        return True

    # ──────────────────────────────────────────────────────────────
    # Diff report generation
    # ──────────────────────────────────────────────────────────────

    def _build_diff_report(self, old_text, new_text):
        parts = [
            "FAILED - Document text doesn't match after removing {}'s tracked changes".format(self.author),
            "",
            "Likely causes:",
            "  1. Modified text inside another author's <w:ins> or <w:del> tags",
            "  2. Made edits without proper tracked changes",
            "  3. Didn't nest <w:del> inside <w:ins> when deleting another's insertion",
            "",
            "For pre-redlined documents, use correct patterns:",
            "  - To reject another's INSERTION: Nest <w:del> inside their <w:ins>",
            "  - To restore another's DELETION: Add new <w:ins> AFTER their <w:del>",
            "",
        ]
        diff = self._word_diff(old_text, new_text)
        if diff:
            parts += ["Differences:", "============", diff]
        else:
            parts.append("Unable to generate word diff (git not available)")
        return "\n".join(parts)

    def _word_diff(self, a, b):
        """Produce a character-level word diff using git."""
        try:
            with tempfile.TemporaryDirectory() as td:
                p = Path(td)
                fa, fb = p / "original.txt", p / "modified.txt"
                fa.write_text(a, encoding="utf-8")
                fb.write_text(b, encoding="utf-8")

                for extra_args in (
                    ["--word-diff-regex=."],
                    [],
                ):
                    proc = subprocess.run(
                        [
                            "git", "diff", "--word-diff=plain", "-U0",
                            "--no-index", str(fa), str(fb),
                        ] + extra_args,
                        capture_output=True, text=True,
                    )
                    if not proc.stdout.strip():
                        continue
                    content = []
                    active = False
                    for line in proc.stdout.split("\n"):
                        if line.startswith("@@"):
                            active = True
                            continue
                        if active and line.strip():
                            content.append(line)
                    if content:
                        return "\n".join(content)

        except (subprocess.CalledProcessError, FileNotFoundError, Exception):
            pass
        return None

    # ──────────────────────────────────────────────────────────────
    # XML manipulation
    # ──────────────────────────────────────────────────────────────

    def _strip_author_changes(self, root):
        """Remove this author's tracked insertions; inline their deletions."""
        ins_tag = "{{{}}}ins".format(_W_NS)
        del_tag = "{{{}}}del".format(_W_NS)
        auth_key = "{{{}}}author".format(_W_NS)

        # Pass 1: remove <w:ins> by this author entirely
        for parent in root.iter():
            doomed = [
                ch for ch in parent
                if ch.tag == ins_tag and ch.get(auth_key) == self.author
            ]
            for el in doomed:
                parent.remove(el)

        # Pass 2: inline <w:del> by this author (convert delText → t)
        deltext_tag = "{{{}}}delText".format(_W_NS)
        t_tag = "{{{}}}t".format(_W_NS)

        for parent in root.iter():
            targets = [
                (ch, list(parent).index(ch))
                for ch in parent
                if ch.tag == del_tag and ch.get(auth_key) == self.author
            ]
            for del_el, idx in reversed(targets):
                for nd in del_el.iter():
                    if nd.tag == deltext_tag:
                        nd.tag = t_tag
                for kid in reversed(list(del_el)):
                    parent.insert(idx, kid)
                parent.remove(del_el)

    def _body_text(self, root):
        """Extract the visible paragraph text from the document body."""
        p_tag = "{{{}}}p".format(_W_NS)
        t_tag = "{{{}}}t".format(_W_NS)

        paragraphs = []
        for p in root.findall(".//{}".format(p_tag)):
            pieces = [t.text for t in p.findall(".//{}".format(t_tag)) if t.text]
            joined = "".join(pieces)
            if joined:
                paragraphs.append(joined)
        return "\n".join(paragraphs)


if __name__ == "__main__":
    raise RuntimeError("This module should not be run directly.")
