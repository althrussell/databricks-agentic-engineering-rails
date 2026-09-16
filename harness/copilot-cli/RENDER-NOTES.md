<!--
GENERATED FILE - do not edit.

Rendered from harness/shared/ by harness/scripts/render.py. Change the policy
there and run `make harness-generate`. `make harness-verify` fails the build if
this file was edited by hand, and says which of the two mistakes it was.
-->

# GitHub Copilot CLI, as rendered from `harness/shared/`

`harness/shared/` is the policy. Every file in this directory except `SETUP.md` is reproduced by `make harness-generate`, and `make harness-verify` fails if one has been edited by hand.

| | |
| :--- | :--- |
| Gateway route | `/ai-gateway/mlflow/v1` (documented) |
| Model traffic through the gateway | **no** — see below |
| Never-automatic tier enforced | by flag for deny, by review for the rest |
| Launcher | `ug copilot`, or `./harness/copilot-cli/launch.sh` |

## Where each file goes

| File | Installs as | Notes |
| :--- | :--- | :--- |
| `mcp-config.json` | `~/.copilot/mcp-config.json` | Fill in the two placeholders; see SETUP.md. |
| `copilot-instructions.md` | `<project>/.github/copilot-instructions.md` | Where the never-automatic tier is stated. |
| `launch.sh` | `run in place` | Carries the permission flags. This is the only place they exist. |

## How the never-automatic tier is enforced here

`--deny-tool` refuses the canonical spelling of each never-automatic action, and only when the session is started through `launch.sh`. There is no hook, so the guard's normalisation is not available here.

**--allow-tool** (22)

- `write`
- `shell(git status)`
- `shell(git diff)`
- `shell(git log)`
- `shell(git show)`
- `shell(git add)`
- `shell(git commit)`
- `shell(git switch)`
- `shell(git restore)`
- `shell(git stash)`
- `shell(git worktree)`
- `shell(make check)`
- `shell(make docs)`
- `shell(make test)`
- `shell(make e2e)`
- `shell(make doctor)`
- `shell(npm run)`
- `shell(npm test)`
- `shell(npm ci)`
- `shell(pytest)`
- `shell(uv run)`
- `shell(python3 scripts/)`

**--deny-tool** (8)

- `shell(git push --force)`
- `shell(git push -f)`
- `shell(gh pr merge)`
- `shell(gh pr ready)`
- `shell(gh release create)`
- `shell(databricks bundle deploy)`
- `shell(databricks bundle destroy)`
- `shell(security find-generic-password)`

## What this harness cannot express

Stated here rather than left for a reader to discover from behaviour.

| | |
| :--- | :--- |
| a committed permission file | Tool permissions are command-line flags, not a config file, so they are rendered into `launch.sh` instead. That is a real difference: a developer who starts `copilot` directly gets none of them. Start it through the launcher. |
| the never-automatic tier, before the command runs | `--deny-tool` refuses the canonical spelling. No pre-execution hook is documented, so the tier is also written into `.github/copilot-instructions.md` and enforced by review. |
| model routing through the gateway | No documented environment variable points Copilot CLI at a custom model endpoint. Its MCP traffic can be governed; its model spend is billed by GitHub. The launcher says so at startup. |

## MCP

Server `databricks` on the governed route. 5 tools against a ceiling of 12.

```
https://REPLACE-WITH-YOUR-WORKSPACE-HOST/ai-gateway/mcp-services/REPLACE.WITH.YOUR_MCP_SERVICE
```

A static `Authorization` header referencing `DAER_MCP_TOKEN`, set by `launch.sh`. Whether Copilot CLI expands an environment variable in that position is **not exercised here**.

`scripts/tool-budget.py --live` measures what the registration costs in context against the ceilings in `harness/shared/mcp.yml`, and reports where the allowlist and the server's advertised tools disagree — context spent on nothing in one direction, a policy line that constrains nothing in the other.

## Not proved here

- **Whether a session's own traffic reaches the model through the governed route.** The route is probed with a real HTTP call at launch; where a session sends its traffic is a different question. A session started with a deliberately invalid gateway token has been seen to answer normally by falling back to an ambient login. The environment the launcher sets is a default, not a control. Confirm from the gateway side, using the request tags.
- **This route.** It is documented and was not exercised during the build. `./harness/copilot-cli/launch.sh --explain` probes it on your workspace, which is the only answer that matters.

