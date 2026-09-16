# Prerequisites

Everything below installs on a laptop you already own, with no admin ticket and no
sandbox. Run the checker first — it tells you which rows you actually need.

```sh
./scripts/doctor.sh
```

Each row is a tool, the version found, the version this pack was built against, and
where to get it. It exits non-zero only when something required is missing, so a yellow
row is information, not a blocker.

## Required for any harness

| Tool | Why | Install |
| :--- | :--- | :--- |
| `git` | Everything | Preinstalled on macOS after `xcode-select --install`; your package manager on Linux |
| `databricks` CLI | Authentication, and minting the short-lived token MCP uses | `brew install databricks`, or the CLI docs in [`SOURCES.md`](SOURCES.md) |
| `python3` 3.12+ | `ug` is a Python tool. Also the one-liner that reads a token out of the CLI's JSON | Preinstalled on macOS; `apt install python3` |
| A POSIX shell | The two scripts here are `sh`, not `bash` | Already there |
| `curl` | Link checking, and probing a gateway route by hand | Already there |

Then log in once:

```sh
databricks auth login --host https://your-workspace.cloud.databricks.com --profile your-profile
databricks auth token --profile your-profile     # should print a token, not an error
```

Then set the profile once, in your shell profile:

```sh
export DATABRICKS_CONFIG_PROFILE=your-profile
```

That is the Databricks CLI's own variable, so every `databricks` command and everything
built on the SDK picks up the same profile and you stop passing `--profile` by hand.

## Required for the governed path

```sh
uv tool install git+https://github.com/databricks/unity-gateway
```

That provides `ug`, also installed as `ucode`, which points a harness at Unity AI
Gateway. It is the supported Databricks tool for this and it is what your `SETUP.md` will
tell you to run.

Two things to know before you run it. It **writes into your own user-scope harness
configuration** — for Claude Code, `~/.claude/ucode-settings.json` and the `env` block of
`~/.claude/settings.json` — which is correct for configuring your own laptop but is your
config it changes, not a file in this repository. And it mints a short-lived token, so
`ug --refresh` is the command for a session that has started failing in a way that looks
like a model error.

`uv` itself: `curl -LsSf https://astral.sh/uv/install.sh | sh`.

## Your harness

One of these. The setup pages cover the rest.

| Harness | Install |
| :--- | :--- |
| Claude Code | `npm install -g @anthropic-ai/claude-code` |
| Codex CLI | `npm install -g @openai/codex` |
| Cursor CLI | `curl https://cursor.com/install -fsS \| bash` |
| GitHub Copilot CLI | `npm install -g @github/copilot` |
| OpenCode | `curl -fsSL https://opencode.ai/install \| bash` |

## Your editor

Use whichever one you already use. A harness is a process, and what governs a session is
the environment it was started in — not what you edit files with.

If that editor is VS Code, start the harness in its **integrated terminal**. That
terminal is a child shell, so it inherits whatever `ug` configured for your user, exactly
as a standalone terminal does. There is nothing extra to install and nothing extra to
configure.

The VS Code **extensions** for Claude Code and Codex are a different route, and this pack
does not cover them. VS Code starts an extension, so its traffic is shaped by whatever
environment VS Code itself resolved, which varies with how VS Code was launched. That is
not a claim that extensions bypass the gateway. It is a claim that nobody here has proved
it either way, and the only thing that settles it is the gateway-side query in
[`03-gateway-auth.md`](03-gateway-auth.md).

## Optional, and what you lose without it

Nothing in this column is needed to set yourself up. These are for running this
repository's own checks, which only matters if you are changing it.

| Tool | Needed for | Without it |
| :--- | :--- | :--- |
| `python3` | `make config` — validating the example configs | The lane exits 2 rather than claiming a pass it did not earn |
| `shellcheck` | `make lint` | The shell scripts are parsed but not linted |
| `make` | Every convenience lane | Run the commands the Makefile runs; they are all one-liners |

`brew install shellcheck`.

## The two failures worth recognising early

**An expired login looks like a broken agent.** A session whose token has expired
reports a model error, not an authentication error, because by then the harness is several
layers away from the CLI. `databricks auth token` is the one-second test;
`./scripts/doctor.sh --live` is the ten-second one. `ug --refresh` re-mints.

**A route your workspace does not expose looks like a broken harness.** Gateway routes are
enabled per workspace, so a route that answers for a colleague can 404 for you. A 404 is
an administrator's answer, not yours — [`03-gateway-auth.md`](03-gateway-auth.md) has the
table of what each status code means and who fixes it.
