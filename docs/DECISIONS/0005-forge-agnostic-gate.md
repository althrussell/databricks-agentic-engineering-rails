# 0005 — The gate is a script, not a workflow file

**Status:** accepted
**Date:** 2026-09-15

## Context

`repo-manifest.yml` promised `.github/workflows/` as a Phase 6 required path,
with the reason "gates that exist only as documentation are advice. This is
where the standard becomes enforcement." The reasoning is right. The
implementation assumed a forge feature.

The assumption broke on contact with the destination. **The repository location
this pack is being delivered into does not run GitHub Actions.** That is not an
unusual constraint: self-hosted GitHub Enterprise Server with Actions disabled,
GitLab, Azure DevOps, Bitbucket, a mirrored read-only remote, and an internal
forge with its own runner are all common, and a team that cannot run the gate is
a team that reads the standard and adopts none of it.

There is a second reason, independent of the destination, and it is the one that
would have justified this change anyway. A pack whose enforcement lives in
`.github/workflows/*.yml` teaches its readers that CI is a GitHub feature. The
lesson it should teach is that the gate is a command, and CI is whatever happens
to invoke it.

## Decision

**`ci/run.sh <lane>` is the gate.** One POSIX `sh` entry point, taking a lane
name, exiting non-zero on failure, with no dependency on any forge, any runner
image or any environment variable a forge supplies. It is runnable on a laptop.
Every lane named in `release-readiness.yml` under `automated_checks` — `pr-lane`,
`starter-check`, `app-deploy-smoke`, `lab-completion-checks` and the rest — is a
lane of this script and nothing else.

Three things then attach to it, in descending order of how much we rely on them:

1. **`make check`** is what the `pr-lane` lane runs. It is already hermetic: no
   network, no credentials, no workspace. This is unchanged and is the reason
   the split is cheap.
2. **`scripts/install-hooks.sh`** installs a `pre-push` hook that runs the same
   lane locally. Opt-in, one command, and removable — a hook nobody can bypass
   is a hook people work around by not pushing.
3. **`ci/adapters/`** holds thin, *optional* invocations for the forges that do
   have runners: a GitHub Actions workflow, a GitLab `.gitlab-ci.yml`, an Azure
   Pipelines file, and a Databricks Job definition in `databricks.yml` for teams
   whose only reliable compute is the platform itself. Each adapter is a handful
   of lines whose entire body is `ci/run.sh <lane>`. They are examples to copy,
   not required paths, and none of them is in `repo-manifest.yml`.

`repo-manifest.yml`'s Phase 6 required paths become `ci/run.sh` and
`scripts/install-hooks.sh`. `.github/workflows/` is removed from the manifest.

## Consequences

- **Nothing enforces the gate on a push to a forge that has no runner.** This is
  the honest cost and it must not be dressed up. On such a forge the gate is a
  pre-push hook and a review checklist, which is weaker than a required status
  check, because both can be skipped by one person in a hurry. The pack says so
  where a reader will see it rather than implying coverage it does not have.
  Where the platform is the only available compute, the Databricks Job adapter
  is the strongest option, and it is a scheduled verdict rather than a blocking
  one.
- The adapters are unverified per forge unless someone runs them. They are
  listed in `docs/PORTABILITY.md` under what was *not* tested, at the same
  standard as the four labelled harnesses.
- A lane's definition lives in one file that a developer can run, so "it passes
  locally but fails in CI" becomes a real bug report rather than a shrug about
  runner environments.
- One more `sh` script, which is the language rule from
  [0004](0004-posix-sh-for-diagnostics.md) applied to exactly the case it was
  written for: this has to run in whatever image a team already has.

## Rejected alternatives

**Keep `.github/workflows/` and note the limitation in the README.** Rejected
because the required path would be permanently unsatisfiable at the delivery
destination, which turns `make check` into a command that fails for a reason
nobody can fix. A required path that cannot be met is a broken check, not a
warning.

**Make the GitHub workflow the gate and treat other forges as a porting
exercise for the reader.** Rejected because the porting exercise is the part
that does not happen. Adoption stops at the first file a team cannot use.

**Use a container-based CI standard (Dagger, Earthly, Nix) so the gate is
reproducible everywhere.** Rejected on dependency weight. The gate has to run in
a stripped image and on a laptop with nothing installed but `make`, `sh` and
`python3`; adding a build engine to guarantee reproducibility of a hermetic
check that is already reproducible buys nothing and costs an install.

**Only a pre-push hook, no adapters.** Rejected because it would give teams who
*do* have runners nothing, and they are the majority. The adapters are cheap
precisely because they contain no logic.

## Revisit when

The delivery destination gains a runner, or a second destination appears with a
forge whose adapter cannot be expressed as a one-line invocation of
`ci/run.sh`. The second is the interesting case: it would mean a lane needs
something from the forge — a token, an artifact store, a matrix — and that is
the point at which the "adapters contain no logic" rule has to be either
defended or replaced.
