# GitHub Copilot CLI — placeholder

**Status: not implemented.** No configuration here, and no renderer for it.

| Question | Answer today |
| :--- | :--- |
| Generated configuration here? | No. There is no renderer for `copilot-cli` in `harness/scripts/render.py`. |
| Can the three tiers be expressed? | Unknown. See `NOTES.md`. |
| Gateway route? | **None is documented.** The route list in claim `gw-coding-agent-routes` names Anthropic, Codex, Cursor, Gemini and MLflow routes. Copilot CLI is not among them. |
| Launcher? | `ug` launches it (claim `ug-agents-and-cursor`). |
| Blocker to promotion | Where the model spend is metered. See below — this is the interesting one. |

## The question this harness raises for the whole pack

Copilot CLI is listed as launchable, and no gateway route is documented for it. The
most likely reading is that its model access comes with the GitHub subscription rather
than from a Databricks serving endpoint (**unverified** — establish it before repeating
it). If that is right, then for this harness:

- Model spend is metered by GitHub, per seat, and does not appear in
  `system.ai_gateway.usage`. Per-team attribution comes from GitHub's own reporting or
  not at all, and the request-tag mechanism this pack leans on has nothing to tag.
- The gateway's other job still applies in full. Governed MCP is an HTTP endpoint
  under `/ai-gateway/mcp-services/`, and any client that can send a bearer token to a
  URL can be made to use it. Tool access, Unity Catalog permissions and the audit
  trail are all still available.

So Copilot CLI can be substantially governed on the tool axis and not on the model
cost axis. That is a legitimate position — a team may prefer a per-seat bill they
already understand — but it must be stated, because "we route everything through the
gateway" would then be false for this harness while being true for the reference one.

## What to do today

Use the tool half. Register governed MCP services and let Unity Catalog own access.
Take `harness/shared/permissions.yml` as a written standard applied by review, and
account for the model spend where it actually lands.

## What promotion requires

`harness/PROMOTION.md`, and first an answer to the question above: establish where the
model spend is metered, and write it down as a ledger claim with evidence. That answer
determines whether promotion means "governed like the reference harness" or "governed
on tools, metered elsewhere", and those need different documentation.
