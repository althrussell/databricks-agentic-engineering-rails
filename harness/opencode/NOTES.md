# OpenCode — what is known, and what would have to be found out

Anything marked **unverified** is a hypothesis to test during promotion. Verified
statements carry the claim id that backs them.

## Established

- Documented as a supported coding-agent integration (`gw-coding-agents-supported`).
- Its route is `/ai-gateway/mlflow/v1`, shared with open-source models generally
  (`gw-coding-agent-routes`). Route availability is per workspace
  (`probe-gw-route-coverage`).
- `ug` launches it (`ug-agents-and-cursor`).

## What the second renderer is actually for

Worth being explicit, because it is easy to treat this as a checkbox.

`harness/shared/` is a single source of truth expressed in a neutral vocabulary:
capabilities are written `tool(Bash)`, `shell(git status)`, `net.fetch(docs...)`,
`mcp(*)` and rendered per harness. Rendering it a second time is the only way to find
out whether that vocabulary describes agent permissions in general or merely describes
Claude Code in a roundabout way.

The reference render already needed two **mechanism substitutions** — capabilities
that could not become rules and were satisfied another way. `tool(Bash)` and `mcp(*)`
became `defaultMode: "default"` plus `autoAllowBashIfSandboxed: false`, because in
Claude Code a matching ask rule prompts even when a more specific allow rule also
matches, and because a bare `Bash` ask rule is skipped entirely for commands that run
sandboxed. Both substitutions are recorded in `RENDER-NOTES.md` rather than hidden.

If the second render needs no substitutions, the vocabulary is probably sound. If it
needs many, the vocabulary is leaking Claude Code's model and should be revised — and
that revision is a better outcome than a second green check. Record substitutions the
same way; `RENDER-NOTES.md` exists so that a reader can see where the generated
configuration stopped being a direct translation.

## Open questions, in the order worth answering

1. **The configuration file: format, location, precedence.** Specifically whether a
   project-scoped committed file exists and whether it wins over user scope. Compare
   claim `cc-defaultmode-project-limit` — some values are simply not deliverable from a
   repository file, and publishing a configuration that silently does less than it says
   is the failure mode to avoid.
2. **A pre-execution hook that can veto a command.** The never-automatic tier depends
   on it. The guard is harness-neutral: it reads a command on stdin, prints a verdict,
   journals its decision, and is proved against the 46 cases in
   `harness/shared/guards/cases.tsv` with no harness present. An adapter is a small
   script; the hook either exists or it does not.
3. **MCP over HTTP with a per-connection header helper.** Governed MCP needs a
   short-lived token minted per connection. Note the finding recorded in
   `harness/evidence/verify-in-sandbox.md`: for Claude Code the helper runs *outside*
   the command sandbox, as a direct child of the harness process, which is why denying
   `~/.databrickscfg` to sandboxed commands does not break MCP authentication. Ask the
   question again here rather than assuming the answer transfers — and if the helper
   runs inside the sandbox, the deny entry and governed MCP are mutually exclusive as
   configured, which is a design decision and not a bug to work around.
4. **Sandboxing.** Is there a filesystem, credential and network boundary equivalent to
   the `sandbox` block, and does it fail closed when unavailable? The reference harness
   sets `failIfUnavailable` so that a platform without a sandbox produces a startup
   failure rather than a silent downgrade. A boundary that silently degrades is worse
   than none, because the team believes it is there.
5. **Model naming on the MLflow route.** The Anthropic route accepts a Unity Catalog
   model name in the request body. Whether the MLflow route names a serving endpoint
   instead, and how a model alias maps to it, is the practical detail that will consume
   an afternoon. Write it down when you find it.

## The promotion is also a test of the checker

`harness/scripts/verify.sh` discovers what to check by finding `.generated.sha256`
files rather than from a list, so a second harness should be picked up with no edit to
the checker. If it is not, that is a defect in the checker worth fixing before the
renderer, because a generated directory nobody verifies drifts silently and the whole
generate-and-verify pair stops meaning anything.
