# harness/

One written policy, one implementation of it, four honest labels, and the scripts that
keep those three descriptions true.

## The layout

| Path | What it is |
| :--- | :--- |
| `shared/` | The policy. Permission tiers, the execution boundary, gateway routing, MCP registration and the guard, each written once in a harness-neutral vocabulary. |
| `claude-code/` | The reference harness. Every file generated from `shared/`, except its hand-written `README.md`. |
| `codex/`, `cursor/`, `copilot-cli/`, `opencode/` | Placeholders. A `STATUS.md` saying what is and is not claimed, and a `NOTES.md` with the open questions. No configuration, on purpose. |
| `scripts/` | Generate, verify, prove. |
| `evidence/` | What the verification scripts found when they last ran against a real workspace. |
| `PROMOTION.md` | What turns a placeholder into a supported harness. |

## The one rule

**Edit `shared/`, never a generated file.** `make harness-generate` renders; `make
harness-verify` fails the build if a generated file was touched by hand. The checker
separates two failures that produce an identical diff and mean opposite things — the
policy moved and nobody regenerated, or someone edited the output and is about to lose
the change — because a checker that reported both as "files differ" would train people
to run the generator until the message went away.

## Commands

| Command | What it does | Needs a workspace? |
| :--- | :--- | :--- |
| `make harness-generate` | Render `shared/` into each implemented harness | No |
| `make harness-verify` | Fail if a generated file drifted from the policy | No |
| `make harness-deny-proof` | Run the guard against 46 cases: 27 that must be denied, 19 that must be allowed | No |
| `make boundary-proof` | Attempt what the boundary should refuse, and report what happened | No |
| `make harness-verify-sandbox PROFILE=x` | Thirteen assertions against a live workspace, and write the evidence file | **Yes** |

The first four are in `make check`. The last is not: it spends money, needs a
credential, and reports on whichever boundary it happens to be inside — so a pass or
fail would mean different things on different machines.

## Why four directories contain no configuration

Because a generated config for a harness nobody has run would put a fifth row in the
support matrix that looks exactly like the row for the one that works. `render.py`
refuses by name for those four and says why. The support level a harness gets is the
one its evidence file supports, which for two of the four may permanently be "tools
governed, model spend metered elsewhere" — a real answer, and better than a checkmark
that means two different things in two different rows.

## Where to start reading

- Adopting this in your own repository: `claude-code/README.md`, then `shared/README.md`.
- Deciding whether to trust it: `evidence/verify-in-sandbox.md`, and specifically its
  closing section on what the run did not prove.
- Adding a harness: `PROMOTION.md`, then the `NOTES.md` of the one you want.
- Understanding why it is built this way: `../docs/DECISIONS/`.
