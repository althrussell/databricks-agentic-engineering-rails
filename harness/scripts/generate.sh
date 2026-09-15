#!/bin/sh
# generate.sh - render harness/shared/ into every implemented harness's config.
#
# Two jobs, and the second is the reason this is a shell script wrapping a Python one
# rather than a Makefile line calling python3 directly:
#
#   1. Find an interpreter that can actually run the renderer, preferring the pinned
#      virtualenv from `make deps` so the output does not depend on whatever the
#      system Python happens to have installed.
#   2. Explain a missing or broken interpreter in one screen. `python3: command not
#      found` in the middle of a build tells a reader nothing about what to install or
#      why this repository wants it, and the first thirty seconds of using a pack like
#      this one is where it earns or loses trust.
#
# Everything about the actual policy lives in harness/scripts/render.py. This file
# deliberately knows nothing about permissions, MCP or the gateway, so that a change
# to the policy never needs a change here.

set -eu

cd "$(dirname "$0")/../.."

RENDER="harness/scripts/render.py"

if [ ! -f "$RENDER" ]; then
  printf '\n  %s is missing.\n\n' "$RENDER" >&2
  printf '  This script is only a launcher. Without the renderer there is nothing to\n' >&2
  printf '  render, and hand-writing the generated directory is the one thing\n' >&2
  printf '  harness/shared/README.md asks you not to do.\n\n' >&2
  exit 1
fi

# The venv first, then the system interpreter. Same order as the Makefile, for the
# same reason: requiring a virtualenv to render a config file is its own friction.
PY=""
if [ -x .venv/bin/python3 ]; then
  PY=.venv/bin/python3
else
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
  done
fi

if [ -z "$PY" ]; then
  printf '\n  No Python interpreter found (looked for .venv/bin/python3, python3, python).\n\n' >&2
  printf '  The renderer parses YAML and emits JSON, which is the one job in this\n' >&2
  printf '  repository that POSIX sh should not be doing by hand. See\n' >&2
  printf '  docs/DECISIONS/0004-two-languages.md for where the line sits, and\n' >&2
  printf '  docs/PREREQUISITES.md for what to install.\n\n' >&2
  exit 1
fi

# An interpreter that exists but cannot import yaml is the common failure, and it is
# worth separating from a missing interpreter because the fix is different.
if ! "$PY" -c 'import yaml' >/dev/null 2>&1; then
  printf '\n  %s cannot import pyyaml.\n\n' "$PY" >&2
  printf '  Run `make deps` to build the pinned virtualenv, or install it into the\n' >&2
  printf '  interpreter you are using. The renderer reads four YAML files in\n' >&2
  printf '  harness/shared/ and will not guess at their contents.\n\n' >&2
  exit 1
fi

exec "$PY" "$RENDER" "$@"
