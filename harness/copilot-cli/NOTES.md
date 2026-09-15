# GitHub Copilot CLI — what is known, and what would have to be found out

Anything marked **unverified** is a hypothesis to test during promotion. Verified
statements carry the claim id that backs them.

## Established

- The gateway documents Copilot CLI among its supported coding-agent integrations
  (`gw-coding-agents-supported`), and `ug` lists it among the agents it launches
  (`ug-agents-and-cursor`).
- No `/ai-gateway/` route is documented for it. The route list in
  `gw-coding-agent-routes` covers Anthropic, Codex, Cursor, Gemini and MLflow. The
  absence is the notable fact and the first thing to check against a current source,
  since a route may have been added since that claim was verified — its
  `reverify_interval_days` is there for this.

## Two axes, and only one of them is likely available

This pack governs two different things and habitually says "the gateway" for both:

| Axis | Mechanism | Available here? |
| :--- | :--- | :--- |
| Which tools, under what authority | Governed MCP under `/ai-gateway/mcp-services/<catalog>.<schema>.<name>`, Unity Catalog permissions, audit | Very likely. It is an HTTP endpoint and a bearer token. |
| Which model, at what cost, charged to whom | A model route under `/ai-gateway/`, request tags, `system.ai_gateway.usage` | Unlikely as shipped, if model access comes with the GitHub subscription (**unverified**). |

Keeping these apart is the main contribution this directory can make. A reader who
takes "governed" as a single property will assume a cost dashboard exists.

## Open questions, in the order worth answering

1. **Where is the model spend metered?** Everything else about this harness follows
   from the answer, including whether it can ever be promoted to the same support level
   as the reference harness or should be documented as a deliberately different one.
2. Can it be pointed at a Databricks serving endpoint at all — through an
   OpenAI-compatible route, or the MLflow route that OpenCode uses? If yes, this
   becomes an ordinary promotion. If no, the honest support level is "tools governed,
   model metered by GitHub", and the matrix should say exactly that.
3. Is there a project-scoped configuration file a repository can commit, and does it
   win over user-scoped settings? Compare claim `cc-defaultmode-project-limit`: for
   Claude Code some keys cannot be delivered from a project file at all, which changed
   what this pack tells administrators to do.
4. Is there a pre-execution hook that can veto a command? Decides whether the
   never-automatic tier is enforceable or only written down. The guard in
   `harness/shared/guards/never-automatic.sh` is harness-neutral, reads a command on
   stdin and prints a verdict, and is proved against 46 cases without any harness
   present — so if a hook exists, most of the work is already done.
5. Does MCP registration support a per-connection header helper, so a short-lived
   token can be minted per connection rather than a long-lived one committed to a file?

## One caution about credentials

This harness authenticates against a second identity provider, so a developer's
machine holds GitHub credentials alongside Databricks ones. `boundary.yml` already
denies reads of `~/.databrickscfg`, `~/.aws`, `~/.ssh` and `~/.netrc` to sandboxed
commands; whoever promotes this harness should check whether GitHub's own credential
store belongs on that list. The principle in `boundary.yml` is that an agent should
not be able to read a credential it does not need for the task in front of it, and
that applies to the credential its own vendor issued.
