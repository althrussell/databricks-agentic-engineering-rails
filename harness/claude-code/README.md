# Claude Code — the reference harness

This is the one harness in this pack that is implemented rather than described. Its
configuration is not written here; it is rendered from `harness/shared/` by
`make harness-generate`, and `make harness-verify` fails the build if anyone edits the
output. This file and nothing else in this directory is hand-written.

Read `RENDER-NOTES.md` next to it for the rendered permission tiers, the capabilities
that could not be expressed as rules and what stands in for them, and the list of
settings keys that a repository's own file is not allowed to deliver.

## Start a session

```sh
make harness-generate          # only after changing harness/shared/
./harness/claude-code/launch.sh --explain
./harness/claude-code/launch.sh
```

`--explain` resolves the profile, probes the gateway route and prints what it would
do. Run it first on a new machine: it turns "the model is erroring" into "this
workspace does not expose that route", which is a different conversation with a
different person.

**Accept the trust dialog once per clone.** Until you do, every `permissions.allow`
entry in `settings.json` is discarded — the harness says so on one line that is easy
to miss — and the session queries every routine command. Deny rules and hooks are
unaffected, so nothing becomes less safe; it just looks broken. Starting a session
interactively in the directory once is enough.

Three environment variables change what the launcher does. None of them is required
for a session to start.

| Variable | Effect |
| :--- | :--- |
| `DAER_PROFILE` | Databricks CLI profile to authenticate with. Default `DEFAULT`. |
| `DAER_TEAM` | The `team` gateway request tag. Unset is recorded as `unset`, not omitted. |
| `DAER_MCP_SERVICE` | Unity Catalog name of the governed MCP service, `catalog.schema.name`. Unset means no MCP, stated at launch. |
| `DAER_NO_UG=1` | Take the environment-only launch path, which writes no file anywhere. |

## What is actually enforced, and by what

Four mechanisms, listed because they fail independently and a reader should know which
one they are relying on at any moment.

| Mechanism | Enforces | Fails when |
| :--- | :--- | :--- |
| `settings.json` permission rules | The canonical spelling of each tier | The command is spelled unusually |
| `hooks/pretooluse-guard.sh` → `harness/shared/guards/never-automatic.sh` | The never-automatic tier, on normalised text, with a journal entry | The action is expressed as data: base64, a written-then-run script, a runtime's own process API |
| `settings.json` sandbox block | Reads of credential paths, egress to unlisted hosts, the unsandboxed retry | The platform has no sandbox — which is why `failIfUnavailable` is on, so that becomes a startup failure rather than a silent downgrade |
| The container in `.devcontainer/` | Everything above, at the OS level, on a filesystem that holds no credential of yours | It is a verified recipe and not yet a verified environment — see the gap register |

The first two are a pair and are meant to be read as one. A permission rule matches
text and leaves no record; the guard normalises the text first and writes a line to
`.daer/guard-journal.jsonl` for every decision it makes. Deploy both. A tier enforced
only by rules is bypassed by a spelling; a tier enforced only by a guard is bypassed by
a broken interpreter, which is why the guard's adapter denies rather than allows when
it cannot run.

## What has actually been run against a workspace

```sh
make harness-verify-sandbox PROFILE=your-profile
```

Thirteen assertions in five stages: that these files are the generator's output and
not a hand edit, that a token can be minted, that a real model call goes through the
governed route *and the same call with an invalid token is refused*, where the
`.mcp.json` header helper runs, and that the never-automatic tier refuses inside a
live session and journals which rule fired. It writes
`harness/evidence/verify-in-sandbox.md` with the workspace host reduced to a shape.

It runs its sessions in a scratch project outside this repository with its own
`CLAUDE_CONFIG_DIR`, and asserts afterwards that your own `~/.claude.json` was neither
modified nor given an entry. Read the last section of the evidence file before quoting
any of it: three things the run deliberately does not prove are listed there, and the
most important is that a session's own traffic reaching the gateway is *not* among
what was proved.

## What this configuration does not claim

- **It does not solve prompt injection.** Every mechanism above limits the blast radius
  of an injection that has already succeeded. None of them prevents one.
- **The permission rules are not a security boundary.** They are the difference between
  an accident and a deliberate act. `harness/shared/boundary.yml` is where capability
  is actually removed.
- **`~/.claude` is denied to sandboxed commands on purpose.** An agent that can rewrite
  its own permission rules does not have permission rules. The same applies to
  `~/.codex`.
- **Nothing here touches your live configuration.** No script in this repository writes
  to `~/.claude`, `~/.codex` or a managed settings file. `launch.sh` will use `ug` when
  it is installed, which does write user-scope configuration; it says so before doing
  it, and `DAER_NO_UG=1` avoids it entirely.

## Copying this into your own project

Copy `harness/` wholesale, not `harness/claude-code/` alone. The hook paths resolve
through `${CLAUDE_PROJECT_DIR}` to `harness/shared/guards/never-automatic.sh`, so a
partial copy produces a hook that denies every command and explains why — safe, and
useless. Then:

- `settings.json` → `.claude/settings.json`
- `mcp.json` → `.mcp.json`
- keep `launch.sh` and `hooks/` where they are

`docs/02-harness-standard.md` covers the same ground for a team that wants the standard
without this repository.
