<!--
GENERATED FILE - do not edit.

Rendered from harness/shared/ by harness/scripts/render.py. Change the policy
there and run `make harness-generate`. `make harness-verify` fails the build if
this file was edited by hand, and says which of the two mistakes it was.
-->

# OpenCode, as rendered from `harness/shared/`

`harness/shared/` is the policy. Every file in this directory except `SETUP.md` is reproduced by `make harness-generate`, and `make harness-verify` fails if one has been edited by hand.

| | |
| :--- | :--- |
| Gateway route | `/ai-gateway/mlflow/v1` (documented) |
| Model traffic through the gateway | **no** — see below |
| Never-automatic tier enforced | by pattern, in three verdicts |
| Launcher | `ug opencode`, or `./harness/opencode/launch.sh` |

## Where each file goes

| File | Installs as | Notes |
| :--- | :--- | :--- |
| `opencode.json` | `<project>/opencode.json` | Project scope, and it expands `{env:VAR}` — so no placeholder to fill in. |
| `AGENTS.md` | `<project>/AGENTS.md` | Where the never-automatic tier is stated. |
| `launch.sh` | `run in place` | Probes the MCP route and reports what the gateway sees. |

## How the never-automatic tier is enforced here

`permission.bash` maps a glob to `allow`, `ask` or `deny`, which is the closest of the five to the shape of the policy. The patterns are written most specific first, so a deploy is refused rather than merely queried whether this harness takes the first match or the most specific one. It is still pattern matching on command text, so the guard is worth running in CI over anything scripted.

**bash patterns** (33)

- `security find-generic-password*` → deny
- `databricks bundle destroy*` → deny
- `databricks bundle deploy*` → deny
- `gh release create*` → deny
- `git push --force*` → deny
- `python3 scripts/*` → allow
- `gh pr create*` → ask
- `git worktree*` → allow
- `gh pr merge*` → deny
- `gh pr ready*` → deny
- `git push -f*` → deny
- `git restore*` → allow
- `make doctor*` → allow
- `databricks*` → ask
- `git commit*` → allow
- `git status*` → allow
- `git switch*` → allow
- `make check*` → allow
- `git stash*` → allow
- `make docs*` → allow
- `make test*` → allow
- `git diff*` → allow
- `git push*` → ask
- `git show*` → allow
- `make e2e*` → allow
- `npm test*` → allow
- `git add*` → allow
- `git log*` → allow
- `npm run*` → allow
- `npm ci*` → allow
- `pytest*` → allow
- `uv run*` → allow
- `*` → ask

## What this harness cannot express

Stated here rather than left for a reader to discover from behaviour.

| | |
| :--- | :--- |
| per-tool MCP permissions | `mcp.<name>.enabled` turns a server on. Which of its tools may be called is decided by Unity Catalog grants on the MCP service, so grant narrowly. |
| net.fetch(host) scoping | `permission.webfetch` is one verdict for every host, so it is set to `ask` rather than allowing the documentation hosts the policy names. |
| the never-automatic tier, before the command runs | A `deny` verdict on a bash pattern refuses the canonical spelling, which is more than three of the five harnesses manage. It is still pattern matching on command text: the tier is also written into `AGENTS.md`. |

## MCP

Server `databricks` on the governed route. 5 tools against a ceiling of 12.

```
{env:DAER_WORKSPACE_HOST}/ai-gateway/mcp-services/{env:DAER_MCP_SERVICE}
```

`{env:DAER_MCP_TOKEN}` is expanded by OpenCode at connect time from the environment `launch.sh` sets. The token is minted once at launch and expires with it.

`scripts/tool-budget.py --live` measures what the registration costs in context against the ceilings in `harness/shared/mcp.yml`, and reports where the allowlist and the server's advertised tools disagree — context spent on nothing in one direction, a policy line that constrains nothing in the other.

## Not proved here

- **Whether a session's own traffic reaches the model through the governed route.** The route is probed with a real HTTP call at launch; where a session sends its traffic is a different question. A session started with a deliberately invalid gateway token has been seen to answer normally by falling back to an ambient login. The environment the launcher sets is a default, not a control. Confirm from the gateway side, using the request tags.
- **This route.** It is documented and was not exercised during the build. `./harness/opencode/launch.sh --explain` probes it on your workspace, which is the only answer that matters.

