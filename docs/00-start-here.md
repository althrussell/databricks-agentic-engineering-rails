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

| Harness | Setup | Model traffic governed | Never-automatic tier enforced |
| :--- | :--- | :--- | :--- |
| Claude Code | `harness/claude-code/SETUP.md` | Yes | Before the command runs, and journalled |
| Codex CLI | `harness/codex/SETUP.md` | Yes | By posture and review |
| OpenCode | `harness/opencode/SETUP.md` | Yes | By pattern, three verdicts |
| Cursor CLI | `harness/cursor/SETUP.md` | No — tools only | By rule and review |
| GitHub Copilot CLI | `harness/copilot-cli/SETUP.md` | No — tools only | By launch flag and review |

That table is the honest version of "multi-harness support". All five get generated
configuration from the same policy; two of them cannot route model traffic through the
gateway at all, and only one can refuse a named command before it runs. Pick with that
in view rather than discovering it in a quarter.

## Which track are you on

**Track A — you are building a Databricks App.** The app runs on Databricks, so the
platform is both your runtime and your governance plane. Read
`docs/03-gateway-auth.md` for how sessions authenticate, then the AppKit and Apps
sources in `docs/SOURCES.md`. The pack's own `make check` lane is the shape a Track A
repository's CI should have.

**Track B — you are writing software that has nothing to do with Databricks, and you
want the models governed anyway.** This is the more common case and it works: the
gateway is a model endpoint and an MCP registry, and neither cares what you are
building. Everything in this pack applies except the Apps-specific sources. Your CI runs
wherever your code lives; `docs/05-ci-test-docs.md` is written to be forge-agnostic for
that reason.

Both tracks share the same first thirty minutes. The split only matters once you are
productive.

## What the pack actually contains

- **`scripts/doctor.sh`** — every tool, its version, and where to get it. Run this
  before asking anyone for help.
- **`harness/shared/`** — the policy. Three permission tiers, an MCP allowlist and a
  budget, expressed once in a vocabulary that is not any one harness's.
- **`harness/<name>/`** — that policy rendered into each harness's own configuration
  format, plus a launcher, plus a hand-written `SETUP.md`. The rendered files are not
  edited; `make harness-verify` fails the build if one has been.
- **`docs/`** — five short documents and a source list. You are reading the first.

## The order to read them in

1. `docs/01-prerequisites.md` — what has to be on the laptop, and how to tell.
2. Your harness's `SETUP.md` — the thirty minutes.
3. `docs/02-permissions.md` — the three tiers, why the middle one is the important one.
4. `docs/03-gateway-auth.md` — `ucode` and `ug`, request tags, what the gateway sees.
5. `docs/04-skills-vs-mcp.md` — the decision people get wrong most often.
6. `docs/05-ci-test-docs.md` — the gates worth enforcing, briefly.

## What this pack does not do

It does not solve prompt injection. Every mechanism here limits the blast radius of an
injection that has already succeeded; none prevents one. It does not make an agent's
output correct. And it is not a security boundary — the permission tiers are the
difference between an accident and a deliberate act, which is worth a great deal and is
not the same thing as containment.

See `DISCLAIMER.md` for the full version of that, including what has and has not been
run against a real workspace.
