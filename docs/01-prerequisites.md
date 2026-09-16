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
| `python3` 3.9+ | The generator, the doctor, the budget check | Preinstalled on macOS; `apt install python3` |
| `databricks` CLI | Authentication, and the token the launchers mint | `brew install databricks` or see the CLI docs in `docs/SOURCES.md` |
| A POSIX shell | The launchers and guards are `sh`, not `bash` | Already there |
| `curl` | Route probing, link checking | Already there |

Then log in once:

```sh
databricks auth login --host https://your-workspace.cloud.databricks.com --profile your-profile
databricks auth token --profile your-profile     # should print a token, not an error
```

Set `DAER_PROFILE=your-profile` in your shell profile, or pass it per session. The
launchers fall back to `DATABRICKS_CONFIG_PROFILE`, then to `DEFAULT`.

## Required for the governed path

```sh
uv tool install git+https://github.com/databricks/unity-gateway
```

That provides `ug` (also aliased `ucode`), which points a harness at Unity AI Gateway.
It writes user-scope configuration for the harness you name, which is why the launchers
say so before invoking it and why `DAER_NO_UG=1` exists for people who would rather not.

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

Use whichever one you already use. A harness is a process; a launcher sets the gateway
environment and `exec`s it, so what governs a session is how it was started and not
what you edit files in.

If that editor is VS Code, run the launcher in its **integrated terminal**:

```sh
./harness/claude-code/launch.sh
```

The integrated terminal is a child shell, so the environment the launcher sets applies
to the session exactly as it does in a standalone terminal. There is nothing extra to
install and nothing extra to configure.

The VS Code **extensions** for Claude Code and Codex are a different route, and this
pack does not cover them. VS Code starts an extension, not the launcher, so whether one
picks up the gateway environment depends on how VS Code resolved its own — which varies
with how VS Code itself was started. That is not a claim that extensions bypass the
gateway. It is a claim that this pack has not proved it either way, and the only thing
that settles it is the gateway-side query in `docs/03-gateway-auth.md`.

## Optional, and what you lose without it

| Tool | Needed for | Without it |
| :--- | :--- | :--- |
| `pyyaml` | `make harness-generate`, `scripts/tool-budget.py` | You can still run `make harness-verify`, which is deliberately dependency-free |
| `pandoc`, `typst` | `make docs` — the PDF build | The Markdown is the source and reads fine |
| `shellcheck` | `make lint` | Nothing checks the shell scripts |
| `make` | Every convenience lane | Run the commands the Makefile runs; they are all one-liners |

`pip install pyyaml`, `brew install pandoc typst shellcheck`.

## The two failures worth recognising early

**An expired login looks like a broken agent.** A session whose token has expired
reports a model error, not an authentication error, because by then the harness is
several layers away from the CLI. `databricks auth token --profile your-profile` is the
one-second test, and `./harness/<name>/launch.sh --explain` is the ten-second one.

**A route your workspace does not expose looks like a broken harness.** Gateway routes
are enabled per workspace. A 404 from a probe is an administrator's answer, not yours —
`docs/03-gateway-auth.md` says which one to ask for.
