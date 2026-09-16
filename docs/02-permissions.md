# Permissions

Three tiers. Whichever harness you use, the policy is one short file you can read in a
sitting — that is deliberate, because a permission policy nobody has read is a
permission policy nobody follows. The reference copies are in
[`harness/`](../harness/), one per harness, in each harness's own format.

## The three tiers

**Auto-allow.** Runs with no prompt. Reading files, local git that cannot leave the
machine, the project's own build and test commands, and a named list of MCP reads. The
test for this tier is *if the agent does this a hundred times and I never look, am I
still fine?* — which is why `git commit` is here and `git push` is not.

**Ask.** Prompts. Pushing a branch, opening a draft PR, anything against the workspace,
and — importantly — every command not otherwise named. This is the tier that does the
work. A policy with a good allow list and no asking default is a policy that permits
everything it forgot to mention.

**Never automatic.** Refused, and not by a prompt. Rewriting published history, merging
or releasing, deploying, reading credentials out of the keychain, messaging a person,
destruction outside the repository. Each one fails in a way the person who clicked
"allow" cannot undo. These are not "dangerous, so ask twice" — they are "not the agent's
to do".

## Why the middle tier is the important one

Everyone's instinct is to spend the effort on the deny list. The deny list is easy: the
actions are obvious and there are eight of them. The allow list is where the real
decision is, because **every prompt you make routine is a prompt someone will stop
reading**. Approve `git status` fifty times a day and by week two you are approving
whatever appears in that dialog. So the allow list is generous where the action is
reversible and empty where it is not, and the asking default catches the rest.

That is also why the never-automatic tier is not implemented as an ask. An action that
cannot be undone should not be reachable by a keystroke that has become muscle memory.

## The five harnesses do not enforce the same things

The tiers above are the same everywhere. What a harness can do about them is not, and
the difference decides which one you should use for work that matters.

| Harness | Auto-allow | Ask | Never automatic |
| :--- | :--- | :--- | :--- |
| Claude Code | `permissions.allow` | `permissions.ask` | `permissions.deny` — a text match |
| OpenCode | `permission.bash` allow | `"*": "ask"` catch-all | `deny` verdicts — a text match |
| Cursor CLI | `permissions.allow` | by omission, not by statement | `permissions.deny` — a text match |
| Codex CLI | `approval_policy` | `approval_policy` | **nothing** — prose in `AGENTS.md` only |
| Copilot CLI | `--allow-tool` flags | default | `--deny-tool` flags, if you passed them |

Codex is the row to read twice. It has no rule list and no pre-execution hook, so its
never-automatic tier is a paragraph in `AGENTS.md` and a human reading the diff. That is
a real cost, and it is the reason the tier is also written in prose for every harness:
prose is the only mechanism all five share.

## What actually enforces this, and what merely describes it

This is the distinction worth carrying away from the page.

**A permission rule is a text match.** It is matched against the command the model
wrote, after the harness splits compound commands and strips a short list of wrappers.
It is not a boundary around the program. A rule anchored on `git push --force` stops
that spelling and not `git -c x=y push --force`, not a quoted subcommand, not a flag
moved after the refspec. Rules stop the accident, which is most of what happens. They do
not stop an adversary, and nothing in a config file will.

**A sandbox removes the capability.** Codex's `sandbox_mode = "workspace-write"` fences
writes to the directory the session started in. That is a different kind of statement
from a deny list: it does not need to predict the spelling. Of the five harnesses it is
the only one here with a fence of that kind, which is worth weighing against its empty
cell in the table above.

**An asking default catches what the list forgot.** OpenCode's `"*": "ask"` is the
cheapest strong control in this whole document. Anything not named is a prompt, so a
rule missing from the allow tier costs one keystroke instead of opening a hole.

**An instruction file is not enforcement.** `CLAUDE.md`, `AGENTS.md` and `rails.mdc`
state the tier for the model that is choosing what to run. That genuinely changes
behaviour and it is not a control: a model can be argued out of it, and content in a
file it reads can do the arguing. Ship it as well as the rules, never instead of them.

An earlier version of this pack shipped a pre-execution hook of its own that normalised
command text before matching it. It was removed along with the rest of the custom code
— see [`DECISIONS/0006`](DECISIONS/0006-guidance-over-machinery.md) — and its removal is
why this section is blunter than it used to be. What you have is text matching plus, on
one harness, a real fence. Plan for that rather than for what a diagram promises.

## The limits, stated plainly

- **None of this prevents prompt injection.** It limits what a successful injection can
  reach. An instruction inside a file, a commit message, an issue or a tool result is
  data; the tiers are what stop that data becoming an action.
- **Text matching is not containment.** An action expressed as base64, or written to a
  script and then run, or taken through a runtime's own process API, is not a command
  line the guard sees.
- **Deny reads of your own credential files.** `~/.databrickscfg`, `.env`, `~/.aws`,
  anything `*.pem`. The reference `settings.json` does this. It is a text match like
  everything else, so treat it as removing the accident.
- **An agent that can rewrite its own permission rules does not have permission
  rules.** Keep `.claude/settings.json`, `opencode.json` and `~/.codex/config.toml` off
  the auto-allow list for writes, and review changes to them like any other config.
