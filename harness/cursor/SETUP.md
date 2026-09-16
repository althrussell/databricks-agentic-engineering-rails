# Cursor CLI — setup

Thirty minutes to a session with governed tools. Prerequisites are in
`docs/01-prerequisites.md`.

One thing to know before you start, because it changes what this setup is worth:
**`ug cursor` configures MCP only.** No documented environment variable points the
Cursor CLI at a custom model endpoint, so its tool calls come under Unity AI Gateway
and its model spend is billed by whatever your Cursor licence bills. This is the one
harness here whose model traffic the gateway does not see. The launcher says so at
startup rather than letting a green `--explain` imply otherwise.

## 1. Install

```sh
curl https://cursor.com/install -fsS | bash        # provides cursor-agent
uv tool install git+https://github.com/databricks/unity-gateway
```

## 2. Check the machine

```sh
./scripts/doctor.sh
```

## 3. Install the configuration

```sh
mkdir -p .cursor/rules
cp harness/cursor/cli.json         .cursor/cli.json
cp harness/cursor/mcp.json         .cursor/mcp.json
cp harness/cursor/rules/rails.mdc  .cursor/rules/rails.mdc
```

**`.cursor/mcp.json` has two placeholders to fill in** —
`REPLACE-WITH-YOUR-WORKSPACE-HOST` and `REPLACE.WITH.YOUR_MCP_SERVICE`. Whether Cursor
expands `${DAER_MCP_TOKEN}` in the `Authorization` header is **not exercised here**; if
the server fails to connect, put the output of `databricks auth token` in your own local
copy and re-mint it when it expires. Do not commit that copy.

`cli.json` has an `allow` list and a `deny` list and no third verdict. That turns out to
be the right shape: anything not allowed prompts, so the ask tier is the file's default
rather than something missing from it.

## 4. Start a session

```sh
export DAER_TEAM=your-team
export DAER_MCP_SERVICE=catalog.schema.your_mcp_service
./harness/cursor/launch.sh --explain
./harness/cursor/launch.sh
```

| Variable | Effect |
| :--- | :--- |
| `DAER_PROFILE` | Databricks CLI profile. Falls back to `DATABRICKS_CONFIG_PROFILE`, then `DEFAULT`. |
| `DAER_TEAM` | The `team` gateway request tag, on MCP traffic. |
| `DAER_MCP_SERVICE` | Unity Catalog name of the governed MCP service. |

There is no environment-only path for this harness: without `ug` there is nothing to
configure, and `launch.sh` refuses rather than starting an ungoverned session from a
script in a pack about governance.

## 5. Confirm the rails

```sh
./harness/scripts/deny-proof.sh
```

The `deny` list refuses the canonical spelling of each never-automatic action. No
pre-execution hook is documented for this harness, so an unusual spelling is caught by
the always-applied rule in `.cursor/rules/rails.mdc` and by the person reading the diff,
not by a program.

## Where to look next

- [RENDER-NOTES.md](RENDER-NOTES.md) — what this harness cannot express, in detail.
- [../shared/permissions.yml](../shared/permissions.yml) — the policy itself.
