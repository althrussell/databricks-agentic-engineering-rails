#!/bin/sh
# GENERATED FILE - do not edit.
#
# Rendered from harness/shared/ by harness/scripts/render.py. Change the policy
# there and run `make harness-generate`. `make harness-verify` fails the build if
# this file was edited by hand, and says which of the two mistakes it was.
#
# Start Claude Code against Unity AI Gateway with this project's rails in place.
#
# There are three reasons this script exists rather than a paragraph of instructions
# telling someone to export four variables:
#
#   1. The workspace host must not be in a committed file. It is an environment
#      identifier, and a repository that names one workspace is both a small leak and
#      a file every fork has to edit before it works. The host is resolved here, at
#      launch, from the CLI profile, and passed in memory.
#   2. Two settings that matter cannot be delivered from a committed project file.
#      `sandbox.network.strictAllowlist` is ignored in `.claude/settings.json` and
#      only takes effect from user, managed or `--settings` scope, and the looser
#      permission modes are likewise ignored from project scope. A project that needs
#      them has to pass them on the command line, which is what this script does.
#   3. The route has to be probed. Gateway routes are exposed per workspace, and a
#      route that is documented can still be absent here: on the workspace this pack
#      was verified against, the Anthropic route answered and two others did not
#      (claim probe-gw-route-coverage). Finding that out in the first thirty seconds
#      beats finding it out from a model error later.
#
# It prints no token, no host and no account name. `--explain` resolves the profile and
# probes the route, then prints the launch it would perform instead of starting the
# session.

set -eu

PROFILE="${DAER_PROFILE:-${DATABRICKS_CONFIG_PROFILE:-DEFAULT}}"
ROUTE="/ai-gateway/anthropic"
PROBE_PATH="/ai-gateway/anthropic/v1/models"
TEAM="${DAER_TEAM:-unset}"
PROJECT="${DAER_PROJECT:-rails-reference}"
EXPLAIN=0

for arg in "$@"; do
  case "$arg" in
    --explain) EXPLAIN=1 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
die()  { printf '\n  %s\n\n' "$*" >&2; exit 1; }
host_shape() {
  # A host is an identifier. When one has to appear in output at all, it appears as
  # its shape: the scheme, the first label's length, and the domain suffix.
  printf '%s' "$1" | sed -e 's#^https\{0,1\}://##' \
                         -e 's#^\([^.]*\)\.#<\1-redacted>.#' \
    | awk -F. '{ printf "https://<workspace>.%s", substr($0, index($0, ".") + 1) }'
}

printf '\n  launching claude code on the rails in this repository\n\n'

# ------------------------------------------------------------------ the toolchain --
command -v claude >/dev/null 2>&1 || die "claude is not on PATH. See docs/PREREQUISITES.md"
command -v databricks >/dev/null 2>&1 || die "the databricks CLI is not on PATH. See docs/PREREQUISITES.md"
command -v curl >/dev/null 2>&1 || die "curl is not on PATH, so the gateway route cannot be probed."

# --------------------------------------------------------------------- the host --
# DATABRICKS_HOST wins when it is set, because that is what the CLI itself does and a
# script that disagreed with the CLI would be a trap. Otherwise it comes from the
# named profile.
HOST="${DATABRICKS_HOST:-}"
if [ -z "$HOST" ]; then
  HOST=$(databricks auth env --profile "$PROFILE" 2>/dev/null \
           | sed -n 's/.*"DATABRICKS_HOST" *: *"\([^"]*\)".*/\1/p' | head -1) || true
fi
if [ -z "$HOST" ]; then
  die "no workspace host for profile '$PROFILE'. Run: databricks auth login --profile $PROFILE"
fi
HOST=$(printf '%s' "$HOST" | sed 's#/*$##')
HOST_DOMAIN=$(printf '%s' "$HOST" | sed -e 's#^https\{0,1\}://##' -e 's#/.*##')
say "profile   $PROFILE"
say "workspace $(host_shape "$HOST")"

# --------------------------------------------------------------------- the token --
# Captured in a variable and never echoed. The guard in
# harness/shared/guards/never-automatic.sh refuses this exact command when the model
# proposes it, for the same reason: its output belongs in memory, not in a transcript.
TOKEN=$(databricks auth token --profile "$PROFILE" 2>/dev/null \
          | sed -n 's/.*"access_token" *: *"\([^"]*\)".*/\1/p' | head -1) || true
if [ -z "$TOKEN" ]; then
  die "could not obtain a token for profile '$PROFILE'. Run: databricks auth login --profile $PROFILE"
fi

# --------------------------------------------------------------------- the probe --
# PROBE_PATH is a whole path on the workspace, route included, so it is appended to
# the host and not to the route. Appending both would probe a doubled path and get a
# 404 that reads like a missing route.
CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 20 \
         -H "Authorization: Bearer $TOKEN" \
         "$HOST$PROBE_PATH" 2>/dev/null) || CODE="000"
case "$CODE" in
  200)
    say "gateway   $ROUTE answered 200" ;;
  404)
    die "the gateway route $ROUTE returned 404 on this workspace.
  Routes are exposed per workspace, so this is a workspace configuration question,
  not a client one. docs/03-gateway-auth-and-governance.md has the admin steps." ;;
  401|403)
    die "the gateway route $ROUTE returned $CODE. The token is valid for the CLI but
  not accepted here, which usually means the route is not enabled for this
  principal. docs/03-gateway-auth-and-governance.md covers the entitlement." ;;
  429)
    die "the gateway returned 429 before the session even started, so a rate limit is
  already exhausted. docs/11-admin-runbook.md covers reading and raising it." ;;
  000)
    die "no response from the gateway route. Check network reachability to the
  workspace host, then re-run." ;;
  *)
    die "the gateway route $ROUTE returned $CODE, which this script does not know how
  to interpret. Do not proceed on an unexplained status." ;;
esac

# ----------------------------------------------------------------- the mcp route --
# mcp.json names the server by Unity Catalog name through ${DAER_MCP_SERVICE}, so that
# one committed file points at a different service in each environment. Unlike
# settings.json, .mcp.json does expand ${VAR} - which is why the host and the service
# name can be variables there and cannot be in the settings file.
#
# An unset variable would expand to an empty segment and produce a URL that fails on
# every MCP call with a message about the server, not about the configuration. Said
# here instead, once, in the one place a reader is already looking.
if [ -z "${DAER_MCP_SERVICE:-}" ]; then
  say "mcp       not configured: DAER_MCP_SERVICE is unset, so the governed MCP"
  say "          server will not connect. The session works without it."
  say "          Set it to the Unity Catalog name of the MCP service, as"
  say "          catalog.schema.name. docs/04-mcp-and-skills.md has the registration."
else
  say "mcp       governed route, service named by DAER_MCP_SERVICE"
fi

# ------------------------------------------------------------- runtime settings --
# The keys a committed project file cannot deliver. Written to a file rather than
# passed inline so that no workspace host appears in the process table, where any
# other user on the machine can read it.
#
# The file outlives this script on purpose. The last line of this script is an `exec`,
# which replaces this process, so an EXIT trap would never run - and even if it did,
# deleting the settings file out from under a session that may re-read it is the wrong
# trade. mktemp creates it 0600 and the chmod says so out loud. It holds the workspace
# domain and no credential.
RUNTIME_SETTINGS="$(mktemp -t daer-settings.XXXXXX)"
chmod 600 "$RUNTIME_SETTINGS"
cat > "$RUNTIME_SETTINGS" <<JSON
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "network": {
      "strictAllowlist": true,
      "allowedDomains": ["$HOST_DOMAIN","docs.databricks.com","developers.databricks.com","code.claude.com","registry.npmjs.org","pypi.org","files.pythonhosted.org","github.com","api.github.com","objects.githubusercontent.com"]
    }
  }
}
JSON

# ------------------------------------------------------------------ attribution --
# Every request carries the tags that make system.ai_gateway.usage answer "which team
# spent this" without instrumenting anything (claim gw-request-tags-header). An
# unset team is recorded as "unset" rather than omitted, because a blank column and a
# missing tag look identical in a query six weeks later.
TAGS=$(printf '{"team":"%s","project":"%s","purpose":"coding-session"}' "$TEAM" "$PROJECT")

if [ "$EXPLAIN" = "1" ]; then
  printf '\n  would run\n\n'
  say "route     $(host_shape "$HOST")$ROUTE"
  say "tags      $TAGS"
  say "settings  strictAllowlist true, workspace domain added at launch"
  if command -v ug >/dev/null 2>&1 && [ "${DAER_NO_UG:-0}" != "1" ]; then
    say "launcher  ug claude"
  else
    say "launcher  claude with gateway environment"
  fi
  printf '\n'
  rm -f "$RUNTIME_SETTINGS"
  exit 0
fi

# ---------------------------------------------------------------------- launch --
# Two variables are passed to the child for the MCP route rather than the model route:
# DAER_WORKSPACE_HOST is what .mcp.json expands into the server URL, and DAER_PROFILE
# is what hooks/mcp-auth-header.sh mints a token from. Passing them here means the
# whole configuration works from one command with nothing exported by hand, and that
# the workspace host still appears in no committed file.
# `ug` is preferred when present: it discovers which models the workspace actually
# serves, skips routes that are unavailable, and replaces the built-in web search
# that the gateway rejects. It writes user-scope configuration under ~/.claude to do
# it, which is stated out loud here because a launcher that edits a developer's
# machine without saying so is the sort of surprise this pack exists to prevent.
# DAER_NO_UG=1 takes the environment-only path, which touches no file at all.
if command -v ug >/dev/null 2>&1 && [ "${DAER_NO_UG:-0}" != "1" ]; then
  say "launcher  ug (updates your user-scope Claude Code configuration)"
  say "          set DAER_NO_UG=1 for the environment-only path"
  printf '\n'
  ANTHROPIC_CUSTOM_HEADERS="x-databricks-use-coding-agent-mode: true
Databricks-Ai-Gateway-Request-Tags: $TAGS" \
  DATABRICKS_CONFIG_PROFILE="$PROFILE" \
  DAER_WORKSPACE_HOST="$HOST" \
  DAER_PROFILE="$PROFILE" \
    exec ug claude --settings "$RUNTIME_SETTINGS" "$@"
fi

say "launcher  claude with gateway environment (no files written)"
printf '\n'
ANTHROPIC_BASE_URL="$HOST$ROUTE" \
ANTHROPIC_AUTH_TOKEN="$TOKEN" \
ANTHROPIC_CUSTOM_HEADERS="x-databricks-use-coding-agent-mode: true
Databricks-Ai-Gateway-Request-Tags: $TAGS" \
CLAUDE_CODE_USE_GATEWAY=1 \
DATABRICKS_CONFIG_PROFILE="$PROFILE" \
DAER_WORKSPACE_HOST="$HOST" \
DAER_PROFILE="$PROFILE" \
  exec claude --settings "$RUNTIME_SETTINGS" "$@"
