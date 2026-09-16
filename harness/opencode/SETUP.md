# OpenCode — setup

Thirty minutes on your own laptop, from nothing to a session with rails on.
Prerequisites are in [`docs/01-prerequisites.md`](../../docs/01-prerequisites.md); the
short version is a Databricks CLI you have logged in with and this repository cloned.

## 1. Install

```sh
curl -fsSL https://opencode.ai/install | bash
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
ug opencode
```

`ug` (also installed as `ucode`) is the Databricks tool that configures a harness to use
Unity AI Gateway. Use it rather than setting the environment by hand: it resolves the
profile, mints a short-lived token and refreshes it, where a hand-set token expires
mid-session and fails in a way that reads like a model error. `ug --refresh` re-mints.

It writes into your own user-scope harness configuration — for OpenCode, a custom
provider block in your `opencode.json`. That is the right thing when you are configuring
your own laptop, which is who this is for, but know that it happens — it is your config,
not this repository's, that changes.

## 5. Install the permission configuration

```sh
cp harness/opencode/opencode.json  opencode.json
cp harness/opencode/AGENTS.md      AGENTS.md
```

If `ug opencode` has already written a provider block into your own `opencode.json`,
merge rather than overwrite — take the `permission` and `mcp` blocks from the file here
and leave the provider block `ug` wrote alone.

The last rule in the `bash` block is `"*": "ask"`. That default is the reason the list
above it can be short: anything not named is a prompt, so a rule missing from the
allow tier costs one keystroke rather than opening a hole. Order matters — the specific
patterns must come before the catch-all.

If you keep the `mcp` block, export a token for it:

```sh
export DATABRICKS_TOKEN=$(databricks auth token | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
```

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
command**, so it stops the obvious spelling and not every spelling. `AGENTS.md` in your
project root is the other half of the tier, for the model choosing what to run. Keep the
two in agreement.

What comes closest to removing a capability is the `"*": "ask"` catch-all, which makes a
command nobody listed into a prompt rather than an allow. That is a real improvement on a
deny list, and it is still not a sandbox.

## Where to look next

- [`docs/02-permissions.md`](../../docs/02-permissions.md) — what the three tiers are
  for, and what defeats each one.
- [`docs/03-gateway-auth.md`](../../docs/03-gateway-auth.md) — routes, request tags,
  and governed versus direct MCP.
