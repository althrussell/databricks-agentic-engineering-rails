# harness/

One written policy, five renderings of it, and the scripts that keep those
descriptions true.

## The layout

| Path | What it is |
| :--- | :--- |
| `shared/` | The policy. Permission tiers, gateway routing, MCP registration and the guard, each written once in a harness-neutral vocabulary. |
| `claude-code/`, `codex/`, `cursor/`, `copilot-cli/`, `opencode/` | One directory per harness. Every file generated from `shared/`, except the hand-written `SETUP.md`. |
| `scripts/` | Generate, verify, prove. |

Each harness directory carries three things worth reading in this order:

1. **`SETUP.md`** — the 30-minute path. Install, configure, launch, verify. Written
   by hand, because an install path is prose and the generator has no business
   inventing it.
2. **`RENDER-NOTES.md`** — generated. What this harness *cannot* express, and what
   was substituted rather than rendered. Read it before you trust the config.
3. **`.generated.sha256`** — the manifest `verify.sh` checks against.

## The one rule

**Edit `shared/`, never a generated file.** `./harness/scripts/generate.sh` renders;
`./harness/scripts/verify.sh` fails the build if a generated file was touched by
hand. The checker separates two failures that produce an identical diff and mean
opposite things — the policy moved and nobody regenerated, or someone edited the
output and is about to lose the change — because a checker that reported both as
"files differ" would train people to run the generator until the message went away.

One inputs digest covers all five directories, because they share a launcher
template. Editing `shared/` therefore marks every directory stale at once, which is
correct: the policy moved, so every rendering of it is out of date.

## Commands

| Command | What it does | Needs a workspace? |
| :--- | :--- | :--- |
| `make harness-generate` | Render `shared/` into all five harness directories | No |
| `make harness-verify` | Fail if a generated file drifted from the policy | No |
| `make harness-deny-proof` | Run the guard against 46 cases: 27 that must be denied, 19 that must be allowed | No |
| `make tool-budget` | Measure what the MCP registration costs in context, against the stated ceilings | No |
| `make tool-budget-live PROFILE=x` | The same, with the tool schemas measured from the live governed route rather than estimated | **Yes** |

The first four are in `make check`. The last is not: it needs a credential and a
workspace, so a pass would mean different things on different machines.

## The five are not equivalent

They are all generated, and they do not all enforce the same things. Two differences
decide most of it:

- **Model traffic through Unity AI Gateway.** Claude Code, Codex and OpenCode: yes.
  Cursor: no — `ug cursor` registers MCP servers only. Copilot CLI: no.
- **The never-automatic tier.** Claude Code enforces it with a `PreToolUse` hook.
  OpenCode expresses it as a `deny` verdict. Cursor has a deny list but no ask tier.
  Copilot CLI carries it as launch flags. Codex has no rule list and no hook at all,
  so its never-automatic tier is written into `AGENTS.md` and enforced by a human
  reading the diff.

`docs/00-start-here.md` has the full comparison table. Each harness's own
`RENDER-NOTES.md` says the same thing about that harness and nothing about the
others, so you cannot mistake one for another.

## Where to start reading

- **Setting yourself up:** `<your harness>/SETUP.md`. Nothing else is required.
- **Deciding whether to trust it:** `<your harness>/RENDER-NOTES.md`, and
  specifically its closing section on what was not proved.
- **Changing the policy:** `shared/README.md`.
- **Understanding why it is built this way:** `../docs/DECISIONS/`.
