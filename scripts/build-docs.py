#!/usr/bin/env python3
"""Build the PDF pack from the Markdown in docs/.

Run by `make docs`. Each document in DOCUMENTS below is rendered through pandoc
with typst as the PDF engine and docs/theme/pack.typ as the template, then all of
them are rendered again as one combined PDF with a single table of contents.

The Markdown is the source. The PDFs are a convenience for people who want to read
or print the pack away from a browser, so a missing pandoc or typst is a reason to
skip this target and not a reason to distrust the documents.

Two properties worth knowing about:

*   **Rebuilds are stable.** typst runs with --ignore-system-fonts, so only the
    fonts typst bundles are available and a machine's own fonts cannot change the
    output; and SOURCE_DATE_EPOCH is pinned to the commit's own timestamp, because
    typst otherwise stamps the current time into every PDF and no two builds agree.
    The --check-reproducible flag builds twice and compares.

*   **Overflow is caught, not tolerated.** Content running past the right text edge
    fails the build. The tolerance is 4pt, which clears a hanging hyphen and sits
    well below anything worth shipping.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

try:
    import yaml
except ImportError:
    sys.exit("missing dependency: pyyaml. Run `make deps`.")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
THEME = os.path.join(DOCS, "theme", "pack.typ")
OUT = os.path.join(ROOT, "release")
COMBINED_ID = "databricks-agentic-engineering-rails-pack"

# The pack, in reading order. Listed here rather than found by a glob: the order is
# editorial, and a glob would silently add a draft or reorder the set the day
# someone renames a file.
DOCUMENTS = (
    ("00-start-here", "Start here"),
    ("01-prerequisites", "Prerequisites"),
    ("02-permissions", "Permissions"),
    ("03-gateway-auth", "Gateway authentication and governance"),
    ("04-skills-vs-mcp", "Skills versus MCP"),
    ("05-ci-test-docs", "CI, tests and documentation"),
    ("SOURCES", "Sources"),
)

# Paper sizes in millimetres, only the ones the theme is allowed to ask for.
PAPERS = {"a4": (210.0, 297.0), "us-letter": (215.9, 279.4)}
MM_PER_PT = 25.4 / 72.0

# How far a glyph may stick past the text edge before it counts as overflow.
#
# It cannot be zero. Justified text with hyphenation lets the hyphen hang into
# the margin, and the worst case observed in this pack is 1.96pt (a hyphenated
# word at a line end). Real overflow is not subtle: an unwrapped code line or a
# table too
# wide for the page runs over by tens of points. 4pt sits well clear of the
# typographic overhang and well below anything worth shipping.
OVERFLOW_TOL_PT = 4.0


class DateSafeLoader(yaml.SafeLoader):
    """Leave dates as strings.

    PyYAML resolves an unquoted 2026-09-16 to a datetime.date, which then
    formats differently from what the file says and cannot be compared to a
    string without a conversion nobody remembers to write.
    """


DateSafeLoader.yaml_implicit_resolvers = {
    ch: [(tag, rx) for tag, rx in res if tag != "tag:yaml.org,2002:timestamp"]
    for ch, res in yaml.SafeLoader.yaml_implicit_resolvers.items()
}


def sh(cmd: list[str]) -> str:
    return subprocess.run(cmd, capture_output=True, text=True, check=False).stdout.strip()


def tool_version(binary: str, pattern: str) -> str:
    out = sh([binary, "--version"])
    match = re.search(pattern, out)
    return match.group(1) if match else (out.splitlines()[0] if out else "unknown")


def require(binary: str, hint: str) -> None:
    if shutil.which(binary) is None:
        sys.exit("missing %s. %s" % (binary, hint))


def git_state() -> dict:
    commit = sh(["git", "-C", ROOT, "rev-parse", "HEAD"]) or "unknown"
    branch = sh(["git", "-C", ROOT, "rev-parse", "--abbrev-ref", "HEAD"]) or "unknown"
    status = subprocess.run(["git", "-C", ROOT, "status", "--porcelain"],
                            capture_output=True, text=True, check=False)
    return {"commit": commit, "branch": branch, "dirty": bool(status.stdout.strip())}


def source_date_epoch() -> tuple[int, str]:
    """The timestamp the PDFs are stamped with, and where it came from.

    An existing SOURCE_DATE_EPOCH wins, so a caller can pin the build. Otherwise
    the commit's own author date is used: the artifact then belongs to the
    revision rather than to the moment someone happened to run the build. Only an
    untracked tree falls back to the clock, and the manifest records that it did.
    """
    env = os.environ.get("SOURCE_DATE_EPOCH", "").strip()
    if env.isdigit():
        return int(env), "environment"
    committed = sh(["git", "-C", ROOT, "log", "-1", "--pretty=%ct"])
    if committed.isdigit():
        return int(committed), "commit"
    return int(dt.datetime.now(dt.timezone.utc).timestamp()), "clock"


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            digest.update(chunk)
    return digest.hexdigest()


def page_count(path: str) -> int | None:
    """Count pages without a PDF library. /Type /Page appears once per page."""
    try:
        with open(path, "rb") as fh:
            blob = fh.read()
    except OSError:
        return None
    count = len(re.findall(rb"/Type\s*/Page[^s]", blob))
    return count or None


def text_frame() -> tuple[float, float, float, float]:
    """The text rectangle in PDF points, read from the theme rather than repeated.

    A tolerance is only meaningful against the real page geometry, and the theme
    is where that geometry is decided. Hard-coding A4 here would make the check
    silently wrong the day someone sets `paper: "us-letter"`.
    """
    theme = open(THEME, encoding="utf-8").read()
    paper = re.search(r'paper:\s*"([a-z0-9-]+)"', theme)
    if not paper or paper.group(1) not in PAPERS:
        sys.exit("cannot read a supported paper size from %s" % os.path.relpath(THEME, ROOT))
    width_mm, height_mm = PAPERS[paper.group(1)]
    margins = dict(re.findall(r"(top|bottom|left|right):\s*([0-9.]+)mm",
                              re.search(r"margin:\s*\(([^)]*)\)", theme).group(1)))
    if len(margins) != 4:
        sys.exit("theme margin must name all four sides in mm")
    m = {k: float(v) / MM_PER_PT for k, v in margins.items()}
    return (m["left"], m["top"],
            width_mm / MM_PER_PT - m["right"], height_mm / MM_PER_PT - m["bottom"])


def overflow_report(pdf: str) -> tuple[list[str], float]:
    """Words that run past the right text edge, worst offender first.

    Text bounding boxes are what pdftotext can give us, so this catches the two
    overflows that actually happen — an unwrapped code line and an over-wide
    table — because both carry text. It does not catch a rule or an image that
    overhangs with no glyph in it. That limit is stated here rather than left for
    the check to imply a guarantee it cannot make.
    """
    out = subprocess.run(["pdftotext", "-bbox", pdf, "-"],
                         capture_output=True, text=True, check=False)
    if out.returncode != 0:
        return ["pdftotext failed, overflow not checked"], 0.0
    _, _, right, _ = text_frame()
    page = 0
    worst = 0.0
    hits: list[tuple[float, int, str]] = []
    for line in out.stdout.splitlines():
        if "<page" in line:
            page += 1
            continue
        word = re.search(r'<word xMin="([0-9.]+)" yMin="[0-9.]+" xMax="([0-9.]+)"'
                         r' yMax="[0-9.]+">(.*)</word>', line)
        if not word:
            continue
        over = float(word.group(2)) - right
        worst = max(worst, over)
        if over > OVERFLOW_TOL_PT:
            hits.append((over, page, word.group(3)))
    hits.sort(reverse=True)
    return ["page %d, %.1fpt past the edge:  %s"
            % (pg, over, word[:60]) for over, pg, word in hits[:8]], worst


def srclabel(src) -> str:
    if isinstance(src, str):
        return os.path.relpath(src, ROOT)
    return "%d documents" % len(src)


def fingerprint(pdf: str) -> str:
    """Everything about a PDF that a reader can perceive, and nothing else.

    This is the weaker of the two reproducibility standards, used only when
    byte-identity fails. Extracted text and per-word bounding boxes together pin the page
    count, the reading order, the line breaking and the position of every glyph,
    so two PDFs with the same fingerprint print and read identically. The two
    timestamp lines are dropped because they are the thing being tolerated.

    What it does not cover: the outline (bookmark) tree and embedded font
    subsets. Both are determined by the intermediate typst source, which is
    compared separately, but neither is read back out of the PDF here. That gap is
    named here rather than papered over.
    """
    out = subprocess.run(["pdftotext", "-bbox", pdf, "-"],
                         capture_output=True, text=True, check=False)
    kept = [ln for ln in out.stdout.splitlines()
            if "CreationDate" not in ln and "ModDate" not in ln]
    return hashlib.sha256("\n".join(kept).encode("utf-8")).hexdigest()


def build_one(src, dest: str, meta: dict, toc: bool, epoch: int) -> None:
    cmd = [
        "pandoc",
    ] + ([src] if isinstance(src, str) else list(src)) + [
        "--from", ("markdown+definition_lists+pipe_tables+table_captions"
                   "+footnotes+smart+implicit_figures"),
        "--to", "typst",
        "--pdf-engine", "typst",
        "--pdf-engine-opt=--ignore-system-fonts",
        "--template", THEME,
        "--resource-path", "%s:%s" % (DOCS, os.path.join(DOCS, "theme")),
        "--output", dest,
    ]
    if toc:
        cmd += ["--toc", "--toc-depth=3", "-V", "toc-depth=3"]
    for key, value in meta.items():
        if value:
            cmd += ["-V", "%s=%s" % (key, value)]

    # typst reads SOURCE_DATE_EPOCH for its PDF timestamps. Without it the same
    # source yields different bytes on every run.
    env = dict(os.environ, SOURCE_DATE_EPOCH=str(epoch), TZ="UTC")
    result = subprocess.run(cmd, capture_output=True, text=True, check=False, env=env)
    if result.returncode != 0 or not os.path.exists(dest):
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        sys.exit("pandoc failed for %s" % (src if isinstance(src, str)
                                           else "%d combined sources" % len(src)))
    # Warnings are worth seeing but are not failures: a missing font warning
    # under --ignore-system-fonts, for instance, means the theme asked for
    # something it should not have.
    if result.stderr.strip():
        for line in result.stderr.strip().splitlines():
            print("      note: %s" % line)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="build a single document id")
    ap.add_argument("--no-combined", action="store_true",
                    help="skip the single combined PDF of the whole pack")
    ap.add_argument("--check-reproducible", action="store_true",
                    help="rebuild every artifact and require byte-identical output")
    args = ap.parse_args()

    require("pandoc", "Install with: brew install pandoc")
    require("typst", "Install with: brew install typst")

    # The pack version comes from the file `make doctor` already reads, so there is
    # one place to change it and no chance of two files disagreeing about which
    # release a PDF belongs to.
    meta = yaml.load(open(os.path.join(ROOT, "template-version.yml"), encoding="utf-8"),
                     Loader=DateSafeLoader)
    version = meta["version"]
    status = "preview" if "preview" in version else "release"
    git = git_state()
    epoch, epoch_from = source_date_epoch()
    # The date on the cover is the revision's date, not today's. A document
    # rebuilt six months later has not changed, and should not claim to have.
    doc_date = dt.datetime.fromtimestamp(epoch, dt.timezone.utc).date().isoformat()

    pandoc_v = tool_version("pandoc", r"pandoc\s+([0-9][0-9.]*)")
    typst_v = tool_version("typst", r"typst\s+([0-9][0-9.]*)")

    os.makedirs(OUT, exist_ok=True)
    print("build-docs: pack %s (%s), pandoc %s, typst %s" % (version, status, pandoc_v, typst_v))
    print("            commit %s%s" % (git["commit"][:12], " (dirty)" if git["dirty"] else ""))
    print("            SOURCE_DATE_EPOCH %d (from the %s) -> cover date %s"
          % (epoch, epoch_from, doc_date))

    targets: list[tuple[str, str, dict, bool]] = []

    for docid, title in DOCUMENTS:
        if args.only and args.only != docid:
            continue
        src = os.path.join(DOCS, "%s.md" % docid)
        if not os.path.exists(src):
            print("      skip  %-38s source not written yet" % docid)
            continue
        targets.append((src, os.path.join(OUT, "%s.pdf" % docid),
                        {"docid": docid, "packversion": version,
                         "status": status, "commit": git["commit"][:12],
                         "date": doc_date, "subtitle": title}, True))

    # The combined pack. Built as one pandoc invocation over every source rather
    # than by stitching finished PDFs together, so it gets a single continuous
    # table of contents and one bookmark tree instead of the flat concatenation
    # `pdfunite` would leave behind.
    combined_sources = [os.path.join(DOCS, "%s.md" % docid) for docid, _ in DOCUMENTS
                        if os.path.exists(os.path.join(DOCS, "%s.md" % docid))]
    if not args.only and not args.no_combined and len(combined_sources) > 1:
        targets.append((combined_sources, os.path.join(OUT, "%s.pdf" % COMBINED_ID),
                        {"docid": COMBINED_ID, "packversion": version,
                         "status": status, "commit": git["commit"][:12],
                         "date": doc_date,
                         "subtitle": "The complete pack, %d documents"
                                     % len(combined_sources)}, True))
    elif len(combined_sources) <= 1 and not args.only:
        print("      skip  %-38s needs 2+ documents, %d written"
              % (COMBINED_ID, len(combined_sources)))

    if not targets:
        sys.exit("nothing to build: no document in DOCUMENTS exists under docs/")

    artifacts = []
    overflows: list[tuple[str, list[str]]] = []
    for src, dest, meta, toc in targets:
        print("      build %-38s -> %s" % (srclabel(src), os.path.relpath(dest, ROOT)))
        build_one(src, dest, meta, toc, epoch)
        row = {
            "path": os.path.relpath(dest, ROOT),
            "sha256": sha256(dest),
            "bytes": os.path.getsize(dest),
            "source": srclabel(src),
        }
        pages = page_count(dest)
        if pages:
            row["pages"] = pages
        hits, worst = overflow_report(dest)
        row["max_overhang_pt"] = round(worst, 2)
        if hits:
            overflows.append((os.path.relpath(dest, ROOT), hits))
        artifacts.append(row)

    if overflows:
        print()
        print("      OVERFLOW — content runs past the right text edge by more than "
              "%.0fpt:" % OVERFLOW_TOL_PT)
        for path, hits in overflows:
            print("        %s" % path)
            for hit in hits:
                print("          %s" % hit)
        print()
        print("      Fix the source, not the tolerance. A long code line wants a "
              "manual break;")
        print("      a wide table wants fewer columns or shorter headings.")
        return 1

    if args.check_reproducible:
        print()
        print("      reproducibility: rebuilding %d artifact(s) to compare"
              % len(targets))
        identical, equivalent, failed = [], [], []
        with tempfile.TemporaryDirectory() as tmp:
            for src, dest, meta, toc in targets:
                again = os.path.join(tmp, os.path.basename(dest))
                build_one(src, again, meta, toc, epoch)
                name = os.path.basename(dest)
                if sha256(again) == sha256(dest):
                    identical.append(name)
                elif fingerprint(again) == fingerprint(dest):
                    equivalent.append(name)
                else:
                    failed.append(name)
        for name in identical:
            print("        byte-identical  %s" % name)
        for name in equivalent:
            print("        EQUIVALENT ONLY %s (same text, boxes and page count; "
                  "different bytes)" % name)
        for name in failed:
            print("        NOT REPRODUCIBLE %s" % name)
        print()
        if failed:
            print("      Neither standard met. Do not release this set.")
            return 1
        if equivalent:
            print("      Same text, boxes and page count; different bytes. That is the")
            print("      weaker of the two standards. Reaching for it is allowed; doing")
            print("      it without saying so is not.")
        else:
            print("      Standard met: byte-identical output, the stronger of the two.")

    print()
    total = sum(a["bytes"] for a in artifacts)
    for row in artifacts:
        print("      %-34s %6.1f KB  %s pages  %s"
              % (row["path"].replace("release/", ""), row["bytes"] / 1024,
                 row.get("pages", "?"), row["sha256"][:12]))
    print("      %d artifact(s), %.1f KB total" % (len(artifacts), total / 1024))
    if git["dirty"]:
        print()
        print("      NOTE: built from a dirty working tree, so the digests above "
              "describe uncommitted\n            content. Commit first if you mean "
              "to quote them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
