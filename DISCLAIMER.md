# Disclaimer

**This is not an official Databricks product.** It is community material,
maintained by an individual, and it is not supported by Databricks. No
Databricks support channel, service level, warranty or commitment covers
anything in this repository. If something here is wrong, the recourse is an
issue on this repository, not a support ticket.

Nothing here supersedes the official documentation. Where this pack and
`docs.databricks.com` or `developers.databricks.com` disagree, the official
documentation is right and this pack has a bug. Every factual claim about a
Databricks behaviour carries a citation in `claims-ledger.json` so that you can
check the source instead of trusting the summary.

This is not legal, security, compliance or financial advice. It is not a
security certification, and passing its checks certifies nothing beyond that
its checks passed.

## What "verified" means here, exactly

This pack takes a narrow and literal view of the word, because a broad one is
how documentation rots without anyone noticing.

- **`claims-ledger.json`** holds one row per load-bearing factual claim about an
  external system. Each row records the source, the source's own words as
  evidence, the method, the date, and how often it must be re-checked. A claim
  that cannot name its source and quote it does not appear in the pack.
- **`status: verified`** means we read that source on that date and it said
  that. It does not mean the behaviour is guaranteed, and it does not mean the
  source still says it today.
- **`status: verified-absent`** means we looked and the documentation does *not*
  state the thing. The absence is the finding. Where this pack gives a number
  that the documentation does not give, it says so and says who measured it.
- **`status: expired`** means the row is past its re-verification interval.
  Treat every statement that depends on it as unsupported until `make reverify`
  has been run and the row updated.
- **`release-readiness.yml`** carries the pack's own release status
  (`PREVIEW` or `RELEASE-READY`) and a per-row result of `passed`, `failed`,
  `not-run` or `expired`. `not-run` is a real value and it is used. A row marked
  `closed_by: humans` cannot be closed by a build.

## What was actually exercised, and what was not

The evidence behind this pack was gathered on **one** workspace and **one**
machine. That is enough to prove something works somewhere; it is not enough to
promise it works for you. The specific limits worth knowing before you rely on
anything:

- **Gateway route availability is per workspace.** On the verification
  workspace the Anthropic route answered, the Codex route returned 404 and the
  Gemini route returned 400. This is why the pack teaches you to probe your own
  workspace rather than to trust a list, and why Claude Code is the reference
  harness rather than the recommended one.
- **Harnesses other than the reference one are labelled, not implemented.** A
  placeholder directory in `harness/` contains a status note and nothing
  loadable. `harness/PROMOTION.md` states the bar it must clear to become
  supported. "Coming soon" with no criteria is how a support matrix starts
  misleading people.
- **Only OpenTofu was exercised** for the admin infrastructure-as-code. The
  configuration targets the Databricks provider and is expected to work with
  Terraform, but Terraform was not installed and not tested. `PORTABILITY.md`
  records that as `NOT VERIFIED`, not as parity.
- **The execution boundary is weaker than intended on the build machine.** No
  container runtime was available, so harness verification ran in a scratch
  `HOME` instead of a container. `docs/DECISIONS/0002-execution-boundary.md`
  states what that does and does not isolate. Read it before you assume the
  isolation you want is the isolation you have.
- **Nothing was verified against a workspace you control.** Entitlements,
  permissions, network egress rules and available models all differ. Run
  `make doctor` and the labs on your own workspace; the pack is built so that
  those produce evidence about *your* environment rather than repeating ours.

## One misreading that costs money

A Unity AI Gateway **budget is not an invoice cap.** Databricks documents that
block thresholds are enforced approximately from a near-real-time cost estimate,
that requests already in flight are not interrupted, and that Databricks is not
responsible for costs incurred above a configured threshold. Size a budget as
near-real-time protection against a runaway, not as a spending limit you can
rely on. This pack repeats that in the gateway document, the admin runbook and
the risk register, and it is repeated here because it is the one item where
believing the friendlier reading has a bill attached.

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
committed file in this repository, and `make check` enforces that with the
forbidden-pattern rules in `repo-manifest.yml` rather than trusting anyone to
remember.
