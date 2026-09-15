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

try:
    import yaml
except ImportError:
    sys.exit("missing dependency: pyyaml. Run `make deps`.")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
THEME = os.path.join(DOCS, "theme", "pack.typ")
OUT = os.path.join(ROOT, "release")
SPECIMEN = os.path.join(DOCS, "theme", "theme-specimen.md")


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


def build_one(src: str, dest: str, meta: dict, toc: bool, epoch: int) -> None:
    cmd = [
        "pandoc", src,
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
        sys.exit("pandoc failed for %s" % os.path.relpath(src, ROOT))
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

    if not targets:
        sys.exit("nothing to build: no source documents exist and the specimen was excluded")

    artifacts = []
    for src, dest, meta, toc in targets:
        print("      build %-38s -> %s" % (os.path.relpath(src, ROOT),
                                           os.path.relpath(dest, ROOT)))
        build_one(src, dest, meta, toc, epoch)
        row = {
            "path": os.path.relpath(dest, ROOT),
            "sha256": sha256(dest),
            "bytes": os.path.getsize(dest),
            "source": os.path.relpath(src, ROOT),
        }
        pages = page_count(dest)
        if pages:
            row["pages"] = pages
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
