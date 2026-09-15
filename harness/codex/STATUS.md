# Codex CLI — placeholder

**Status: not implemented.** This directory holds no configuration, and
`make harness-generate codex` refuses rather than producing one. A generated config
for a harness nobody has run would put a fifth row in the support matrix that looks
exactly like the row for the one that works.

| Question | Answer today |
| :--- | :--- |
| Generated configuration here? | No. There is no renderer for `codex` in `harness/scripts/render.py`. |
| Can the three tiers be expressed? | Partly, and not in the same shape. See `NOTES.md`. |
| Gateway route? | `/ai-gateway/codex/v1` is documented (claim `gw-coding-agent-routes`), and returned **404** on the workspace this pack was verified against (claim `probe-gw-route-coverage`). Probe your own. |
| Launcher? | `ug codex` (claim `ug-agents-and-cursor`). |
| Blocker to promotion | The never-automatic tier. Codex's permission model is mode-shaped, not rule-shaped. |

## What to do today

Use Codex if your team already does. Take the parts of this pack that are not
harness-specific — they are most of it:

- `harness/shared/` as the written policy, applied by review rather than by file
- the gateway route and request tags, which are an HTTP concern and harness-agnostic
- the CI checks, the documentation standard and the e2e discipline

What you do not get is the generated `settings.json`, the guard hook wired to
`PreToolUse`, and the evidence file in `harness/evidence/`. Do not describe a Codex
setup as being on these rails until someone has produced those three.

## What promotion requires

`harness/PROMOTION.md`. Five conditions, and the fifth is the one that is usually
skipped: a run of `harness/scripts/verify-in-sandbox.sh` against a real workspace,
with a demonstrated refusal, committed as evidence.
