# 0002 — Where agent commands actually run

**Status:** provisional — settled once harness verification has been run inside a
rootless container on a machine that has one. Tracked as `g-container-runtime` in
`release-readiness.yml`.
**Date:** 2026-09-15

## Context

A coding agent's value comes from running commands, and a command that can run
`make test` can run `curl | sh`. The boundary around those commands is the whole
of the practical security story: permission tiers decide what the agent is
*allowed* to attempt, and the boundary decides what happens when the decision is
wrong — because of a prompt injection in a fetched page, a mistaken deny that was
never tested, or an ordinary bug.

Two things need isolating, and they are not the same thing.

**Credentials.** The agent must be able to reach the gateway, which means a token
must exist somewhere it can read. The human's own `~/.databrickscfg`, OAuth token
cache and harness configuration (`~/.claude/`, `~/.codex/`) are not that place.

**Everything else.** The filesystem outside the repository, the network, and the
rest of the machine.

## Decision

The intended boundary is an unprivileged container: `.devcontainer/`, built by
`make sandbox-build`, run with `--cap-drop ALL --security-opt no-new-privileges`,
with only the repository mounted and only the app port published.

**Credentials are created inside the boundary, never carried into it.** The flow
is: build the boundary, then run `databricks auth login --host "$DATABRICKS_HOST"
--profile labs` *within* it, then `make harness-verify-sandbox PROFILE=labs`. The
token that results lives and dies with the boundary. `$DATABRICKS_HOST` is
supplied by the human at the prompt; it is never written into a committed file,
and `make check` enforces that with a forbidden-pattern rule rather than trusting
anyone to remember.

**On a machine with no container runtime, the targets refuse.** `make
sandbox-build` looks for docker, podman, finch and nerdctl, and exits non-zero
with a pointer to this record when it finds none. It does not silently do
something weaker under the same name. The scratch-`HOME` fallback below is a
different thing with a different name and different guarantees.

**The fallback is a scratch `HOME`.** The verification scripts run with `HOME`
pointed at `.harness-scratch/` inside the repository, gitignored because it holds
a live OAuth token cache while a session is running.

### What the scratch HOME isolates, and what it does not

| | Container boundary | Scratch `HOME` |
|---|---|---|
| The human's harness configuration and permission tiers | isolated | isolated |
| The human's `~/.databrickscfg` and OAuth token cache | isolated | isolated |
| The filesystem outside the repository | isolated | **not isolated** |
| Outbound network | controllable | **not isolated** |
| Process capabilities and privilege escalation | dropped | **unchanged** |
| Survives the session | no, disposable | yes, until deleted |

The fallback is therefore adequate for verifying *our own* harness configuration,
which is what Phase 1 needs it for: the question being answered is "does this
generated config launch, route through the gateway, register MCP and honour its
deny rules", and none of that requires filesystem isolation. It is **not**
adequate for running an agent against untrusted input, and the security document
must not present it as though it were.

## Consequences

- The harness proof shipped with this revision is honest about what it isolates
  and weaker than what the pack recommends. That asymmetry is published in
  `DISCLAIMER.md`, carried as a known gap in `release-readiness.yml`, and
  reported by `scripts/doctor.sh`, which probes for a runtime and prints its
  absence rather than staying quiet.
- `make sandbox-build` failing on this machine is the correct behaviour and will
  read as a bug to anyone who has not read this record. That is why the failure
  message names this file.
- Because credentials are created inside the boundary, the boundary must be able
  to complete an OAuth flow, which means a browser hand-off. That is friction,
  and it is the price of the token never existing outside.

## Rejected alternatives

**Mount the human's `~/.databrickscfg` or OAuth token cache into the boundary.**
Rejected outright, and it is worth being explicit because it is the obvious
shortcut and it appears in a lot of published devcontainer setups. It defeats the
purpose: the credential is the highest-value thing on the machine, a mounted
token outlives the container, and the blast radius of a compromised agent session
becomes the human's entire workspace access rather than one disposable login. The
inconvenience of logging in inside the boundary is the feature.

**Use the host directly and rely on permission tiers alone.** Rejected because
permission tiers are a policy layer inside the agent, and the whole point of a
boundary is to survive that layer being wrong. A deny rule that was never
exercised is a comment.

**Install a container runtime on the build machine as part of this build.**
Rejected on process grounds, not technical ones: it needs privileges this build
does not have and should not take. It is the human's call and their command to
run. The gap is recorded so the decision is theirs to make with the cost visible.

**Drop the container from the standard and recommend the scratch `HOME`.**
Rejected because it would lower the recommendation to match what we happened to
be able to run. The standard describes what teams should do; this record
describes what this build achieved. Conflating the two is how a standard becomes
a description of the status quo.

## Revisit when

A rootless runtime is available and `make harness-verify-sandbox` has completed
inside it against a real workspace. At that point this record is superseded by
one whose status is `accepted`, the `g-container-runtime` gap closes with
evidence, and the comparison table above becomes documentation of a fallback
rather than a description of what shipped.
