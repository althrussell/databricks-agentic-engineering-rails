# Codex CLI — what is known, and what would have to be found out

Kept separate from `STATUS.md` because these are working notes with a shelf life.
Anything below marked **unverified** is a hypothesis to test during promotion, not a
fact this pack asserts. The verified statements carry the claim id that backs them.

## Established

- The gateway documents Codex CLI as a supported coding agent (`gw-coding-agents-supported`).
- Its route is `/ai-gateway/codex/v1` (`gw-coding-agent-routes`).
- That route **returned 404 on the workspace this pack was verified against**, while
  the Anthropic route returned 200 (`probe-gw-route-coverage`). Route availability is
  per workspace. A team adopting Codex should probe before planning around it —
  `harness/claude-code/launch.sh --explain` shows the shape of that probe.
- `ug codex` launches it, and `ug codex --refresh` re-reads the workspace
  configuration (`ug-agents-and-cursor`, `ug-refresh`).

## The structural problem: modes versus rules

This is the reason Codex is a placeholder rather than the second implementation.

`harness/shared/permissions.yml` describes three tiers as sets of *actions*:
auto-allow, ask, never-automatic. Rendering that into Claude Code is mostly
mechanical because its permission model is a list of per-pattern rules with an
`ask` verdict, so each tier becomes a list.

Codex's model is understood to be **mode-shaped** — a session-wide approval posture
combined with a sandbox scope — rather than a list of per-command rules
(**unverified** in detail; the mode names and the exact file keys must be read from
the current release, not from this note). If that holds, then:

- The **auto-allow** tier translates well. A mode that permits writes inside the
  working directory and asks about anything outside it is close to what the tier
  means.
- The **ask** tier translates approximately. Sessions can be made to ask; making
  them ask about *this list of actions specifically* is the part to prove.
- The **never-automatic** tier has no obvious equivalent. A tier that must refuse a
  named action regardless of the current approval posture, and journal the refusal,
  is exactly what a rule list gives you and what a mode does not.

So promotion turns on one question: **is there a pre-execution hook?** Something
Codex consults before running a command, which can veto it and which we can point at
`harness/shared/guards/never-automatic.sh`. That guard is already harness-neutral —
it reads a command on stdin and prints a verdict, and `cases.tsv` proves it against
46 cases without any harness present. If such a hook exists, promotion is largely an
adapter and the existing guard does the work. If it does not, the honest outcome is a
promoted harness that documents two enforceable tiers and one tier enforced by review,
which is a real answer and should be published as one rather than papered over.

## Open questions, in the order worth answering

1. Is there a pre-execution hook or wrapper that can veto a command? Everything else
   depends on this.
2. What is the config file, its format, and its precedence order? Specifically:
   is there a **project-scoped** file a repository can commit, and can a
   **machine-scoped** file override it? The equivalent question for Claude Code
   produced claim `cc-defaultmode-project-limit`, which changed what this pack tells
   administrators to do — some settings simply cannot be delivered by a file in a
   repository, and finding that out late means publishing a configuration that
   silently does less than it says.
3. Does it support MCP over HTTP with a per-connection header helper? Governed MCP
   through Unity AI Gateway needs a short-lived token minted per connection. Static
   headers in a committed file are not an acceptable substitute.
4. Does the sandbox have a credential-deny equivalent, and does the header helper run
   inside or outside it? For Claude Code the answer is *outside*, which is recorded in
   `harness/evidence/verify-in-sandbox.md` and matters enough that it changed how
   `.mcp.json` is reviewed. Ask the same question here; do not assume the same answer.
5. Does `ug codex` write user-scope configuration, and does it collide with a
   project-scope file? `launch.sh` already has a `DAER_NO_UG=1` path for this reason.

## A constraint on doing the work

`/etc/codex/managed_config.toml` and `~/.codex/` are the machine's and the
developer's own configuration. Nothing in this repository writes to either, and the
verification script asserts afterwards that it did not. Whoever promotes this harness
inherits that rule: prove the configuration in a scratch project with an isolated
config directory, the way `harness/scripts/verify-in-sandbox.sh` does, so a failed
experiment costs a `rm -rf` and not somebody's working setup.
