# Schemas

Every committed JSON Schema in this pack lives here and nowhere else. Each one
declares the file it governs in its own `validates` key, and each one is executed
by `scripts/validate-manifests.py`, which runs in `make check` and in the PR lane.

A schema that sits in a repository without a check that runs it is worse than no
schema, because it looks like a control. `validate-manifests.py` therefore fails
when it finds a schema whose target file is absent and for which no fixture
exists — the schema is reported as *present but unenforced* rather than skipped.

## What each schema governs

| Schema | Validates | Run by | Also cross-checked against |
|---|---|---|---|
| `sources.schema.json` | `sources.yml` | `make check` | Document ids must exist in `release-readiness.yml` |
| `claims-ledger.schema.json` | `claims-ledger.json` | `make check` | `used_in` ids resolve to real documents; totals match the rows; re-verification dates |
| `release-readiness.schema.json` | `release-readiness.yml` | `make check` | A `passed` row must name the current HEAD; `RELEASE-READY` requires every test passed |
| `repo-manifest.schema.json` | `repo-manifest.yml` | `make check` | Required paths exist on disk and clear `min_bytes`; forbidden patterns are scanned |
| `quality-attributes.schema.json` | `quality-attributes.yml` | `make check` | Journey targets resolve to attributes; exceptions are not past expiry |
| `template-version.schema.json` | `template-version.yml` | `make check` | Verified tool versions agree with the `local-toolchain` claim |
| `release-manifest.schema.json` | `release/release-manifest.json` | `make check`, `make docs` | Validated against `fixtures/valid/` on a clean clone, and against the real file once a build has run |

## Why the rules are shaped this way

Most of these schemas spend their length on one idea: make the dishonest version
of a file unrepresentable, rather than relying on a reviewer to notice it.

- `evidence` in the claims ledger has a **minimum length**. A claim whose
  evidence is "yes" is a memory, not a citation.
- `used_in` has **minItems 1**. A claim no document uses is either dead research
  or a document that lost its citation, and both are worth surfacing.
- A `passed` success test **requires** its evidence and a full 40-character SHA.
  Without both, "passed" is an opinion; with a short SHA, it is ambiguous across
  the repository's lifetime.
- A `humans`-closed success test **requires** a named validation protocol, so a
  test that only a person can close cannot be quietly closed by a build.
- A measurement in `quality-attributes.yml` **requires** its environment and
  revision, because a number from a laptop is not production evidence.
- An exception **requires** `expires_on`. A date is the only thing that makes an
  exception temporary.
- `min_bytes` in the repo manifest exists because the cheapest way to satisfy a
  path check is an empty file.

## Fixtures

`fixtures/valid/` holds one minimal valid instance per schema whose real target
is produced by a build rather than committed. That is what keeps
`release-manifest.schema.json` under test on a fresh clone instead of first being
exercised on release day.

`fixtures/invalid/` holds instances that **must** be rejected, with
`expectations.json` recording the rule each one tests and a `must_mention` string.
The self-test requires each fixture to be rejected *and* for the error to mention
that string, so a fixture cannot start failing for an unrelated reason — a typo, a
renamed key — and silently stop testing its rule.

## Proving the checks can fail

```bash
python3 scripts/validate-manifests.py --self-test
```

This plants a defect for each failure mode the acceptance criteria name — an
orphaned factual claim, a missing required path, a stub file, disagreeing totals,
a `RELEASE-READY` declaration over a not-run test, a dangling journey target, an
expired claim — and requires every one to be caught. A validator nobody has
watched fail is not evidence of anything.

Note the deliberate asymmetry in one case: an expired claim is a **warning** in
the default lane and a **failure** under `--strict-expiry`, which the scheduled
re-verification job uses. A fork should not break because a date passed, but the
maintainers should hear about it.

## Adding a schema

1. Put it here, named `<target>.schema.json`.
2. Give it a `validates` key naming the file it governs, and a `description`
   that says which check runs it.
3. Add the target to `repo-manifest.yml` if it is a promised path.
4. If the target is built rather than committed, add a minimal instance to
   `fixtures/valid/`.
5. Run `make check` and confirm the new schema appears in the pass list, then
   break the target on purpose once and confirm it appears in the fail list.

Step 5 is not optional. It is the only step that proves the other four did
anything.
