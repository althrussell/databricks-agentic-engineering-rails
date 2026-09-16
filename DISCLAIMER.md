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
  build. It appears in a generated `RENDER-NOTES.md` only where that happened.
- **"documented"** means the route was probed and the behaviour is described by
  the source, but nothing was exercised. It is the weaker label and it is used
  more often than the strong one.
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
  returned 400. This is why every generated launcher probes your own workspace
  rather than trusting a list, and why `docs/00-start-here.md` does not name a
  recommended harness.
- **Not every harness is governed the same way.** Cursor and GitHub Copilot CLI
  route MCP traffic through Unity AI Gateway but **not** model traffic. Codex has
  no rule list and no pre-execution hook, so its never-automatic tier is written
  into `AGENTS.md` and enforced by a human reading the diff. Each harness's
  `RENDER-NOTES.md` states its own limits, and the comparison table in
  `docs/00-start-here.md` carries them as columns rather than as footnotes.
- **Only OpenTofu was exercised** for infrastructure-as-code. The configuration
  targets the Databricks provider and is expected to work with Terraform, but
  Terraform was not installed and not tested. Treat parity as untested.
- **Nothing was verified against a workspace you control.** Entitlements,
  permissions, network egress rules and available models all differ. Run
  `./scripts/doctor.sh` and your harness's `launch.sh --explain` on your own
  workspace; both are built to produce evidence about *your* environment rather
  than to repeat ours.

## One misreading that costs money

A Unity AI Gateway **budget is not an invoice cap.** Databricks documents that
block thresholds are enforced approximately from a near-real-time cost estimate,
that requests already in flight are not interrupted, and that Databricks is not
responsible for costs incurred above a configured threshold. Size a budget as
near-real-time protection against a runaway, not as a spending limit you can
rely on. This is repeated in `docs/03-gateway-auth.md`, and it is repeated here
because it is the one item where believing the friendlier reading has a bill
attached.

## Trademarks and branding

Every product name in this repository is used nominatively — to name the thing
being written about. No endorsement, affiliation or sponsorship is claimed or
implied, and no Databricks logo, wordmark or other brand asset is reproduced
here or in the PDFs this repository builds. See `NOTICE` for the full
attribution list.

## Your data

Nothing in this repository collects, transmits or stores your data. The checks
run locally. `scripts/doctor.sh` deliberately never prints your workspace host,
because its output is designed to be pasted into a ticket or a chat message. No
workspace URL, account identifier or personal identifier appears in any
committed file in this repository.
