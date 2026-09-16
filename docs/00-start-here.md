# Start here

You have a laptop, a harness you like, and a Databricks workspace. This pack gets you
from that to a session whose model spend is attributable, whose tools are governed by
Unity Catalog, and which will not force-push to a shared branch because a file it read
told it to.

It should take about thirty minutes. If it takes longer than that, the fault is ours and
`scripts/doctor.sh` is where to start looking.

## The whole path

```sh
git clone https://github.com/althrussell/databricks-agentic-engineering-rails
cd databricks-agentic-engineering-rails
./scripts/doctor.sh                       # is this laptop ready
```

Then pick your harness and follow its own setup page. They are short, and they differ
from each other in ways that matter:

| Harness | Setup | Model traffic governed | Never-automatic tier | Real fence |
| :--- | :--- | :--- | :--- | :--- |
| Claude Code | [`harness/claude-code/SETUP.md`](../harness/claude-code/SETUP.md) | Yes, verified | Deny rules — a text match | None |
| Codex CLI | [`harness/codex/SETUP.md`](../harness/codex/SETUP.md) | Route not verified here | **Prose only** | `sandbox_mode = workspace-write` |
| OpenCode | [`harness/opencode/SETUP.md`](../harness/opencode/SETUP.md) | Route not verified here | Deny verdicts — a text match | `"*": "ask"` catch-all |
| Cursor CLI | [`harness/cursor/SETUP.md`](../harness/cursor/SETUP.md) | **No — tools only** | Deny rules — a text match | None |
| GitHub Copilot CLI | [`harness/copilot-cli/SETUP.md`](../harness/copilot-cli/SETUP.md) | **No — tools only** | Deny flags, if you passed them | None |

That table is the honest version of "multi-harness support", and the last two columns are
the ones to read. Two harnesses cannot route model traffic through the gateway at all.
One has no rule mechanism for the never-automatic tier. And the column that actually
constrains a session — the fence that removes a capability rather than pattern-matching a
command string — is empty for three of the five. Pick with that in view rather than
discovering it in a quarter.

Nothing here enforces a tier before the command runs. An earlier version of this pack
shipped a pre-execution hook for Claude Code; it was custom code and it is gone, for the
reasons in [`DECISIONS/0006`](DECISIONS/0006-guidance-over-machinery.md).

## Which track are you on

**Track A — you are building a Databricks App.** The app runs on Databricks, so the
platform is both your runtime and your governance plane. Read
[`03-gateway-auth.md`](03-gateway-auth.md) for how sessions authenticate, then the AppKit
and Apps sources in [`SOURCES.md`](SOURCES.md). The lane table in
[`05-ci-test-docs.md`](05-ci-test-docs.md) is the shape a Track A repository's CI should
have.

**Track B — you are writing software that has nothing to do with Databricks, and you
want the models governed anyway.** This is the more common case and it works: the
gateway is a model endpoint and an MCP registry, and neither cares what you are
building. Everything in this pack applies except the Apps-specific sources. Your CI runs
wherever your code lives; [`05-ci-test-docs.md`](05-ci-test-docs.md) is written to be
forge-agnostic for that reason.

Both tracks share the same first thirty minutes. The split only matters once you are
productive.

## What the pack actually contains

- **[`harness/<name>/`](../harness/)** — for each harness, a `SETUP.md` and the two or
  three configuration files it tells you to copy. Small, hand-maintained, in the
  harness's own documented format. This is the part you take.
- **[`docs/`](.)** — six short documents and a source list. You are reading the first.
- **`scripts/doctor.sh`** — every tool, its version, and where to get it. Run this before
  asking anyone for help.

There is deliberately no code here that you install or run in your own project. What
governs a session is `ug`, which Databricks maintains, plus configuration files your
harness already reads. If you were expecting a framework, the reasoning for its absence
is [`DECISIONS/0006`](DECISIONS/0006-guidance-over-machinery.md).

## The order to read them in

1. [`01-prerequisites.md`](01-prerequisites.md) — what has to be on the laptop, and how
   to tell.
2. Your harness's `SETUP.md` — the thirty minutes.
3. [`02-permissions.md`](02-permissions.md) — the three tiers, why the middle one is the
   important one, and what a permission rule does not stop.
4. [`03-gateway-auth.md`](03-gateway-auth.md) — `ug` and `ucode`, request tags, what the
   gateway sees.
5. [`04-skills-vs-mcp.md`](04-skills-vs-mcp.md) — the decision people get wrong most
   often.
6. [`05-ci-test-docs.md`](05-ci-test-docs.md) — the gates worth enforcing, briefly.

## What this pack does not do

It does not solve prompt injection. Every mechanism here limits the blast radius of an
injection that has already succeeded; none prevents one. It does not make an agent's
output correct. And it is not a security boundary — the permission tiers are the
difference between an accident and a deliberate act, which is worth a great deal and is
not the same thing as containment.

See [`DISCLAIMER.md`](../DISCLAIMER.md) for the full version of that, including what has
and has not been run against a real workspace.
