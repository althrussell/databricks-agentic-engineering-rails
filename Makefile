# Makefile — the one entry point.
#
# Two ways to run the checks means one of them rots, so every check a human runs and
# every check CI runs is a target here. If CI does something this Makefile cannot do,
# that is a defect in the Makefile.
#
# The split that matters:
#
#   make check        hermetic. No network, no workspace, no credentials. This is the
#                     pull-request lane. A check that can fail because someone else's
#                     web server is down does not belong in it.
#   make check-live   network and workspace. Scheduled lane. Failures here are news
#                     about the world, not about the change under review.
#
# Run `make help` for the list.

SHELL := /bin/sh
.DEFAULT_GOAL := help

# Prefer the pinned virtualenv from `make deps` when it exists, so the checks do not
# depend on whatever the system python happens to have installed. Fall back to the
# system interpreter, because requiring a venv to run a linter is its own friction.
PY := $(shell if [ -x .venv/bin/python3 ]; then echo .venv/bin/python3; else echo python3; fi)

# The versions this pack was exercised against, read from the file that records them
# rather than repeated here. One source of truth, and `make doctor` compares the
# reader's machine against the same numbers.
PANDOC_PINNED := $(shell sed -n '/^  pandoc:/,/^  [a-z_]*:/p' template-version.yml | sed -n 's/^    version: *"\(.*\)"/\1/p' | head -1)
TYPST_PINNED  := $(shell sed -n '/^  typst:/,/^  [a-z_]*:/p'  template-version.yml | sed -n 's/^    version: *"\(.*\)"/\1/p' | head -1)
PANDOC_FOUND  := $(shell pandoc --version 2>/dev/null | head -1 | sed 's/^pandoc *//')
TYPST_FOUND   := $(shell typst --version 2>/dev/null | head -1 | sed 's/^typst *//')

# The Databricks CLI profile the live targets authenticate with. DEFAULT is the CLI's
# own default, so the live lanes work on a machine that has run `databricks auth login`
# once and nothing else. Override per invocation:
#   make tool-budget-live PROFILE=my-workspace
PROFILE ?= DEFAULT

.PHONY: help check check-live lint links test docs deps doctor clean \
        harness-generate harness-verify harness-deny-proof \
        tool-budget tool-budget-live

## help: list the targets
help:
	@printf '\n  databricks-agentic-engineering-rails\n\n'
	@sed -n 's/^## \([a-z0-9-]*\): \(.*\)/  make \1|\2/p' $(MAKEFILE_LIST) \
	  | awk -F'|' '{ printf "  %-24s %s\n", $$1, $$2 }'
	@printf '\n  Start with `make doctor`. Hermetic by default: `make check` needs no\n'
	@printf '  network and no credentials.\n\n'

# --------------------------------------------------------------------- checks --
## check: every check that needs no network and no credentials
check: lint links harness-verify test
	@./scripts/tool-budget.py --quiet
	@printf '\n  check passed\n\n'

## check-live: the checks that need the network or a workspace
check-live:
	@./scripts/link-check.sh --external
	@./scripts/doctor.sh --live

## lint: every shell script parses, every python file compiles
lint:
	@printf '\n  syntax\n\n'
	@for f in $$(find scripts harness -name '*.sh' 2>/dev/null | sort); do \
	  sh -n "$$f" || exit 1; printf '  ok      %s parses\n' "$$f"; \
	done
	@for f in $$(find scripts harness -name '*.py' 2>/dev/null | sort); do \
	  $(PY) -m py_compile "$$f" || exit 1; printf '  ok      %s compiles\n' "$$f"; \
	done
	@rm -rf scripts/__pycache__ harness/scripts/__pycache__
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -s sh $$(find scripts harness -name '*.sh' | sort) \
	    && printf '  ok      shellcheck clean\n'; \
	else \
	  printf '  --      shellcheck not installed, so the shell scripts are parsed and\n'; \
	  printf '          not linted. brew install shellcheck\n'; \
	fi

## links: every relative link in the docs resolves to a file that exists
links:
	@./scripts/link-check.sh --internal

## test: the never-automatic tier against its verdict table
test:
	@printf '\n  harness\n\n'
	@./harness/scripts/deny-proof.sh

# ----------------------------------------------------------------------- docs --
## docs: build the PDFs from the markdown
docs:
	@if [ "$(PANDOC_FOUND)" != "$(PANDOC_PINNED)" ]; then \
	  printf '  note: pandoc %s found, %s recorded. Output may differ from the release.\n' \
	    "$(PANDOC_FOUND)" "$(PANDOC_PINNED)"; fi
	@if [ "$(TYPST_FOUND)" != "$(TYPST_PINNED)" ]; then \
	  printf '  note: typst %s found, %s recorded. Output may differ from the release.\n' \
	    "$(TYPST_FOUND)" "$(TYPST_PINNED)"; fi
	@$(PY) scripts/build-docs.py

# ------------------------------------------------------------------ machine ----
## deps: create .venv with the pinned check dependencies
deps:
	@command -v uv >/dev/null 2>&1 || { printf '  uv is not installed. See docs/01-prerequisites.md\n'; exit 1; }
	@uv venv .venv
	@uv pip install --python .venv/bin/python3 --quiet pyyaml==6.0.3
	@printf '\n  .venv ready. `make check` will use it automatically.\n\n'

## doctor: what this machine has, in a table worth pasting into a bug report
doctor:
	@./scripts/doctor.sh

## clean: remove build output
clean:
	@rm -rf release .venv scripts/__pycache__ harness/scripts/__pycache__
	@printf '  removed release/, .venv/ and __pycache__\n'

# ------------------------------------------------------------------ harness ----
## harness-generate: render every harness config from harness/shared/
harness-generate:
	@./harness/scripts/generate.sh

## harness-verify: fail if a generated harness config has been hand-edited
harness-verify:
	@./harness/scripts/verify.sh

## harness-deny-proof: run the never-automatic tier against its verdict table
harness-deny-proof:
	@./harness/scripts/deny-proof.sh

## tool-budget: report what the MCP configuration costs in context
tool-budget:
	@./scripts/tool-budget.py

## tool-budget-live: the same, measured against the governed route (needs a workspace)
tool-budget-live:
	@DAER_PROFILE=$(PROFILE) ./scripts/tool-budget.py --live
