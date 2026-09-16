# Permissions

Three tiers. The whole policy is `harness/shared/permissions.yml`, and it is short
enough to read in one sitting, which is deliberate: a permission policy nobody has read
is a permission policy nobody follows.

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

## One policy, five renderings

`harness/shared/permissions.yml` is written in a vocabulary that belongs to no harness:

```
tool(Read)              a named capability the harness provides
shell(git status)       a command, matched on its leading text
net.fetch(host)         an outbound fetch to one host
mcp(server.tool)        one tool on one MCP server
mcp(*)                  every MCP tool
```

`make harness-generate` renders that into each harness's own format. The renderer's
first rule is that **a capability it cannot express raises an error rather than being
dropped**, because a permission tier that vanished during rendering leaves a
configuration that still looks careful. The only escape is a recorded substitution
naming the mechanism used instead — and the renderer then checks that the mechanism is
really present in the file it produced.

Read `harness/<name>/RENDER-NOTES.md` for what your harness could not express. It is
different for each one, and it is generated, so it cannot drift from the configuration
it describes.

## What actually enforces this

Two mechanisms, and it matters which one you are relying on:

**Permission rules** match command text. They stop the canonical spelling of an action
and leave no record. They are bypassed by an unusual spelling: a global option before
the subcommand, a quoted subcommand, a flag moved after the refspec.

**The guard** — `harness/shared/guards/never-automatic.sh` — normalises the text first,
then classifies it, then writes one line per decision to `.daer/guard-journal.jsonl`.
Where a harness supports a pre-execution hook, this runs before the command does. Where
it does not, run the guard in CI over anything scripted.

Deploy both where you can. A tier enforced only by rules is bypassed by a spelling; a
tier enforced only by a guard is bypassed by a broken interpreter, which is why the
adapter denies rather than allows when it cannot run.

```sh
./harness/scripts/deny-proof.sh
```

Forty-six cases: commands that must be refused and commands that must not be. A guard
that denies everything fails that as loudly as one that denies nothing.

## The limits, stated plainly

- **None of this prevents prompt injection.** It limits what a successful injection can
  reach. An instruction inside a file, a commit message, an issue or a tool result is
  data; the tiers are what stop that data becoming an action.
- **Text matching is not containment.** An action expressed as base64, or written to a
  script and then run, or taken through a runtime's own process API, is not a command
  line the guard sees.
- **`~/.claude` and `~/.codex` are denied on purpose.** An agent that can rewrite its
  own permission rules does not have permission rules.
