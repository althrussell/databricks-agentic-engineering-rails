# GitHub Copilot CLI — setup

Thirty minutes on your own laptop, from nothing to a session with rails on.
Prerequisites are in [`docs/01-prerequisites.md`](../../docs/01-prerequisites.md); the
short version is a Databricks CLI you have logged in with and this repository cloned.

## 1. Install

```sh
npm install -g @github/copilot
```

## 2. Log in to Databricks

```sh
databricks auth login --host https://your-workspace.cloud.databricks.com --profile your-profile
export DATABRICKS_CONFIG_PROFILE=your-profile
```

`DATABRICKS_CONFIG_PROFILE` is the CLI's own variable, so every `databricks` command and
every tool that uses the SDK picks up the same profile. Set it in your shell profile and
stop passing `--profile` by hand.

## 3. Check the machine before blaming the harness

```sh
./scripts/doctor.sh
```

Every row is a tool, a version and where to get it. Fix the red rows first. A good share
of "the agent is broken" is a missing CLI or an expired login.

## 4. Point the harness at the gateway

```sh
uv tool install git+https://github.com/databricks/unity-gateway
ug copilot
```

`ug` (also installed as `ucode`) is the Databricks tool that configures a harness to use
Unity AI Gateway. Use it rather than setting the environment by hand: it resolves the
profile, mints a short-lived token and refreshes it, where a hand-set token expires
mid-session and fails in a way that reads like a model error. `ug --refresh` re-mints.

It writes into your own user-scope harness configuration — for Copilot CLI, the MCP
registration only. That is the right thing when you are configuring your own laptop,
which is who this is for, but know that it happens — it is your config, not this
repository's, that changes.

## 5. Install the configuration

```sh
mkdir -p .github
cp harness/copilot-cli/copilot-instructions.md  .github/copilot-instructions.md
cp harness/copilot-cli/mcp-config.json          ~/.copilot/mcp-config.json
```

**Permissions here are command-line flags, not a file.** There is no permission
document to copy, so the tier lives in how you start the session. Put it in an alias so
that starting a session the short way is also starting it the safe way:

```sh
alias copilot-rails='copilot --deny-tool "shell(git push --force)" --deny-tool "shell(gh pr merge)" --deny-tool "shell(databricks bundle deploy)"'
```

A session started with a bare `copilot` has none of those rules in force. That is the
whole weakness of a flag-based tier and there is no way to configure it away.

The `tools` array in `mcp-config.json` is the allowlist of MCP tools this harness may
call. Keep it short: every tool listed costs context in every session.

## 6. Confirm it is actually governed

A session that answers is not a session that went through the gateway. During the build
of this pack a session started with a deliberately invalid gateway token answered
normally, by falling back to an ambient login. The only answer that counts comes from
the gateway side:

```sql
SELECT request_time, model_name, request_tags
FROM system.ai_gateway.usage
WHERE request_time > current_timestamp() - INTERVAL 15 MINUTES
ORDER BY request_time DESC
```

If your session is not in that table, it did not go through the gateway, whatever the
client told you.

## 7. Confirm the rails are live

Inside a session, ask for something in the never-automatic tier — `git push --force` is
the usual one — and watch it be refused.

Then read the limit honestly: a permission rule is matched against the **text of the
command**, so it stops the obvious spelling and not every spelling.
`.github/copilot-instructions.md` is the other half of the tier, for the model choosing
what to run. Keep the two in agreement.

What removes the capability rather than describing it is nothing at this layer. The deny
flags are a text match, there is no working-directory sandbox, and the flags only apply if
you remembered to pass them.

## What this harness cannot express

**`ug copilot` configures MCP and not model routing.** No documented environment
variable points Copilot CLI at a custom model endpoint, so its tools are governed and
its model spend is metered by your Copilot licence. The gateway route documented for it
is shared with OpenCode, and which of the two Copilot CLI actually uses has not been
verified here.

There is also no configuration file for permissions and no pre-execution hook, so the
tier depends on the flags being present every time. An alias is a convention, not a
control.

## Where to look next

- [`docs/02-permissions.md`](../../docs/02-permissions.md) — what the three tiers are
  for, and what defeats each one.
- [`docs/03-gateway-auth.md`](../../docs/03-gateway-auth.md) — routes, request tags,
  and governed versus direct MCP.
