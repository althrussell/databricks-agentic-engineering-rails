<!--
GENERATED FILE - do not edit.

Rendered from harness/shared/ by harness/scripts/render.py. Change the policy
there and run `make harness-generate`. `make harness-verify` fails the build if
this file was edited by hand, and says which of the two mistakes it was.
-->

# Claude Code, as rendered from `harness/shared/`

This directory is output. `harness/shared/` is the policy, and every file
here except `README.md` is reproduced by `make harness-generate`.
`make harness-verify` fails if one has been edited by hand.

## Where each file goes

| File | Installs as | Notes |
| :--- | :--- | :--- |
| `settings.json` | `<project>/.claude/settings.json` | Project scope. Two of its
sibling keys deliberately are not here; see the table below. |
| `mcp.json` | `<project>/.mcp.json` | Expands `${VAR}`, which `settings.json`
does not. |
| `launch.sh` | run in place | Resolves the workspace, probes the gateway route,
injects what project scope cannot deliver. |
| `hooks/pretooluse-guard.sh` | run in place | Adapter around the shared
classifier. |
| `hooks/mcp-auth-header.sh` | run in place | `headersHelper` for the governed
MCP route. |

The paths in `settings.json` are relative to the repository root through
`${CLAUDE_PROJECT_DIR}`, so a team that copies `harness/` wholesale into their
own project gets working hooks with no edit. A team that copies only
`harness/claude-code/` gets a hook that denies everything and says why, which
is the intended failure.

## The permission tiers as rendered

Default mode `default`: anything not named below prompts.

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

### What the deny rules do not catch

A `Bash(...)` rule matches the text of the command as written. The deny rules
above stop the canonical spelling of each never-automatic action and miss the
same action written with a global option before the subcommand, with the
subcommand quoted, or with the flag moved to the end. That is why the tier is
also enforced by `harness/shared/guards/never-automatic.sh`, which normalises
the text first and is held to `harness/shared/guards/cases.tsv` by
`make harness-deny-proof`. The rules are the fast path; the guard is the one
that has been tested against the awkward spellings.

## Capabilities not rendered as rules

The neutral policy names these; this harness expresses them another way. The
renderer refuses to build unless the substituted mechanism is actually present
in the file it produced.

### `tool(Bash)` (unclassified-shell)

Rendered as a rule this becomes a bare `Bash` ask entry, which outranks every narrower allow rule in the auto-allow tier and prompts for `git status`. It is also skipped for commands that run inside the sandbox, so it would be simultaneously too broad and too narrow. The asking default mode does the job the tier wants - anything not explicitly allowed prompts - and autoAllowBashIfSandboxed keeps that true for sandboxed commands, which otherwise run without a prompt.

- Substituted by `permissions.defaultMode` = `"default"`
- Substituted by `sandbox.autoAllowBashIfSandboxed` = `false`

### `mcp(*)` (unknown-mcp-tools)

`mcp__*` is accepted only as a deny or ask rule, and as an ask rule it outranks the named tool allows above it, so every approved read would prompt. The asking default mode covers the same ground: a tool that is not named in the allow list is not allowed, and prompts.

- Substituted by `permissions.defaultMode` = `"default"`

## Keys this scope would ignore

Written into a repository's own settings file, each of these reads as enforced
and does nothing. The renderer refuses to emit them here.

| Key | Why not, and where it goes instead |
| :--- | :--- |
| `sandbox.network.strictAllowlist` | Takes effect only from user, managed or `--settings` scope. Set in a project file it silently does nothing, and the allowlist prompts for an unlisted host instead of denying it. Delivered by launch.sh through `--settings`. |
| `sandbox.filesystem.disabled` | Cannot be set from a project file at all, which is correct - a checked-out repository must not be able to switch filesystem isolation off. Listed here so nobody adds it later expecting it to work. |
| `permissions.defaultMode=auto` | The looser modes do not take effect from project or local settings. A repo that wants one has to say so in its documentation and let a human choose it, which is the right shape for that decision anyway. |
| `permissions.defaultMode=bypassPermissions` | Same as auto, and for a stronger reason: a repository that could turn the permission system off for whoever cloned it is a supply-chain vector. |
| `sandbox.credentials mask entries` | A `mask` entry authorises the sandbox proxy to send a real credential to a named host, so it is honoured only from settings the human or their administrator controls. Every credential entry this renderer writes is `deny`, which any scope may add. |

## MCP

Servers: databricks. Tools allowed: 5 against a ceiling of 12; servers 1 against 3.

The registration carries no tool allowlist of its own. Which tools may be
called is decided by the permission rules above, and the renderer fails if the
two files disagree about which tools exist. `scripts/tool-budget.py --live`
measures the context cost against the ceilings, by asking the governed route
what its tools actually cost - and reports where the allowlist and the
server's advertised tools disagree, which is context spent on nothing in one
direction and a policy line that constrains nothing in the other.

## Proved, and worth knowing

From `harness/evidence/verify-in-sandbox.md`, which is what
`make harness-verify-sandbox` writes when it runs against a real workspace.

- **`headersHelper` runs outside the Bash sandbox**, as a direct child of the
  harness process. It was observed reading `~/.databrickscfg`, minting a token
  and reaching a host on no allowlist. So the `credentials.files` deny entry
  above does not break MCP authentication - that was the open question - but the
  helper is a command named in `.mcp.json` that runs with the developer's full
  authority and outside every boundary configured here. Treat it as trusted
  code: `.mcp.json` belongs in the set of files whose edits are not automatic.
- **These rules load only in a trusted project.** Until the trust dialog is
  accepted, every `permissions.allow` entry is dropped and the harness says so
  on one easily missed line. Deny rules and hooks keep working, so the failure
  is toward refusing, but a clone where nobody accepted the dialog queries every
  routine command and looks broken.

## Not yet proved

Stated here rather than left for a reader to discover:

- Whether a *session* reaches the model through the governed route. The route
  itself is proved by a real call over HTTP; where a session sends its traffic
  is a different question, and a session started with a deliberately invalid
  gateway token has been seen to answer normally by falling back to an ambient
  login. The environment variables `launch.sh` sets are a default, not a
  control. Enforce the route with managed settings, and confirm it from the
  gateway side using the request tags.
- Whether the four placeholder harnesses can express these tiers at all. Until
  one is rendered and run, `harness/PROMOTION.md` is a checklist and not a
  claim.

