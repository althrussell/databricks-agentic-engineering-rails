# harness/

Reference configuration for five coding harnesses. Copy the directory for the one you
use; ignore the rest.

Nothing here is generated and nothing here is ours to run. Each file is a small,
hand-maintained configuration in the harness's own documented format, so what you read
is what the harness reads — and you can diff it against your own config without
learning a build step first.

## The layout

| Path | What it is |
| :--- | :--- |
| `claude-code/`, `codex/`, `cursor/`, `copilot-cli/`, `opencode/` | One directory per harness: a `SETUP.md` and the two or three config files it tells you to copy. |

Each directory holds:

1. **`SETUP.md`** — the 30-minute path. Install, log in, point it at the gateway, copy
   the config, confirm it worked. Start here.
2. **A permission configuration** in that harness's own format — `settings.json`,
   `config.toml`, `cli.json`, `opencode.json`, or command-line flags where the harness
   has no file for it.
3. **An instruction file** — `AGENTS.md`, `CLAUDE.md`, `rails.mdc` or
   `copilot-instructions.md` — carrying the never-automatic tier in prose.

The last two are a pair, and the reason is worth stating once. A permission rule is
matched against the **text of a command**, so it stops the obvious spelling of an action
and not every spelling of it. The instruction file is the same tier written for the
model that is choosing what to run. Neither is sufficient alone. Change one, change the
other.

## The five are not equivalent

Two differences decide most of the choice between them.

**Model traffic through Unity AI Gateway** — whether your spend is attributable:

| Harness | Model traffic | How |
| :--- | :--- | :--- |
| Claude Code | Governed, verified | `ug claude` sets the Anthropic route; a real call returned 200 |
| Codex CLI | Governed, route not verified here | `ug codex` writes a provider block; the route 404'd on the workspace this was built against |
| OpenCode | Governed, route not verified here | `ug opencode` writes a provider block in `opencode.json` |
| Cursor CLI | **Not governed** | `ug cursor` registers MCP only; no documented custom model endpoint |
| Copilot CLI | **Not governed** | `ug copilot` registers MCP only; no documented custom model endpoint |

**What actually constrains the session**, as opposed to describing the constraint:

| Harness | The real fence |
| :--- | :--- |
| Codex CLI | `sandbox_mode = "workspace-write"` — writes are fenced to the working tree |
| OpenCode | `"*": "ask"` — an unlisted command is a prompt, not an allow |
| Claude Code | A `deny` list, matched on command text. No working-directory sandbox |
| Cursor CLI | A `deny` list, matched on command text |
| Copilot CLI | `--deny-tool` flags, present only if you started the session with them |

Read down the second table before quoting the first. A governed route tells you where
the spend is recorded; it says nothing about what the session can do to your machine.

## Where to start reading

- **Setting yourself up:** `<your harness>/SETUP.md`. Nothing else is required.
- **Deciding whether to trust it:** [`../docs/02-permissions.md`](../docs/02-permissions.md),
  and the "what this harness cannot express" section in your `SETUP.md`.
- **Understanding the gateway:** [`../docs/03-gateway-auth.md`](../docs/03-gateway-auth.md).
- **Why it is shaped this way:** [`../docs/DECISIONS/`](../docs/DECISIONS/).
