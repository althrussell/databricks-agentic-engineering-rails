#!/bin/sh
# deny-proof.sh - prove the never-automatic tier actually refuses.
#
# Runs every row of harness/shared/guards/cases.tsv through
# harness/shared/guards/never-automatic.sh and fails on any disagreement, then
# checks that the table and the policy still describe the same set of rules.
#
# Why this exists as a test rather than a screenshot
# --------------------------------------------------
# "Permission tiers with a demonstrated deny" is easy to satisfy once, by hand, in
# a session nobody can re-run. That demonstration decays: the next person edits a
# pattern, the deny stops firing, and the evidence in the document still shows it
# working. This script runs in `make check`, so the deny is demonstrated on every
# change to the repository, and a pattern that stops matching fails the build in
# the same commit that broke it.
#
# It needs no model, no network and no credentials: the guard is a text classifier,
# so its behaviour is fully determined by the string it is given. That is the
# reason the tier was implemented as a classifier plus a table in the first place.
#
# Language: POSIX sh, per docs/DECISIONS/0004-posix-sh-for-diagnostics.md. This
# script has to run inside the execution boundary and in a minimal CI image, next
# to the sh guard it is testing. The one manifest value it reads out of
# permissions.yml is a flat key at a fixed indentation, extracted with awk exactly
# as doctor.sh reads template-version.yml, and the extraction fails loudly when it
# finds nothing rather than reporting success on an empty set.
#
# Exit: 0 every row behaved as specified and the rule sets agree. 1 otherwise.

set -eu

here=$(dirname "$0")
root=$(cd "$here/../.." && pwd)

GUARD="$root/harness/shared/guards/never-automatic.sh"
CASES="$root/harness/shared/guards/cases.tsv"
POLICY="$root/harness/shared/permissions.yml"

TAB=$(printf '\t')

fail() {
  echo "deny-proof: FAIL: $*" >&2
  failures=$((failures + 1))
}

failures=0

# ------------------------------------------------------------------- preflight --
for f in "$GUARD" "$CASES" "$POLICY"; do
  if [ ! -f "$f" ]; then
    echo "deny-proof: missing required file: $f" >&2
    exit 1
  fi
done
if [ ! -x "$GUARD" ]; then
  echo "deny-proof: guard is not executable: $GUARD" >&2
  echo "deny-proof: a guard the harness cannot run is a guard that is not enforcing." >&2
  exit 1
fi

# The guard's usage contract is part of what the hook adapter relies on: an adapter
# that mistakes a usage error for an allow would fail open. Prove exit 2 first.
if "$GUARD" >/dev/null 2>&1; then
  fail "guard exited 0 with no argument; expected the usage error, exit 2"
else
  rc=$?
  [ "$rc" -eq 2 ] || fail "guard exited $rc with no argument; expected 2"
fi

# ------------------------------------------------------------- the case table --
# `while ... done < file` keeps the loop in this shell, so the counters below
# survive. A pipeline would put them in a subshell and every total would print 0.
total=0
denies=0
allows=0
seen_rules=""

while IFS="$TAB" read -r expect rule command why || [ -n "${expect:-}" ]; do
  case "$expect" in
    ''|'#'*) continue ;;
    expect) continue ;;   # the header row
  esac
  if [ -z "${command:-}" ]; then
    fail "row $((total + 1)) has fewer than three tab-separated fields: $expect $rule"
    continue
  fi

  total=$((total + 1))

  out=$("$GUARD" "$command" 2>&1) && rc=0 || rc=$?
  got_rule=$(printf '%s' "$out" | awk -F"$TAB" 'NR==1{print $1}')
  got_reason=$(printf '%s' "$out" | awk -F"$TAB" 'NR==1{print $2}')

  case "$expect" in
    deny)
      denies=$((denies + 1))
      case " $seen_rules " in
        *" $rule "*) ;;
        *) seen_rules="$seen_rules $rule" ;;
      esac
      if [ "$rc" -ne 3 ]; then
        fail "expected deny($rule), got exit $rc: $command"
      elif [ "$got_rule" != "$rule" ]; then
        fail "expected rule $rule, guard said $got_rule: $command"
      elif [ -z "$got_reason" ]; then
        # A deny with no reason is a dead end for whoever hit it. The hook adapter
        # surfaces this string to the model and to the human, and both need to know
        # what to do instead.
        fail "rule $rule denied with an empty reason: $command"
      fi
      ;;
    allow)
      allows=$((allows + 1))
      if [ "$rc" -eq 3 ]; then
        fail "expected no opinion, guard denied as $got_rule: $command"
      elif [ "$rc" -ne 0 ]; then
        fail "expected exit 0, got $rc: $command"
      elif [ -n "$out" ]; then
        fail "guard printed output while allowing, which an adapter may misread: $command"
      fi
      ;;
    *)
      fail "row $total has an unknown expectation '$expect'; use deny or allow"
      ;;
  esac
done < "$CASES"

if [ "$total" -eq 0 ]; then
  echo "deny-proof: the case table is empty. An empty table passes every assertion" >&2
  echo "deny-proof: and proves nothing, so it is treated as a failure." >&2
  exit 1
fi
if [ "$allows" -eq 0 ]; then
  echo "deny-proof: the table has no allow rows. A guard that refuses everything" >&2
  echo "deny-proof: passes a deny test and makes the harness unusable." >&2
  exit 1
fi

# ------------------------------------------------------ table against policy --
# Every never-automatic capability in permissions.yml names a guard_rule. If the
# table does not exercise one, that rule is unproven no matter how many rows pass.
policy_rules=$(awk '/^[ \t]+guard_rule:[ \t]*/ {
                      sub(/^[ \t]+guard_rule:[ \t]*/, "");
                      gsub(/[ \t\r]+$/, "");
                      if ($0 != "") print $0
                    }' "$POLICY" | sort -u)
if [ -z "$policy_rules" ]; then
  echo "deny-proof: found no guard_rule keys in $POLICY." >&2
  echo "deny-proof: either the never-automatic tier lost its guards or this file's" >&2
  echo "deny-proof: shape changed. Both need a human, so this is a failure and not" >&2
  echo "deny-proof: an empty result." >&2
  exit 1
fi

covered=0
for r in $policy_rules; do
  case " $seen_rules " in
    *" $r "*) covered=$((covered + 1)) ;;
    *) fail "permissions.yml declares guard_rule '$r' and no case exercises it" ;;
  esac
done
for r in $seen_rules; do
  if ! printf '%s\n' "$policy_rules" | grep -qx "$r"; then
    fail "cases.tsv expects rule '$r', which permissions.yml does not declare"
  fi
done

declared=$(printf '%s\n' "$policy_rules" | wc -l | tr -d ' ')

if [ "$failures" -ne 0 ]; then
  echo "deny-proof: $failures failure(s) across $total case(s)." >&2
  exit 1
fi

echo "deny-proof: $total cases as specified ($denies deny, $allows allow); $covered/$declared guard rules exercised."
