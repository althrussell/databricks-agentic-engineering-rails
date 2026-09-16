# 0004 — The doctor and the link checker carry no interpreter

**Status:** accepted
**Date:** 2026-09-15

## Context

`make check` and `make doctor` are the two commands a new reader runs first, and
the two a stuck reader runs when something is wrong. Both therefore have to work
in the least hospitable environment the pack asks anyone to use: a laptop that has
just been set up, and whatever CI image a team already has.

`harness/scripts/render.py` and `scripts/build-docs.py` are Python and need to be —
they parse YAML, emit JSON and drive pandoc. Writing the doctor and the link
checker in Python too looked like consistency.

The problem is what happens when the interpreter is the fault. A doctor written
in Python cannot report a broken or absent Python, and that is the single most
common environment failure it exists to diagnose. It fails with a traceback, or
with `command not found`, at the exact moment the reader most needs a legible
answer.

## Decision

`scripts/doctor.sh` and `scripts/link-check.sh` are POSIX `sh`, using only `awk`,
`sed` and `tr`. No Python, no Node, no `jq`, no Bash-only syntax. Both are checked
with `sh -n` in `make check`.

They still read from the same source of truth as everything else:
`doctor.sh` parses the expected versions out of `template-version.yml` with `awk`
rather than hard-coding them, so a version bump is one edit, not two.

`doctor.sh` never prints `DATABRICKS_HOST` — only whether it is set. Its output is
designed to be pasted into a ticket or a chat message, and a workspace URL is an
environment identifier.

## Consequences

- Two languages in `scripts/`, with a rule for which is which: anything that has
  to run when the environment is broken is `sh`; anything that parses YAML or
  emits JSON is Python. The rule is stated here so the next script does not get its language
  chosen by coin flip.
- `link-check.sh` resolves relative paths and heading anchors with `sed` and
  `awk`, including collapsing `docs/../harness/README.md` to `harness/README.md`
  so an error names a path a reader can act on. This is more code than the Python
  equivalent, and it is the cost being accepted deliberately.
- Both scripts count their own verdicts from captured output, because every check
  runs inside a pipeline subshell and a variable incremented there does not
  survive. This is a `sh` idiom that reads oddly and is commented at the site.

## Rejected alternatives

**Write both in Python for consistency.** Rejected for the reason above: the
diagnostic tool cannot share a dependency with the thing most likely to be
broken.

**Write both in Bash and use arrays.** Rejected because the boundary image and
several common CI images ship `dash` or `busybox ash` as `/bin/sh`, and a
Bash-only construct fails there in ways that look like a logic bug rather than a
portability one.

**Use `jq` for the JSON the doctor reports in `--json` mode.** Rejected because
`jq` is exactly the kind of dependency a minimal image lacks, and the doctor's
job is to work in a minimal image. The JSON it emits is assembled by hand and is
simple enough to be correct by inspection.

## Revisit when

Either script grows past roughly 300 lines or needs to parse anything with
nesting. At that point the `sh` implementation stops being simpler than the
alternative, and the honest move is to split the manifest-parsing part into
Python and leave a thin `sh` shim that still works when Python does not.
