#!/bin/sh
# boundary-proof.sh - make the execution boundary refuse something, and watch it.
#
# Usage:  boundary-proof.sh [--offline] [--expect boundary|none|auto] [--probe-check] [--quiet]
# Exit:   0  the expectation held
#         1  the expectation did not hold: a limit that should refuse did not
#         2  this script cannot do its job, or --expect auto found no boundary
#
# Why this exists as a script and not a section of a document
# ----------------------------------------------------------
# harness/shared/boundary.yml ends with the requirement this file satisfies: each
# limit is demonstrated by an attempt that is expected to fail, not asserted by a
# line in a document. A boundary nobody has watched refuse something is a
# configuration file.
#
# The one thing to understand before reading the output
# ----------------------------------------------------
# This script proves things about the boundary it is running inside, and nothing
# about any other. Run from a normal terminal it is inside no boundary at all, so
# almost every probe comes back ALLOWED - and that is the correct result, not a
# bug. Three places to run it:
#
#   make boundary-proof             this terminal. Expect ALLOWED everywhere. This
#                                   is what no boundary looks like, which is worth
#                                   seeing once.
#   inside `make sandbox-shell`     the container boundary. Expect REFUSED.
#   as a Bash tool call in a        the harness sandbox. Expect REFUSED for the
#   session using this settings.json  filesystem, credential and network layers.
#
# Every probe is one of three verdicts, and the third is the one that keeps this
# script honest:
#
#   REFUSED       the attempt was made and the boundary stopped it.
#   ALLOWED       the attempt was made and succeeded. No boundary, or a hole.
#   INCONCLUSIVE  the attempt could not distinguish the two. Reported as its own
#                 verdict and never counted as a pass, because "the credential
#                 file could not be read" and "there is no credential file" look
#                 identical from here and mean opposite things.
#
# Nothing is destructive. The write probes create one clearly named canary file
# and remove it, on the success path and again from the EXIT trap. The credential
# probes read a single byte and send it to /dev/null: no content is ever put in a
# variable, printed, or written anywhere.

set -eu

cd "$(dirname "$0")/../.."

OFFLINE=0
EXPECT=auto
PROBE_CHECK=0
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --offline)     OFFLINE=1 ;;
    --probe-check) PROBE_CHECK=1 ;;
    --quiet)       QUIET=1 ;;
    --expect)
      shift
      [ $# -gt 0 ] || { printf 'boundary-proof.sh: --expect needs a value\n' >&2; exit 2; }
      EXPECT="$1" ;;
    --expect=*)    EXPECT=${1#--expect=} ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      printf 'boundary-proof.sh: unknown argument %s\n' "$1" >&2
      exit 2 ;;
  esac
  shift
done

case "$EXPECT" in
  boundary|none|auto) ;;
  *) printf 'boundary-proof.sh: --expect takes boundary, none or auto (got %s)\n' "$EXPECT" >&2
     exit 2 ;;
esac

TAB=$(printf '\t')
RESULTS=$(mktemp -t daer-boundary.XXXXXX)
CANARY_HOME="${HOME:-/nonexistent}/.daer-boundary-canary"
CANARY_ROOT="/.daer-boundary-canary"

cleanup() {
  rm -f "$RESULTS" "$CANARY_HOME" "$CANARY_ROOT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# verdict category id detail
record() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RESULTS"
}

say()   { [ "$QUIET" = 1 ] || printf '  %s\n' "$*"; }
blank() { [ "$QUIET" = 1 ] || printf '\n'; }

# --------------------------------------------------------------- the deny list --
# Read from boundary.yml so this script cannot drift away from the policy it is
# proving. It is a flat list of quoted scalars, which sed can lift without this
# script acquiring a YAML dependency it would not survive inside a stripped
# container (docs/DECISIONS/0004-posix-sh-for-diagnostics.md).
#
# The extraction is checked rather than trusted. A sed expression that silently
# matches nothing would leave this script testing zero credential paths and
# printing a clean summary, which is the worst thing a proof script can do.
BOUNDARY_YML=harness/shared/boundary.yml
if [ ! -f "$BOUNDARY_YML" ]; then
  printf '\n  %s is missing, so there is no policy to prove. Exiting 2.\n\n' "$BOUNDARY_YML" >&2
  exit 2
fi
DENY_READ=$(sed -n '/^  deny_read:/,/^  deny_read_note:/p' "$BOUNDARY_YML" \
              | sed -n 's/^    - "\(.*\)"$/\1/p')
DENY_COUNT=$(printf '%s\n' "$DENY_READ" | grep -c . || true)
if [ "${DENY_COUNT:-0}" -lt 4 ]; then
  printf '\n  Read only %s entries from deny_read in %s.\n' "${DENY_COUNT:-0}" "$BOUNDARY_YML" >&2
  printf '  The policy has more than that, so this extraction is broken and the\n' >&2
  printf '  credential probes would test almost nothing while reporting a pass.\n' >&2
  printf '  Exiting 2 rather than proving something vacuous.\n\n' >&2
  exit 2
fi
STRIP_ENV=$(sed -n '/^  strip_env:/,/^  strip_env_note:/p' "$BOUNDARY_YML" \
              | sed -n 's/^    - \([A-Z_][A-Z0-9_]*\)$/\1/p')
STRIP_COUNT=$(printf '%s\n' "$STRIP_ENV" | grep -c . || true)
if [ "${STRIP_COUNT:-0}" -lt 3 ]; then
  printf '\n  Read only %s entries from strip_env in %s. Same problem as above.\n\n' \
    "${STRIP_COUNT:-0}" "$BOUNDARY_YML" >&2
  exit 2
fi

# ----------------------------------------------------------------- probe check --
# Hermetic, makes no attempt, and answers one question: would each probe produce a
# meaningful verdict on this machine? This is what `make check` runs. It cannot
# tell you whether the boundary works - only that the probes are still pointed at
# something, which is the part that rots.
if [ "$PROBE_CHECK" = 1 ]; then
  # No `broken` counter here on purpose. The two ways this check can find real rot
  # - a sed extraction that stopped matching, or a missing boundary.yml - already
  # exited 2 above. Everything below is a description of this machine, and a
  # machine that happens to lack sudo is not a defect in the policy.
  blank
  say "boundary probe check (no attempt is made)"
  blank
  say "$(printf '%-22s %s' "deny_read entries" "$DENY_COUNT from $BOUNDARY_YML")"
  say "$(printf '%-22s %s' "strip_env entries" "$STRIP_COUNT from $BOUNDARY_YML")"
  present=0
  for p in $DENY_READ; do
    expanded=$(printf '%s' "$p" | sed "s|^~|${HOME:-/nonexistent}|")
    [ -e "$expanded" ] && present=$((present + 1))
  done
  if [ "$present" = 0 ]; then
    say "$(printf '%-22s %s' "credential probe" \
      "INCONCLUSIVE here: none of the $DENY_COUNT paths exist on this machine")"
  else
    say "$(printf '%-22s %s' "credential probe" \
      "$present of $DENY_COUNT paths exist, so a refusal here would mean something")"
  fi
  for c in curl sudo ps; do
    if command -v "$c" >/dev/null 2>&1; then
      say "$(printf '%-22s %s' "$c" "present")"
    else
      say "$(printf '%-22s %s' "$c" "absent: the probes using it report INCONCLUSIVE")"
    fi
  done
  if [ -r /proc/self/status ]; then
    say "$(printf '%-22s %s' "/proc/self/status" "readable, so NoNewPrivs is checkable")"
  else
    say "$(printf '%-22s %s' "/proc/self/status" "absent (macOS): NoNewPrivs INCONCLUSIVE")"
  fi
  blank
  printf '  ok      boundary probes are pointed at the policy (%s deny_read, %s strip_env)\n' \
    "$DENY_COUNT" "$STRIP_COUNT"
  exit 0
fi

printf '\n  boundary proof\n\n'

# ------------------------------------------------------------ where we are now --
# Reported before any probe, because every verdict below has to be read against
# it. Detection is best-effort and is never used to decide a verdict: a probe's
# result comes from the attempt, not from this guess.
WHERE="a normal shell, inside no boundary"
if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
  WHERE="a container"
elif [ -r /proc/1/cgroup ] && grep -qE '(docker|containerd|libpod|kubepods)' /proc/1/cgroup 2>/dev/null; then
  WHERE="a container"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] || [ -n "${CLAUDECODE:-}" ]; then
  WHERE="a harness session (sandbox status decided by the probes, not by this line)"
fi
say "running in $WHERE"

# ============================================================ 1. filesystem ====
# The working tree is writable by design, so the discriminator is a write just
# outside it. HOME is the right target: writable on any normal machine, outside
# the working tree in every boundary this pack configures.
if [ -n "${HOME:-}" ] && (set -C; : > "$CANARY_HOME") 2>/dev/null; then
  rm -f "$CANARY_HOME" 2>/dev/null || true
  record ALLOWED filesystem fs-write-home "wrote and removed a canary in HOME"
else
  record REFUSED filesystem fs-write-home "could not create a file in HOME"
fi

# The root filesystem. Split from the probe above because on macOS the system
# volume is read-only under SIP, so a refusal here is the operating system and not
# the boundary - counting it as a pass would be borrowing credit.
if (set -C; : > "$CANARY_ROOT") 2>/dev/null; then
  rm -f "$CANARY_ROOT" 2>/dev/null || true
  record ALLOWED filesystem fs-write-root "wrote and removed a canary at /"
elif [ "$(uname -s 2>/dev/null || echo unknown)" = "Darwin" ]; then
  record INCONCLUSIVE filesystem fs-write-root \
    "refused, but macOS mounts / read-only under SIP, so this is not evidence about the boundary"
else
  record REFUSED filesystem fs-write-root "could not create a file at /"
fi

# The working tree must stay writable. A boundary that refuses everything passes
# every deny probe and makes the harness useless, which is the same reason half of
# harness/shared/guards/cases.tsv is allow rows.
WT_CANARY=".daer-boundary-canary"
if (set -C; : > "$WT_CANARY") 2>/dev/null; then
  rm -f "$WT_CANARY" 2>/dev/null || true
  record ALLOWED filesystem fs-write-worktree "the working tree is writable, as it must be"
else
  record REFUSED filesystem fs-write-worktree \
    "the working tree is NOT writable. This breaks the harness rather than securing it"
fi

# ============================================================ 2. credentials ===
# One byte, to /dev/null. A path that does not exist is INCONCLUSIVE and not a
# pass: absent and unreadable are the same observation from here.
cred_refused=0
cred_allowed=0
cred_absent=0
for p in $DENY_READ; do
  expanded=$(printf '%s' "$p" | sed "s|^~|${HOME:-/nonexistent}|")
  if [ ! -e "$expanded" ]; then
    cred_absent=$((cred_absent + 1))
    continue
  fi
  if [ -d "$expanded" ]; then
    if ls "$expanded" >/dev/null 2>&1; then
      cred_allowed=$((cred_allowed + 1))
    else
      cred_refused=$((cred_refused + 1))
    fi
    continue
  fi
  if dd if="$expanded" of=/dev/null bs=1 count=1 >/dev/null 2>&1; then
    cred_allowed=$((cred_allowed + 1))
  else
    cred_refused=$((cred_refused + 1))
  fi
done
if [ "$cred_allowed" -gt 0 ]; then
  record ALLOWED credentials cred-read \
    "$cred_allowed of $DENY_COUNT deny_read paths could be read ($cred_refused refused, $cred_absent absent)"
elif [ "$cred_refused" -gt 0 ]; then
  record REFUSED credentials cred-read \
    "every one of the $cred_refused deny_read paths present on this machine refused to be read ($cred_absent absent)"
else
  record INCONCLUSIVE credentials cred-read \
    "none of the $DENY_COUNT deny_read paths exist here, so nothing was proved either way"
fi

# ============================================================ 3. environment ===
# The ambiguity is structural: a token that is absent because the boundary removed
# it and one that was never set look identical. Resolvable only by planting a
# canary outside and looking for it inside, so that is what this reports.
env_present=""
for v in $STRIP_ENV; do
  eval "val=\${$v:-}"
  [ -n "${val:-}" ] && env_present="$env_present $v"
done
if [ -n "$env_present" ]; then
  record ALLOWED environment env-strip \
    "still in this environment:$env_present"
elif [ -n "${DAER_CANARY_ENV:-}" ]; then
  record REFUSED environment env-strip \
    "a canary was planted in $DAER_CANARY_ENV outside and is not visible here"
else
  record INCONCLUSIVE environment env-strip \
    "none of the $STRIP_COUNT names are set, but nothing planted one. Re-run as: DAER_CANARY_ENV=GITHUB_TOKEN GITHUB_TOKEN=daer-canary <enter the boundary> boundary-proof.sh"
fi

# ============================================================ 4. network =======
if [ "$OFFLINE" = 1 ]; then
  record INCONCLUSIVE network net-denied "skipped: --offline"
  record INCONCLUSIVE network net-allowed "skipped: --offline"
elif ! command -v curl >/dev/null 2>&1; then
  record INCONCLUSIVE network net-denied "no curl on PATH"
  record INCONCLUSIVE network net-allowed "no curl on PATH"
else
  # example.com is reserved by the IETF for exactly this and is on no allowlist in
  # boundary.yml. A refusal here is the allowlist working.
  if curl -s -o /dev/null -m 10 https://example.com 2>/dev/null; then
    record ALLOWED network net-denied "reached example.com, which is on no allowlist"
  else
    record REFUSED network net-denied "could not reach example.com"
  fi
  # The positive control. Without it, a machine with no network at all would
  # report a perfectly working allowlist.
  if curl -s -o /dev/null -m 15 https://docs.databricks.com 2>/dev/null; then
    record ALLOWED network net-allowed "reached docs.databricks.com, which is allowlisted, as it must be"
  else
    record REFUSED network net-allowed \
      "could NOT reach docs.databricks.com, which is allowlisted. Either there is no network here, or the allowlist is denying its own entries - so the line above is not evidence of an allowlist"
  fi
fi

# ============================================================ 5. privilege =====
if ! command -v sudo >/dev/null 2>&1; then
  record REFUSED privilege priv-sudo "no sudo binary exists here"
elif sudo -n true 2>/dev/null; then
  record ALLOWED privilege priv-sudo "sudo -n true succeeded: this shell can become root without a prompt"
else
  record REFUSED privilege priv-sudo "sudo -n true failed"
fi

if [ -r /proc/self/status ]; then
  nnp=$(sed -n 's/^NoNewPrivs:[[:space:]]*//p' /proc/self/status 2>/dev/null | head -1)
  case "${nnp:-}" in
    1) record REFUSED privilege priv-no-new-privs "NoNewPrivs is 1: setuid cannot raise privileges" ;;
    0) record ALLOWED privilege priv-no-new-privs "NoNewPrivs is 0: --security-opt no-new-privileges is not in effect" ;;
    *) record INCONCLUSIVE privilege priv-no-new-privs "could not read NoNewPrivs" ;;
  esac
else
  record INCONCLUSIVE privilege priv-no-new-privs \
    "no /proc/self/status. This is a Linux control and macOS cannot report on it"
fi

# ============================================================ 6. processes =====
# A PID namespace of its own is the observable. On a host, PID 1 is the init
# system and the whole machine's process table is visible.
if [ -r /proc/1/comm ]; then
  pid1=$(cat /proc/1/comm 2>/dev/null || echo unknown)
  case "$pid1" in
    systemd|init|launchd)
      record ALLOWED processes proc-namespace "PID 1 is $pid1: the host process table is visible" ;;
    *)
      record REFUSED processes proc-namespace "PID 1 is $pid1, not an init system: this is a private PID namespace" ;;
  esac
elif command -v ps >/dev/null 2>&1; then
  n=$(ps -e 2>/dev/null | grep -c . || echo 0)
  if [ "$n" -gt 60 ]; then
    record ALLOWED processes proc-namespace "$n processes visible: no PID isolation"
  else
    record INCONCLUSIVE processes proc-namespace \
      "$n processes visible, which is few, but ps alone cannot prove a namespace"
  fi
else
  record INCONCLUSIVE processes proc-namespace "no /proc and no ps"
fi

# ================================================================ the report ===
# --quiet drops the per-probe rows and keeps the summary, except for a limit that
# did not hold: the whole reason to run this is to see those, so they are printed
# in every mode.
last_cat=""
while IFS="$TAB" read -r verdict category id detail || [ -n "${verdict:-}" ]; do
  [ -n "${verdict:-}" ] || continue
  if [ "$category" != "$last_cat" ]; then
    blank
    say "$category"
    last_cat="$category"
  fi
  say "$(printf '%-13s %-20s %s' "$verdict" "$id" "$detail")"
done < "$RESULTS"

refused=$(awk -F"$TAB" '$1 == "REFUSED"' "$RESULTS" | grep -c . || true)
allowed=$(awk -F"$TAB" '$1 == "ALLOWED"' "$RESULTS" | grep -c . || true)
unknown=$(awk -F"$TAB" '$1 == "INCONCLUSIVE"' "$RESULTS" | grep -c . || true)

# Two probes are positive controls: they are supposed to be ALLOWED, and counting
# them as holes would make a working boundary look broken.
POSITIVE="fs-write-worktree net-allowed"
holes=0
for id in $(awk -F"$TAB" '$1 == "ALLOWED" { print $3 }' "$RESULTS"); do
  is_positive=0
  for p in $POSITIVE; do [ "$p" = "$id" ] && is_positive=1; done
  [ "$is_positive" = 0 ] && holes=$((holes + 1))
done

printf '\n  %s refused, %s allowed, %s inconclusive (%s of the allowed are limits that did not hold)\n\n' \
  "$refused" "$allowed" "$unknown" "$holes"

case "$EXPECT" in
  none)
    # The negative control. Run outside every boundary, this must find holes; if it
    # does not, the probes are broken and every REFUSED they ever print is worthless.
    if [ "$holes" -gt 0 ]; then
      printf '  ok      --expect none: %s limit(s) did not hold, so the probes are live.\n\n' "$holes"
      exit 0
    fi
    printf '  FAIL    --expect none: every limit refused, outside any boundary.\n' >&2
    printf '          That is not a secure machine, it is a broken proof script: these\n' >&2
    printf '          probes cannot distinguish a boundary from their own failure.\n\n' >&2
    exit 1 ;;
  boundary)
    if [ "$holes" = 0 ]; then
      printf '  ok      --expect boundary: every applicable limit refused.\n'
      [ "$unknown" -gt 0 ] && printf '          %s probe(s) were inconclusive and are NOT counted as passes.\n' "$unknown"
      printf '\n'
      exit 0
    fi
    printf '  FAIL    --expect boundary: %s limit(s) did not hold. See ALLOWED above.\n\n' "$holes" >&2
    exit 1 ;;
  auto)
    if [ "$holes" = 0 ]; then
      printf '  ok      every applicable limit refused.\n\n'
      exit 0
    fi
    printf '  No boundary is in effect here: %s limit(s) did not hold.\n' "$holes" >&2
    printf '  Exiting 2, because this is a report and not a verdict. To make it one,\n' >&2
    printf '  say which answer you expected: --expect boundary, or --expect none to\n' >&2
    printf '  assert that this shell is deliberately unconfined.\n\n' >&2
    exit 2 ;;
esac
