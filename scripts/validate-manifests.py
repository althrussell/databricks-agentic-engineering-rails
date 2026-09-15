#!/usr/bin/env python3
"""Validate every committed manifest against its schema, and every claim against
the rest of the repository.

Run by `make check`. Three jobs, in order of how often they catch something:

1.  **Schema validation.** Each file in schemas/ declares the path it validates.
    Every schema must be executed by this script; a schema that validates nothing
    is reported as a failure, because an unenforced schema is worse than none - it
    looks like a control.

2.  **Cross-reference checks.** Schemas can enforce that a claim names a
    document; only this script can check that the document exists. The same goes
    for journey targets, required paths, expiring exceptions, and a `passed`
    release row whose revision is no longer HEAD.

3.  **Forbidden patterns.** A workspace identifier or token-shaped string in a
    committed file is a leak that no amount of review reliably catches.

Exit status is 1 if any check FAILs. WARNs do not fail the build; each one says
which command would turn it into a real result, because a warning that cannot be
resolved is noise.

Modes:
    --self-test       Prove the checks fail on planted defects, then exit. This is
                      what stops the validator from being a script that always
                      passes.
    --strict-expiry   Treat an expired claim as a failure rather than a warning.
                      Used by the scheduled re-verification job, not by the PR
                      lane: a fork should not break because a date passed.
"""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import fnmatch
import json
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    sys.exit("missing dependency: pyyaml. Run `make deps` (or `pip install pyyaml jsonschema`).")
try:
    import jsonschema
except ImportError:
    sys.exit("missing dependency: jsonschema. Run `make deps` (or `pip install pyyaml jsonschema`).")


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TODAY = dt.date.today()


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

class DateSafeLoader(yaml.SafeLoader):
    """A loader that leaves dates as strings.

    PyYAML resolves an unquoted 2026-09-15 into a date object, so the same file
    validates or fails depending on whether someone remembered a quote. Removing
    the timestamp resolver makes the result depend on the content instead of on
    the typist.
    """


DateSafeLoader.yaml_implicit_resolvers = {
    ch: [(tag, regexp) for tag, regexp in resolvers if tag != "tag:yaml.org,2002:timestamp"]
    for ch, resolvers in yaml.SafeLoader.yaml_implicit_resolvers.items()
}


def load(path: str):
    with open(path, encoding="utf-8") as fh:
        if path.endswith((".yml", ".yaml")):
            return yaml.load(fh, Loader=DateSafeLoader)
        return json.load(fh)


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

class Report:
    def __init__(self) -> None:
        self.rows: list[tuple[str, str, str]] = []

    def ok(self, where: str, msg: str) -> None:
        self.rows.append(("PASS", where, msg))

    def warn(self, where: str, msg: str) -> None:
        self.rows.append(("WARN", where, msg))

    def fail(self, where: str, msg: str) -> None:
        self.rows.append(("FAIL", where, msg))

    @property
    def failures(self) -> int:
        return sum(1 for level, _, _ in self.rows if level == "FAIL")

    @property
    def warnings(self) -> int:
        return sum(1 for level, _, _ in self.rows if level == "WARN")

    def render(self) -> None:
        for level, where, msg in self.rows:
            if level == "PASS":
                print("  pass  %-34s %s" % (where, msg))
        for level, where, msg in self.rows:
            if level == "WARN":
                print("  WARN  %-34s %s" % (where, msg))
        for level, where, msg in self.rows:
            if level == "FAIL":
                print("  FAIL  %-34s %s" % (where, msg))
        print()
        print("  %d checks, %d failed, %d warned"
              % (len(self.rows), self.failures, self.warnings))


# ---------------------------------------------------------------------------
# 1. Schema validation
# ---------------------------------------------------------------------------

def schema_files() -> list[str]:
    d = os.path.join(ROOT, "schemas")
    return sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".schema.json"))


def validate_against(schema: dict, data, where: str, rpt: Report, label: str) -> bool:
    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(data), key=lambda e: list(e.path))
    if not errors:
        rpt.ok(where, "%s valid" % label)
        return True
    for err in errors[:6]:
        loc = "/".join(str(p) for p in err.absolute_path) or "(root)"
        rpt.fail(where, "%s: %s -> %s" % (label, loc, err.message))
    if len(errors) > 6:
        rpt.fail(where, "%s: %d further schema errors" % (label, len(errors) - 6))
    return False


def check_schemas(rpt: Report) -> dict:
    """Validate each schema's declared target. Returns the loaded documents."""
    loaded: dict[str, object] = {}
    for spath in schema_files():
        sname = os.path.basename(spath)
        schema = load(spath)

        # A schema must say what it validates, or nothing can enforce it.
        target = schema.get("validates")
        if not target:
            rpt.fail(sname, "no `validates` key: nothing can tell which file this schema governs")
            continue

        # The schema itself must be a legal schema. A typo in a schema silently
        # accepts everything, which is the most expensive way to pass a check.
        try:
            jsonschema.Draft202012Validator.check_schema(schema)
        except jsonschema.exceptions.SchemaError as exc:
            rpt.fail(sname, "not a valid Draft 2020-12 schema: %s" % exc.message)
            continue

        tpath = os.path.join(ROOT, target)
        if os.path.exists(tpath):
            data = load(tpath)
            loaded[target] = data
            validate_against(schema, data, sname, rpt, target)
        else:
            # Not built yet: the fixture is what keeps the schema exercised.
            fixture = os.path.join(ROOT, "schemas", "fixtures", "valid",
                                   os.path.basename(target))
            if os.path.exists(fixture):
                validate_against(schema, load(fixture), sname, rpt,
                                 "fixture for %s (target not built yet)" % target)
            else:
                rpt.fail(sname, "target %s absent and no fixture in schemas/fixtures/valid/: "
                                "schema is present but unenforced" % target)
    return loaded


# ---------------------------------------------------------------------------
# 2. Cross-reference checks
# ---------------------------------------------------------------------------

def check_document_references(readiness: dict, sources: dict, claims: dict, rpt: Report) -> None:
    """Every `supports` and `used_in` id must name a real document."""
    known = {d["id"] for d in readiness["documents"]}

    orphans = []
    for claim in claims["claims"]:
        for doc in claim["used_in"]:
            if doc not in known:
                orphans.append((claim["id"], doc))
    if orphans:
        for cid, doc in orphans[:8]:
            rpt.fail("claims-ledger.json",
                     "claim %s cites document '%s', which is not in release-readiness.yml" % (cid, doc))
    else:
        rpt.ok("claims-ledger.json", "all %d claims resolve to known documents" % len(claims["claims"]))

    bad_sources = []
    for page in sources["pages"] + sources.get("repositories", []):
        for doc in page.get("supports", []):
            if doc not in known:
                bad_sources.append((page["url"], doc))
    if bad_sources:
        for url, doc in bad_sources[:8]:
            rpt.fail("sources.yml", "%s supports unknown document '%s'" % (url, doc))
    else:
        rpt.ok("sources.yml", "every source maps to a known document")


def check_claim_totals(claims: dict, rpt: Report) -> None:
    """A totals block that disagrees with the rows means the file was hand-edited
    after generation, and the next reader cannot tell which half to trust."""
    rows = claims["claims"]
    if claims["totals"]["claims"] != len(rows):
        rpt.fail("claims-ledger.json", "totals.claims says %d, file holds %d"
                 % (claims["totals"]["claims"], len(rows)))
        return
    by_status: dict[str, int] = {}
    for row in rows:
        by_status[row["status"]] = by_status.get(row["status"], 0) + 1
    if by_status != claims["totals"]["by_status"]:
        rpt.fail("claims-ledger.json", "totals.by_status %s disagrees with rows %s"
                 % (claims["totals"]["by_status"], by_status))
    else:
        rpt.ok("claims-ledger.json", "totals agree with rows")


def check_claim_expiry(claims: dict, rpt: Report, strict: bool) -> None:
    stale = []
    for row in claims["claims"]:
        verified = dt.date.fromisoformat(row["verified_on"])
        due = verified + dt.timedelta(days=row["reverify_interval_days"])
        if TODAY > due and row["status"] != "expired":
            stale.append((row["id"], due.isoformat()))
    if not stale:
        rpt.ok("claims-ledger.json", "no claim is past its re-verification date")
        return
    msg = "%d claim(s) past due, earliest %s: %s" % (
        len(stale), min(d for _, d in stale), ", ".join(i for i, _ in stale[:6]))
    if strict:
        rpt.fail("claims-ledger.json", msg + " - re-verify or mark expired")
    else:
        rpt.warn("claims-ledger.json", msg + " - run `make reverify` (fails under --strict-expiry)")


def git_head() -> str | None:
    try:
        out = subprocess.run(["git", "-C", ROOT, "rev-parse", "HEAD"],
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def check_release_rows(readiness: dict, rpt: Report) -> None:
    head = git_head()
    passed = [t for t in readiness["success_tests"] if t["result"] == "passed"]

    for test in passed:
        if head is None:
            rpt.warn("release-readiness.yml",
                     "%s is passed but HEAD is unknown (no git repository here), so the "
                     "revision cannot be checked" % test["id"])
        elif test["revision_tested"] != head:
            rpt.fail("release-readiness.yml",
                     "%s is passed against %s but HEAD is %s - re-run it or set the result "
                     "to expired" % (test["id"], test["revision_tested"][:12], head[:12]))
    if passed and head is not None:
        current = [t for t in passed if t["revision_tested"] == head]
        if len(current) == len(passed):
            rpt.ok("release-readiness.yml", "all %d passed row(s) are against HEAD" % len(passed))

    # RELEASE-READY is a claim about every row, so check it rather than trust it.
    if readiness["release_status"] == "RELEASE-READY":
        unmet = [t["id"] for t in readiness["success_tests"] if t["result"] != "passed"]
        if unmet:
            rpt.fail("release-readiness.yml",
                     "release_status is RELEASE-READY but %s did not pass" % ", ".join(unmet))
        else:
            rpt.ok("release-readiness.yml", "RELEASE-READY and every success test passed")
    else:
        counts: dict[str, int] = {}
        for test in readiness["success_tests"]:
            counts[test["result"]] = counts.get(test["result"], 0) + 1
        rpt.ok("release-readiness.yml", "%s: %s" % (readiness["release_status"], counts))

    # A human-closed test needs a protocol that exists on disk, not just a path.
    for test in readiness["success_tests"]:
        proto = test.get("human_validation")
        if test["closed_by"] == "humans" and proto:
            if not os.path.exists(os.path.join(ROOT, proto)):
                rpt.warn("release-readiness.yml",
                         "%s names %s, which does not exist yet (created in Phase 5)"
                         % (test["id"], proto))

    # Documents listed as complete must actually be there.
    for doc in readiness["documents"]:
        if doc["status"] == "complete" and "path" in doc:
            if not os.path.exists(os.path.join(ROOT, doc["path"])):
                rpt.fail("release-readiness.yml",
                         "document %s is marked complete but %s is missing"
                         % (doc["id"], doc["path"]))


def check_required_paths(manifest: dict, rpt: Report) -> None:
    phase = manifest["current_phase"]
    missing, thin, pending = [], [], 0

    for entry in manifest["required_paths"]:
        if entry.get("phase", 0) > phase:
            pending += 1
            continue
        path = os.path.join(ROOT, entry["path"])
        if not os.path.exists(path):
            missing.append(entry["path"])
            continue
        floor = entry.get("min_bytes")
        if floor and os.path.isfile(path) and os.path.getsize(path) < floor:
            thin.append("%s (%d < %d bytes)" % (entry["path"], os.path.getsize(path), floor))

    for path in missing:
        rpt.fail("repo-manifest.yml", "required path missing: %s" % path)
    for entry in thin:
        rpt.fail("repo-manifest.yml", "required path is a stub: %s" % entry)
    if not missing and not thin:
        rpt.ok("repo-manifest.yml",
               "every required path for phase %d is present; %d pending in later phases"
               % (phase, pending))

    for exc in manifest.get("exceptions", []):
        expires = exc.get("expires_on")
        if expires and dt.date.fromisoformat(expires) < TODAY:
            rpt.fail("repo-manifest.yml",
                     "exception for %s expired on %s" % (exc["path"], expires))


def check_quality_attributes(qa: dict, rpt: Report) -> None:
    ids = {a["id"] for a in qa["attributes"]}
    dangling = [(j["id"], t) for j in qa["critical_journeys"] for t in j["targets"] if t not in ids]
    for jid, target in dangling:
        rpt.fail("quality-attributes.yml", "journey %s targets unknown attribute %s" % (jid, target))
    if not dangling:
        rpt.ok("quality-attributes.yml",
               "%d journeys resolve to %d attributes" % (len(qa["critical_journeys"]), len(ids)))

    covered = {t for j in qa["critical_journeys"] for t in j["targets"]}
    unused = sorted(ids - covered)
    if unused:
        rpt.warn("quality-attributes.yml",
                 "attribute(s) no critical journey references: %s - either a journey is "
                 "missing or the attribute is not critical" % ", ".join(unused))

    for exc in qa.get("exceptions", []):
        if dt.date.fromisoformat(exc["expires_on"]) < TODAY:
            rpt.fail("quality-attributes.yml",
                     "exception %s against %s expired on %s"
                     % (exc["id"], exc["applies_to"], exc["expires_on"]))


def check_toolchain_agreement(tv: dict, claims: dict, rpt: Report) -> None:
    """template-version.yml and the claims ledger both record tool versions. If
    they drift, one of them is lying and a reader cannot tell which."""
    row = next((c for c in claims["claims"] if c["id"] == "local-toolchain"), None)
    if row is None:
        rpt.warn("template-version.yml", "no local-toolchain claim to cross-check against")
        return
    evidence = row["evidence"]
    mismatched = []
    for key, val in tv["verified_against"].items():
        if val["status"] != "verified" or key == "os":
            continue
        version = val["version"]
        if version not in evidence:
            mismatched.append("%s %s" % (key, version))
    if mismatched:
        rpt.warn("template-version.yml",
                 "version(s) not found in the local-toolchain claim evidence: %s"
                 % ", ".join(mismatched))
    else:
        rpt.ok("template-version.yml", "verified tool versions agree with the claims ledger")


# ---------------------------------------------------------------------------
# 3. Forbidden patterns
# ---------------------------------------------------------------------------

SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", "release",
             ".pytest_cache", "dist", "build", ".mypy_cache", ".ruff_cache"}
TEXT_EXT = {".md", ".yml", ".yaml", ".json", ".py", ".sh", ".ts", ".tsx", ".js",
            ".jsx", ".sql", ".tf", ".toml", ".cfg", ".txt", ".typ", ".html", ".css", ""}


def tracked_text_files() -> list[str]:
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            ext = os.path.splitext(name)[1].lower()
            if ext in TEXT_EXT:
                files.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    return sorted(files)


def check_forbidden(manifest: dict, rpt: Report) -> None:
    patterns = manifest.get("forbidden_patterns", [])
    if not patterns:
        return
    files = tracked_text_files()
    hits = []
    for spec in patterns:
        rx = re.compile(spec["pattern"])
        allow = spec.get("allow_in", [])
        for rel in files:
            if any(fnmatch.fnmatch(rel, glob) for glob in allow):
                continue
            try:
                with open(os.path.join(ROOT, rel), encoding="utf-8", errors="ignore") as fh:
                    for lineno, line in enumerate(fh, 1):
                        if rx.search(line):
                            hits.append((spec["pattern"], rel, lineno))
                            break
            except OSError:
                continue
    for pattern, rel, lineno in hits[:12]:
        rpt.fail("forbidden-patterns", "/%s/ found at %s:%d" % (pattern, rel, lineno))
    if not hits:
        rpt.ok("forbidden-patterns",
               "%d pattern(s) checked across %d files, no match" % (len(patterns), len(files)))


# ---------------------------------------------------------------------------
# Self-test: prove the checks can fail
# ---------------------------------------------------------------------------

def self_test() -> int:
    """Plant defects and require each one to be caught.

    A validator nobody has watched fail is not evidence of anything. Each case
    below is one of the failure modes the acceptance criteria name explicitly.
    """
    print("self-test: planting defects and requiring each to be caught")
    cases = []

    readiness = load(os.path.join(ROOT, "release-readiness.yml"))
    claims = load(os.path.join(ROOT, "claims-ledger.json"))
    sources = load(os.path.join(ROOT, "sources.yml"))
    manifest = load(os.path.join(ROOT, "repo-manifest.yml"))
    qa = load(os.path.join(ROOT, "quality-attributes.yml"))

    # (1) an orphaned factual claim
    bad = copy.deepcopy(claims)
    bad["claims"][0]["used_in"] = ["99-document-that-does-not-exist"]
    rpt = Report()
    check_document_references(readiness, sources, bad, rpt)
    cases.append(("orphaned claim citation", rpt.failures > 0))

    # (2) a missing required path
    bad = copy.deepcopy(manifest)
    bad["required_paths"].append(
        {"path": "definitely-not-here.md", "why": "planted by the self-test", "phase": 0})
    rpt = Report()
    check_required_paths(bad, rpt)
    cases.append(("missing required path", rpt.failures > 0))

    # (3) a required path that exists but is empty
    stub = os.path.join(ROOT, ".selftest-stub.md")
    with open(stub, "w", encoding="utf-8") as fh:
        fh.write("x\n")
    try:
        bad = copy.deepcopy(manifest)
        bad["required_paths"].append(
            {"path": ".selftest-stub.md", "why": "planted by the self-test",
             "phase": 0, "min_bytes": 500})
        rpt = Report()
        check_required_paths(bad, rpt)
        cases.append(("stub file below min_bytes", rpt.failures > 0))
    finally:
        os.remove(stub)

    # (4) totals that disagree with the rows
    bad = copy.deepcopy(claims)
    bad["totals"]["claims"] = 999
    rpt = Report()
    check_claim_totals(bad, rpt)
    cases.append(("claim totals disagree with rows", rpt.failures > 0))

    # (5) RELEASE-READY declared while a test has not run
    bad = copy.deepcopy(readiness)
    bad["release_status"] = "RELEASE-READY"
    rpt = Report()
    check_release_rows(bad, rpt)
    cases.append(("RELEASE-READY with a not-run test", rpt.failures > 0))

    # (6) a journey pointing at a target that does not exist
    bad = copy.deepcopy(qa)
    bad["critical_journeys"][0]["targets"] = ["qa-invented"]
    rpt = Report()
    check_quality_attributes(bad, rpt)
    cases.append(("journey targets unknown attribute", rpt.failures > 0))

    # (7) an expired claim under strict mode
    bad = copy.deepcopy(claims)
    bad["claims"][0]["verified_on"] = "2000-01-01"
    rpt = Report()
    check_claim_expiry(bad, rpt, strict=True)
    cases.append(("expired claim under --strict-expiry", rpt.failures > 0))

    # (8) the same claim must only warn in the default lane
    rpt = Report()
    check_claim_expiry(bad, rpt, strict=False)
    cases.append(("expired claim warns without --strict-expiry",
                  rpt.failures == 0 and rpt.warnings > 0))

    # (9) a schema-invalid document is rejected
    schema = load(os.path.join(ROOT, "schemas", "claims-ledger.schema.json"))
    bad = copy.deepcopy(claims)
    bad["claims"][0]["evidence"] = "yes"
    rpt = Report()
    validate_against(schema, bad, "self-test", rpt, "planted one-word evidence")
    cases.append(("one-word evidence rejected by schema", rpt.failures > 0))

    # (10) a claim used by no document at all
    bad = copy.deepcopy(claims)
    bad["claims"][0]["used_in"] = []
    rpt = Report()
    validate_against(schema, bad, "self-test", rpt, "planted claim with empty used_in")
    cases.append(("claim used by nothing rejected by schema", rpt.failures > 0))

    # (11) every committed invalid fixture must be rejected, and rejected for the
    # reason it was written for. A fixture that fails for an unrelated reason has
    # stopped testing its rule without anyone noticing.
    inv = os.path.join(ROOT, "schemas", "fixtures", "invalid")
    expectations = os.path.join(inv, "expectations.json")
    if os.path.isdir(inv):
        declared = {}
        if os.path.exists(expectations):
            for spec in load(expectations)["fixtures"]:
                declared[spec["file"]] = spec

        present = {n for n in os.listdir(inv) if n.endswith(".invalid.json")}
        undeclared = sorted(present - set(declared))
        for name in undeclared:
            cases.append(("invalid fixture %s is not in expectations.json" % name, False))
        orphaned = sorted(set(declared) - present)
        for name in orphaned:
            cases.append(("expectations.json names missing fixture %s" % name, False))

        for name in sorted(present & set(declared)):
            spec = declared[name]
            spath = os.path.join(ROOT, "schemas", spec["schema"])
            if not os.path.exists(spath):
                cases.append(("fixture %s names missing schema %s" % (name, spec["schema"]), False))
                continue
            rpt = Report()
            validate_against(load(spath), load(os.path.join(inv, name)), "self-test", rpt, name)
            rejected = rpt.failures > 0
            wanted = spec["must_mention"].lower()
            on_point = any(wanted in msg.lower() for _, _, msg in rpt.rows)
            cases.append(("invalid fixture rejected on its own rule (%s): %s"
                          % (spec["must_mention"], name), rejected and on_point))

    width = max(len(name) for name, _ in cases)
    bad_cases = 0
    for name, caught in cases:
        print("  %-*s  %s" % (width, name, "caught" if caught else "NOT CAUGHT"))
        if not caught:
            bad_cases += 1
    print()
    if bad_cases:
        print("self-test FAILED: %d of %d planted defects went undetected"
              % (bad_cases, len(cases)))
        return 1
    print("self-test passed: %d planted defects, all caught" % len(cases))
    return 0


# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--self-test", action="store_true",
                    help="prove the checks fail on planted defects, then exit")
    ap.add_argument("--strict-expiry", action="store_true",
                    help="treat an expired claim as a failure (scheduled re-verification)")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    print("validate-manifests: %s" % ROOT)
    rpt = Report()
    loaded = check_schemas(rpt)

    readiness = loaded.get("release-readiness.yml")
    claims = loaded.get("claims-ledger.json")
    sources = loaded.get("sources.yml")
    manifest = loaded.get("repo-manifest.yml")
    qa = loaded.get("quality-attributes.yml")
    tv = loaded.get("template-version.yml")

    if readiness and claims and sources:
        check_document_references(readiness, sources, claims, rpt)
    if claims:
        check_claim_totals(claims, rpt)
        check_claim_expiry(claims, rpt, args.strict_expiry)
    if readiness:
        check_release_rows(readiness, rpt)
    if manifest:
        check_required_paths(manifest, rpt)
        check_forbidden(manifest, rpt)
    if qa:
        check_quality_attributes(qa, rpt)
    if tv and claims:
        check_toolchain_agreement(tv, claims, rpt)

    rpt.render()
    return 1 if rpt.failures else 0


if __name__ == "__main__":
    sys.exit(main())
