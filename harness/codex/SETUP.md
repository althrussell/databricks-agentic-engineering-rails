# Codex CLI — setup

Thirty minutes to a governed session. Prerequisites are in `docs/01-prerequisites.md`.

Read this first, because it is the honest summary of what you get: Codex's permission
model is a session posture plus a filesystem fence, not a list of rules. It cannot be
told to refuse a named command before it runs. The never-automatic tier is therefore
written into `AGENTS.md`, where the model is told about it, and enforced by the person
reading the diff. That is weaker than a hook, and it is the reason `launch.sh` says so
at startup rather than leaving you to infer it.

## 1. Install

```sh
npm install -g @openai/codex
uv tool install git+https://github.com/databricks/unity-gateway
```

## 2. Check the machine

```sh
./scripts/doctor.sh
```

## 3. Install the configuration

Codex has no project-scoped configuration file, so `config.toml` here is a fragment for
your own machine rather than a file to commit into a project.

```sh
cat harness/codex/config.toml >> ~/.codex/config.toml     # then read it
cp harness/codex/AGENTS.md ./AGENTS.md                    # project root
```

**Two values in `config.toml` are yours to fill in.** The MCP server URL contains
`REPLACE-WITH-YOUR-WORKSPACE-HOST` and `REPLACE.WITH.YOUR_MCP_SERVICE`, because Codex
does not expand environment variables inside that file and a committed file must not
carry your workspace host. Replace both with your own values in your own copy under
`~/.codex/`. Nothing you edit there is checked by `make harness-verify` — that check
covers this repository's rendered output, not your home directory.

Merging by hand is deliberate. Appending blindly will produce a duplicate key if you
already have a `[sandbox_workspace_write]` section, and Codex will tell you so.

## 4. Start a session

```sh
export DAER_TEAM=your-team
export DAER_MCP_SERVICE=catalog.schema.your_mcp_service
./harness/codex/launch.sh --explain
./harness/codex/launch.sh
```

The launcher mints a short-lived token into `DAER_MCP_TOKEN`, which is what
`bearer_token_env_var` in `config.toml` reads — so no credential is written to disk.
The token is minted once, at launch: a session that outlives it loses MCP and keeps
working otherwise. Re-launch to refresh.

| Variable | Effect |
| :--- | :--- |
| `DAER_PROFILE` | Databricks CLI profile. Falls back to `DATABRICKS_CONFIG_PROFILE`, then `DEFAULT`. |
| `DAER_TEAM` | The `team` gateway request tag. |
| `DAER_MCP_SERVICE` | Unity Catalog name of the governed MCP service. |
| `DAER_NO_UG=1` | Take the environment-only path instead of `ug codex`. |

## 5. Confirm what you can

```sh
./harness/scripts/deny-proof.sh
```

This exercises the shared classifier, which on this harness is **not** wired in front
of the model — there is no documented pre-execution hook. Run it in CI over anything
scripted, and treat the `AGENTS.md` tier as policy the human enforces.

## Where to look next

- [RENDER-NOTES.md](RENDER-NOTES.md) — what this harness cannot express, in detail.
- [../shared/permissions.yml](../shared/permissions.yml) — the policy itself.
