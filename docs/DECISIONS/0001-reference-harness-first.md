# 0001 — One harness implemented, four honestly labelled

**Status:** accepted
**Date:** 2026-09-15

## Context

The pack's harness policy is multi-harness first-class: Claude Code, Codex CLI,
Cursor, Gemini CLI and OpenCode all deserve a supported path, and the harness
standard is written so that no document assumes one of them. That is the right
end state and it is not reachable in one step.

Two facts made a five-harness first release impossible to do honestly.

The first is that gateway route availability is per workspace, not per product.
On the verification workspace the Anthropic route returned 200, the Codex route
returned 404 and the Gemini route returned 400 (`probe-gw-route-coverage` in
`claims-ledger.json`). A Codex configuration written on that workspace could be
generated, committed and documented, but not *run*, and so not verified.

The second is that `ug` itself does not treat the harnesses alike. It launches
Codex, Claude Code, Gemini CLI, OpenCode, GitHub Copilot CLI and Pi, but Cursor
is supported for MCP registration only, with no model routing
(`ug-agents-and-cursor`). Cursor cannot reach parity through `ug` alone, whatever
we write about it.

The failure mode we are avoiding is specific and common: a support matrix with
five green cells, four of which mean "we wrote a config file". A reader picks
Cursor on the strength of the matrix, spends an afternoon, and discovers the
limitation we already knew about.

## Decision

One harness — Claude Code — is implemented end to end and verified by running
it: permission tiers with a deny that is demonstrated rather than described,
launch through the gateway, MCP registration, and a tool budget. Every artefact
for it is generated from `harness/shared/`, which is the single source of truth.

The other four ship as placeholder directories containing exactly `STATUS.md`,
`NOTES.md` and `.gitkeep`. Nothing loadable. A placeholder that contains a
plausible-looking settings file is worse than an empty one, because a reader will
try it.

`harness/PROMOTION.md` states the bar a placeholder must clear to become
supported, and `repo-integrity` in `make check` fails if anything loadable
appears in a placeholder directory. The bar is written down so that "coming soon"
resolves to something a contributor can actually complete.

## Consequences

- A reader whose team standardised on Codex or Cursor gets a status note and a
  promotion bar, not a working configuration. That is a real cost and the harness
  standard says so on its first page rather than in a footnote.
- The generator is load-bearing from day one. Because the reference harness is
  produced by `harness/scripts/generate.sh` from `harness/shared/` rather than
  hand-written, promoting a placeholder is a matter of adding a renderer, not of
  reverse-engineering what the reference harness does.
- `make harness-verify` must fail on hand-edited output, or the single source of
  truth quietly becomes one of several. It is in the hermetic lane for that
  reason.

## Rejected alternatives

**Ship all five as generated-but-unverified.** Rejected because generating a
config is not evidence that it works, and the pack's whole argument is that
unverified output presented as verified is the defect. Four cells would have been
green on the strength of a file existing.

**Ship only Claude Code and say nothing about the others.** Rejected because
silence is read as "not considered". The asymmetries above are findings worth
publishing: a reader choosing a harness needs to know that Cursor's limitation
comes from the launcher and that route coverage is a property of their own
workspace, not of the product.

**Pick whichever harness the verification workspace supported and call it the
recommended one.** Rejected because the workspace is an accident of this build.
Claude Code is the *reference* harness — the one used to prove the pattern — and
the documents are careful with that word. A reader on a workspace where the Codex
route answers should promote Codex, and the promotion path exists so they can.

## Revisit when

Any of: the Codex or Gemini route answers on the verification workspace; `ug`
gains model routing for Cursor; or a contributor completes `PROMOTION.md` for a
second harness. The first placeholder promoted supersedes this record with one
that says two harnesses are supported and how the second got there.
