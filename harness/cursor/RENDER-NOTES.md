<!--
GENERATED FILE - do not edit.

Rendered from harness/shared/ by harness/scripts/render.py. Change the policy
there and run `make harness-generate`. `make harness-verify` fails the build if
this file was edited by hand, and says which of the two mistakes it was.
-->

# Cursor CLI, as rendered from `harness/shared/`

`harness/shared/` is the policy. Every file in this directory except `SETUP.md` is reproduced by `make harness-generate`, and `make harness-verify` fails if one has been edited by hand.

| | |
| :--- | :--- |
| Gateway route | `/ai-gateway/cursor/v1` (documented) |
| Model traffic through the gateway | **no** — see below |
| Never-automatic tier enforced | by rule for deny, by review for the rest |
| Launcher | `ug cursor`, or `./harness/cursor/launch.sh` |

## Where each file goes

| File | Installs as | Notes |
| :--- | :--- | :--- |
| `cli.json` | `<project>/.cursor/cli.json` | Allow and deny. There is no ask list; not-allowed prompts. |
| `mcp.json` | `<project>/.cursor/mcp.json` | Fill in the two placeholders; see SETUP.md. |
| `rules/rails.mdc` | `<project>/.cursor/rules/rails.mdc` | Always-applied rule carrying the never-automatic tier. |
| `launch.sh` | `run in place` | Probes the MCP route and reports what the gateway does and does not see for this harness. |

## How the never-automatic tier is enforced here

The `deny` list refuses the canonical spelling of each never-automatic action. No pre-execution hook is documented, so an unusual spelling is caught by the always-applied rule and the person reading the diff, not by a program.

**Allowed with no prompt** (23)

- `Read(**)`
- `Write(**)`
- `Shell(git status)`
- `Shell(git diff)`
- `Shell(git log)`
- `Shell(git show)`
- `Shell(git add)`
- `Shell(git commit)`
- `Shell(git switch)`
- `Shell(git restore)`
- `Shell(git stash)`
- `Shell(git worktree)`
- `Shell(make check)`
- `Shell(make docs)`
- `Shell(make test)`
- `Shell(make e2e)`
- `Shell(make doctor)`
- `Shell(npm run)`
- `Shell(npm test)`
- `Shell(npm ci)`
- `Shell(pytest)`
- `Shell(uv run)`
- `Shell(python3 scripts/)`

**Refused by rule** (8)

- `Shell(git push --force)`
- `Shell(git push -f)`
- `Shell(gh pr merge)`
- `Shell(gh pr ready)`
- `Shell(gh release create)`
- `Shell(databricks bundle deploy)`
- `Shell(databricks bundle destroy)`
- `Shell(security find-generic-password)`

## What this harness cannot express

Stated here rather than left for a reader to discover from behaviour.

| | |
| :--- | :--- |
| the ask tier as a list | `.cursor/cli.json` takes `allow` and `deny` and has no third verdict. That turns out to be the right shape: anything not allowed prompts, so the ask tier is the default and is deliberately absent from the file rather than missing from it. |
| per-tool MCP permissions | The registration in `.cursor/mcp.json` enables a server, not a tool list. Which of the server's tools may be called is decided by Unity Catalog grants on the MCP service, not here — so grant narrowly. |
| net.fetch(host) scoping | No per-host fetch permission is documented for the CLI. |
| model routing through the gateway | `ug cursor` configures MCP only, and no environment variable for a custom model endpoint is documented. So Cursor's tools come under governance and its model spend is metered by whatever your Cursor licence bills. This is the one harness here whose model traffic the gateway does not see, and the launcher says so at startup. |

## MCP

Server `databricks` on the governed route. 5 tools against a ceiling of 12.

```
https://REPLACE-WITH-YOUR-WORKSPACE-HOST/ai-gateway/mcp-services/REPLACE.WITH.YOUR_MCP_SERVICE
```

A static `Authorization` header referencing `DAER_MCP_TOKEN`. Whether Cursor expands an environment variable in that position is **not exercised here**; if the server fails to connect, paste the output of `databricks auth token` into your own local copy and re-mint it when it expires.

`scripts/tool-budget.py --live` measures what the registration costs in context against the ceilings in `harness/shared/mcp.yml`, and reports where the allowlist and the server's advertised tools disagree — context spent on nothing in one direction, a policy line that constrains nothing in the other.

## Not proved here

- **Whether a session's own traffic reaches the model through the governed route.** The route is probed with a real HTTP call at launch; where a session sends its traffic is a different question. A session started with a deliberately invalid gateway token has been seen to answer normally by falling back to an ambient login. The environment the launcher sets is a default, not a control. Confirm from the gateway side, using the request tags.
- **This route.** It is documented and was not exercised during the build. `./harness/cursor/launch.sh --explain` probes it on your workspace, which is the only answer that matters.

