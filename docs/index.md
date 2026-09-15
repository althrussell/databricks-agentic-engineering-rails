---
title: Databricks Agentic Engineering Rails
description: Standards, working code and proofs for building software with coding agents on Databricks.
---

# Databricks Agentic Engineering Rails

**Standards, working code and proofs for building software with coding agents on
Databricks — to a production standard, on rails a team can actually follow.**

![Ten navy ceramic blocks lie scattered at random angles on an oat surface to the left of a pair of glossy lava-red rails; between the rails the same blocks form a single evenly spaced procession climbing to a stack of four smoked-glass slabs on brushed posts](assets/img/hero-on-rails.jpg)

> **This site is PREVIEW, and it is mostly a table of contents for work that has
> not been written yet.** Phase 1 of 6 is complete: the reference harness is
> implemented and verified against a live workspace. The 21 documents below are
> listed with their real status, and most of them say `planned`. Nothing is
> marked as passing that has not been run.

This site is built by the plain GitHub Pages branch build from `main` and
`/docs`. There is no workflow file and no Actions run anywhere in this
repository — see [decision 0005](DECISIONS/0005-forge-agnostic-gate.md) for why
that constraint also shaped how the gate is enforced.

## What to read first

Nothing on this site yet is the right place to start, because the documents are
Phase 3. Until they exist, the repository itself is the material:

| Question | Where the answer lives, in the repository |
|---|---|
| Which of the two tracks am I on? | `README.md`, "Which track are you on?" — and see below |
| Is my machine ready? | `make doctor` |
| What does the standard actually enforce? | `harness/shared/` — permissions, gateway, mcp, boundary, guards |
| What has actually been run, and against what? | `harness/evidence/verify-in-sandbox.md` |
| Why was it built this way? | [the decision records](DECISIONS/README.md) |
| What is required, and which phase creates it? | `repo-manifest.yml` |
| What is claimed, and on whose authority? | `claims-ledger.json` and `sources.yml` |

The repository `README.md` is the full front door: audiences, the argument, the
three ways to start, and an honest account of what is not built. Read it there.

### The two tracks

**Track A** is a Databricks App: TypeScript, AppKit-first, hosted by Databricks
and reachable at a workspace URL. **Track B** is everything off-platform — any
language, any runtime you already own — using models hosted on Databricks through
the governed gateway and nothing else from the platform. One question separates
them: does the thing you are shipping have to run on Databricks?

Everything built so far is shared by both. Phase 1 delivered the harness, the
governed route and the gates, and none of it is track-specific, so the first move
is the same either way. The track-specific parts are `track-a-app/` and
`track-b-service/` in Phase 2, and documents 09 and 10 in the table below. Both
are listed there as `planned`, which is what they are.

## Decision records

Five records, each with the alternatives that were rejected and the observable
condition that should reopen it. The rule stated in the index is the one worth
carrying away: **an agent may draft a decision record; a human owns the
decision.**

- [Index and format](DECISIONS/README.md)
- [0001 — One harness implemented, four honestly labelled](DECISIONS/0001-reference-harness-first.md)
- [0002 — Where agent commands actually run](DECISIONS/0002-execution-boundary.md)
- [0003 — pandoc + typst, four fonts, byte-identical output](DECISIONS/0003-pdf-toolchain.md)
- [0004 — The doctor and the link checker carry no interpreter](DECISIONS/0004-posix-sh-for-diagnostics.md)
- [0005 — The gate is a script, not a workflow file](DECISIONS/0005-forge-agnostic-gate.md)

## The documents

Twenty-one documents, listed here with the status recorded in
`release-readiness.yml`. That file is the source of truth and `make check`
validates it, so this table cannot quietly disagree with it for long. Every row
marked `planned` is a file that does not exist; the links will start working as
Phase 3 lands.

| # | Document | Status | Standalone | PDF |
|---|---|---|---|---|
| 00 | Recommendations and Practices — the standalone digest | planned | yes | yes |
| 01 | Field Guide to Production Agentic Engineering on Databricks | planned | yes | yes |
| 02 | IDE and Harness Standard | planned | | yes |
| 03 | Authentication and Governance with Unity AI Gateway | planned | | yes |
| 04 | Skills and MCP — when each, and how to govern both | planned | | yes |
| 05 | Repository, CI and Gates | planned | | yes |
| 06 | Testing Standard — real tests, real end-to-end | planned | yes | yes |
| 07 | Documentation Standard — docs as a tested artifact | planned | | yes |
| 08 | Review and Evidence — reviewing work you did not type | planned | yes | yes |
| 09 | Databricks Apps to a Production Standard (Track A) | planned | | yes |
| 10 | Off-Platform Engineering with Databricks-Hosted Models (Track B) | planned | | yes |
| 11 | Platform Admin Runbook | planned | | yes |
| 12 | Operating Model and Metrics | planned | yes | yes |
| 13 | Risk Register and Threat Model | planned | | yes |
| 14 | Adoption Ladder — zero, capable, compounding | planned | yes | yes |
| 15 | Production Readiness — SLOs, performance, resilience, recovery | planned | | yes |
| 16 | Security, Privacy and Supply Chain | planned | | yes |
| — | Prerequisites — entitlements, previews and regions | planned | | |
| — | Portability — verified scope, not aspiration | planned | | |
| — | Glossary | planned | | |
| — | Reference Card — two printable pages | planned | yes | yes |

**Standalone** means the document is designed to be read with no repository and
no network. Success test 4 depends on that property alone: one PDF, forwarded,
with no dependency on anything else the pack builds.

## The four success tests

The bar the pack sets for itself, from `release-readiness.yml`. All four are
recorded as `not-run`, because three are closed by people and no cohort has run
them. `not-run` is not a soft pass.

| # | The bar | Closed by | Result |
|---|---|---|---|
| st-1 | Five engineers new to coding agents finish one day with a governed harness, a passing gate, and one change shipped to a Databricks App with evidence on the pull request | humans | not-run |
| st-2 | A second generated project reaches the productive checkpoint in under an hour with no further reading | humans | not-run |
| st-3 | A platform admin who did not author the runbook stands up the governance plane — budgets, rate limits, model and MCP services, policies, dashboards — in under a day, and sees per-team spend and per-tool usage the same afternoon | humans | not-run |
| st-4 | A reader who will never clone the repository forwards one PDF to their team and applies its standards to their own codebase the same week | humans | not-run |

## Illustrations

The images on this site and in the repository README are decorative and were
generated. Every point they illustrate is also made in prose, a table or a
diagram on the same page — see [the note on how they were made and why that rule
exists](assets/img/README.md).

## What this is not

Not a Databricks product, not supported software, and not a claim of coverage it
has not tested. Every external fact it relies on has a row in
`claims-ledger.json` with its source, the method used to check it, and the date;
every source has a row in `sources.yml` with the status code it returned. The
full statement is in `DISCLAIMER.md` in the repository.
