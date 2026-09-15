#!/bin/sh
# GENERATED FILE - do not edit.
#
# Rendered from harness/shared/ by harness/scripts/render.py. Change the policy
# there and run `make harness-generate`. `make harness-verify` fails the build if
# this file was edited by hand, and says which of the two mistakes it was.
#
# PreToolUse adapter: Claude Code's hook protocol on the outside, the shared
# never-automatic classifier on the inside.
#
# Claude Code hands this script a JSON object on stdin and reads a JSON object from
# stdout. The classifier at harness/shared/guards/never-automatic.sh knows nothing about either. Keeping the
# translation here is what lets one policy serve every harness: a second harness
# writes a second adapter, not a second policy.
#
# Three rules this adapter follows, in order of how much damage breaking them does:
#
#   1. It never emits "allow". A hook that allows overrides the ask tier, so an
#      adapter that returned allow for everything the classifier ignores would
#      silently auto-approve every prompt in the configuration. Silence means "no
#      opinion", and the permission rules then decide. This is the single most
#      important line in the file.
#   2. It fails closed. If it cannot read the payload, it denies and says why,
#      rather than treating an unreadable command as a safe one.
#   3. It journals every decision it makes, because a tier that refuses without a
#      record cannot be reviewed or appealed (permissions.yml, design default 3).
#
# The classifier's contract: exit 0 no opinion, exit 3 denied with
# "<rule-id><TAB><reason>" on stdout, exit 2 usage error.

set -eu

GUARD="${CLAUDE_PROJECT_DIR:-.}/harness/shared/guards/never-automatic.sh"
JOURNAL="${CLAUDE_PROJECT_DIR:-.}/.daer/guard-journal.jsonl"

payload=$(cat)

# ------------------------------------------------------------------- interpreter --
# python3 parses the payload and builds the response. Both directions are JSON with
# real escaping rules - a command containing a quote, a newline or a backslash is
# ordinary, and a sed-based extraction would mangle it and then classify the mangled
# text. Rather than guess, this adapter requires python3 and denies without it.
#
# Denying every Bash command because an interpreter is missing is loud and annoying,
# which is the intended failure: a guard that quietly stops guarding is worse.
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1; then PY=$c; break; fi
done

emit_deny() {
  # $1 rule id, $2 reason. Escaping is done by the interpreter, not by hand.
  RULE="$1" REASON="$2" "$PY" -c '
import json, os
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "[%s] %s" % (os.environ["RULE"], os.environ["REASON"]),
}}))
'
}

journal() {
  # $1 verdict, $2 rule, $3 the classified text. Appended, never rotated here; the
  # file is git-ignored and is the reviewable record of what the tier did.
  mkdir -p "$(dirname "$JOURNAL")" 2>/dev/null || return 0
  VERDICT="$1" RULE="$2" TEXT="$3" SESSION="${session_id:-}" TOOL="${tool_name:-}" \
    "$PY" -c '
import json, os, sys, time
row = {
    "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "session": os.environ.get("SESSION", ""),
    "tool": os.environ.get("TOOL", ""),
    "verdict": os.environ.get("VERDICT", ""),
    "rule": os.environ.get("RULE", ""),
    "text": os.environ.get("TEXT", ""),
}
sys.stdout.write(json.dumps(row) + "\n")
' >> "$JOURNAL" 2>/dev/null || true
}

if [ -z "$PY" ]; then
  # No interpreter, so no escaping and no journal. The response below is the one
  # JSON literal in this file that is safe to write by hand: it contains no
  # attacker-controlled text.
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"[guard-unavailable] The permission guard needs python3 to read the tool payload and could not find it. Every command is denied until it is installed, because a guard that cannot read a command cannot judge it."}}'
  exit 0
fi

if [ ! -x "$GUARD" ]; then
  emit_deny guard-unavailable \
    "The never-automatic classifier is missing or not executable at harness/shared/guards/never-automatic.sh. Regenerate with 'make harness-generate' and check the file mode."
  exit 0
fi

# ---------------------------------------------------------------- read the payload --
# One interpreter call for every field, so the payload is parsed once. A field that
# is absent comes back empty, and an unparseable payload sets parse_error.
fields=$(printf '%s' "$payload" | "$PY" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception as exc:
    print("parse_error\t%s" % str(exc).replace("\t", " ").replace("\n", " ")[:200])
    raise SystemExit(0)
if not isinstance(d, dict):
    print("parse_error\tpayload was not a JSON object")
    raise SystemExit(0)
ti = d.get("tool_input") or {}
if not isinstance(ti, dict):
    ti = {}
def clean(v):
    if not isinstance(v, str):
        v = "" if v is None else str(v)
    return v.replace("\t", " ").replace("\r", " ").replace("\n", " ")
print("tool_name\t%s" % clean(d.get("tool_name")))
print("session_id\t%s" % clean(d.get("session_id")))
print("command\t%s" % clean(ti.get("command")))
')

parse_error=""
tool_name=""
session_id=""
command=""
# Read the flat key/value listing back. IFS is a literal tab, so a value containing
# spaces survives intact; the interpreter above already removed tabs from values.
TAB=$(printf '\t')
while IFS="$TAB" read -r k v; do
  case "$k" in
    parse_error) parse_error="$v" ;;
    tool_name) tool_name="$v" ;;
    session_id) session_id="$v" ;;
    command) command="$v" ;;
  esac
done <<EOF
$fields
EOF

if [ -n "$parse_error" ]; then
  journal deny payload-unreadable "$parse_error"
  emit_deny payload-unreadable \
    "The hook could not parse the tool payload, so it cannot tell what this call does. Denied on the fail-safe rule rather than approved on optimism."
  exit 0
fi

# ------------------------------------------------------- choose the text to classify --
# For a shell tool the command is the whole story. For an MCP tool the interesting
# text is the tool's own name: permissions.yml keeps a message-a-person entry with no
# rule string precisely so that registering a messaging server cannot make sending a
# message automatic, and the classifier recognises the mcp__server__tool shape.
case "$tool_name" in
  Bash|PowerShell)
    text="$command" ;;
  mcp__*)
    text="$tool_name" ;;
  *)
    # Some other tool matched the hook. Nothing to classify; stay silent so the
    # permission rules decide.
    exit 0 ;;
esac

if [ -z "$text" ]; then
  # A shell call with no command string is malformed, not harmless.
  if [ "$tool_name" = "Bash" ] || [ "$tool_name" = "PowerShell" ]; then
    journal deny payload-unreadable "empty command on $tool_name"
    emit_deny payload-unreadable \
      "This call names a shell tool with no command in it. Denied because there is nothing to check."
  fi
  exit 0
fi

# ------------------------------------------------------------------------ classify --
verdict=$("$GUARD" "$text" 2>/dev/null) && rc=0 || rc=$?

case "$rc" in
  0)
    # No opinion. Emit nothing: silence leaves the allow, ask and deny rules in
    # charge, and an "allow" here would override the ask tier.
    exit 0 ;;
  3)
    rule=$(printf '%s' "$verdict" | cut -f1)
    reason=$(printf '%s' "$verdict" | cut -f2-)
    journal deny "$rule" "$text"
    emit_deny "$rule" "$reason"
    exit 0 ;;
  *)
    journal deny guard-error "exit $rc on: $text"
    emit_deny guard-error \
      "The permission guard exited $rc instead of returning a verdict. Denied while the guard is broken, because an unchecked command is not a safe one."
    exit 0 ;;
esac
