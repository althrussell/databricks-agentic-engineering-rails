# Cursor — placeholder

**Status: not implemented,** and the reason is different from the other three. Cursor
is the one entry in this list where the gap is not "nobody has done the work yet" but
a documented limit in the launcher.

| Question | Answer today |
| :--- | :--- |
| Generated configuration here? | No. There is no renderer for `cursor` in `harness/scripts/render.py`. |
| Can the three tiers be expressed? | Unknown. See `NOTES.md`. |
| Gateway route? | `/ai-gateway/cursor/v1` is documented (claim `gw-coding-agent-routes`). Probe your own workspace; route availability varies (claim `probe-gw-route-coverage`). |
| Launcher? | `ug cursor` supports **MCP only, not model routing** (claim `ug-agents-and-cursor`). |
| Blocker to promotion | Model spend is not routed through the gateway by the launcher, so the cost and visibility half of this pack does not apply to it as shipped. |

## Read this before treating Cursor as governed

Two governance questions are separate and only one of them has an answer here.

- **Which tools can the agent reach, and under what authority?** Governable. `ug
  cursor` registers MCP servers, and a governed MCP service routed through Unity AI
  Gateway is the same HTTP endpoint whatever calls it.
- **Which model answered, at what cost, charged to whom?** Not governed through the
  launcher. Model routing is explicitly outside what `ug cursor` does. Spend and
  request tags for Cursor sessions do not arrive in `system.ai_gateway.usage` by
  virtue of anything in this pack.

A team that adopts Cursor and reports "we are on the gateway" is describing the first
of those and will be understood to mean the second. That misunderstanding is expensive
in exactly the situation this pack exists to prevent: an unattributed model bill with
no per-team breakdown. Say which half you have.

## What to do today

Use the MCP half, which is real: register governed MCP services through `ug cursor`
and let Unity Catalog own tool access. For model spend, either configure Cursor's own
provider settings against the documented gateway route directly and verify from the
gateway side that traffic arrives, or account for that spend separately and knowingly.

## What promotion requires

`harness/PROMOTION.md`, plus one condition specific to this harness: evidence that a
Cursor session's model traffic appears in `system.ai_gateway.usage` with the request
tags attached. Until someone produces that query result, the honest support level is
"MCP governed, model spend not".
