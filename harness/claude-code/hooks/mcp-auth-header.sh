#!/bin/sh
# GENERATED FILE - do not edit.
#
# Rendered from harness/shared/ by harness/scripts/render.py. Change the policy
# there and run `make harness-generate`. `make harness-verify` fails the build if
# this file was edited by hand, and says which of the two mistakes it was.
#
# headersHelper for the governed MCP route.
#
# Claude Code runs this before every MCP connection, and again when a connection
# answers 401 or 403. It reads a JSON object of string pairs from stdout and merges
# those headers over any static ones, so this is where a short-lived workspace token
# and the gateway's attribution tag come from.
#
# Why a helper rather than a literal header in mcp.json
# ----------------------------------------------------
# `.mcp.json` does expand ${VAR} in `headers`, so `"Authorization": "Bearer
# ${DATABRICKS_TOKEN}"` looks like it would work. Two reasons not to:
#
#   * A set of credential-looking variable names read as empty in a remote server's
#     url and headers, and that set is documented by example rather than
#     exhaustively (claim cc-mcp-var-expansion). A configuration that silently
#     interpolates an empty string produces a 401 that reads like a broken server.
#   * A literal header is a token frozen at launch. Workspace OAuth tokens are
#     short-lived, so a session long enough to be useful outlives it. This helper is
#     re-run on 401, which is exactly the moment a fresh token is wanted.
#
# It also carries the request tag, so MCP traffic is attributable in
# system.ai_gateway.usage the same way model traffic is. Untagged spend has no owner.
#
# Two constraints from the harness worth keeping in view when editing this file:
# stdout must be a JSON object and nothing else, and the whole thing has ten seconds.
# Anything slow or chatty here becomes a failed MCP connection.

set -eu

PROFILE="${DAER_PROFILE:-${DATABRICKS_CONFIG_PROFILE:-DEFAULT}}"
TEAM="${DAER_TEAM:-unset}"
PROJECT="${DAER_PROJECT:-rails-reference}"

# Diagnostics go to stderr, never stdout, because stdout is parsed as JSON. The
# server name and URL arrive in the environment; they are echoed back in the failure
# message because "MCP auth failed" without a server name is unactionable when more
# than one server is registered.
SERVER="${CLAUDE_CODE_MCP_SERVER_NAME:-unknown}"

fail() {
  # No headers on stdout. What Claude Code does with a non-zero headersHelper is not
  # documented, so this script does the two things that are certainly useful: it
  # writes an actionable reason to stderr, where it appears next to the MCP
  # connection error, and it exits non-zero rather than emitting a header object with
  # no Authorization in it. An empty object would let the harness fall back to its own
  # OAuth flow and pop a browser window for a server that never needed one.
  printf 'mcp-auth-header: %s\n' "$1" >&2
  printf 'mcp-auth-header: server=%s profile=%s\n' "$SERVER" "$PROFILE" >&2
  exit 1
}

command -v databricks >/dev/null 2>&1 \
  || fail "the databricks CLI is not on PATH, so no workspace token can be minted."

# Captured in a variable. Never printed except as the header value, never logged, and
# never passed as an argument to another program, where the process table would hold
# it.
raw=$(databricks auth token --profile "$PROFILE" 2>/dev/null) \
  || fail "databricks auth token failed for profile '$PROFILE'. Run: databricks auth login --profile $PROFILE"

token=$(printf '%s' "$raw" | sed -n 's/.*"access_token" *: *"\([^"]*\)".*/\1/p' | head -1)
[ -n "$token" ] \
  || fail "no access_token in the CLI response for profile '$PROFILE'. The profile may be configured but not logged in."

# The output below is assembled by hand rather than by an interpreter, because ten
# seconds is the whole budget and starting python for two string pairs is a poor use
# of it. Hand-assembled JSON is only safe if the values cannot need escaping, so this
# checks rather than assumes: a token is base64url plus separators, and anything
# outside that set is refused instead of emitted into a broken header.
case "$token" in
  *[!A-Za-z0-9._~+/=-]*)
    fail "the minted token contains a character this helper will not put into a JSON string by hand. This is a bug in the helper, not in the token; report it rather than loosening the check." ;;
esac

# The same restriction, for the same reason, on the two tag values a human sets from
# the environment. A team name with a quote in it would otherwise produce malformed
# JSON on stdout, which the harness reports as an unparseable helper response - a
# considerably worse error message than this one.
for v in "$TEAM" "$PROJECT"; do
  case "$v" in
    ""|*[!A-Za-z0-9._-]*)
      fail "DAER_TEAM and DAER_PROJECT become gateway request tags and must be non-empty and limited to letters, digits, dot, underscore and hyphen. Got team='$TEAM' project='$PROJECT'." ;;
  esac
done

printf '{"Authorization":"Bearer %s","Databricks-Ai-Gateway-Request-Tags":"{\\"team\\":\\"%s\\",\\"project\\":\\"%s\\",\\"purpose\\":\\"mcp\\"}"}\n' \
  "$token" "$TEAM" "$PROJECT"
