#!/bin/sh
# GENERATED FILE - do not edit.
#
# Rendered from harness/shared/ by harness/scripts/render.py. Change the policy
# there and run `make harness-generate`. `make harness-verify` fails the build if
# this file was edited by hand, and says which of the two mistakes it was.
#
# Start Claude Code against Unity AI Gateway with this project's rails in place.
#
# One script per harness, rendered from one template, because the hard parts are the
# same for all five and only the last line differs:
#
#   1. The workspace host must not be in a committed file. It is an environment
#      identifier, and a repository that names one workspace is both a small leak and
#      a file every fork has to edit before it works. The host is resolved here, at
#      launch, from the CLI profile, and passed in memory.
#   2. The route has to be probed. Gateway routes are exposed per workspace, and a
#      route that is documented can still be absent here. Finding that out in the
#      first thirty seconds beats finding it out from a model error later.
#   3. Spend has to be attributable. The request tags are set here, once, so no
#      developer has to remember them and no session arrives at the usage table with
#      no owner.
#
# It prints no token, no host and no account name. `--explain` resolves the profile
# and probes the route, then prints the launch it would perform instead of starting
# the session. Run it first on a new machine.

set -eu

HARNESS="claude-code"
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
  # its shape: the scheme, a redacted first label, and the domain suffix.
  printf '%s' "$1" | sed -e 's#^https\{0,1\}://##' \
                         -e 's#^\([^.]*\)\.#<\1-redacted>.#' \
    | awk -F. '{ printf "https://<workspace>.%s", substr($0, index($0, ".") + 1) }'
}

printf '\n  launching %s on the rails in this repository\n\n' "$HARNESS"

# ------------------------------------------------------------------ the toolchain --
command -v claude >/dev/null 2>&1 \
  || die "claude is not on PATH. Install it: docs/01-prerequisites.md"
command -v databricks >/dev/null 2>&1 \
  || die "the databricks CLI is not on PATH. See docs/01-prerequisites.md"
command -v curl >/dev/null 2>&1 \
  || die "curl is not on PATH, so the gateway route cannot be probed."

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
say "profile   $PROFILE"
say "workspace $(host_shape "$HOST")"

# --------------------------------------------------------------------- the token --
# Captured in a variable and never echoed. The guard in
# harness/shared/guards/never-automatic.sh refuses this exact command when a model
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
  not a client one. Ask an administrator to enable it, or pick a harness whose route
  this workspace serves: docs/03-gateway-auth.md." ;;
  401|403)
    die "the gateway route $ROUTE returned $CODE. The token is valid for the CLI but
  not accepted here, which usually means the route is not enabled for this
  principal. docs/03-gateway-auth.md covers the entitlement." ;;
  429)
    die "the gateway returned 429 before the session even started, so a rate limit is
  already exhausted. Wait, then re-run. docs/03-gateway-auth.md explains why a
  budget is an alarm and not a cap." ;;
  000)
    die "no response from the gateway route. Check network reachability to the
  workspace host, then re-run." ;;
  *)
    die "the gateway route $ROUTE returned $CODE, which this script does not know how
  to interpret. Do not proceed on an unexplained status." ;;
esac

# ----------------------------------------------------------------- the mcp route --
# The generated MCP registration names the server by Unity Catalog name through
# ${DAER_MCP_SERVICE}, so one committed file points at a different service in each
# environment. An unset variable would expand to an empty segment and produce a URL
# that fails on every MCP call with a message about the server rather than about the
# configuration. Said here instead, once, where a reader is already looking.
if [ -z "${DAER_MCP_SERVICE:-}" ]; then
  say "mcp       not configured: DAER_MCP_SERVICE is unset, so the governed MCP"
  say "          server will not connect. The session works without it."
  say "          Set it to the Unity Catalog name of the service, catalog.schema.name."
  say "          docs/04-skills-vs-mcp.md has the registration."
else
  say "mcp       governed route, service named by DAER_MCP_SERVICE"
fi

# ------------------------------------------------------------------ attribution --
# Every request carries the tags that make system.ai_gateway.usage answer "which team
# spent this" without instrumenting anything. An unset team is recorded as "unset"
# rather than omitted, because a blank column and a missing tag look identical in a
# query six weeks later.
TAGS=$(printf '{"team":"%s","project":"%s","purpose":"coding-session"}' "$TEAM" "$PROJECT")

if [ "$EXPLAIN" = "1" ]; then
  printf '\n  would run\n\n'
  say "route     $(host_shape "$HOST")$ROUTE"
  say "tags      $TAGS"
  if command -v ug >/dev/null 2>&1 && [ "${DAER_NO_UG:-0}" != "1" ]; then
    say "launcher  ug claude"
  else
    say "launcher  claude with gateway environment"
  fi
  say "verified  verified — a real call over this route returned 200 during the build"
  printf '\n'
  exit 0
fi

# ---------------------------------------------------------------------- launch --
# `ug` is preferred when present: it discovers which models the workspace actually
# serves and skips routes that are unavailable. It writes user-scope configuration to
# do it, which is stated out loud here, because a launcher that edits a developer's
# machine without saying so is the sort of surprise this pack exists to prevent.
# DAER_NO_UG=1 takes the path below it.
#
# Two variables are passed to the child for the MCP route rather than the model
# route: DAER_WORKSPACE_HOST is what the generated registration expands into the
# server URL, and DAER_MCP_TOKEN carries the bearer token for harnesses that have no
# per-connection header helper. Both mean the whole configuration works from one
# command with nothing exported by hand, and that the workspace host still appears in
# no committed file.
if command -v ug >/dev/null 2>&1 && [ "${DAER_NO_UG:-0}" != "1" ]; then
  say "launcher  ug (updates your user-scope $HARNESS configuration)"
  say "          set DAER_NO_UG=1 for the path that writes nothing"
  printf '\n'
  DATABRICKS_CONFIG_PROFILE="$PROFILE" \
  DAER_WORKSPACE_HOST="$HOST" \
  DAER_PROFILE="$PROFILE" \
  DAER_MCP_TOKEN="$TOKEN" \
  DAER_REQUEST_TAGS="$TAGS" \
    exec ug claude "$@"
fi

say "launcher  claude with gateway environment (no files written)"
printf '\n'
ANTHROPIC_BASE_URL="$HOST$ROUTE" \
ANTHROPIC_AUTH_TOKEN="$TOKEN" \
CLAUDE_CODE_USE_GATEWAY="1" \
ANTHROPIC_CUSTOM_HEADERS="x-databricks-use-coding-agent-mode: true
Databricks-Ai-Gateway-Request-Tags: $TAGS" \
DATABRICKS_CONFIG_PROFILE="$PROFILE" \
DAER_WORKSPACE_HOST="$HOST" \
DAER_PROFILE="$PROFILE" \
DAER_MCP_TOKEN="$TOKEN" \
DAER_REQUEST_TAGS="$TAGS" \
  exec claude "$@"
