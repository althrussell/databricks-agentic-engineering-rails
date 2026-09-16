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

# docs/../harness/README.md and harness/README.md are the same file, and only one
# of them is worth printing in an error a reader has to act on.
collapse() {
  printf '%s' "$1" | sed -e 's|/\./|/|g' -e ':a' -e 's|[^/][^/]*/\.\./||; ta' -e 's|^\./||'
}

# --------------------------------------------------------------- pages exclude --
# A link can resolve perfectly on disk and on GitHub and still 404 in a browser,
# because the Pages build excludes the file. That happened here: `exclude: README.md`
# in docs/_config.yml unpublished docs/DECISIONS/README.md and
# docs/assets/img/README.md, both linked from the homepage, and this checker called
# the site fine because it was looking at the filesystem.
#
# So the exclude list is read and links into it are reported. Parsed with sed rather
# than a YAML library because this script carries no interpreter (see
# docs/DECISIONS/0004-posix-sh-for-diagnostics.md); the list is a flat sequence of
# scalars, which sed can read correctly, and a nested one produces a line with a colon
# in it, which assert_pages_excludes_readable refuses to guess at.
PAGES_CONFIG=docs/_config.yml
pages_excludes() {
  [ -f "$PAGES_CONFIG" ] || return 0
  sed -n '/^exclude:/,/^[^ #-]/{ s/^  *- *//p; }' "$PAGES_CONFIG" \
    | sed 's/[[:space:]]*$//; s/^"//; s/"$//' \
    | grep -v '^$'
}

# Read once, so the file is parsed one time rather than once per link, and so the
# refusal below has something to inspect before any checking starts.
PAGES_EXCLUDES=$(pages_excludes)

# Where the refusal has to live, and why it is not next to the code it protects.
#
# The obvious home for this is inside pages_excluded, beside the case that cannot
# handle a nested entry. It was there. It did not work, and a control run is what
# found that out: the message printed, and the script went on to report "0 broken"
# - the unearned pass the message exists to prevent.
#
# The cause is three layers of subshell. pages_excluded matches inside a pipeline;
# it is called from check_internal; check_internal runs inside OUT=$(run), which is
# a command substitution. `exit` in any of those exits a subshell nobody is reading
# the status of. So no check in this script can be fatal from where it runs, and
# anything that must stop the run has to be called from the top level, before
# OUT=$(run). That is a property of the script's shape, not of this one check.
assert_pages_excludes_readable() {
  bad=$(printf '%s\n' "$PAGES_EXCLUDES" | grep ':' || true)
  [ -n "$bad" ] || return 0
  printf '\n  CANNOT CHECK  %s: an exclude entry is not a plain path.\n' \
    "$PAGES_CONFIG" >&2
  printf '%s\n' "$bad" | sed 's/^/                  /' >&2
  printf '  This check reads a flat list of paths and cannot tell what a nested\n' >&2
  printf '  entry excludes. Exiting 2 rather than reporting a pass it did not earn:\n' >&2
  printf '  a link into an excluded file resolves on disk and 404s on the site.\n\n' >&2
  exit 2
}

# Does a repository-relative path fall under one of those entries? Jekyll matches a
# bare name at every depth and a trailing-slash entry as a directory prefix, so both
# shapes are handled. Fed by a heredoc rather than a pipe so that `return` returns
# from the function, and read line by line so a path containing a space still works.
pages_excluded() {
  rel=${1#docs/}
  [ "$rel" = "$1" ] && return 1          # not under docs/, so Pages never sees it
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in
      */) case "$rel" in "${pat}"*) return 0 ;; esac ;;
      *)  case "$rel" in "$pat"|*/"$pat") return 0 ;; esac ;;
    esac
  done <<EOF
$PAGES_EXCLUDES
EOF
  return 1
}

fail() { printf '  BROKEN  %s\n' "$1"; }
warn() { printf '  warn    %s\n' "$1"; }

# ------------------------------------------------------- links split over a line --
# A relative .md link inside docs/ has to sit on one line, and this is not a style
# rule. `jekyll-relative-links` is what turns [text](0001-thing.md) into a link to
# the published page, and it matches a link with a regex that does not cross a
# newline. Wrap the link text and the plugin does not see the link at all: Pages
# copies the .md through untouched and serves it as text/markdown, so the reader
# gets the raw file - front matter, pipe tables and all - instead of a page.
#
# It returns 200, which is why this is a separate check. Every other test here asks
# whether a target resolves, and a wrapped link resolves perfectly. It also never
# reached the link loop above, because that loop reads a line at a time and half a
# link matches nothing. This was live on docs/index.md and no check could see it.
check_wrapped() {
  for file in $(markdown_files); do
    case "$file" in docs/*) ;; *) continue ;; esac   # only the Pages-published tree
    awk -v F="$file" '
      /^[ \t]*```/ { fence = !fence; next }
      fence { next }
      { line[NR] = $0 }
      END {
        for (i = 1; i < NR; i++) {
          if (line[i] ~ /\[[^]]*$/ && line[i + 1] ~ /^[^]]*\]\([^)]*\.md[^)]*\)/) {
            target = line[i + 1]
            sub(/^[^]]*\]\(/, "", target)
            sub(/\).*$/, "", target)
            printf "  BROKEN  %s:%d -> %s (link text wraps onto line %d, so ", F, i, target, i + 1
            printf "jekyll-relative-links leaves it alone and the site serves raw markdown; "
            printf "put the whole link on one line)\n"
          }
        }
      }' "$file"
  done
}

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
        if pages_excluded "$full"; then
          fail "$file:$lineno -> $target (exists on disk, excluded from the Pages build by $PAGES_CONFIG, so it 404s on the site)"
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
# Every URL in the markdown, including the table in docs/SOURCES.md. Two things are
# skipped, because neither is a URL this pack is claiming you can reach:
#
#   a fenced block          an example in a snippet. Which is why a source URL
#                           belongs in a table and not in a fence.
#   "## Excluded, and why"  a section whose entire subject is URLs that are NOT
#                           sources, and whose commonest reason for listing one is
#                           that it 404s. Fetching those makes this check report a
#                           permanent failure for a page the document already says
#                           does not exist, and a checker with a failure nobody can
#                           fix is a checker everybody learns to skip.
#
# The rejected first attempt is worth recording, because it looked better than it was:
# skip any URL inside backticks, on the reasoning that backticks mean quoted. It does
# hide the excluded entries, and it also silently stopped checking
# `curl -fsSL https://opencode.ai/install | bash` and the two other installer URLs in
# docs/01-prerequisites.md - the links whose rot would strand a reader on step one.
# A URL's formatting does not say whether it should resolve. The section it is filed
# under does.
external_urls() {
  {
    for file in $(markdown_files); do
      awk '
        /^[ \t]*```/ { f = !f; next }
        f { next }
        /^## / { skip = ($0 ~ /^## Excluded, and why[ \t]*$/) }
        skip { next }
        { print }
      ' "$file" \
        | grep -o 'https\{0,1\}://[A-Za-z0-9._~:/?#@!$&*+,;=%-]*' \
        | sed 's/[.,)]*$//'
    done
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
    internal) check_internal; check_wrapped ;;
    external) check_external ;;
    all)      check_internal; check_wrapped; check_external ;;
  esac
}

# The one place in this script where a refusal can still stop the run. Only the modes
# that check internal links make a claim about the Pages build, so only they need it.
case "$MODE" in internal|all) assert_pages_excludes_readable ;; esac

OUT=$(run)
printf '%s\n' "$OUT"
BROKEN=$(printf '%s\n' "$OUT" | grep -c '^  BROKEN' || true)
WARNED=$(printf '%s\n' "$OUT" | grep -c '^  warn' || true)
printf '\n  %s: %d broken, %d warning(s)\n\n' "$MODE" "${BROKEN:-0}" "${WARNED:-0}"
[ "${BROKEN:-0}" -gt 0 ] && exit 1
exit 0
