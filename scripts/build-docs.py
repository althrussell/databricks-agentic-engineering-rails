#!/usr/bin/env python3
"""Build the PDF pack from Markdown, then record what was built.

Run by `make docs`. Every document listed in release-readiness.yml with
`pdf: true` is rendered through pandoc with typst as the PDF engine and
docs/theme/pack.typ as the template. The specimen page is always built, because
the pipeline needs something to prove itself against before the documents exist
and something to compare against after a theme change.

Two properties this script exists to guarantee:

*   **The artifact names its origin.** Every PDF is recorded in
    release/release-manifest.json with a full sha256, the commit it was built
    from, whether the working tree was dirty, and the pandoc and typst versions.
    A PDF with no manifest row is an untraceable binary.

*   **The build is reproducible.** Two things are needed for that, and only the
    first is obvious. typst runs with --ignore-system-fonts, so only the four
    fonts typst bundles are available and a machine's own fonts cannot change the
    output. And SOURCE_DATE_EPOCH is pinned to the commit's own timestamp, because
    typst otherwise stamps the current time into the PDF and every rebuild
    produces different bytes - which would make the sha256 in the manifest a
    record of when the build ran rather than of what it built.

    Verify it with `make docs-repro`, which builds twice and compares digests.

The manifest is validated against schemas/release-manifest.schema.json before the
build is called a success, so a malformed manifest fails here rather than in the
release workflow.
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
SPECIMEN = os.path.join(DOCS, "theme", "theme-specimen.md")
COMBINED_ID = "databricks-agentic-engineering-rails-pack"

# Paper sizes in millimetres, only the ones the theme is allowed to ask for.
PAPERS = {"a4": (210.0, 297.0), "us-letter": (215.9, 279.4)}
MM_PER_PT = 25.4 / 72.0

# How far a glyph may stick past the text edge before it counts as overflow.
#
# It cannot be zero. Justified text with hyphenation lets the hyphen hang into
# the margin, and the specimen's own worst case is 1.96pt (the word "restruc-"
# on page 1). Real overflow is not subtle: an unwrapped code line or a table too
# wide for the page runs over by tens of points. 4pt sits well clear of the
# typographic overhang and well below anything worth shipping.
OVERFLOW_TOL_PT = 4.0


class DateSafeLoader(yaml.SafeLoader):
    """Leave dates as strings; see scripts/validate-manifests.py for why."""


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
    overhangs with no glyph in it; PORTABILITY.md records that limit rather than
    letting the check imply a guarantee it cannot make.
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

    This is the declared equivalence check of §13, used only when byte-identity
    fails. Extracted text and per-word bounding boxes together pin the page
    count, the reading order, the line breaking and the position of every glyph,
    so two PDFs with the same fingerprint print and read identically. The two
    timestamp lines are dropped because they are the thing being tolerated.

    What it does not cover: the outline (bookmark) tree and embedded font
    subsets. Both are determined by the intermediate typst source, which is
    compared separately, but neither is read back out of the PDF here. That gap
    is named in PORTABILITY.md rather than papered over.
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
    ap.add_argument("--only", help="build a single document id (or 'specimen')")
    ap.add_argument("--specimen-only", action="store_true",
                    help="build only the theme specimen page")
    ap.add_argument("--no-combined", action="store_true",
                    help="skip the single combined PDF of the whole pack")
    ap.add_argument("--check-reproducible", action="store_true",
                    help="rebuild every artifact and require byte-identical output")
    args = ap.parse_args()

    require("pandoc", "Install with: brew install pandoc")
    require("typst", "Install with: brew install typst")

    readiness = yaml.load(open(os.path.join(ROOT, "release-readiness.yml"), encoding="utf-8"),
                          Loader=DateSafeLoader)
    version = readiness["pack_version"]
    status = readiness["release_status"]
    git = git_state()
    built_on = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
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

    # The specimen always builds: before Phase 3 it is the only proof the
    # pipeline works, and afterwards it is the theme's regression target.
    if not args.only or args.only == "specimen":
        targets.append((SPECIMEN, os.path.join(OUT, "theme-specimen.pdf"),
                        {"docid": "theme-specimen", "packversion": version,
                         "status": status, "commit": git["commit"][:12],
                         "date": doc_date}, False))

    if not args.specimen_only:
        for doc in readiness["documents"]:
            if not doc.get("pdf") or (args.only and args.only != doc["id"]):
                continue
            src = os.path.join(ROOT, doc["path"])
            if not os.path.exists(src):
                print("      skip  %-38s source not written yet" % doc["id"])
                continue
            targets.append((src, os.path.join(OUT, "%s.pdf" % doc["id"]),
                            {"docid": doc["id"], "packversion": version,
                             "status": status, "commit": git["commit"][:12],
                             "date": doc_date,
                             "subtitle": doc["title"]}, True))

    # The combined pack. Built as one pandoc invocation over every source rather
    # than by stitching finished PDFs together, so it gets a single continuous
    # table of contents and one bookmark tree instead of the flat concatenation
    # `pdfunite` would leave behind.
    combined_sources = [os.path.join(ROOT, d["path"]) for d in readiness["documents"]
                        if d.get("pdf") and os.path.exists(os.path.join(ROOT, d["path"]))]
    if (not args.only and not args.specimen_only and not args.no_combined
            and len(combined_sources) > 1):
        targets.append((combined_sources, os.path.join(OUT, "%s.pdf" % COMBINED_ID),
                        {"docid": COMBINED_ID, "packversion": version,
                         "status": status, "commit": git["commit"][:12],
                         "date": doc_date,
                         "subtitle": "The complete pack, %d documents"
                                     % len(combined_sources)}, True))
    elif len(combined_sources) <= 1 and not args.only and not args.specimen_only:
        print("      skip  %-38s needs 2+ documents, %d written"
              % (COMBINED_ID, len(combined_sources)))

    if not targets:
        sys.exit("nothing to build: no source documents exist and the specimen was excluded")

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

    manifest = {
        "schema_version": 1,
        "pack_version": version,
        "built_on": built_on.isoformat().replace("+00:00", "Z"),
        "git": git,
        "toolchain": {"pandoc": pandoc_v, "typst": typst_v,
                      "os": "%s-%s" % (sys.platform, os.uname().machine),
                      "source_date_epoch": epoch,
                      "source_date_epoch_from": epoch_from},
        "artifacts": artifacts,
    }
    mpath = os.path.join(OUT, "release-manifest.json")
    with open(mpath, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")

    # Validate what we just wrote. A build that emits an invalid manifest has
    # produced untraceable artifacts, which is a failed build.
    try:
        import jsonschema
        schema = json.load(open(os.path.join(ROOT, "schemas", "release-manifest.schema.json"),
                                encoding="utf-8"))
        jsonschema.Draft202012Validator(schema).validate(manifest)
        print("      manifest valid against schemas/release-manifest.schema.json")
    except ImportError:
        print("      WARN: jsonschema not installed, manifest not validated here "
              "(`make check` will validate it)")
    except Exception as exc:  # noqa: BLE001 - report and fail, whatever the cause
        sys.exit("release manifest is invalid: %s" % exc)

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
            print("      Standard met: declared equivalence, not byte-identity.")
            print("      Record the renderer limitation in claims-ledger.json and "
                  "name it in PORTABILITY.md")
            print("      before releasing, per §13. Reaching for the weaker standard "
                  "is allowed; doing it silently is not.")
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
        print("      NOTE: built from a dirty working tree. The manifest records this. "
              "A release build must be from a clean tree or its checksums mean nothing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
