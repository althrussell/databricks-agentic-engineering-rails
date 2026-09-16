#!/bin/sh
# doctor.sh — what this machine actually has, in a table you can paste into a bug
# report.
#
# Run it before blaming the harness. A good share of "the agent is broken" is a
# missing CLI or an expired login, and those are one minute each.
#
# Deliberate constraints:
#
#   * POSIX sh, no python. The most common failure this has to survive is a broken or
#     absent python, and a doctor written in python cannot report that.
#   * Nothing printed identifies the workspace or the person. The host is reported as
#     set or unset, never echoed: this output gets pasted into tickets, and a
#     workspace URL is an environment identifier.
#   * Versions are read from the tool itself and compared with template-version.yml.
#     A difference is reported as a difference, never as a failure — the recorded
#     column is what this was exercised against, not a floor.
#
# Exit status: 0 if every required tool is present, 1 otherwise. A version difference
# never changes the exit status.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSIONS="$ROOT/template-version.yml"

LIVE=0
for arg in "$@"; do
  case "$arg" in
    --live) LIVE=1 ;;
    -h|--help) printf 'usage: scripts/doctor.sh [--live]\n\n  --live  also check that your Databricks login works (needs network)\n'; exit 0 ;;
    *) printf 'doctor: unknown argument %s\n' "$arg" >&2; exit 2 ;;
  esac
done

# Pull "version" out of one block of template-version.yml, so a version bump is one
# edit rather than two places that can disagree.
recorded() {
  [ -f "$VERSIONS" ] || { printf '(no record)'; return; }
  awk -v key="$1" '
    $0 ~ "^  " key ":$" { inblock = 1; next }
    inblock && /^  [a-z_]+:$/ { inblock = 0 }
    inblock && $1 == "version:" { $1 = ""; sub(/^ /, ""); gsub(/"/, ""); print; exit }
  ' "$VERSIONS"
}

REQUIRED_MISSING=0
ROWS=""

# add <label> <requirement> <found> <recorded>
add() {
  label=$1; req=$2; found=$3; rec=$4
  if [ -z "$found" ]; then
    if [ "$req" = required ]; then
      verdict=MISSING; REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    else
      verdict=absent
    fi
    found="-"
  elif [ -z "$rec" ] || [ "$rec" = "(no record)" ]; then verdict=found
  elif [ "$found" = "$rec" ]; then verdict=ok
  else verdict=differs
  fi
  ROWS="$ROWS$label|$req|$found|${rec:--}|$verdict
"
}

# First line of `<cmd> <flag>`, reduced to something that looks like a version.
probe() {
  cmd=$1; shift
  command -v "$cmd" >/dev/null 2>&1 || { printf ''; return; }
  "$cmd" "$@" 2>/dev/null | head -1 | tr -d '\r' \
    | sed 's/.*[Vv]ersion //; s/^v//; s/^[^0-9]*//; s/ .*//' | head -1
}

add "git"        required "$(probe git --version)"        ""
add "databricks" required "$(probe databricks --version)" "$(recorded databricks_cli)"
add "uv"         optional "$(probe uv --version)"         "$(recorded uv)"
add "python3"    optional "$(probe python3 --version)"    "$(recorded python)"
add "node"       optional "$(probe node --version)"       "$(recorded node)"
add "gh"         optional "$(probe gh --version)"         "$(recorded gh)"

# ug reports a commit-qualified version between releases (0.1.0+84.gfddf95b). The
# trailing g<hash> is the only thing that identifies the build, so it is printed whole
# rather than trimmed to three digits like everything else.
UG_RAW=""
for c in ug ucode; do
  command -v "$c" >/dev/null 2>&1 && { UG_RAW=$("$c" --version 2>/dev/null | head -1 | tr -d '\r'); break; }
done
add "ug" optional "$(printf '%s' "$UG_RAW" | sed 's/.*[Vv]ersion //; s/^v//; s/^[^0-9]*//')" "$(recorded unity_gateway_cli)"

# Which harnesses are installed. At least one is required: without one there is
# nothing to configure.
HARNESSES=""
for pair in "claude:Claude Code" "codex:Codex CLI" "cursor-agent:Cursor CLI" \
            "copilot:Copilot CLI" "opencode:OpenCode"; do
  bin=${pair%%:*}; name=${pair#*:}
  command -v "$bin" >/dev/null 2>&1 && HARNESSES="$HARNESSES    $name ($bin)
"
done

env_state() { eval "v=\${$1:-}"; [ -n "${v:-}" ] && printf 'set' || printf 'unset'; }
TOKENISH=none
for var in DATABRICKS_TOKEN ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY; do
  eval "v=\${$var:-}"
  [ -n "${v:-}" ] && TOKENISH="$var present in this shell"
done

PACK_VERSION=$(sed -n 's/^version: *//p' "$VERSIONS" 2>/dev/null | head -1)

printf '\n  databricks-agentic-engineering-rails — environment report\n'
printf '  pack %s\n\n' "${PACK_VERSION:-unknown}"
printf '  %-14s %-9s %-22s %-20s %s\n' TOOL NEEDED FOUND RECORDED VERDICT
printf '  %-14s %-9s %-22s %-20s %s\n' -------------- --------- ---------------------- -------------------- -------
printf '%s' "$ROWS" | while IFS='|' read -r label req found rec verdict; do
  [ -z "$label" ] && continue
  printf '  %-14s %-9s %-22s %-20s %s\n' "$label" "$req" "$found" "$rec" "$verdict"
done

printf '\n  Harnesses found\n'
if [ -n "$HARNESSES" ]; then printf '%s' "$HARNESSES"
else printf '    none — install one; see docs/01-prerequisites.md\n'; fi

printf '\n  Environment (values deliberately not printed)\n'
printf '    DATABRICKS_HOST             %s\n' "$(env_state DATABRICKS_HOST)"
printf '    DATABRICKS_CONFIG_PROFILE   %s\n' "$(env_state DATABRICKS_CONFIG_PROFILE)"
printf '    token in this shell         %s\n' "$TOKENISH"
[ -n "$UG_RAW" ] && printf '    ug --version                %s\n' "$UG_RAW"
printf '\n'

if [ "$LIVE" -eq 1 ]; then
  printf '  Login check\n'
  if ! command -v databricks >/dev/null 2>&1; then
    printf '    databricks CLI absent, skipping\n\n'
  elif databricks current-user me >/dev/null 2>&1; then
    printf '    workspace auth               working\n\n'
  else
    printf '    workspace auth               not working (run: databricks auth login)\n\n'
  fi
fi

if [ "$REQUIRED_MISSING" -gt 0 ]; then
  printf '  %d required tool(s) missing. See docs/01-prerequisites.md.\n\n' "$REQUIRED_MISSING"
fi

exit $([ "$REQUIRED_MISSING" -gt 0 ] && echo 1 || echo 0)
