---
title: Databricks Agentic Engineering Rails
description: Get a coding agent set up on your laptop, governed through Unity AI Gateway, in about thirty minutes.
---

# Databricks Agentic Engineering Rails

**Get a coding agent set up on your own laptop — governed through Unity AI Gateway,
with permissions that actually refuse things — in about thirty minutes.**

![Ten navy ceramic blocks lie scattered at random angles on an oat surface to the left of a pair of glossy lava-red rails; between the rails the same blocks form a single evenly spaced procession climbing to a stack of four smoked-glass slabs on brushed posts](assets/img/hero-on-rails.jpg)

You have a laptop, a harness you like, and a Databricks workspace. This pack gets you
from that to a session whose model spend is attributable, whose tools are governed by
Unity Catalog, and which will not force-push to a shared branch because a file it read
told it to.

**→ [Start here](00-start-here.md).** Everything else on this page is reference.

## The documents

Read in this order, or read only the one you need — each stands alone.

| # | Document | What it answers |
|---|---|---|
| 00 | [Start here](00-start-here.md) | Which harness, and what the whole path looks like |
| 01 | [Prerequisites](01-prerequisites.md) | What to install, and what `doctor.sh` checks |
| 02 | [Permissions](02-permissions.md) | Three tiers, why the middle one matters, rules versus a guard |
| 03 | [Gateway authentication and governance](03-gateway-auth.md) | `ucode`/`ug`, request tags, budgets, governed versus direct MCP |
| 04 | [Skills versus MCP](04-skills-vs-mcp.md) | Which one to reach for, and what each costs in context |
| 05 | [CI, tests and documentation](05-ci-test-docs.md) | What to enforce, and what "real end-to-end" means |
| — | [Sources](SOURCES.md) | Every URL behind a claim, with the status code and the date it was read |

The PDFs of the same set are built by `make docs`. They are a convenience for reading
or printing away from a browser; the Markdown is the source.

## The harness directories

One policy in `harness/shared/`, rendered into five harness directories. Each carries a
hand-written `SETUP.md` (the 30-minute path) and a generated `RENDER-NOTES.md` (what
that harness *cannot* express). The five are not equivalent, and the table in
[Start here](00-start-here.md) says how they differ in the two ways that matter: whether
model traffic is governed, and whether the never-automatic tier is actually enforced.

## Decision records

Four records, each with the alternatives that were rejected and the observable
condition that should reopen it. The rule stated in the index is the one worth
carrying away: **an agent may draft a decision record; a human owns the
decision.**

- [Index and format](DECISIONS/README.md)
- [0001 — Five harnesses generated, each labelled by what it can enforce](DECISIONS/0001-generate-every-harness.md)
- [0003 — pandoc + typst, bundled fonts, stable rebuilds](DECISIONS/0003-pdf-toolchain.md)
- [0004 — The doctor and the link checker carry no interpreter](DECISIONS/0004-posix-sh-for-diagnostics.md)
- [0005 — The gate is a command, not a workflow file](DECISIONS/0005-the-gate-is-a-command.md)

There is no 0002. It recorded an execution-boundary decision — containers and
sandboxing — that was removed from scope, and a record whose subject no longer exists
is deleted rather than left to be found and followed.

## How this site is built

The plain GitHub Pages branch build from `main` and `/docs`. There is no workflow file
and no Actions run anywhere in this repository, which is a constraint of the
destination rather than a preference — see
[decision 0005](DECISIONS/0005-the-gate-is-a-command.md) for why that also shaped how
the gate is enforced.

## Illustrations

The images on this site and in the repository README are decorative and were
generated. Every point they illustrate is also made in prose, a table or a
diagram on the same page — see [the note on how they were made and why that rule
exists](assets/img/README.md).

## What this is not

Not a Databricks product, not supported software, and not a claim of coverage it has
not tested. Every source is listed in [Sources](SOURCES.md) with the status code it
returned and the date it was read. The full statement is in `DISCLAIMER.md` in the
repository:
<https://github.com/althrussell/databricks-agentic-engineering-rails>
