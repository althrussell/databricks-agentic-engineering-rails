# OpenCode — setup

Thirty minutes to a governed session. Prerequisites are in `docs/01-prerequisites.md`.

Of the four non-reference harnesses this is the cleanest fit for the policy:
`permission.bash` maps a pattern to `allow`, `ask` or `deny`, which is the same three
verdicts the shared policy uses, and `opencode.json` expands `{env:VAR}` — so there is
no placeholder to fill in and no credential in a file.

## 1. Install

```sh
curl -fsSL https://opencode.ai/install | bash
uv tool install git+https://github.com/databricks/unity-gateway
```

## 2. Check the machine

```sh
./scripts/doctor.sh
```

## 3. Install the configuration

```sh
cp harness/opencode/opencode.json  ./opencode.json     # project root
cp harness/opencode/AGENTS.md      ./AGENTS.md         # project root
```

Both are project-scoped, so they can be committed into your own repository as they are.

The bash patterns are written **most specific first**, and that ordering is the whole
safety property: `shell(databricks)` is the ask tier and
`shell(databricks bundle deploy)` is never-automatic, so a map that reached
`databricks*` first would prompt for a deploy instead of refusing it. Do not reorder
them by hand — and you cannot, usefully, because `make harness-verify` will fail. Change
`harness/shared/permissions.yml` and regenerate.

## 4. Start a session

```sh
export DAER_TEAM=your-team
export DAER_MCP_SERVICE=catalog.schema.your_mcp_service
./harness/opencode/launch.sh --explain
./harness/opencode/launch.sh
```

The launcher sets `DAER_WORKSPACE_HOST`, `DAER_MCP_SERVICE` and `DAER_MCP_TOKEN`, which
`opencode.json` expands at connect time. The token is minted once at launch and expires
with it; re-launch to refresh.

| Variable | Effect |
| :--- | :--- |
| `DAER_PROFILE` | Databricks CLI profile. Falls back to `DATABRICKS_CONFIG_PROFILE`, then `DEFAULT`. |
| `DAER_TEAM` | The `team` gateway request tag. |
| `DAER_MCP_SERVICE` | Unity Catalog name of the governed MCP service. |

Model routing lives in your `opencode.json` provider block, not in an environment
variable, so `ug opencode` is the supported way to point this harness at the gateway.

## 5. Confirm the rails

```sh
./harness/scripts/deny-proof.sh
```

A `deny` verdict on a bash pattern refuses the canonical spelling before the command
runs, which is more than three of the five harnesses manage. It is still pattern
matching on command text, so the classifier is worth running in CI over anything
scripted.

## Where to look next

- [RENDER-NOTES.md](RENDER-NOTES.md) — what this harness cannot express, in detail.
- [../shared/permissions.yml](../shared/permissions.yml) — the policy itself.
