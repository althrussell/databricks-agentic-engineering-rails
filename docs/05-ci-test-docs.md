# CI, tests and documentation

Brief on purpose. These are the gates worth enforcing on a repository where agents write
code, and no more than that.

## The shape of the gate

One command that a developer runs and CI runs identically:

```sh
make check
```

If the local command and the CI job differ, the CI job is a surprise generator. Whatever
your forge, have it run the same entry point.

This repository's own lane is a reasonable starting shape:

| Lane | What it protects |
| :--- | :--- |
| `make lint` | Shell scripts parse and pass `shellcheck` |
| `make harness-verify` | No generated configuration has been hand-edited |
| `make links` | No document points at a file that does not exist |
| `make test` | The classifier refuses what it must and allows what it must |
| `make docs` | The PDFs build from the Markdown |

Note what `make harness-verify` is doing there, because it is the gate specific to this
kind of work: it catches the case where someone edited generated output instead of the
policy. That edit is about to be silently reverted by the next person who regenerates,
and it looks like nothing in a diff.

## Tests that are worth having

**Test the boundary you actually rely on.** `harness/scripts/deny-proof.sh` is the model:
forty-six cases in a table, twenty-seven that must be refused and nineteen that must not.
Both halves matter. A guard that denies everything passes a deny-only test suite and
makes the tool unusable, so the allow cases are what keep the deny cases honest.

**Real end-to-end, not stubs.** A test that mocks the thing being tested proves that the
mock works. If a code path talks to a workspace, one test should talk to a workspace —
and if the credentials for that are not available in CI, then that test runs somewhere
else and its result is recorded, rather than being replaced by a mock that always passes.
Say which of your tests are real and which are not. A suite whose coverage is unknown is
a suite whose passing means nothing.

**Positive controls.** Every check that can silently find nothing needs a case that
proves it can find something. This is not theoretical: during the build of this pack, a
wrapped `grep` with an `-I` flag returned no output and exit 0 over a set of files that
definitely contained the string, three separate times. A scan with no positive control is
not evidence.

**Exit non-zero for "cannot check".** A checker that skips itself because a tool is
missing, and reports success, is worse than no checker. `harness/scripts/verify.sh` exits
2 when it can find no sha256 tool, and `scripts/tool-budget.py` exits 2 rather than
reporting zero bytes when it cannot connect — because zero and unknown mean opposite
things.

## Documentation that stays true

Three rules, all of which are enforced by a script here rather than by review:

1. **Every relative link resolves.** `make links` fails otherwise. A document pointing at
   a file that was deleted six weeks ago is how a reader learns not to trust the rest of
   it.
2. **Every external source is listed with a date and a status code.** `docs/SOURCES.md`,
   re-checked by `make check-live`. A URL in prose with no recorded check is a claim about
   the past tense.
3. **Say what is not proved.** Each generated `RENDER-NOTES.md` ends with a "not proved
   here" section, and it is the section to read first. A document that only lists what
   works is marketing.

Link text carries meaning too: `make links` warns on "here", "this link" and "read more",
because those point nowhere in a printed PDF or a screen reader.

## The forge question

Nothing in this pack requires a particular CI system. The gate is a shell command and a
non-zero exit, which every forge understands. That is deliberate — see
`docs/DECISIONS/0005-forge-agnostic-gate.md` — and it is also why the checks are POSIX
`sh` and Python with one optional dependency rather than something that needs a runner.

The one thing worth insisting on: **the gate runs on the pull request, not after the
merge.** An agent that can open a PR and a gate that runs post-merge is an agent that can
land a broken main branch politely.

## Review, briefly

Agent-written code needs the same review as anyone's, with one addition: read the diff
for what it *touched*, not only for what it *changed*. The characteristic agent failure is
not a wrong line, it is fourteen files edited when the task named one. `git diff --stat`
first, every time.
