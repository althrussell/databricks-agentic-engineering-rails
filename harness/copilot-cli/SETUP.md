# GitHub Copilot CLI — setup

Thirty minutes to a session with governed tools. Prerequisites are in
`docs/01-prerequisites.md`.

Two facts that shape everything below:

- **Permissions are command-line flags here, not a file.** They live in `launch.sh`,
  which is the only place they exist. A developer who types `copilot` gets none of them.
- **No documented environment variable points Copilot CLI at a custom model endpoint.**
  Its MCP traffic can be governed; its model spend is billed by GitHub. The launcher
  says so at startup.

## 1. Install

```sh
npm install -g @github/copilot
uv tool install git+https://github.com/databricks/unity-gateway
```

## 2. Check the machine

```sh
./scripts/doctor.sh
```

## 3. Install the configuration

```sh
mkdir -p ~/.copilot .github
cp harness/copilot-cli/mcp-config.json           ~/.copilot/mcp-config.json
cp harness/copilot-cli/copilot-instructions.md   .github/copilot-instructions.md
```

**`~/.copilot/mcp-config.json` has two placeholders to fill in** —
`REPLACE-WITH-YOUR-WORKSPACE-HOST` and `REPLACE.WITH.YOUR_MCP_SERVICE`. Whether Copilot
CLI expands `${DAER_MCP_TOKEN}` in the `Authorization` header is **not exercised here**;
if the server fails to connect, put a token from `databricks auth token` in your own
copy under `~/.copilot/` and re-mint it when it expires. That file is outside this
repository and outside `make harness-verify`.

## 4. Start a session

```sh
export DAER_TEAM=your-team
export DAER_MCP_SERVICE=catalog.schema.your_mcp_service
./harness/copilot-cli/launch.sh --explain
./harness/copilot-cli/launch.sh
```

The launcher appends the permission tiers as `--allow-tool` and `--deny-tool` flags.
Start every session this way. If you find yourself typing `copilot` directly, alias it:

```sh
alias copilot-rails='"$PWD"/harness/copilot-cli/launch.sh'
```

| Variable | Effect |
| :--- | :--- |
| `DAER_PROFILE` | Databricks CLI profile. Falls back to `DATABRICKS_CONFIG_PROFILE`, then `DEFAULT`. |
| `DAER_TEAM` | The `team` gateway request tag, on MCP traffic. |
| `DAER_MCP_SERVICE` | Unity Catalog name of the governed MCP service. |

## 5. Confirm the rails

```sh
./harness/scripts/deny-proof.sh
```

`--deny-tool` refuses the canonical spelling of each never-automatic action, and only in
a session started through `launch.sh`. There is no hook here, so the classifier's
normalisation is not in front of the model — run it in CI over anything scripted, and
treat the tier in `.github/copilot-instructions.md` as policy the human enforces.

## Where to look next

- [RENDER-NOTES.md](RENDER-NOTES.md) — what this harness cannot express, in detail.
- [../shared/permissions.yml](../shared/permissions.yml) — the policy itself.
