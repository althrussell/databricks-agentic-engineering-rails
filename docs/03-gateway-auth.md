# Gateway authentication and governance

Unity AI Gateway is two things at once, and keeping them apart makes the rest of this
document simpler:

1. **A model endpoint.** Your harness talks to it instead of to a vendor API. Spend
   appears in a system table with your tags on it.
2. **An MCP registry.** Tools registered through it are governed by Unity Catalog and
   metered like model calls.

You can have either without the other. Two of the five harnesses covered here can only
have the second one.

## Authenticating

```sh
databricks auth login --host https://your-workspace.cloud.databricks.com --profile your-profile
export DATABRICKS_CONFIG_PROFILE=your-profile
uv tool install git+https://github.com/databricks/unity-gateway
ug claude          # or: ug codex | ug opencode | ug cursor | ug copilot
```

`ug`, also installed as `ucode`, is the Databricks tool that points a harness at the
gateway. Use it rather than exporting a base URL and a token by hand. It resolves the
profile, mints a short-lived token, writes the configuration in the shape that harness
actually reads, and `ug --refresh` re-mints when the token expires. A hand-set token
expires mid-session and fails in a way that reads like a model error, which is an
afternoon nobody gets back.

Nothing in this repository writes to `~/.claude`, `~/.codex` or a managed settings file.
`ug` does, and it is your own user-scope configuration it writes. Each `SETUP.md` says so
on the line before it tells you to run it.

## What `ug` configures, per harness

This asymmetry is the most useful fact in this pack, and it is not in anyone's marketing:

| Command | What it configures | Model traffic through the gateway |
| :--- | :--- | :--- |
| `ug claude` | `~/.claude/ucode-settings.json` and the `env` block of `~/.claude/settings.json` | **Yes** — verified here, 200 on the Anthropic route |
| `ug codex` | A custom provider block in `~/.codex/config.toml` | Provider written; the route was **not** verified on the workspace used here |
| `ug opencode` | A custom provider block in your `opencode.json` | Provider written; route not verified here |
| `ug cursor` | The MCP registration only | **No.** Model spend goes to Cursor's own billing |
| `ug copilot` | The MCP registration only | **No.** Model spend goes to GitHub's own billing |

Read the bottom two rows before you standardise on a harness. Registering MCP is real
governance over *tools* and none at all over *spend*: those sessions will not appear in
your usage table, will not be constrained by your rate limits, and will not show up in the
report you are asked for at the end of the quarter. If a governed model bill is the
requirement, that is a harness choice, not a configuration one.

## Routes are per workspace

This is the single most common surprise. Gateway routes are enabled per workspace, so a
route that answers on one workspace 404s on another. During the build of this pack, on one
workspace, the Anthropic route answered 200, the Codex route 404 and the Gemini route 400.

So nothing here promises you a route. Check the one you need before you plan around it,
and treat a colleague's working setup as evidence about their workspace and not about
yours.

| Result | What it means | Who fixes it |
| :--- | :--- | :--- |
| 200 | The route is live for you | Nobody |
| 404 | The route is not enabled on this workspace | A workspace administrator |
| 401, 403 | Your token is expired or lacks access | You, then an administrator |
| 429 | You are over the rate limit | Wait, or ask for a higher QPM |
| 000 | No network, or a proxy in the way | Your network |

## Request tags, and why they are not optional

Spend lands in `system.ai_gateway.usage` with a `request_tags` column, populated from the
`Databricks-Ai-Gateway-Request-Tags` header. That column is how spend gets an owner, and
it is the difference between a gateway that survives its first cost review and one that
gets switched off.

Two practical points.

**Confirm what actually arrives; do not assume it.** Whether your session carries tags
depends on the harness and on how it was configured, and the only place that answers is
the usage table itself — the query is at the end of this document. The usage-tracking
reference in [`SOURCES.md`](SOURCES.md) is the authority on the header.

**Agree the vocabulary before you have forty developers, not after.** Three keys are
enough: `team`, `project`, `purpose`. Past spend cannot be retagged, because those rows
are already written, so a month of untagged traffic is a month you will never be able to
attribute. And where you can set a tag, set it to a literal `unset` rather than omitting
it: an absent tag is invisible in a `GROUP BY`, whereas a row that says `unset` turns up
in the first query anyone runs.

## What the governance actually gives an administrator

- **Visibility.** `system.ai_gateway.usage`, tagged. Per team, per project, per model.
- **Budgets.** Which are **alarms, not caps**. A budget does not stop a request. It
  tells someone. Plan accordingly.
- **Rate limits.** Which are real, and surface as HTTP 429 to the harness. This is the
  control that actually constrains, so it is the one to reason about.
- **Model choice.** Which routes exist at all.

The admin-side setup is in the AI Gateway sources listed in [`SOURCES.md`](SOURCES.md). It
is a workspace administrator's job and is out of scope for a developer setting up a laptop.

## Governed MCP versus direct MCP

These look almost identical and are not:

```
{workspace}/ai-gateway/mcp-services/{catalog.schema.name}    governed
{workspace}/api/2.0/mcp/...                                  UC-governed, gateway-invisible
```

The first passes through the gateway: it appears in `system.ai_gateway.usage` and is
subject to QPM limits. The second is still governed by Unity Catalog permissions — it is
not a back door — but the gateway does not see it, so it is absent from your usage figures
and unconstrained by your rate limits.

Every reference config in [`harness/`](../harness/) uses the governed route. If you paste
a URL of the second shape into an `mcp.json` you have not done anything unsafe, but you
have left the gateway's field of view, and the two lines look the same in review.

Which of the server's tools a session may call is decided by Unity Catalog grants on the
MCP service, not by the harness config. Grant narrowly.

## Tokens and their lifetime

Two tokens, two lifetimes, and the confusion between them accounts for a lot of wasted
debugging.

- **Model traffic.** `ug` mints and refreshes it. You do not handle it. `ug --refresh`
  when a session starts failing.
- **MCP.** The reference configs read `${DATABRICKS_TOKEN}` from the environment, so no
  credential is written to a file you might commit. You export it yourself:

  ```sh
  export DATABRICKS_TOKEN=$(databricks auth token | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
  ```

  It is short-lived, and it expires inside a running session without the session ending.

Learn the signature: **when workspace tools stop answering but the model keeps working,
that is the MCP token, not the agent.** Re-export it and reconnect. The reverse — the
model failing while tools work — is `ug --refresh`.

## What governs a session, and what does not

What governs a session is the configuration and environment of the process that was
started, which reaches every child of it. A shell inside your editor is a child of that
shell, so a harness started in VS Code's **integrated terminal** is governed exactly as
one started in a standalone terminal.

It does not reach a process something else starts. An editor **extension** is started by
the editor, so its traffic is shaped by whatever environment the editor resolved for
itself. That is not a claim that extensions bypass the gateway. It is a claim that nobody
here has proved it either way. Treat an extension session as unverified until a row for it
appears in the usage table.

## The only check that settles it

A session that answers is not a session that went through the gateway. During the build of
this pack, a session started with a deliberately invalid gateway token answered
normally — it fell back to an ambient login. A client-side green tick proves that
something answered, and nothing about who.

Run this on the workspace, in a SQL editor or a notebook, within a few minutes of using a
session:

```sql
SELECT request_time, model_name, request_tags
FROM system.ai_gateway.usage
WHERE request_time > current_timestamp() - INTERVAL 15 MINUTES
ORDER BY request_time DESC
```

If your session is not in that table, it did not go through the gateway, whatever the
client told you.

## What is not proved

- Setting a base URL is setting a **default**, not installing a control. A fallback path
  that still exists will still be taken.
- The Codex and OpenCode provider routes are written by `ug` but were not verified 200
  on the workspace used to build this. Verify on yours with the query above.
- Cursor and Copilot CLI model spend is ungoverned here by design of what `ug` configures
  for them today. That is a current state, not a permanent one — re-check it rather than
  quoting this page in a year.
