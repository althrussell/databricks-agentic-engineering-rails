<!--
GENERATED FILE - do not edit.

Rendered from harness/shared/ by harness/scripts/render.py. Change the policy
there and run `make harness-generate`. `make harness-verify` fails the build if
this file was edited by hand, and says which of the two mistakes it was.
-->

# Claude Code, as rendered from `harness/shared/`

`harness/shared/` is the policy. Every file in this directory except `SETUP.md` is reproduced by `make harness-generate`, and `make harness-verify` fails if one has been edited by hand.

| | |
| :--- | :--- |
| Gateway route | `/ai-gateway/anthropic` (verified) |
| Model traffic through the gateway | yes |
| Never-automatic tier enforced | before the command runs, and journalled |
| Launcher | `ug claude`, or `./harness/claude-code/launch.sh` |

## Where each file goes

| File | Installs as | Notes |
| :--- | :--- | :--- |
| `settings.json` | `<project>/.claude/settings.json` | Project scope. Accept the trust dialog once per clone or every `allow` entry is discarded. |
| `mcp.json` | `<project>/.mcp.json` | Expands `${VAR}`, which `settings.json` does not. |
| `launch.sh` | `run in place` | Resolves the workspace, probes the route, sets the request tags. |
| `hooks/pretooluse-guard.sh` | `run in place` | Adapter around the shared classifier. |
| `hooks/mcp-auth-header.sh` | `run in place` | `headersHelper` for the governed MCP route. |

## How the never-automatic tier is enforced here

A `PreToolUse` hook calls `harness/shared/guards/never-automatic.sh`, which classifies the command on normalised text and writes one line to `.daer/guard-journal.jsonl` for every decision. This is the strongest enforcement of the five.

**Allowed with no prompt** (33)

- `Read`
- `Glob`
- `Grep`
- `Edit`
- `Write`
- `NotebookEdit`
- `Bash(git status:*)`
- `Bash(git diff:*)`
- `Bash(git log:*)`
- `Bash(git show:*)`
- `Bash(git add:*)`
- `Bash(git commit:*)`
- `Bash(git switch:*)`
- `Bash(git restore:*)`
- `Bash(git stash:*)`
- `Bash(git worktree:*)`
- `Bash(make check:*)`
- `Bash(make docs:*)`
- `Bash(make test:*)`
- `Bash(make e2e:*)`
- `Bash(make doctor:*)`
- `Bash(npm run:*)`
- `Bash(npm test:*)`
- `Bash(npm ci:*)`
- `Bash(pytest:*)`
- `Bash(uv run:*)`
- `Bash(python3 scripts/:*)`
- `WebFetch(domain:docs.databricks.com)`
- `WebFetch(domain:developers.databricks.com)`
- `WebFetch(domain:code.claude.com)`
- `mcp__databricks__get_current_user`
- `mcp__databricks__get_table_stats_and_schema`
- `mcp__databricks__list_compute`

**Prompts** (5)

- `Bash(git push:*)`
- `Bash(gh pr create:*)`
- `Bash(databricks:*)`
- `mcp__databricks__execute_sql`
- `mcp__databricks__manage_app`

**Refused by rule, and again by the guard** (8)

- `Bash(git push --force:*)`
- `Bash(git push -f:*)`
- `Bash(gh pr merge:*)`
- `Bash(gh pr ready:*)`
- `Bash(gh release create:*)`
- `Bash(databricks bundle deploy:*)`
- `Bash(databricks bundle destroy:*)`
- `Bash(security find-generic-password:*)`

## Capabilities not rendered as rules

The neutral policy names these; this harness expresses them another way. The renderer refuses to build unless the substituted mechanism is actually present in the file it produced.

### `tool(Bash)` (unclassified-shell)

Rendered as a rule this becomes a bare `Bash` ask entry, which outranks every narrower allow rule in the auto-allow tier and prompts for `git status`. The asking default mode does the job the tier wants: anything not explicitly allowed prompts.

- Substituted by `permissions.defaultMode` = `"default"`

### `mcp(*)` (unknown-mcp-tools)

`mcp__*` is accepted only as a deny or ask rule, and as an ask rule it outranks the named tool allows above it, so every approved read would prompt. The asking default mode covers the same ground: a tool that is not named in the allow list is not allowed, and prompts.

- Substituted by `permissions.defaultMode` = `"default"`

## What this harness cannot express

Stated here rather than left for a reader to discover from behaviour.

| | |
| :--- | :--- |
| permissions.defaultMode=acceptEdits or bypassPermissions | The looser modes do not take effect from project or local settings. A repo that wants one has to say so in its documentation and let a human choose it, which is the right shape for that decision anyway. |

## MCP

Server `databricks` on the governed route. 5 tools against a ceiling of 12.

```
${DAER_WORKSPACE_HOST}/ai-gateway/mcp-services/${DAER_MCP_SERVICE}
```

A per-connection `headersHelper` mints a fresh token for every MCP connection. It runs outside the harness's own command sandbox, as a direct child of the harness process, with the developer's full authority — so `.mcp.json` is a file whose edits are not routine.

`scripts/tool-budget.py --live` measures what the registration costs in context against the ceilings in `harness/shared/mcp.yml`, and reports where the allowlist and the server's advertised tools disagree — context spent on nothing in one direction, a policy line that constrains nothing in the other.

## Not proved here

- **Whether a session's own traffic reaches the model through the governed route.** The route is probed with a real HTTP call at launch; where a session sends its traffic is a different question. A session started with a deliberately invalid gateway token has been seen to answer normally by falling back to an ambient login. The environment the launcher sets is a default, not a control. Confirm from the gateway side, using the request tags.

