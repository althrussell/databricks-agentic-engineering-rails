# Gateway authentication and governance

Unity AI Gateway is two things at once, and keeping them apart makes the rest of this
document simpler:

1. **A model endpoint.** Your harness talks to it instead of to a vendor API. Spend
   appears in a system table with your tags on it.
2. **An MCP registry.** Tools registered through it are governed by Unity Catalog and
   metered like model calls.

You can have either without the other. Two of the five harnesses in this pack can only
have the second one.

## Authenticating

```sh
databricks auth login --host https://your-workspace.cloud.databricks.com --profile your-profile
uv tool install git+https://github.com/databricks/unity-gateway
./harness/<name>/launch.sh --explain
```

`ug` (aliased `ucode`) configures a named harness to use the gateway. `--explain`
resolves the profile, makes a real HTTP call to the route and prints what it would do
without starting anything. Run it first on any new machine.

The launchers never print a token, a workspace host or an account name, and no script in
this repository writes to `~/.claude`, `~/.codex` or a managed settings file. `ug`
itself does write user-scope configuration for the harness you name; the launcher says
so on the line before it happens, and `DAER_NO_UG=1` takes an environment-only path
instead.

## Routes are per workspace

This is the single most common surprise. Gateway routes are enabled per workspace, so a
route that answers on one workspace 404s on another. During the build of this pack, on
one workspace, the Anthropic route answered 200, the Codex route 404 and the Gemini
route 400. That is why every launcher probes rather than promises, and why
`RENDER-NOTES.md` distinguishes a route that was exercised from one that is merely
documented.

| Probe result | What it means | Who fixes it |
| :--- | :--- | :--- |
| 200 | The route is live for you | Nobody |
| 404 | The route is not enabled on this workspace | A workspace administrator |
| 401, 403 | Your token is expired or lacks access | You, then an administrator |
| 429 | You are over the rate limit | Wait, or ask for a higher QPM |
| 000 | No network, or a proxy in the way | Your network |

## Request tags, and why they are not optional

Every launcher sets a `Databricks-Ai-Gateway-Request-Tags` header with three keys:
`team`, `project`, `purpose`. They land in `system.ai_gateway.usage`, which is how spend
gets an owner.

```sh
export DAER_TEAM=your-team
export DAER_PROJECT=your-project
```

An unset team is recorded as the literal `unset` rather than omitted. That is a
deliberate choice: an absent tag is invisible in a `GROUP BY`, and a row that says
`unset` shows up in the first query anyone runs. Untagged spend has no owner, and
untagged spend is what gets a gateway switched off.

## What the governance actually gives an administrator

- **Visibility.** `system.ai_gateway.usage`, tagged. Per team, per project, per model.
- **Budgets.** Which are **alarms, not caps**. A budget does not stop a request. It
  tells someone. Plan accordingly.
- **Rate limits.** Which are real, and surface as HTTP 429 to the harness. This is the
  control that actually constrains, so it is the one to reason about.
- **Model choice.** Which routes exist at all.

The admin-side setup is in the AI Gateway sources listed in `docs/SOURCES.md`. It is a
workspace administrator's job and is out of scope for a developer setting up a laptop.

## Governed MCP versus direct MCP

These look almost identical and are not:

```
{workspace}/ai-gateway/mcp-services/{catalog.schema.name}    governed
{workspace}/api/2.0/mcp/...                                  UC-governed, gateway-invisible
```

The first passes through the gateway: it appears in `system.ai_gateway.usage` and is
subject to QPM limits. The second is still governed by Unity Catalog permissions — it is
not a back door — but the gateway does not see it, so it is absent from your usage
figures and unconstrained by your rate limits.

This pack renders only the governed route. A generated configuration that quietly
bypassed the gateway would be worse than no generated configuration, because it would
carry the authority of having been produced by a program.

Which of the server's tools a session may call is decided by Unity Catalog grants on the
MCP service, not by the harness config. Grant narrowly.

## Tokens and their lifetime

The launchers mint a short-lived token with `databricks auth token` and pass it in the
environment. Two shapes result:

- **Claude Code** has a per-connection header helper, so MCP gets a fresh token for
  every connection. That helper runs as a direct child of the harness process with your
  full authority, which is why `.mcp.json` is a file whose edits are not routine.
- **The other four** carry the launch-time token in a header, so it expires with the
  token. A session that outlives it loses MCP and keeps working otherwise. Re-launch to
  refresh.

That difference is stated in each harness's `RENDER-NOTES.md` rather than smoothed over.

## What is not proved

A launcher setting `ANTHROPIC_BASE_URL` is setting a default, not installing a control.
During the build of this pack, a session started with a deliberately invalid gateway
token answered normally by falling back to an ambient login. **A green probe does not
prove that a session's own traffic went through the gateway.** Confirm from the gateway
side, using the request tags — that query is the only answer that counts.
