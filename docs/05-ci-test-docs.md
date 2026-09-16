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
| `make config` | Every harness config a reader copies is valid JSON or TOML |
| `make links` | No document points at a file that does not exist |
| `make links-live` | Every external URL still answers. Separate, because it can fail for reasons that have nothing to do with your change |

Note what `make config` is doing there, because it is the lane that exists for a reason
specific to this repository. The harness configs are maintained by hand, so a trailing
comma in a `settings.json` is now a way for this pack to ship something broken. The check
costs four lines and answers for that risk directly. **Add the gate that answers for the
risk you actually took**, not the gate that is conventional.

Keep the network out of the main lane. A check that can fail because someone else's web
server is down does not belong in the lane that blocks a pull request, or people learn to
re-run it until it passes — which is the habit that makes every other lane worthless
too.

## Tests that are worth having

**Test the boundary you actually rely on, in both directions.** If you write a rule that
refuses dangerous commands, test both the commands that must be refused *and* the
ordinary commands of a working day that must not be. A rule that denies everything passes
a deny-only suite and makes the tool unusable, so the allow cases are what keep the deny
cases honest. This applies to any classifier, not just a permission rule: a checker with
only positive cases and a checker with only negative cases are both untested.

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
missing, and reports success, is worse than no checker — it converts an unknown into a
green tick. Two live examples here: `make config` exits 2 when `python3` is absent rather
than reporting that the configs are fine, and `scripts/link-check.sh` exits 2 when the
Pages exclusion list contains an entry it cannot interpret. Zero and unknown mean
opposite things and must not print the same way.

## Documentation that stays true

Three rules, all of which are enforced by a script here rather than by review:

1. **Every relative link resolves.** `make links` fails otherwise. A document pointing at
   a file that was deleted six weeks ago is how a reader learns not to trust the rest of
   it.
2. **Every external source is listed with a date and a status code.**
   [`SOURCES.md`](SOURCES.md), re-checked by `make links-live`. A URL in prose with no
   recorded check is a claim about the past tense.
3. **Say what is not proved.** Every `SETUP.md` here ends with a "what this harness
   cannot express" section, and [`03-gateway-auth.md`](03-gateway-auth.md) ends with
   "what is not proved". Those are the sections to read first. A document that only lists
   what works is marketing.

Link text carries meaning too: `make links` warns on "here", "this link" and "read more",
because those point nowhere in a printed PDF or a screen reader.

## The forge question

Nothing in this pack requires a particular CI system. The gate is a shell command and a
non-zero exit, which every forge understands. That is deliberate — see
[`DECISIONS/0005`](DECISIONS/0005-the-gate-is-a-command.md) — and it is also why the
checks are POSIX `sh` rather than something that needs a runner. This repository ships no
workflow file at all, not even a disabled one, because an inert workflow file gets read
as coverage.

The one thing worth insisting on: **the gate runs on the pull request, not after the
merge.** An agent that can open a PR and a gate that runs post-merge is an agent that can
land a broken main branch politely.

## Review, briefly

Agent-written code needs the same review as anyone's, with one addition: read the diff
for what it *touched*, not only for what it *changed*. The characteristic agent failure is
not a wrong line, it is fourteen files edited when the task named one. `git diff --stat`
first, every time.
