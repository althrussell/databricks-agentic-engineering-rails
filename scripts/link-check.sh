#!/bin/sh
# link-check.sh — do the links in this pack point at anything?
#
# Split in two on purpose, because the two halves have different failure
# characteristics and belong in different lanes:
#
#   --internal   No network. Every relative link resolves to a file that exists,
#                and every #anchor resolves to a heading in that file. Runs in the
#                pull-request lane, where a check that can fail because someone
#                else's web server is down is worse than no check at all.
#   --external   Network, with retries. Every http(s) URL answers. Runs on a
#                schedule, where a 503 is a retry rather than a blocked merge.
#
# Written in POSIX sh with awk and sed and no python, so it runs inside the
# execution boundary and in CI images that carry neither python nor node.
#
# Exit status: 0 if nothing is broken, 1 otherwise. Warnings never change it.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODE=internal
ATTEMPTS=3
TIMEOUT=25

for arg in "$@"; do
  case "$arg" in
    --internal) MODE=internal ;;
    --external) MODE=external ;;
    --all)      MODE=all ;;
    -h|--help)
      cat <<'USAGE'
usage: scripts/link-check.sh [--internal|--external|--all]

  --internal  (default) relative links and anchors, no network
  --external  http(s) URLs, with retries. Needs network.
  --all       both
USAGE
      exit 0 ;;
    *) printf 'link-check: unknown argument %s\n' "$arg" >&2; exit 2 ;;
  esac
done

cd "$ROOT" || exit 2

# Every markdown file that is part of the pack. release/ holds build output and
# .git holds history; neither is source.
markdown_files() {
  find . -name '*.md' \
    ! -path './.git/*' ! -path './release/*' ! -path './node_modules/*' \
    ! -path './.harness-scratch/*' | sed 's|^\./||' | sort
}

# GitHub's heading slug, near enough for a link inside one repository: lowercase,
# drop anything that is not a letter, digit, space, hyphen or underscore, then
# spaces to hyphens.
slug() {
  printf '%s\n' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9 _-]//g; s/^ *//; s/ *$//; s/ /-/g'
}

# docs/../schemas/README.md and schemas/README.md are the same file, and only one
# of them is worth printing in an error a reader has to act on.
collapse() {
  printf '%s' "$1" | sed -e 's|/\./|/|g' -e ':a' -e 's|[^/][^/]*/\.\./||; ta' -e 's|^\./||'
}

fail() { printf '  BROKEN  %s\n' "$1"; }
warn() { printf '  warn    %s\n' "$1"; }

# ---------------------------------------------------------------- internal ----
check_internal() {
  printf '\n  internal links (no network)\n\n'
  for file in $(markdown_files); do
    dir=$(dirname "$file")
    # One link per line: text<TAB>target. Skips fenced code by tracking ``` state,
    # because a link inside an example is not a link.
    awk '
      /^[ \t]*```/ { fence = !fence; next }
      fence { next }
      {
        line = $0
        while (match(line, /\[[^]]*\]\([^)]*\)/)) {
          m = substr(line, RSTART, RLENGTH)
          line = substr(line, RSTART + RLENGTH)
          tclose = index(m, "](")
          text = substr(m, 2, tclose - 2)
          target = substr(m, tclose + 2, length(m) - tclose - 2)
          print NR "\t" text "\t" target
        }
      }
    ' "$file" | while IFS="$(printf '\t')" read -r lineno text target; do
      case "$target" in
        http://*|https://*|mailto:*|tel:*) continue ;;
        '') fail "$file:$lineno empty link target"; continue ;;
      esac
      anchor=""
      case "$target" in
        \#*) path="$file"; anchor=${target#\#} ;;
        *\#*) path=${target%%\#*}; anchor=${target#*\#} ;;
        *) path="$target" ;;
      esac
      if [ -n "$path" ] && [ "$path" != "$file" ]; then
        full=$(collapse "$dir/$path")
        if [ ! -e "$full" ]; then
          fail "$file:$lineno -> $target (no such path)"
          continue
        fi
      else
        full="$file"
      fi
      if [ -n "$anchor" ]; then
        case "$full" in
          *.md)
            want=$(slug "$anchor")
            if ! awk '/^[ \t]*```/ { f = !f; next } !f && /^#+ / { sub(/^#+[ \t]*/, ""); print }' "$full" \
                 | while read -r heading; do slug "$heading"; done | grep -qx "$want"; then
              fail "$file:$lineno -> $target (no heading matching #$want in $full)"
            fi
            ;;
        esac
      fi
      # Link text carries the meaning for anyone reading with a screen reader or
      # skimming a printed PDF, where "here" points nowhere.
      case "$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')" in
        here|this|link|this\ link|click\ here|read\ more|more)
          warn "$file:$lineno link text \"$text\" carries no meaning out of context" ;;
      esac
    done
  done
}

# ---------------------------------------------------------------- external ----
# URLs come from two places: prose in the markdown, and sources.yml, which is the
# list the pack claims to have verified. Both have to answer.
external_urls() {
  {
    for file in $(markdown_files); do
      awk '/^[ \t]*```/ { f = !f; next } !f { print }' "$file" \
        | grep -o 'https\{0,1\}://[A-Za-z0-9._~:/?#@!$&*+,;=%-]*' \
        | sed 's/[.,)]*$//'
    done
    [ -f sources.yml ] && grep -o 'https\{0,1\}://[^ ]*' sources.yml | sed 's/[.,)]*$//'
  } | sed 's|/$||' | sort -u
}

check_external() {
  printf '\n  external links (network, %d attempts each)\n\n' "$ATTEMPTS"
  if ! command -v curl >/dev/null 2>&1; then
    fail "curl is not installed, so no external link could be checked"
    return
  fi
  external_urls | while read -r url; do
    [ -z "$url" ] && continue
    attempt=1
    code=000
    while [ "$attempt" -le "$ATTEMPTS" ]; do
      code=$(curl -sSL -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$url" 2>/dev/null || printf '000')
      case "$code" in
        2*|3*) break ;;
      esac
      # A 405 means the URL exists and dislikes the method. That is not a broken
      # link and retrying will not change it.
      [ "$code" = 405 ] && break
      attempt=$((attempt + 1))
      [ "$attempt" -le "$ATTEMPTS" ] && sleep $((attempt * 2))
    done
    case "$code" in
      2*|3*) printf '  ok      %s %s\n' "$code" "$url" ;;
      405)   printf '  ok      %s %s (endpoint, not a page)\n' "$code" "$url" ;;
      *)     printf '  BROKEN  %s %s after %d attempt(s)\n' "$code" "$url" "$ATTEMPTS" ;;
    esac
  done
}

# Every check above runs inside a pipeline, so its counter increments happen in a
# subshell and are lost. The output is the authority instead: it is captured once
# and the verdict is counted from it.
run() {
  case "$MODE" in
    internal) check_internal ;;
    external) check_external ;;
    all)      check_internal; check_external ;;
  esac
}

OUT=$(run)
printf '%s\n' "$OUT"
BROKEN=$(printf '%s\n' "$OUT" | grep -c '^  BROKEN' || true)
WARNED=$(printf '%s\n' "$OUT" | grep -c '^  warn' || true)
printf '\n  %s: %d broken, %d warning(s)\n\n' "$MODE" "${BROKEN:-0}" "${WARNED:-0}"
[ "${BROKEN:-0}" -gt 0 ] && exit 1
exit 0
