# Cursor — what is known, and what would have to be found out

Anything marked **unverified** is a hypothesis to test during promotion, not a fact
this pack asserts. Verified statements carry the claim id that backs them.

## Established

- Cursor is documented as a supported coding-agent integration for the gateway
  (`gw-coding-agents-supported`) and has a route, `/ai-gateway/cursor/v1`
  (`gw-coding-agent-routes`).
- `ug cursor` supports **MCP only, not model routing** (`ug-agents-and-cursor`). This
  is the load-bearing fact for this directory.
- Route availability is per workspace and must be probed
  (`probe-gw-route-coverage`).

## Why an IDE is a different problem from a CLI

The other three placeholders are command-line agents, and the whole enforcement model
in `harness/shared/` assumes a shape they share: an agent that runs shell commands in
a project directory, a settings file in that directory, and a hook consulted before
each command. The three tiers are then a list of shell commands and tool names.

An IDE agent breaks two of those assumptions (**unverified** in current detail, and
worth re-reading before acting on):

1. **Configuration is often user-scoped rather than project-scoped.** A repository can
   commit a file, but whether that file wins over the developer's own settings is the
   question that decides whether this pack can put anything on rails at all. The
   equivalent finding for Claude Code is claim `cc-defaultmode-project-limit`: some
   keys cannot be delivered from a project file no matter how correct the file is.
   Answer this before writing a renderer, not after.
2. **Not every action is a shell command.** An IDE agent edits files through the
   editor's own APIs. A guard that inspects shell commands never sees those edits. The
   never-automatic tier here is mostly about `git push --force`, `gh pr merge` and
   deploys, which *are* shell commands, so this may matter less than it first appears —
   but "the guard sees a subset of what the agent does" is a sentence that has to be
   written down in whatever gets published, not discovered by a reader.

## The trust boundary is also different

Claude Code's sandbox denies reads of `~/.databrickscfg`, `~/.aws`, `~/.ssh` and, for
a reason worth pausing on, `~/.claude` — an agent that can rewrite its own permission
rules does not have permission rules (`harness/shared/boundary.yml`). Ask the same
question here: **can the agent edit the files that configure it?** For an agent living
inside an editor whose configuration is a file in the editor's own directory, the
answer is plausibly yes, and if it is, then the rules are advisory and should be
described as advisory.

## Open questions, in the order worth answering

1. Can a project-scoped, committed file configure agent permissions, and does it win
   over user-scoped settings? If not, this pack can contribute a policy document and a
   review checklist, and should say only that.
2. Can model traffic be pointed at `/ai-gateway/cursor/v1` with request tags attached,
   and does it then appear in `system.ai_gateway.usage`? This is the single evidence
   item that would close the gap `STATUS.md` describes. It is a query, not an opinion.
3. Is there a pre-execution hook for shell commands that can veto one? If yes, the
   existing guard adapts; the guard is already harness-neutral and proved against 46
   cases in `harness/shared/guards/cases.tsv` with no harness present.
4. Can the agent read credential files and its own configuration? Determines whether
   the boundary in `boundary.yml` is expressible at all.

## A note on scope

Cursor being MCP-only through `ug` is not a criticism of Cursor, and this pack should
not read as one. It is a statement about which of two governance questions the
launcher answers. Report it that way, with the split in `STATUS.md` intact, so a
reader can decide with the facts rather than with a verdict.
