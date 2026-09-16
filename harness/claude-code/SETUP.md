# Claude Code — setup

Thirty minutes, on your own laptop, from nothing to a governed session. Prerequisites
are in `docs/01-prerequisites.md`; the short version is a Databricks CLI you have
logged in with, Python 3.9+, and this repository cloned.

## 1. Install

```sh
npm install -g @anthropic-ai/claude-code      # or: brew install claude-code
uv tool install git+https://github.com/databricks/unity-gateway
```

The second one is `ug`, the launcher that points a harness at Unity AI Gateway. It is
optional — `DAER_NO_UG=1` takes an environment-only path that writes no file anywhere —
but it is the shortest route and the one this pack assumes.

## 2. Check the machine before blaming the harness

```sh
./scripts/doctor.sh
```

Every row is a tool, a version and where to get it. Fix the red rows first. Roughly
half of "the agent is broken" turns out to be a missing CLI or an expired login.

## 3. Install the configuration

Nothing here is hand-written except this file. `make harness-generate` renders the rest
from `harness/shared/`, and `make harness-verify` fails if one of the rendered files has
been edited.

```sh
cp harness/claude-code/settings.json  .claude/settings.json
cp harness/claude-code/mcp.json       .mcp.json
```

Leave `launch.sh` and `hooks/` where they are: the hook paths resolve through
`${CLAUDE_PROJECT_DIR}` to `harness/shared/guards/never-automatic.sh`, so copying this
directory without `harness/shared/` produces a hook that denies every command and
explains why — safe, and useless.

**Accept the trust dialog once per clone.** Until you do, every `permissions.allow`
entry is discarded and the session queries every routine command. The harness says so
on one line that is easy to miss. Deny rules and hooks are unaffected, so nothing is
less safe; it only looks broken.

## 4. Start a session

```sh
export DAER_TEAM=your-team
export DAER_MCP_SERVICE=catalog.schema.your_mcp_service   # optional
./harness/claude-code/launch.sh --explain
./harness/claude-code/launch.sh
```

`--explain` resolves the profile, makes a real HTTP call to the gateway route and
prints what it would do without starting anything. Run it first on a new machine: it
turns "the model is erroring" into "this workspace does not expose that route", which
is a different conversation with a different person.

| Variable | Effect |
| :--- | :--- |
| `DAER_PROFILE` | Databricks CLI profile. Falls back to `DATABRICKS_CONFIG_PROFILE`, then `DEFAULT`. |
| `DAER_TEAM` | The `team` gateway request tag. Unset is recorded as `unset`, not omitted — untagged spend has no owner. |
| `DAER_MCP_SERVICE` | Unity Catalog name of the governed MCP service, `catalog.schema.name`. Unset means no MCP, stated at launch. |
| `DAER_NO_UG=1` | Take the environment-only path, which writes no user-scope file. |

## 5. Confirm the rails are live

```sh
./harness/scripts/deny-proof.sh
```

It runs the never-automatic classifier over a table of commands that must be refused
and commands that must not be, so a guard that denies everything fails as loudly as one
that denies nothing.

Inside a session, ask for something in the never-automatic tier — `git push --force`
is the usual one — and watch it be refused twice: once by the permission rule, once by
the hook, which writes a line to `.daer/guard-journal.jsonl` naming the rule that
fired.

## Where to look next

- [RENDER-NOTES.md](RENDER-NOTES.md) — the rendered tiers, what this harness cannot
  express, and what is not proved here. Read this before quoting any of it.
- [../shared/permissions.yml](../shared/permissions.yml) — the policy itself. Change it
  here, not in the generated output.
