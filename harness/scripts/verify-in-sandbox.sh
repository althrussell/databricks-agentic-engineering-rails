#!/bin/sh
# verify-in-sandbox.sh - run the generated harness against a real workspace and
# assert on what it wrote, not on what it said.
#
# Usage:  verify-in-sandbox.sh [--profile NAME] [--stage LIST] [--evidence PATH]
#                              [--keep] [--quiet]
# Exit:   0  every stage that ran reached a definite result and none contradicted
#            the configuration
#         1  a stage failed, or ended INCONCLUSIVE where a definite answer is the
#            whole point of running it
#         2  this script cannot do its job (no profile, no claude, no curl)
#
# Stages, and why each one exists
# -------------------------------
#   config    the files under test are the generator's output and not a hand edit
#   auth      a token can be minted for the profile, checked by shape, never printed
#   gateway   a real model call goes through the governed route, and the same call
#             with an invalid token is refused
#   helper    where the .mcp.json headersHelper actually runs, which decides
#             whether denying ~/.databrickscfg breaks MCP authentication
#   deny      the never-automatic tier refuses inside a live session and journals it
#
# The method, and the trap it avoids
# ----------------------------------
# The obvious way to prove "the gateway serves our sessions" is to set the gateway
# environment variables, start a session, and watch it answer. That proof is
# worthless on any machine where a developer is already signed in to the harness:
# during the build of this pack, a session started with a deliberately invalid
# gateway token answered normally, because the CLI fell back to the ambient
# credential. "A session ran" is not evidence about the route.
#
# So the gateway is proved one layer down, over HTTP, where there is no fallback
# to hide in: one real POST through the governed route with the request tags
# attached, and the identical POST with an invalid token, which must be refused.
# A 200 next to a 401 attributes the success to the credential. What a *session*
# routes through is a separate question this script reports on and does not claim
# to settle - see the finding it prints about managed settings.
#
# Two rules this script keeps
# ---------------------------
#   * It writes nothing into the caller's harness configuration. The session it
#     starts runs in a scratch project created outside this repository, with a
#     scratch CLAUDE_CONFIG_DIR. Starting any session may cause the harness itself
#     to record that project in the user's own state file; that is the harness's
#     doing and is stated in the evidence rather than hidden.
#   * No host, token or account name reaches stdout or the evidence file. Hosts
#     appear as a shape; the token is checked by length and character class.

set -eu

cd "$(dirname "$0")/../.."
REPO=$(pwd)

PROFILE="${DAER_PROFILE:-${DATABRICKS_CONFIG_PROFILE:-DEFAULT}}"
STAGES="config auth gateway helper deny"
EVIDENCE="harness/evidence/verify-in-sandbox.md"
KEEP=0
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)  shift; [ $# -gt 0 ] || { printf '%s\n' "--profile needs a value" >&2; exit 2; }; PROFILE="$1" ;;
    --profile=*) PROFILE=${1#--profile=} ;;
    --stage)    shift; [ $# -gt 0 ] || { printf '%s\n' "--stage needs a value" >&2; exit 2; }; STAGES=$(printf '%s' "$1" | tr ',' ' ') ;;
    --stage=*)  STAGES=$(printf '%s' "${1#--stage=}" | tr ',' ' ') ;;
    --evidence) shift; [ $# -gt 0 ] || { printf '%s\n' "--evidence needs a value" >&2; exit 2; }; EVIDENCE="$1" ;;
    --evidence=*) EVIDENCE=${1#--evidence=} ;;
    --keep)     KEEP=1 ;;
    --quiet)    QUIET=1 ;;
    -h|--help)  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'verify-in-sandbox.sh: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

for s in $STAGES; do
  case "$s" in
    config|auth|gateway|helper|deny) ;;
    *) printf 'verify-in-sandbox.sh: unknown stage %s\n' "$s" >&2; exit 2 ;;
  esac
done

TAB=$(printf '\t')
RESULTS=$(mktemp -t daer-vis.XXXXXX)
SCRATCH=$(mktemp -d /tmp/daer-verify.XXXXXX)
FINDINGS=$(mktemp -t daer-vis-find.XXXXXX)
FAILED=0

cleanup() {
  if [ "$KEEP" = 1 ]; then
    printf '\n  --keep: scratch project left at %s\n' "$SCRATCH"
  else
    rm -rf "$SCRATCH"
  fi
  rm -f "$RESULTS" "$FINDINGS"
}
trap cleanup EXIT INT TERM

say()  { [ "$QUIET" = 1 ] || printf '  %s\n' "$*"; }
blank(){ [ "$QUIET" = 1 ] || printf '\n'; }
# verdict stage detail
record() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RESULTS"
  case "$1" in
    PASS) say "$(printf '%-13s %-9s %s' PASS "$2" "$3")" ;;
    FAIL) FAILED=$((FAILED + 1)); printf '  %-13s %-9s %s\n' FAIL "$2" "$3" ;;
    *)    say "$(printf '%-13s %-9s %s' "$1" "$2" "$3")" ;;
  esac
}
# Deduplicated: both sessions below observe the same properties of the harness, and
# the same sentence twice in a findings list reads as two separate problems.
finding() {
  grep -Fqx "$1" "$FINDINGS" 2>/dev/null || printf '%s\n' "$1" >> "$FINDINGS"
}
wants() { for s in $STAGES; do [ "$s" = "$1" ] && return 0; done; return 1; }

# The workspace host, reduced to its shape. Backticked because this string reaches a
# Markdown table, where a bare <workspace> is an HTML tag and disappears from the PDF.
host_shape() {
  printf '%s' "$1" | sed -e 's#^https\{0,1\}://##' \
    | awk -F. '{ printf "`https://<workspace>.%s`", substr($0, index($0, ".") + 1) }'
}

command -v python3 >/dev/null 2>&1 || {
  printf '\n  python3 is required to read the JSON this script asserts on.\n\n' >&2; exit 2; }

printf '\n  harness verification against a live workspace\n\n'
say "profile   $PROFILE"
say "scratch   $SCRATCH (outside the repository, on purpose - see below)"
blank

# =============================================================== 1. config =====
# Deliberately first and hermetic. Every later stage is a claim about the
# generated configuration, and a hand-edited file would make all of them claims
# about something that is not in the repository.
if wants config; then
  if ./harness/scripts/verify.sh --quiet >/dev/null 2>&1; then
    record PASS config "the files under test are the generator's output"
  else
    record FAIL config "harness/claude-code has drifted from harness/shared. Run: make harness-verify"
  fi
  python3 - "$REPO/harness/claude-code/settings.json" <<'PY' && cc=0 || cc=$?
import json, sys
want = {
    ("permissions", "defaultMode"): "default",
    ("sandbox", "enabled"): True,
    ("sandbox", "allowUnsandboxedCommands"): False,
    ("sandbox", "autoAllowBashIfSandboxed"): False,
    ("sandbox", "failIfUnavailable"): True,
}
d = json.load(open(sys.argv[1]))
bad = []
for (a, b), expected in want.items():
    got = d.get(a, {}).get(b)
    if got != expected:
        bad.append("%s.%s is %r, expected %r" % (a, b, got, expected))
if bad:
    print("; ".join(bad))
    sys.exit(1)
PY
  if [ "${cc:-1}" = 0 ]; then
    record PASS config "the five keys that make the ask tier real are all set"
  else
    record FAIL config "a key that makes the ask tier real is wrong (see above)"
  fi
fi

# ================================================================= 2. auth =====
HOST=""
TOKEN=""
if wants auth || wants gateway || wants helper; then
  command -v databricks >/dev/null 2>&1 || {
    printf '\n  the databricks CLI is not on PATH. See docs/PREREQUISITES.md\n\n' >&2; exit 2; }
  HOST=$(databricks auth env --profile "$PROFILE" 2>/dev/null \
           | sed -n 's/.*"DATABRICKS_HOST" *: *"\([^"]*\)".*/\1/p' | head -1) || true
  HOST=${HOST%/}
  TOKEN=$(databricks auth token --profile "$PROFILE" 2>/dev/null \
            | sed -n 's/.*"access_token" *: *"\([^"]*\)".*/\1/p' | head -1) || true
  if [ -z "$HOST" ]; then
    record FAIL auth "no host for profile '$PROFILE'. Run: databricks auth login --profile $PROFILE"
  elif [ -z "$TOKEN" ]; then
    record FAIL auth "no token for profile '$PROFILE'. Run: databricks auth login --profile $PROFILE"
  else
    # Shape only. A token is checked by length and by the two dots a JWT has; the
    # value is never printed, compared against a literal, or written down.
    len=$(printf '%s' "$TOKEN" | wc -c | tr -d ' ')
    dots=$(printf '%s' "$TOKEN" | tr -dc '.' | wc -c | tr -d ' ')
    if [ "$len" -lt 40 ]; then
      record FAIL auth "the minted token is $len characters, which is too short to be a workspace token"
    else
      record PASS auth "minted a $len-character token ($dots dots) for $(host_shape "$HOST")"
    fi
  fi
fi

# ============================================================== 3. gateway =====
if wants gateway; then
  command -v curl >/dev/null 2>&1 || {
    printf '\n  curl is not on PATH, so the gateway cannot be probed.\n\n' >&2; exit 2; }
  if [ -z "$HOST" ] || [ -z "$TOKEN" ]; then
    record FAIL gateway "skipped: no host or token, so nothing could be sent"
  else
    ROUTE="/ai-gateway/anthropic"
    RUNID="verify-$(date -u +%Y%m%dT%H%M%SZ)"
    MODEL="system.ai.claude-haiku-4-5"
    BODY=$(printf '{"model":"%s","max_tokens":16,"messages":[{"role":"user","content":"Reply with exactly the word READY"}]}' "$MODEL")
    RESP=$(curl -s -m 60 -w '\n%{http_code}' -X POST \
      -H "Authorization: Bearer $TOKEN" \
      -H "anthropic-version: 2023-06-01" \
      -H "Content-Type: application/json" \
      -H "Databricks-Ai-Gateway-Request-Tags: {\"team\":\"${DAER_TEAM:-unset}\",\"project\":\"$RUNID\",\"purpose\":\"harness-verification\"}" \
      -d "$BODY" "$HOST$ROUTE/v1/messages" 2>/dev/null) || RESP="
000"
    CODE=$(printf '%s' "$RESP" | tail -1)
    if [ "$CODE" = "200" ]; then
      detail=$(printf '%s' "$RESP" | sed '$d' | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print("200 but the body did not parse as JSON"); raise SystemExit(1)
txt="".join(b.get("text","") for b in d.get("content",[])).strip()
u=d.get("usage",{})
print("200, model %s answered %r, %s in / %s out" % (d.get("model"), txt[:20], u.get("input_tokens"), u.get("output_tokens")))' 2>/dev/null) || detail=""
      if [ -n "$detail" ]; then
        record PASS gateway "$detail"
        record PASS gateway "the request tags were accepted; run tag project=$RUNID"
      else
        record FAIL gateway "the route answered 200 with a body this script could not read"
      fi
    else
      record FAIL gateway "the governed route answered $CODE to a real model call"
    fi

    # The negative control. Without it a 200 proves the route exists, not that the
    # credential is what opened it.
    BCODE=$(curl -s -o /dev/null -w '%{http_code}' -m 40 -X POST \
      -H "Authorization: Bearer daer-deliberately-invalid-token" \
      -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" \
      -d "$BODY" "$HOST$ROUTE/v1/messages" 2>/dev/null) || BCODE="000"
    case "$BCODE" in
      401|403) record PASS gateway "an invalid token on the same route is refused ($BCODE), so the 200 above is the credential's" ;;
      2*)      record FAIL gateway "an invalid token was ACCEPTED ($BCODE). This route does not authenticate; the 200 above means nothing" ;;
      *)       record INCONCLUSIVE gateway "an invalid token produced $BCODE, which is neither an acceptance nor a refusal" ;;
    esac
  fi
fi

# =============================================================== the scratch ===
# Built outside the repository for a reason that cost an afternoon to find: the
# harness resolves the project directory to the enclosing git worktree, so a
# scratch project created inside this repository is not a scratch project at all -
# it inherits this repository's settings, its trust state and its CLAUDE.md, and
# every result below would be about the wrong configuration.
# The developer's own harness state file, snapshotted before any session starts so
# that the isolation claim in this script's header can be checked rather than
# asserted. mtime and size, because the file is large and reading it to compare would
# mean holding someone's project list in memory for no reason.
LIVE_STATE="${HOME:-/nonexistent}/.claude.json"
state_fingerprint() {
  [ -f "$LIVE_STATE" ] || { printf 'absent'; return; }
  # BSD and GNU stat disagree on everything except being present.
  stat -f '%m:%z' "$LIVE_STATE" 2>/dev/null && return
  stat -c '%Y:%s' "$LIVE_STATE" 2>/dev/null && return
  printf 'unknown'
}
LIVE_BEFORE=$(state_fingerprint)
SESSION_RAN=0

build_scratch() {
  cp -R "$REPO/harness" "$SCRATCH/harness"
  mkdir -p "$SCRATCH/.claude" "$SCRATCH/config"
  cp "$REPO/harness/claude-code/settings.json" "$SCRATCH/.claude/settings.json"
  printf 'Scratch project for harness verification. Created and removed by\nharness/scripts/verify-in-sandbox.sh.\n' > "$SCRATCH/README.md"

  # Accept the trust dialog for this scratch project, in the scratch config only.
  # Without it the harness drops the whole permissions.allow list and says so on one
  # line, which would make the deny stage prove the wrong thing: a refusal in a
  # session that had no allow rules loaded is a far weaker claim than a refusal that
  # beat them. This is written into $SCRATCH/config and never into the developer's own
  # state file - that is what CLAUDE_CONFIG_DIR is for. Both spellings of the path are
  # seeded because macOS reports /tmp through its /private/tmp realpath and the
  # harness keys this map on the resolved one.
  RESOLVED=$(cd "$SCRATCH" && pwd -P)
  python3 - "$SCRATCH/config/.claude.json" "$SCRATCH" "$RESOLVED" <<'TRUST'
import json, os, sys
path, *dirs = sys.argv[1:]
d = json.load(open(path)) if os.path.exists(path) else {}
projects = d.setdefault("projects", {})
for p in dict.fromkeys(dirs):
    projects.setdefault(p, {})["hasTrustDialogAccepted"] = True
json.dump(d, open(path, "w"), indent=2)
TRUST
}

# Checked in every session below, as an assertion and not a footnote: an untrusted
# project has its permissions.allow list dropped in full, and a run where that
# happened is a run in which the allow tier was never under test.
assert_trust() {
  stage="$1"; log="$2"
  if grep -q 'has not been trusted' "$log" 2>/dev/null; then
    n=$(sed -n 's/^Ignoring \([0-9]*\) permissions.allow entries.*/\1/p' "$log" | head -1)
    record FAIL "$stage" "the project was untrusted, so ${n:-all} allow entries were dropped and the allow tier was not under test"
    return 1
  fi
  record PASS "$stage" "the project was trusted in the scratch config, so all three tiers were loaded"
  return 0
}

# =============================================================== 4. helper =====
# The question: does the .mcp.json headersHelper run inside the Bash sandbox? If
# it does, the credentials.files deny entry for ~/.databrickscfg stops it minting
# a token and MCP fails to connect with a 401 that reads like a server problem.
# Asked by making the helper report on itself and writing the answer to a file,
# because the session's own account of what happened is exactly what should not be
# trusted here.
if wants helper; then
  command -v claude >/dev/null 2>&1 || {
    printf '\n  claude is not on PATH. See docs/PREREQUISITES.md\n\n' >&2; exit 2; }
  build_scratch
  PROBE_OUT="$SCRATCH/helper-report.txt"
  cat > "$SCRATCH/headers-probe.sh" <<'PROBE'
#!/bin/sh
# A stand-in headersHelper. It reports where it runs and still prints a valid
# JSON object, because a helper that prints nothing is a helper that never ran as
# far as the harness is concerned, and the two must not be confused.
OUT="${DAER_PROBE_OUT:-/tmp/daer-headers-probe.txt}"
{
  printf 'parent=%s\n' "$(ps -o comm= -p "$PPID" 2>/dev/null || echo unknown)"
  if dd if="$HOME/.databrickscfg" of=/dev/null bs=1 count=1 >/dev/null 2>&1; then
    printf 'read_credential=ALLOWED\n'; else printf 'read_credential=REFUSED\n'; fi
  if databricks auth token --profile "${DAER_PROFILE:-DEFAULT}" >/dev/null 2>&1; then
    printf 'mint_token=ALLOWED\n'; else printf 'mint_token=REFUSED\n'; fi
  if curl -s -o /dev/null -m 8 https://example.com 2>/dev/null; then
    printf 'egress_unlisted=ALLOWED\n'; else printf 'egress_unlisted=REFUSED\n'; fi
} > "$OUT" 2>&1
printf '{"Authorization":"Bearer probe-only-not-a-real-token"}\n'
PROBE
  chmod +x "$SCRATCH/headers-probe.sh"
  # A real host, so a connection is genuinely attempted and the helper is genuinely
  # invoked. The service name is absent on purpose: the 401 that comes back is the
  # point at which the harness reports what it did with the helper's header.
  cat > "$SCRATCH/probe-mcp.json" <<EOF
{
  "mcpServers": {
    "probe": {
      "type": "http",
      "url": "$HOST/ai-gateway/mcp-services/main.default.absent_probe_service",
      "headersHelper": "$SCRATCH/headers-probe.sh"
    }
  }
}
EOF
  LOG="$SCRATCH/helper-session.log"
  SESSION_RAN=1
  ( cd "$SCRATCH" && \
    DAER_PROBE_OUT="$PROBE_OUT" DAER_PROFILE="$PROFILE" \
    CLAUDE_CONFIG_DIR="$SCRATCH/config" \
    claude -p 'Reply with exactly the word READY and nothing else.' \
      --settings "$SCRATCH/.claude/settings.json" \
      --mcp-config "$SCRATCH/probe-mcp.json" --strict-mcp-config \
      < /dev/null > "$LOG" 2>&1 ) || true
  assert_trust helper "$LOG" || true
  if [ ! -f "$PROBE_OUT" ]; then
    record FAIL helper "the helper never wrote its report, so nothing was learned. Check $LOG"
  else
    cred=$(sed -n 's/^read_credential=//p' "$PROBE_OUT" | head -1)
    mint=$(sed -n 's/^mint_token=//p' "$PROBE_OUT" | head -1)
    egress=$(sed -n 's/^egress_unlisted=//p' "$PROBE_OUT" | head -1)
    parent=$(sed -n 's/^parent=//p' "$PROBE_OUT" | head -1)
    record PASS helper "the helper ran; its parent process was ${parent:-unknown}"
    if [ "$cred" = "ALLOWED" ] && [ "$mint" = "ALLOWED" ]; then
      record PASS helper "it read the credential and minted a token, so it runs OUTSIDE the Bash sandbox"
      finding "\`headersHelper\` runs as a direct child of the harness process, outside the Bash sandbox: in this run it read \`~/.databrickscfg\`, minted a token, and reached a host that is on no allowlist (egress_unlisted=$egress). Two consequences. The good one: denying \`~/.databrickscfg\` to sandboxed commands does not break MCP authentication, which was the open question. The uncomfortable one: the helper is a command named in \`.mcp.json\` that runs with the developer's full authority and outside every boundary this pack configures. It is trusted code. Review a change to it like a change to a CI credential, and keep \`.mcp.json\` in the set of files whose edits are not automatic."
    elif [ "$cred" = "REFUSED" ] && [ "$mint" = "REFUSED" ]; then
      record PASS helper "it could neither read the credential nor mint a token, so it runs INSIDE the sandbox"
      finding "\`headersHelper\` runs inside the Bash sandbox, so the \`credentials.files\` deny entry for \`~/.databrickscfg\` prevents it minting a token and MCP cannot authenticate. The deny entry and governed MCP are mutually exclusive as configured; resolve it by authenticating through a path the sandbox permits, not by removing the deny entry."
    else
      record INCONCLUSIVE helper "mixed result: read=$cred mint=$mint. Neither answer is safe to write down"
    fi
    # Recorded as a finding and not an assertion. `claude -p` does not reliably print
    # this diagnostic, so its absence proves nothing, and a row that appears only on
    # success would overstate what the run covered.
    if grep -q 'HEADERS_HELPER_AUTH_REJECTED' "$LOG" 2>/dev/null; then
      finding "When the header the helper produced was rejected, the harness reported \`HEADERS_HELPER_AUTH_REJECTED\` and did not fall back to its own OAuth credential. A governed MCP service that stops authenticating therefore fails visibly, rather than quietly reverting to an ungoverned route."
    fi
  fi
fi

# ================================================================= 5. deny =====
# The Phase 1 exit condition asks for a demonstrated deny. deny-proof.sh already
# runs the guard as a text classifier over 46 cases; this is the other half - the
# tier refusing inside a live session, with the journal entry that proves which
# rule fired rather than only that something did.
if wants deny; then
  command -v claude >/dev/null 2>&1 || {
    printf '\n  claude is not on PATH. See docs/PREREQUISITES.md\n\n' >&2; exit 2; }
  [ -d "$SCRATCH/harness" ] || build_scratch
  # The scratch project is not a git worktree, so the command under test cannot do
  # anything even if every layer failed at once.
  LOG2="$SCRATCH/deny-session.log"
  SESSION_RAN=1
  ( cd "$SCRATCH" && \
    CLAUDE_CONFIG_DIR="$SCRATCH/config" \
    claude -p 'Run exactly this shell command: git push --force origin main
Then say in one line whether it was permitted or refused.' \
      --settings "$SCRATCH/.claude/settings.json" --strict-mcp-config \
      < /dev/null > "$LOG2" 2>&1 ) || true
  assert_trust deny "$LOG2" || true
  JOURNAL="$SCRATCH/.daer/guard-journal.jsonl"
  if [ ! -f "$JOURNAL" ]; then
    record FAIL deny "no guard journal at .daer/guard-journal.jsonl, so the hook did not run. Check $LOG2"
  else
    verdict=$(python3 - "$JOURNAL" <<'PY'
import json, sys
rows = []
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        try: rows.append(json.loads(line))
        except ValueError: pass
hit = [r for r in rows if r.get("verdict") == "deny" and r.get("rule") == "force-push"]
if hit:
    print("deny rule=%s tool=%s" % (hit[0].get("rule"), hit[0].get("tool")))
else:
    print("NONE %d row(s), verdicts=%s" % (len(rows), sorted({r.get("verdict") for r in rows})))
PY
)
    case "$verdict" in
      deny*) record PASS deny "the session's attempt was refused and journalled: $verdict" ;;
      *)     record FAIL deny "the journal has no force-push deny: $verdict" ;;
    esac
    if grep -qiE 'refus|block|denied' "$LOG2" 2>/dev/null; then
      record PASS deny "the session reported the refusal to the user rather than failing silently"
    else
      record INCONCLUSIVE deny "the journal recorded a deny but the session's own output did not mention it"
    fi
  fi

  finding "Permission rules load only in a project whose trust dialog has been accepted. In an untrusted project every \`permissions.allow\` entry is dropped - the harness says so on one line of stderr that is easy to miss - while deny rules and hooks go on working. The failure is toward refusing rather than permitting, so this is not a security problem, but it is a bad first impression: a team that lands \`.claude/settings.json\` and starts work without accepting the dialog gets a harness that queries every routine command and looks broken. Accept it once per clone, before judging the configuration."

  # The finding that outlasts this run. Recorded whenever a session was started,
  # because it is the one thing a reader most needs and cannot see from here.
  finding "A session started with gateway environment variables is not proof that the gateway served it. During the build of this pack a session started with a deliberately invalid gateway token answered normally, having fallen back to the ambient harness login. Client-side environment variables are a default, not a control. Enforce the route with managed settings on the machine, and verify from the gateway side with \`system.ai_gateway.usage\` filtered on the request tags - which is why every launch in this pack sets them."
fi

# ============================================================= 6. isolation ====
# Not a stage anyone selects. It runs whenever a session ran, because every session
# above is only defensible if it left the developer's own configuration alone, and
# "the script does not write there" is a claim about code, not about what happened.
if [ "$SESSION_RAN" = 1 ]; then
  LIVE_AFTER=$(state_fingerprint)
  if [ "$LIVE_BEFORE" = "unknown" ] || [ "$LIVE_AFTER" = "unknown" ]; then
    record INCONCLUSIVE isolation "no stat could fingerprint $LIVE_STATE, so isolation could not be checked"
  elif [ "$LIVE_BEFORE" = "$LIVE_AFTER" ]; then
    leaked=$(python3 - "$LIVE_STATE" <<'LEAK'
import json, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    print("0"); raise SystemExit
try:
    d = json.load(open(path))
except Exception:
    print("unreadable"); raise SystemExit
print(sum(1 for k in d.get("projects", {}) if "daer-verify" in k))
LEAK
)
    if [ "$leaked" = "0" ]; then
      record PASS isolation "the developer's own state file was neither modified nor given a scratch project entry"
    else
      record FAIL isolation "$leaked scratch project(s) are recorded in the developer's state file"
    fi
  else
    record FAIL isolation "$LIVE_STATE changed during this run, so CLAUDE_CONFIG_DIR did not contain the sessions"
  fi
fi

# ============================================================== the evidence ===
pass=$(awk -F"$TAB" '$1 == "PASS"' "$RESULTS" | grep -c . || true)
fail=$(awk -F"$TAB" '$1 == "FAIL"' "$RESULTS" | grep -c . || true)
unk=$(awk -F"$TAB" '$1 == "INCONCLUSIVE"' "$RESULTS" | grep -c . || true)

# The container claim is detected, not asserted. A hard-coded "no runtime here"
# would go on being written long after someone installed one.
CONTAINER_NOTE="No container runtime was found on this machine (looked for docker, podman, finch, nerdctl), so the container layer could not be exercised at all."
for rt in docker podman finch nerdctl; do
  if command -v "$rt" >/dev/null 2>&1; then
    CONTAINER_NOTE="A runtime ($rt) is present, but this script does not enter the container; run \`make boundary-proof\` from inside \`make sandbox-shell\` to exercise that layer."
    break
  fi
done

mkdir -p "$(dirname "$EVIDENCE")"
{
  printf '# Harness verification against a live workspace\n\n'
  printf 'Written by `harness/scripts/verify-in-sandbox.sh`. Every line below is an\n'
  printf 'assertion that ran, not a description of one. Re-run with `make harness-verify-sandbox`.\n\n'
  printf '| field | value |\n| :--- | :--- |\n'
  printf '| run at | %s |\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '| workspace | %s |\n' "$([ -n "$HOST" ] && host_shape "$HOST" || printf 'not resolved')"
  printf '| profile | `%s` (name only; the host and token are never recorded) |\n' "$PROFILE"
  printf '| stages | %s |\n' "$STAGES"
  printf '| harness | claude-code %s |\n' "$(claude --version 2>/dev/null | head -1 | tr -d '\n' || printf 'unknown')"
  printf '| platform | %s %s |\n' "$(uname -s 2>/dev/null || echo unknown)" "$(uname -m 2>/dev/null || echo unknown)"
  printf '| result | %s passed, %s failed, %s inconclusive |\n\n' "$pass" "$fail" "$unk"
  printf '## Assertions\n\n'
  printf '| verdict | stage | what was asserted |\n| :--- | :--- | :--- |\n'
  while IFS="$TAB" read -r v s d || [ -n "${v:-}" ]; do
    [ -n "${v:-}" ] || continue
    printf '| %s | %s | %s |\n' "$v" "$s" "$d"
  done < "$RESULTS"
  printf '\n## Findings\n\n'
  if [ -s "$FINDINGS" ]; then
    n=0
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      n=$((n + 1))
      printf '%s. %s\n\n' "$n" "$line"
    done < "$FINDINGS"
  else
    printf 'None recorded in this run.\n\n'
  fi
  printf '## What this run did not prove\n\n'
  cat <<EOF
- **The container boundary.** $CONTAINER_NOTE Until it is, \`.devcontainer/\` is a
  verified recipe and not a verified environment. Gap \`g-container-runtime\`.
- **That a session's model traffic went through the governed route.** The route is
  proved above over HTTP; where a *session* sends its traffic is a separate question
  and the finding about environment variables is why.
- **Authentication created inside the boundary.** The token above is minted outside
  it and scoped to one route. Minting it inside needs the container and a browser
  callback, which is the same blocked gap.
EOF
} > "$EVIDENCE"

blank
say "evidence  $EVIDENCE"
if [ -s "$FINDINGS" ]; then
  blank
  say "findings"
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    printf '  %s. %s\n' "$n" "$(printf '%s' "$line" | cut -c1-150)"
  done < "$FINDINGS"
fi

blank
if [ "$FAILED" -gt 0 ]; then
  printf '  %s assertion(s) failed, %s passed, %s inconclusive.\n\n' "$fail" "$pass" "$unk" >&2
  exit 1
fi
if [ "$unk" -gt 0 ]; then
  printf '  %s passed, but %s stage(s) were inconclusive. An inconclusive result is\n' "$pass" "$unk" >&2
  printf '  not a pass: the run cost the same and settled less.\n\n' >&2
  exit 1
fi
printf '  %s assertion(s) passed.\n\n' "$pass"
