#!/bin/sh
# doctor.sh — what this machine actually has, in a table you can paste into a bug
# report.
#
# Two jobs, and they pull in the same direction:
#
#   1. Preflight. Lab 00 runs this before anything else, because "it did not work"
#      is unanswerable and "typst is missing" is fixable in a minute.
#   2. Support. The first thing to attach to an issue. Every version here is read
#      from the tool itself, never from a manifest, so the output describes the
#      machine rather than the repository's hopes about it.
#
# Deliberate constraints:
#
#   * POSIX sh, no python. The most common failure this script has to survive is a
#     broken or absent python, and a doctor written in python cannot report that.
#   * Nothing is printed that identifies the workspace or the person. The host is
#     reported as set or unset, never echoed: this output gets pasted into tickets
#     and chat, and a workspace URL is an environment identifier.
#   * Tool versions are compared with the versions recorded in template-version.yml
#     and any difference is reported as a difference, not as a failure. A newer
#     pandoc is not a defect. It is a fact worth knowing when a PDF renders oddly.
#
# Exit status: 0 if every required tool is present, 1 otherwise. A version
# difference never changes the exit status.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSIONS="$ROOT/template-version.yml"

FORMAT=table
LIVE=0
for arg in "$@"; do
  case "$arg" in
    --json) FORMAT=json ;;
    --live) LIVE=1 ;;
    -h|--help)
      cat <<'USAGE'
usage: scripts/doctor.sh [--json] [--live]

  --json  machine-readable output for CI and for the evidence record
  --live  additionally probe the configured workspace (needs network and auth).
          Off by default so the preflight works on a plane.
USAGE
      exit 0 ;;
    *) printf 'doctor: unknown argument %s\n' "$arg" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- recorded ----
# Pull "version" out of one block of template-version.yml. Reading the recorded
# value from the same file that new-project.sh stamps into generated projects keeps
# one source of truth; hard-coding the numbers here would give two.
recorded() {
  [ -f "$VERSIONS" ] || { printf '(no record)'; return; }
  awk -v key="$1" '
    $0 ~ "^  " key ":$" { inblock = 1; next }
    inblock && /^  [a-z_]+:$/ { inblock = 0 }
    inblock && $1 == "version:" {
      v = $2
      gsub(/"/, "", v)
      $1 = ""; sub(/^ /, "")
      gsub(/"/, "")
      print
      exit
    }
  ' "$VERSIONS" | sed 's/^version: *//; s/"//g'
}

# ------------------------------------------------------------------ report ----
REQUIRED_MISSING=0
ROWS=""

# add <label> <requirement> <found> <recorded> <note>
add() {
  label=$1; req=$2; found=$3; rec=$4; note=$5
  if [ -z "$found" ]; then
    if [ "$req" = required ]; then
      verdict=MISSING
      REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    else
      verdict=absent
    fi
    found="-"
  elif [ -z "$rec" ] || [ "$rec" = "(no record)" ]; then
    verdict=found
  elif [ "$found" = "$rec" ]; then
    verdict=ok
  else
    verdict=differs
  fi
  ROWS="$ROWS$label|$req|$found|${rec:--}|$verdict|$note
"
}

# first line of `<cmd> <flag>`, stripped down to something that looks like a
# version. Tools disagree wildly about their format; this keeps the digits.
probe() {
  cmd=$1; shift
  command -v "$cmd" >/dev/null 2>&1 || { printf ''; return; }
  "$cmd" "$@" 2>/dev/null | head -1 | tr -d '\r' \
    | sed 's/.*[Vv]ersion //; s/^v//; s/^[^0-9]*//; s/ .*//' | head -1
}

# ------------------------------------------------------------------ probes ----
add "python3"        required "$(probe python3 --version)"     "$(recorded python)"            "runs the checks and the doc build"
add "pandoc"         required "$(probe pandoc --version)"      "$(recorded pandoc)"            "markdown to typst"
add "typst"          required "$(probe typst --version)"       "$(recorded typst)"             "typst to PDF"
add "git"            required "$(probe git --version)"         ""                              "revision stamped into every PDF"
add "make"           required "$(probe make --version)"        ""                              "the one entry point"
add "databricks"     required "$(probe databricks --version)"  "$(recorded databricks_cli)"    "auth, apps, bundles"
add "uv"             optional "$(probe uv --version)"          "$(recorded uv)"                "installs the gateway CLI"
add "node"           optional "$(probe node --version)"        "$(recorded node)"              "AppKit; floor is 22"
add "gh"             optional "$(probe gh --version)"          "$(recorded gh)"                "pull requests and CI logs"
add "tofu"           optional "$(probe tofu --version)"        "$(recorded opentofu)"          "admin plane IaC"
add "jq"             optional "$(probe jq --version)"          ""                              "reading API and manifest JSON"

# ug reports a commit-qualified version between releases (0.1.0+14.g93986a8). The
# trailing g<hash> is the only thing that identifies the build, so it is printed
# whole rather than trimmed to three digits like everything else.
UG_RAW=""
if command -v ug >/dev/null 2>&1; then
  UG_RAW=$(ug --version 2>/dev/null | head -1 | tr -d '\r')
elif command -v ucode >/dev/null 2>&1; then
  UG_RAW=$(ucode --version 2>/dev/null | head -1 | tr -d '\r')
fi
UG_FOUND=$(printf '%s' "$UG_RAW" | sed 's/.*[Vv]ersion //; s/^v//; s/^[^0-9]*//')
add "ug" optional "${UG_FOUND:-}" "$(recorded unity_gateway_cli)" "report this string verbatim in bug reports"

# A container runtime is what makes the execution boundary a boundary rather than a
# scratch HOME. Absent is a supported state with a published residual risk, so this
# is a warning with a pointer, not a failure.
RUNTIME=""
for candidate in docker podman finch nerdctl; do
  if command -v "$candidate" >/dev/null 2>&1; then
    RUNTIME="$candidate $(probe "$candidate" --version)"
    break
  fi
done
add "container runtime" optional "${RUNTIME:-}" "" "see docs/DECISIONS/0002-execution-boundary.md"

# ------------------------------------------------------------ environment -----
# Set or unset. Never the value: this output is meant to be pasted.
env_state() {
  eval "v=\${$1:-}"
  [ -n "$v" ] && printf 'set' || printf 'unset'
}
HOST_STATE=$(env_state DATABRICKS_HOST)
PROFILE_STATE=$(env_state DATABRICKS_CONFIG_PROFILE)
TOKENISH=none
for var in DATABRICKS_TOKEN ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY; do
  eval "v=\${$var:-}"
  [ -n "${v:-}" ] && TOKENISH="$var present in this shell"
done

PACK_VERSION=$(sed -n 's/^version: *//p' "$VERSIONS" 2>/dev/null | head -1)
REVISION=$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || printf 'not a git checkout')
DIRTY=$(git -C "$ROOT" status --porcelain 2>/dev/null | head -1)
[ -n "$DIRTY" ] && TREE="dirty" || TREE="clean"

# ------------------------------------------------------------------ output ----
if [ "$FORMAT" = json ]; then
  printf '{\n'
  printf '  "pack_version": "%s",\n' "${PACK_VERSION:-unknown}"
  printf '  "revision": "%s",\n' "$REVISION"
  printf '  "working_tree": "%s",\n' "$TREE"
  printf '  "databricks_host": "%s",\n' "$HOST_STATE"
  printf '  "config_profile": "%s",\n' "$PROFILE_STATE"
  printf '  "token_in_environment": "%s",\n' "$TOKENISH"
  printf '  "ug_version_raw": "%s",\n' "$UG_RAW"
  printf '  "tools": [\n'
  first=1
  printf '%s' "$ROWS" | while IFS='|' read -r label req found rec verdict note; do
    [ -z "$label" ] && continue
    [ $first -eq 0 ] && printf ',\n'
    first=0
    printf '    {"tool": "%s", "requirement": "%s", "found": "%s", "recorded": "%s", "verdict": "%s"}' \
      "$label" "$req" "$found" "$rec" "$verdict"
  done
  printf '\n  ],\n'
  printf '  "required_missing": %d\n' "$REQUIRED_MISSING"
  printf '}\n'
else
  printf '\n  databricks-agentic-engineering-rails — environment report\n'
  printf '  pack %s at %s (%s working tree)\n\n' "${PACK_VERSION:-unknown}" "$REVISION" "$TREE"
  printf '  %-18s %-9s %-22s %-20s %s\n' TOOL NEEDED FOUND RECORDED VERDICT
  printf '  %-18s %-9s %-22s %-20s %s\n' ------------------ --------- ---------------------- -------------------- -------
  printf '%s' "$ROWS" | while IFS='|' read -r label req found rec verdict note; do
    [ -z "$label" ] && continue
    printf '  %-18s %-9s %-22s %-20s %s\n' "$label" "$req" "$found" "$rec" "$verdict"
  done
  printf '\n  Environment (values deliberately not printed)\n'
  printf '    DATABRICKS_HOST             %s\n' "$HOST_STATE"
  printf '    DATABRICKS_CONFIG_PROFILE   %s\n' "$PROFILE_STATE"
  printf '    long-lived token in shell   %s\n' "$TOKENISH"
  [ -n "$UG_RAW" ] && printf '    ug --version                %s\n' "$UG_RAW"
  printf '\n'
  if [ "$REQUIRED_MISSING" -gt 0 ]; then
    printf '  %d required tool(s) missing. See docs/PREREQUISITES.md for how to install them.\n\n' "$REQUIRED_MISSING"
  else
    printf '  Every required tool is present. `make check` and `make docs` should run.\n\n'
  fi
  printf '  A verdict of "differs" is information, not a fault: the recorded column is\n'
  printf '  what this pack was exercised against, not a floor. Report both if something\n'
  printf '  renders or behaves unexpectedly.\n\n'
fi

# ------------------------------------------------------------------- live -----
if [ "$LIVE" -eq 1 ]; then
  printf '  Live probe\n'
  if ! command -v databricks >/dev/null 2>&1; then
    printf '    databricks CLI absent, skipping\n\n'
  else
    if databricks current-user me >/dev/null 2>&1; then
      printf '    workspace auth               working\n'
    else
      printf '    workspace auth               not working (run: databricks auth login)\n'
    fi
    printf '    (route availability is per workspace and is probed by lab 01, not here)\n\n'
  fi
fi

exit $([ "$REQUIRED_MISSING" -gt 0 ] && echo 1 || echo 0)
