# Makefile - the one entry point.
#
# Two ways to run the checks means one of them rots, so every check a human runs and
# every check CI runs is a target here. If CI does something this Makefile cannot do,
# that is a defect in the Makefile.
#
# The split that matters:
#
#   make check        no credentials, no workspace. This is the pull-request lane.
#   make links-live   reaches other people's web servers. A failure here is news about
#                     the world, not about the change under review.
#
# Nothing here is needed to set up a harness. These targets check this guide: that its
# scripts parse, its example configs are valid, and its links resolve. Setting yourself
# up is harness/<your-harness>/SETUP.md and needs none of it.
#
# Run `make help` for the list.

SHELL := /bin/sh
.DEFAULT_GOAL := help

.PHONY: help check lint config links links-live doctor

## help: list the targets
help:
	@printf '\n  databricks-agentic-engineering-rails\n\n'
	@sed -n 's/^## \([a-z0-9-]*\): \(.*\)/  make \1|\2/p' $(MAKEFILE_LIST) \
	  | awk -F'|' '{ printf "  %-16s %s\n", $$1, $$2 }'
	@printf '\n  Setting up a harness? You do not need any of these.\n'
	@printf '  Read harness/<your-harness>/SETUP.md instead.\n\n'

## check: every check that needs no credentials and no workspace
check: lint config links
	@printf '\n  check passed\n\n'

## lint: every shell script parses
lint:
	@printf '\n  syntax\n\n'
	@for f in $$(find scripts -name '*.sh' | sort); do \
	  sh -n "$$f" || exit 1; printf '  ok      %s parses\n' "$$f"; \
	done
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -s sh $$(find scripts -name '*.sh' | sort) \
	    && printf '  ok      shellcheck clean\n'; \
	else \
	  printf '  --      shellcheck not installed, so the scripts are parsed and not\n'; \
	  printf '          linted. brew install shellcheck\n'; \
	fi

## config: every harness config a reader copies is valid JSON or TOML
#
# These files are hand-maintained, which is the cost accepted in
# docs/DECISIONS/0006-guidance-over-machinery.md. A config with a trailing comma is the
# failure that decision made possible, so this is the check that answers for it.
#
# It exits 2 rather than passing when python3 is absent, because a checker that cannot
# run and reports success is worse than no checker. tomllib needs Python 3.11, so a
# missing tomllib is reported as "not validated" rather than treated as a pass.
config:
	@printf '\n  configs\n\n'
	@command -v python3 >/dev/null 2>&1 || { \
	  printf '  CANNOT CHECK  python3 absent, so the JSON and TOML configs were not\n'; \
	  printf '                validated. Exiting 2 rather than reporting a pass.\n'; \
	  exit 2; }
	@for f in $$(find harness -name '*.json' | sort); do \
	  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$$f" || exit 1; \
	  printf '  ok      %s is valid JSON\n' "$$f"; \
	done
	@if python3 -c 'import tomllib' 2>/dev/null; then \
	  for f in $$(find harness -name '*.toml' | sort); do \
	    python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$$f" || exit 1; \
	    printf '  ok      %s is valid TOML\n' "$$f"; \
	  done; \
	else \
	  printf '  --      python3 has no tomllib (needs 3.11), so the TOML was not validated\n'; \
	fi

## links: every relative link in the docs resolves, and none is wrapped
links:
	@./scripts/link-check.sh --internal

## links-live: every external URL in the docs still answers
links-live:
	@./scripts/link-check.sh --external

## doctor: what this machine has, in a table worth pasting into a bug report
doctor:
	@./scripts/doctor.sh
