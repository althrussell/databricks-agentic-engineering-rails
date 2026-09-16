# Disclaimer

**This is not an official Databricks product.** It is community material,
maintained by an individual, and it is not supported by Databricks. No
Databricks support channel, service level, warranty or commitment covers
anything in this repository. If something here is wrong, the recourse is an
issue on this repository, not a support ticket.

Nothing here supersedes the official documentation. Where this pack and
`docs.databricks.com` or `developers.databricks.com` disagree, the official
documentation is right and this pack has a bug. Every factual claim about a
Databricks behaviour carries a citation in [`docs/SOURCES.md`](docs/SOURCES.md)
so that you can check the source instead of trusting the summary.

This is not legal, security, compliance or financial advice. It is not a
security certification, and passing its checks certifies nothing beyond that
its checks passed.

## What "verified" means here, exactly

This pack takes a narrow and literal view of the word, because a broad one is
how documentation rots without anyone noticing.

- **[`docs/SOURCES.md`](docs/SOURCES.md)** lists every source behind a
  load-bearing claim, with the URL, the HTTP status it returned and the date it
  was read. A claim that cannot name its source does not appear in the pack.
- **"verified"** means a real call over that route returned 200 during the
  build. Only one route earned that word: the Anthropic model route, from Claude
  Code, on one workspace.
- **"documented"** means the source describes the behaviour and nothing here
  exercised it. It is the weaker label and it is used far more often than the
  strong one — including for the Codex and OpenCode gateway routes.
- **"we read that source on that date and it said that"** is the strongest claim
  made about any external system's behaviour. It does not mean the behaviour is
  guaranteed, and it does not mean the source still says it today. Check the date
  in `docs/SOURCES.md` before relying on a claim that matters.

## What was actually exercised, and what was not

The evidence behind this pack was gathered on **one** workspace and **one**
machine. That is enough to prove something works somewhere; it is not enough to
promise it works for you. The specific limits worth knowing before you rely on
anything:

- **Gateway route availability is per workspace.** On the build workspace the
  Anthropic route answered 200, the Codex route returned 404 and the Gemini route
  returned 400. This is why nothing here promises you a route, and why
  `docs/00-start-here.md` does not name a recommended harness.
- **Not every harness is governed the same way.** Cursor and GitHub Copilot CLI
  route MCP traffic through Unity AI Gateway but **not** model traffic. Codex has
  no rule list at all, so its never-automatic tier is prose in `AGENTS.md` and is
  enforced by a human reading the diff. Each harness's `SETUP.md` ends with what
  that harness cannot express, and the comparison table in
  `docs/00-start-here.md` carries the differences as columns rather than as
  footnotes.
- **Nothing here enforces a permission tier before a command runs.** An earlier
  version of this pack shipped a pre-execution hook for Claude Code. It was
  removed, for the reasons in
  `docs/DECISIONS/0006-guidance-over-machinery.md`. What is left is text
  matching, review, and — on two harnesses — a working-directory fence.
- **Nothing was verified against a workspace you control.** Entitlements,
  permissions, network egress rules and available models all differ. Run
  `./scripts/doctor.sh --live` on your own machine, then the usage-table query in
  `docs/03-gateway-auth.md` on your own workspace. Both produce evidence about
  *your* environment rather than repeating ours, and the second is the only one
  that can settle whether a session was governed.

## One misreading that costs money

A Unity AI Gateway **budget is not an invoice cap.** Databricks documents that
block thresholds are enforced approximately from a near-real-time cost estimate,
that requests already in flight are not interrupted, and that Databricks is not
responsible for costs incurred above a configured threshold. Size a budget as
near-real-time protection against a runaway, not as a spending limit you can
rely on. This is stated in `docs/03-gateway-auth.md` too, and it is repeated
here because it is the one item where believing the friendlier reading has a bill
attached.

## Trademarks and branding

Every product name in this repository is used nominatively — to name the thing
being written about. No endorsement, affiliation or sponsorship is claimed or
implied, and no Databricks logo, wordmark or other brand asset is reproduced
anywhere in this repository. See `NOTICE` for the full attribution list.

## Your data

Nothing in this repository collects, transmits or stores your data. The checks
run locally. `scripts/doctor.sh` deliberately never prints your workspace host,
because its output is designed to be pasted into a ticket or a chat message. No
workspace URL, account identifier or personal identifier appears in any
committed file in this repository.
