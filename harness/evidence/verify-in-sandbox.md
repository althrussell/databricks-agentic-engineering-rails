# Harness verification against a live workspace

Written by `harness/scripts/verify-in-sandbox.sh`. Every line below is an
assertion that ran, not a description of one. Re-run with `make harness-verify-sandbox`.

| field | value |
| :--- | :--- |
| run at | 2026-09-15T04:44:54Z |
| workspace | `https://<workspace>.cloud.databricks.com` |
| profile | `labs` (name only; the host and token are never recorded) |
| stages | config auth gateway helper deny |
| harness | claude-code 2.1.272 (Claude Code) |
| platform | Darwin arm64 |
| result | 13 passed, 0 failed, 0 inconclusive |

## Assertions

| verdict | stage | what was asserted |
| :--- | :--- | :--- |
| PASS | config | the files under test are the generator's output |
| PASS | config | the five keys that make the ask tier real are all set |
| PASS | auth | minted a 978-character token (2 dots) for `https://<workspace>.cloud.databricks.com` |
| PASS | gateway | 200, model claude-haiku-4-5-20251001 answered 'READY', 14 in / 5 out |
| PASS | gateway | the request tags were accepted; run tag project=verify-20260915T044432Z |
| PASS | gateway | an invalid token on the same route is refused (401), so the 200 above is the credential's |
| PASS | helper | the project was trusted in the scratch config, so all three tiers were loaded |
| PASS | helper | the helper ran; its parent process was claude |
| PASS | helper | it read the credential and minted a token, so it runs OUTSIDE the Bash sandbox |
| PASS | deny | the project was trusted in the scratch config, so all three tiers were loaded |
| PASS | deny | the session's attempt was refused and journalled: deny rule=force-push tool=Bash |
| PASS | deny | the session reported the refusal to the user rather than failing silently |
| PASS | isolation | the developer's own state file was neither modified nor given a scratch project entry |

## Findings

1. `headersHelper` runs as a direct child of the harness process, outside the Bash sandbox: in this run it read `~/.databrickscfg`, minted a token, and reached a host that is on no allowlist (egress_unlisted=ALLOWED). Two consequences. The good one: denying `~/.databrickscfg` to sandboxed commands does not break MCP authentication, which was the open question. The uncomfortable one: the helper is a command named in `.mcp.json` that runs with the developer's full authority and outside every boundary this pack configures. It is trusted code. Review a change to it like a change to a CI credential, and keep `.mcp.json` in the set of files whose edits are not automatic.

2. Permission rules load only in a project whose trust dialog has been accepted. In an untrusted project every `permissions.allow` entry is dropped - the harness says so on one line of stderr that is easy to miss - while deny rules and hooks go on working. The failure is toward refusing rather than permitting, so this is not a security problem, but it is a bad first impression: a team that lands `.claude/settings.json` and starts work without accepting the dialog gets a harness that queries every routine command and looks broken. Accept it once per clone, before judging the configuration.

3. A session started with gateway environment variables is not proof that the gateway served it. During the build of this pack a session started with a deliberately invalid gateway token answered normally, having fallen back to the ambient harness login. Client-side environment variables are a default, not a control. Enforce the route with managed settings on the machine, and verify from the gateway side with `system.ai_gateway.usage` filtered on the request tags - which is why every launch in this pack sets them.

## What this run did not prove

- **The container boundary.** No container runtime was found on this machine (looked for docker, podman, finch, nerdctl), so the container layer could not be exercised at all. Until it is, `.devcontainer/` is a
  verified recipe and not a verified environment. Gap `g-container-runtime`.
- **That a session's model traffic went through the governed route.** The route is
  proved above over HTTP; where a *session* sends its traffic is a separate question
  and the finding about environment variables is why.
- **Authentication created inside the boundary.** The token above is minted outside
  it and scoped to one route. Minting it inside needs the container and a browser
  callback, which is the same blocked gap.
