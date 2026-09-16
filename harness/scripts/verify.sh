#!/bin/sh
# verify.sh - fail if a generated harness configuration no longer matches the policy.
#
# Usage:  verify.sh [--quiet] [harness ...]
# Exit:   0  every generated directory matches harness/shared/
#         1  drift, a missing file, an unexpected file, or a broken manifest
#         2  this script cannot do its job (no sha256 tool, no manifest anywhere)
#
# Why this is POSIX sh and not Python
# -----------------------------------
# It has to work when the environment that produced the generated files is broken.
# The renderer needs a YAML parser; the check does not, because `.generated.sha256`
# is deliberately a flat tab-separated file. So `make check` can tell you that your
# harness config has drifted even on a machine where `make harness-generate` would
# fail for want of a dependency. See docs/DECISIONS/0004-posix-sh-for-diagnostics.md.
#
# The two failures it separates
# -----------------------------
# These look identical in a diff and mean opposite things:
#
#   * The policy moved. Someone edited harness/shared/ and did not regenerate. The
#     generated files are stale. The fix is `make harness-generate`, and reviewing
#     the resulting diff is the point of the exercise.
#   * The output moved. Someone edited a generated file directly, usually to fix
#     something in a hurry. The fix is to make the change in harness/shared/ and
#     regenerate, because the edit is about to be silently reverted by the next
#     person who runs the generator.
#
# A checker that reported both as "files differ" would train people to run the
# generator until the message went away, which turns the second case into a lost
# change and a confused afternoon.

set -eu

cd "$(dirname "$0")/../.."

QUIET=0
TARGETS=""
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    -*)
      printf 'verify.sh: unknown option %s\n' "$arg" >&2
      exit 2 ;;
    *) TARGETS="$TARGETS $arg" ;;
  esac
done

TAB=$(printf '\t')
FAILED=0
CHECKED=0

say()  { [ "$QUIET" = 1 ] || printf '  %s\n' "$*"; }
loud() { printf '  %s\n' "$*"; }
fail() { FAILED=$((FAILED + 1)); printf '  FAIL    %s\n' "$*"; }

# ------------------------------------------------------------------ the hash tool --
# Both spellings exist in the wild and neither is guaranteed. A checker that silently
# skipped its own check because a tool was missing would be worse than no checker, so
# the absence is exit 2 and not a pass.
if command -v shasum >/dev/null 2>&1; then
  hash_stdin() { shasum -a 256 | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
  hash_stdin() { sha256sum | awk '{print $1}'; }
else
  printf '\n  No sha256 tool found (looked for shasum, sha256sum).\n' >&2
  printf '  This check compares hashes and cannot degrade into something weaker\n' >&2
  printf '  under the same name. Exiting 2 rather than reporting a pass.\n\n' >&2
  exit 2
fi
hash_file() { hash_stdin < "$1"; }

# ------------------------------------------------------------- the inputs digest --
# Must agree exactly with inputs_digest() in harness/scripts/render.py: one line per
# input file, "<sha256><two spaces><path relative to the repository root>", sorted as
# bytes, hashed as a whole. The sort is over the whole line and therefore over the
# hash, which is why LC_ALL=C matters - a locale-aware sort would order these
# differently from Python's and every comparison would fail for no reason.
#
# One digest covers all five harnesses because they share a launcher template. A scope
# that pretended otherwise would call a stale directory fresh, which is the one wrong
# answer this file must never give.
inputs_digest() {
  {
    printf '%s  %s\n' "$(hash_file harness/scripts/render.py)" harness/scripts/render.py
    find harness/shared harness/scripts/templates -type f \
         ! -name '*.pyc' ! -name '.DS_Store' 2>/dev/null \
      | grep -v '/__pycache__/' \
      | while IFS= read -r f; do
          printf '%s  %s\n' "$(hash_file "$f")" "$f"
        done
  } | LC_ALL=C sort | hash_stdin
}

# ------------------------------------------------------------------ what to check --
# Every directory under harness/ that carries a manifest. Discovered rather than
# listed, so promoting a harness does not mean remembering to edit this file.
if [ -n "$TARGETS" ]; then
  DIRS=""
  for t in $TARGETS; do DIRS="$DIRS harness/$t"; done
else
  DIRS=$(find harness -mindepth 2 -maxdepth 2 -name '.generated.sha256' \
           -exec dirname {} \; 2>/dev/null | LC_ALL=C sort)
fi

if [ -z "$(printf '%s' "$DIRS" | tr -d ' \n')" ]; then
  printf '\n  No generated harness configuration found.\n' >&2
  printf '  Run `make harness-generate` first. Exiting 2: "nothing to check" is not\n' >&2
  printf '  the same result as "everything checks out".\n\n' >&2
  exit 2
fi

for dir in $DIRS; do
  manifest="$dir/.generated.sha256"

  if [ ! -f "$manifest" ]; then
    fail "$dir has no .generated.sha256. Run: make harness-generate"
    continue
  fi

  # ------------------------------------------------------------------- the schema --
  schema=$(awk -F"$TAB" '$1 == "schema" { print $2; exit }' "$manifest")
  if [ "$schema" != "1" ]; then
    fail "$manifest declares schema '$schema'; this checker reads schema 1 only. A newer manifest needs a newer verify.sh, not a best guess."
    continue
  fi

  # --------------------------------------------------------- policy versus output --
  # Read first, because it decides which of the two stories the rest of the output
  # tells. A stale directory is expected to have differing file hashes; saying
  # "hand-edited" about every one of them would be six wrong messages.
  recorded=$(awk -F"$TAB" '$1 == "inputs" { print $2; exit }' "$manifest")
  if [ -z "$recorded" ]; then
    fail "$manifest records no inputs digest, so this check cannot tell a stale directory from an edited one. Regenerate it."
    continue
  fi
  actual=$(inputs_digest)
  if [ "$recorded" = "$actual" ]; then
    stale=0
  else
    stale=1
  fi

  # --------------------------------------------------------------- the file hashes --
  drifted=0
  missing=0
  notexec=0
  absent=0
  listed=""

  while IFS="$TAB" read -r kind a b c || [ -n "${kind:-}" ]; do
    case "$kind" in
      file)
        mode="$a"; want="$b"; rel="$c"
        listed="$listed $rel"
        path="$dir/$rel"
        if [ ! -f "$path" ]; then
          missing=$((missing + 1))
          fail "$path is in the manifest and not on disk."
          continue
        fi
        got=$(hash_file "$path")
        if [ "$got" != "$want" ]; then
          drifted=$((drifted + 1))
          [ "$stale" = 1 ] || fail "$path was edited by hand."
        fi
        # Mode is checked as the one property that changes behaviour: a hook or a
        # launcher that is not executable fails at the moment someone needs it, with
        # an error about the shell rather than about the file. Comparing the full
        # permission bits would mean parsing `stat` output, which differs between
        # macOS and Linux, for no additional protection.
        case "$mode" in
          7*)
            if [ ! -x "$path" ]; then
              notexec=$((notexec + 1))
              fail "$path is recorded as executable and is not. Run: make harness-generate"
            fi ;;
          *)
            if [ -x "$path" ]; then
              notexec=$((notexec + 1))
              fail "$path is recorded as non-executable and is executable."
            fi ;;
        esac
        ;;
      unmanaged)
        listed="$listed $a"
        if [ ! -f "$dir/$a" ]; then
          absent=$((absent + 1))
          fail "$dir/$a is declared hand-written and is absent. The generator will not create it; write it or remove the declaration."
        fi
        ;;
    esac
  done < "$manifest"

  if [ "$stale" = 1 ]; then
    loud "STALE   $dir"
    loud "        harness/shared/, the templates or the renderer changed after the last"
    loud "        render, so these files describe the previous policy. $drifted of the"
    loud "        recorded files differ."
    loud "        Fix: make harness-generate, then read the diff. That diff is the"
    loud "        review of the policy change."
    FAILED=$((FAILED + 1))
  fi

  # ------------------------------------------------------------ unexpected files --
  # A file in a generated directory that the manifest does not know about is either a
  # rename that was not finished or something hand-written that will be silently
  # overwritten one day. Both are worth a line.
  extra=0
  for path in $(find "$dir" -type f ! -name '.generated.sha256' 2>/dev/null | LC_ALL=C sort); do
    rel=${path#"$dir/"}
    found=0
    for known in $listed; do
      [ "$known" = "$rel" ] && { found=1; break; }
    done
    if [ "$found" = 0 ]; then
      extra=$((extra + 1))
      fail "$path is not in the manifest. Either the renderer should produce it, or it should be declared hand-written, or it should not be here."
    fi
  done

  CHECKED=$((CHECKED + 1))
  count=$(awk -F"$TAB" '$1 == "file"' "$manifest" | wc -l | tr -d ' ')
  if [ "$stale" = 0 ] && [ "$drifted" = 0 ] && [ "$missing" = 0 ] \
     && [ "$notexec" = 0 ] && [ "$extra" = 0 ] && [ "$absent" = 0 ]; then
    say "ok      $dir matches harness/shared/ ($count files)"
  fi
done

if [ "$FAILED" -gt 0 ]; then
  printf '\n  harness-verify: %d problem(s) across %d directory/ies.\n\n' "$FAILED" "$CHECKED" >&2
  exit 1
fi

if [ "$QUIET" = 1 ]; then
  printf '  ok      harness config matches harness/shared/ (%d directory/ies)\n' "$CHECKED"
else
  printf '\n  harness-verify: %d generated directory/ies match the policy.\n\n' "$CHECKED"
fi
