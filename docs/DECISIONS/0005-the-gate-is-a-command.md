# 0005 — The gate is a command, not a workflow file

**Status:** accepted
**Date:** 2026-09-16

## Context

A pack about production standards has to say how the standards get enforced, and
the obvious answer is a `.github/workflows/*.yml` with a required status check.

Two things argue against making that the gate here.

The first is the destination. **The repository location this pack is delivered
into does not run GitHub Actions**, and its documentation site is a plain branch
build from `main` and `/docs` for that reason. That constraint is not unusual:
GitHub Enterprise Server with Actions disabled, GitLab, Azure DevOps, Bitbucket,
a mirrored read-only remote, and an internal forge with its own runner are all
common. A team that cannot run the gate is a team that reads the standard and
adopts none of it.

The second would have justified the decision anyway. A pack whose enforcement
lives in a workflow file teaches its readers that CI is a GitHub feature. The
lesson it should teach is that the gate is a command, and CI is whatever happens
to invoke it.

## Decision

**`make check` is the gate.** It parses every shell script, validates every JSON and
TOML config, and checks every link in the documentation — internal, external, and the
one structural case where a wrapped markdown link silently serves raw markdown. It
exits non-zero on the first failure. It needs no network for the parts that matter, no
credentials and no workspace, so it runs identically on a laptop and in whatever runner
a team already has. Every check in it is a script in `scripts/` that can also be run
alone.

The gate is deliberately small, and it got smaller. It used to also verify that five
generated harness directories matched their source policy and that an MCP tool budget
was within a ceiling. Both checks were sound; both existed only because this repository
was maintaining machinery that it no longer has. A gate that checks generated files is
a cost of generating files, not a benefit of having a gate. See
[0006](0006-guidance-over-machinery.md).

This repository ships **no workflow file at all**. Not a disabled one, not an
example one. `docs/05-ci-test-docs.md` states what the reader's own CI should
invoke — one line, `make check` — and leaves the file that invokes it to the
reader's forge, because that file is three lines they can write and cannot be
wrong about.

`make links` reaches the network, because a documentation pack whose external links
have rotted is a documentation pack nobody trusts twice. It is separable for the case
where a runner has no egress. Nothing in the gate needs a credential or a workspace,
because a gate that needs credentials is a gate that gets skipped.

## Consequences

- **Nothing enforces the gate on a push.** This is the honest cost and it must not
  be dressed up. Here the gate is a command a developer runs and a reviewer can
  ask about, which is weaker than a required status check because both can be
  skipped by one person in a hurry. The pack says so where a reader will see it
  rather than implying coverage it does not have.
- Every check is runnable locally, so "it passes on my machine but fails in CI"
  becomes a real bug report rather than a shrug about runner images.
- A reader adopting this in their own repository copies one line into their own CI
  configuration. That is the whole porting exercise, which is the point.

## Rejected alternatives

**Ship a GitHub Actions workflow and note the limitation.** Rejected because the
file would be permanently inert at the destination, and an inert workflow file is
read as coverage. Someone would eventually cite a green badge that never ran.

**Ship adapters for several forges — Actions, GitLab, Azure Pipelines, a
Databricks Job.** Rejected as scope that does not earn its keep. Each adapter is a
handful of lines whose entire body is `make check`, so the pack would be
maintaining four files to save each reader three lines, and four files nobody
exercised would join the set of things claimed but not verified.

**Use a container-based CI standard (Dagger, Earthly, Nix) so the gate is
reproducible everywhere.** Rejected on dependency weight. The gate has to run on a
laptop with nothing installed but `make`, `sh` and `python3`; adding a build
engine to guarantee reproducibility of a check that is already hermetic buys
nothing and costs an install. This also follows from
[0004](0004-posix-sh-for-diagnostics.md).

## Revisit when

The destination gains a runner, or a check appears that genuinely needs something
only a forge can supply — a token, an artifact store, a build matrix. The second
is the interesting case: it would mean `make check` is no longer runnable on a
laptop, which is the property this record is protecting.
