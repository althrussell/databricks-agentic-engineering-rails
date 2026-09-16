# 0001 — Five harnesses generated, each labelled by what it can enforce

**Status:** accepted
**Date:** 2026-09-16

## Context

The pack's harness policy is multi-harness first-class: a developer arrives with a
harness already chosen, usually by their team, and the setup path has to work for
whichever one that is. Five are in scope — Claude Code, Codex CLI, Cursor CLI,
GitHub Copilot CLI and OpenCode.

The tempting shape is one policy rendered five times, with a support matrix
showing five green cells. That shape is dishonest, because the five harnesses do
not enforce the same things:

- **Claude Code** has a pre-execution hook and per-connection credential helpers.
  A refusal can be made to actually refuse.
- **Codex CLI** has an approval posture (`approval_policy`, `sandbox_mode`) and no
  rule list and no pre-execution hook. Nothing in its configuration can express
  "never do this without asking".
- **Cursor CLI** has an allow list and a deny list and no middle tier. A command
  absent from the allow list prompts, which is the ask tier by omission rather
  than by statement.
- **GitHub Copilot CLI** takes permissions only as `--allow-tool` and
  `--deny-tool` launch flags, so the policy lives in the launcher and not in a
  file anyone can review.
- **OpenCode** has a pattern-to-verdict map with all three verdicts, which is the
  cleanest fit of the five.

Two further asymmetries are about the gateway rather than about permissions.
`ug` routes model traffic for Claude Code, Codex, OpenCode and Copilot CLI, but
for Cursor it registers MCP servers only — Cursor's model traffic does not pass
through Unity AI Gateway. And Copilot CLI's model traffic is likewise not
governed. Route availability is also per workspace, not per product: on the build
workspace the Anthropic route answered 200, the Codex route 404 and the Gemini
route 400.

The failure mode being avoided is specific: a reader picks a harness on the
strength of a matrix, spends an afternoon, and discovers a limitation that was
known when the matrix was written.

## Decision

All five harnesses are generated from `harness/shared/`, and every generated
directory carries a `RENDER-NOTES.md` whose "what this harness cannot express"
table is written for that harness and no other. The renderer refuses to drop a
capability silently: `render.py` raises `Unrenderable` when a harness has no way
to express a rule, and the build fails rather than producing a file that reads as
though the rule is in force.

Where a mechanism is substituted rather than rendered — Claude Code expresses
`tool(Bash)` and `mcp(*)` through `permissions.defaultMode` instead of as rules,
because an `ask` rule there outranks a narrower `allow` — the substitution is
declared, and `check_substitutions()` fails the build if the substituted mechanism
is absent from the produced document.

The comparison table in `docs/00-start-here.md` carries two columns that are the
whole point of it: **Model traffic governed** and **Never-automatic tier
enforced**. Cursor and Copilot CLI are "no" in the first. Codex is "no" in the
second.

## Consequences

- A reader on Codex gets a working setup and an explicit statement that their
  never-automatic tier is documented in `AGENTS.md` and enforced by a human
  reading the diff. That is a real cost, stated on the first page they read.
- One digest covers all five directories, because they share a launcher template.
  Editing `harness/shared/` marks every directory stale at once, which is correct:
  the policy moved, so every rendering of it is out of date.
- Five renderers is more code than one. The alternative is five hand-maintained
  configurations, which become five policies within a quarter, invisibly, because
  each file looks reasonable on its own.

## Rejected alternatives

**Implement one harness and ship the other four as placeholders.** This was the
earlier decision, and it was reversed. A developer who has already chosen Cursor
is not helped by a promotion bar; they need a config and an honest note about what
it cannot do. The placeholder approach optimised for the pack's own tidiness over
the reader's afternoon.

**Render all five and present them as equivalent.** Rejected because generating a
config is not evidence that it enforces anything. Three of the five cannot express
the middle tier the way Claude Code can, and a matrix that hid that would be the
exact defect this pack argues against.

**Normalise downward — express only what all five harnesses support.** Rejected
because it would throw away Claude Code's hook, which is the only mechanism here
that turns a written refusal into an actual one. The policy is allowed to be
richer than the weakest renderer; the renderer is required to say so.

## Revisit when

`ug` gains model routing for Cursor; Codex CLI gains a pre-execution hook or a
rule list; or a sixth harness is added. Any of those changes a "no" in the
comparison table, and that table is the summary of this record.
