# 0006 — Guidance over machinery: no generator, no PDF pipeline

**Status:** accepted
**Date:** 2026-09-16

## Context

This repository exists to get a developer productive with a coding harness against
Databricks in about half an hour, using proven tools configured the way people who have
done it already would configure them. It is a guide with reference configuration
attached.

It had stopped being that, and the drift was measurable rather than a matter of taste.
Counted at commit `5475ec2`, immediately before this decision:

| | lines |
| :--- | ---: |
| Shell and Python written here | 4,757 |
| Documentation | 2,934 |
| Harness configuration a reader actually copies | 386 |
| Machinery whose only job was maintaining those 386 lines | 4,470 |

The last two rows are the finding. The ratio of apparatus to product was about **twelve
to one**. The code generator, `render.py`, was 1,423 lines — the largest file in the
repository — and what it produced was eleven small config files. Five `launch.sh`
scripts came to 958 lines between them, and the operative content of each was one line:

```sh
exec ug claude "$@"
```

The rest was probing, explaining, tagging and refusing — all of it reasonable, none of
it something a customer asked for or would maintain. A separate 703 lines
(`build-docs.py` at 422, plus a 281-line typst template) turned the same markdown into PDFs.

Two failures follow from a ratio like that, and both are worse than the wasted effort.

**It teaches the wrong thing.** A reader who came for "how do I configure Codex against
the AI Gateway" found a build system, and the implicit lesson was that this needs a
build system. It does not. `ug` is a Databricks tool that already does the hard part.

**It cannot be adopted piecemeal.** Every generated file carried a header telling the
reader not to edit it and to change `harness/shared/` instead. That is correct advice
for someone who has adopted the whole apparatus and useless for the much more common
reader who wants to copy one `settings.json` into a project they already have.

There is also a straightforward maintenance argument. Custom code written for one
customer engagement, wrapping tools that ship their own releases, goes stale at the
speed of those tools and is nobody's job to update.

## Decision

**Delete the machinery. Keep and expand the guidance and the configuration it
describes.**

Specifically: no code generator, no digest manifests, no `RENDER-NOTES.md`, no
per-harness launcher, no pre-execution hook of our own, no MCP token helper, no guard
engine, no tool-budget measurement tool, and no PDF pipeline. What remains in
`harness/` is eleven configuration files and five `SETUP.md`, hand-maintained.

Where a deleted script encoded something true, the fact moved into prose rather than
being deleted with it. Three examples, because they are the point of this record:

- The launchers probed the gateway route before starting, because a route documented for
  the platform is not necessarily enabled on a given workspace. That is now the
  "Routes are per workspace" section of `docs/03-gateway-auth.md`, with the probe
  results table.
- `tool-budget.py` measured what an MCP registration costs in context. The durable fact
  — every registered tool's schema is in the prompt of every session whether you call
  it or not, and schemas are only measurable once you connect — is now a paragraph in
  `docs/04-skills-vs-mcp.md`.
- The guard normalised command text before matching it, because a rule anchored on the
  first two words misses the same command spelled differently. That limitation is now
  stated plainly in `docs/02-permissions.md` and in every `SETUP.md`, which is more
  useful than a 314-line implementation that only ever protected this repository.

Two things follow that are worth stating so they are not mistaken for oversights.

**The five harness directories are now maintained by hand, and may drift.** That is a
real cost and it is accepted knowingly. Five hand-maintained configs can become five
policies within a quarter, invisibly, which is precisely the argument
[0001](0001-generate-every-harness.md) made for generating them. The argument was sound
and the price was wrong: 4,470 lines of drift prevention for 386 lines of exposure. A
reader who copies one directory was never protected by the generator anyway, because
they took the output and left the policy behind.

**Claude Code loses its enforced middle tier.** The `PreToolUse` hook was the one
mechanism here that could refuse a command before it ran, and it is gone. What is left
is the harness's own `deny` list, which is matched against command text. The
documentation says so rather than implying the tier is still enforced — see
`docs/02-permissions.md`, which now leads with what each harness actually fences.

## Consequences

- Shell and Python in the repository fall from 4,757 lines to 472, in two files:
  `doctor.sh` and `link-check.sh`. Both check the guide itself; neither is something a
  reader installs or copies.
- The gate shrinks with it. No `harness-verify`, no `harness-generate`, no deny-proof
  suite, no tool budget, no PDF build. What is left parses the shell, validates the
  configs and checks every link. See [0005](0005-the-gate-is-a-command.md).
- The documentation is the deliverable, so GitHub Pages is the only published form.
  Anyone who needs a PDF can print a page, which is a browser feature and not
  a 703-line dependency on pandoc, typst and bundled font licensing.
- The 0003 record, on the PDF toolchain, is deleted rather than superseded. Its
  decision is not live and its hundred lines described a pipeline no longer present;
  the reasoning is in git history. `0001` is superseded rather than deleted, because
  most of it is still the live decision.
- Readers on an earlier version who ran `make harness-generate` have nothing to
  migrate: the generated files are the files that remain, minus the headers telling
  them not to edit them.

## Rejected alternatives

**Keep the generator and cut the documentation instead.** Rejected because it inverts
the brief. The value here is knowing which route is verified, which harness cannot
govern model spend, and what a permission rule does not stop. None of that is code.

**Keep the generator but shrink it.** Rejected because the cost is not the line count,
it is the concept. Any generator makes its output not-to-be-edited, and the primary use
of this repository is copying one file into a project that already exists.

**Keep the five `launch.sh` scripts, drop everything else.** Tempting, because a probe
before launch is genuinely useful. Rejected because `ug` is the supported Databricks
tool for exactly this, it is maintained by the team that owns the gateway, and a
wrapper around it competes with its own upstream. `ug --refresh` and a gateway-side
query in `system.ai_gateway.usage` cover what the launchers covered, and the second is
the only evidence that ever counted.

**Keep the PDF pipeline for offline distribution.** Rejected on weight. It was 703
lines, three system dependencies and a font licensing review, to produce a format that
was never asked for and goes stale the moment the markdown changes.

## Revisit when

Two conditions, and the first is likelier.

**The eleven configuration files visibly drift.** The observable signal is a reader
reporting that one harness's tiers differ from another's in a way neither `SETUP.md`
explains. The right response then is a checker that compares the five configs against
each other and reports differences — perhaps 100 lines — and not a generator. A test is
not a build system.

**A harness gains a mechanism that needs real code to configure.** If the honest
configuration of some future harness cannot be expressed as a file a reader copies,
this record is the thing standing in the way and should be reopened rather than
worked around.
