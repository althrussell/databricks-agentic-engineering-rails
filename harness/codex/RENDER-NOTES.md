<!--
GENERATED FILE - do not edit.

Rendered from harness/shared/ by harness/scripts/render.py. Change the policy
there and run `make harness-generate`. `make harness-verify` fails the build if
this file was edited by hand, and says which of the two mistakes it was.
-->

# Codex CLI, as rendered from `harness/shared/`

`harness/shared/` is the policy. Every file in this directory except `SETUP.md` is reproduced by `make harness-generate`, and `make harness-verify` fails if one has been edited by hand.

| | |
| :--- | :--- |
| Gateway route | `/ai-gateway/codex/v1` (documented) |
| Model traffic through the gateway | yes |
| Never-automatic tier enforced | by posture and by review |
| Launcher | `ug codex`, or `./harness/codex/launch.sh` |

## Where each file goes

| File | Installs as | Notes |
| :--- | :--- | :--- |
| `config.toml` | `~/.codex/config.toml (merge)` | User scope. Codex has no project-scoped equivalent. |
| `AGENTS.md` | `<project>/AGENTS.md` | Where the never-automatic tier is stated, since no hook can enforce it. |
| `launch.sh` | `run in place` | Resolves the workspace, probes the route, sets the request tags. |

## How the never-automatic tier is enforced here

`approval_policy` and `sandbox_mode` decide what prompts. No pre-execution hook is documented, so the never-automatic tier is written into `AGENTS.md` and enforced by the human reading the diff.

## What this harness cannot express

Stated here rather than left for a reader to discover from behaviour.

| | |
| :--- | :--- |
| per-command allow and ask lists | Codex's permission model is a session-wide approval posture plus a filesystem scope, not a list of per-command rules. `approval_policy = "on-request"` is the closest equivalent of the ask tier: it asks before anything outside the scope. It cannot be told to ask about *this list of commands specifically*, so the auto-allow tier is advice here rather than configuration. |
| the never-automatic tier, before the command runs | No pre-execution hook is documented, so nothing can veto a named command. The tier is rendered into `AGENTS.md` instead, where the model is told about it, and enforced by review. That is weaker and is stated in the launcher's output, not only here. |
| net.fetch(host) scoping | `sandbox_workspace_write.network_access` is a single switch for every command the agent runs, with no per-host list. It is left on because the auto-allow tier includes `npm ci` and `uv run`, which need it. |

## MCP

Server `databricks` on the governed route. 5 tools against a ceiling of 12.

```
https://REPLACE-WITH-YOUR-WORKSPACE-HOST/ai-gateway/mcp-services/REPLACE.WITH.YOUR_MCP_SERVICE
```

`bearer_token_env_var` reads the token from `DAER_MCP_TOKEN`, which `launch.sh` sets from `databricks auth token`. It is minted once at launch, so a session outliving the token loses MCP and keeps working otherwise. Re-launch to refresh.

`scripts/tool-budget.py --live` measures what the registration costs in context against the ceilings in `harness/shared/mcp.yml`, and reports where the allowlist and the server's advertised tools disagree — context spent on nothing in one direction, a policy line that constrains nothing in the other.

## Not proved here

- **Whether a session's own traffic reaches the model through the governed route.** The route is probed with a real HTTP call at launch; where a session sends its traffic is a different question. A session started with a deliberately invalid gateway token has been seen to answer normally by falling back to an ambient login. The environment the launcher sets is a default, not a control. Confirm from the gateway side, using the request tags.
- **This route.** It is documented and was not exercised during the build. `./harness/codex/launch.sh --explain` probes it on your workspace, which is the only answer that matters.

