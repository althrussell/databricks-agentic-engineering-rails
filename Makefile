# Makefile — the one entry point.
#
# Two ways to run the checks means one of them rots, so every check a human runs
# and every check CI runs is a target here. If CI does something this Makefile
# cannot do, that is a defect in the Makefile.
#
# The split that matters:
#
#   make check        hermetic. No network, no workspace, no credentials. This is
#                     the pull-request lane. A check that can fail because someone
#                     else's web server is down does not belong in it.
#   make check-live   network and workspace. Scheduled lane. Failures here are news
#                     about the world, not about the change under review.
#
# Run `make help` for the list.

SHELL := /bin/sh
.DEFAULT_GOAL := help

# Prefer the pinned virtualenv from `make deps` when it exists, so the checks do
# not depend on whatever the system python happens to have installed. Fall back to
# the system interpreter, because requiring a venv to run a linter is its own kind
# of friction.
PY := $(shell if [ -x .venv/bin/python3 ]; then echo .venv/bin/python3; else echo python3; fi)

# The versions this pack was exercised against, read from the file that records
# them rather than repeated here. One source of truth, and `make doctor` compares
# the reader's machine against the same numbers.
PANDOC_PINNED := $(shell sed -n '/^  pandoc:/,/^  [a-z_]*:/p' template-version.yml | sed -n 's/^    version: *"\(.*\)"/\1/p' | head -1)
TYPST_PINNED  := $(shell sed -n '/^  typst:/,/^  [a-z_]*:/p'  template-version.yml | sed -n 's/^    version: *"\(.*\)"/\1/p' | head -1)
PANDOC_FOUND  := $(shell pandoc --version 2>/dev/null | head -1 | sed 's/^pandoc *//')
TYPST_FOUND   := $(shell typst --version 2>/dev/null | head -1 | sed 's/^typst *//')

PROFILE ?= labs
RUNTIME := $(shell for c in docker podman finch nerdctl; do command -v $$c >/dev/null 2>&1 && { echo $$c; break; }; done)

.PHONY: help check check-live docs docs-repro deps doctor reverify clean \
        selftest sandbox-build sandbox-shell harness-verify-sandbox \
        harness-generate harness-verify test e2e

## help: list the targets
help:
	@printf '\n  databricks-agentic-engineering-rails\n\n'
	@sed -n 's/^## \([a-z0-9-]*\): \(.*\)/  make \1|\2/p' $(MAKEFILE_LIST) \
	  | awk -F'|' '{ printf "  %-28s %s\n", $$1, $$2 }'
	@printf '\n  Hermetic by default. `make check` needs no network and no credentials.\n\n'

# --------------------------------------------------------------------- checks --
## check: every check that needs no network and no credentials
check: selftest
	@$(PY) scripts/validate-manifests.py
	@./scripts/link-check.sh --internal
	@printf '\n  syntax\n\n'
	@for f in $$(find scripts harness -name '*.sh' 2>/dev/null); do \
	  sh -n "$$f" || exit 1; printf '  ok      %s parses\n' "$$f"; \
	done
	@for f in $$(find scripts -name '*.py' 2>/dev/null); do \
	  $(PY) -m py_compile "$$f" || exit 1; printf '  ok      %s compiles\n' "$$f"; \
	done
	@rm -rf scripts/__pycache__
	@printf '\n  check passed\n\n'

## check-live: the checks that need the network or a workspace
check-live:
	@./scripts/link-check.sh --external
	@./scripts/doctor.sh --live

## selftest: plant defects in the manifests and require every one to be caught
selftest:
	@$(PY) scripts/validate-manifests.py --self-test

# ----------------------------------------------------------------------- docs --
## docs: build every PDF and write release/release-manifest.json
docs:
	@if [ "$(PANDOC_FOUND)" != "$(PANDOC_PINNED)" ]; then \
	  printf '  note: pandoc %s found, %s recorded. Output may differ from the release.\n' \
	    "$(PANDOC_FOUND)" "$(PANDOC_PINNED)"; fi
	@if [ "$(TYPST_FOUND)" != "$(TYPST_PINNED)" ]; then \
	  printf '  note: typst %s found, %s recorded. Output may differ from the release.\n' \
	    "$(TYPST_FOUND)" "$(TYPST_PINNED)"; fi
	@$(PY) scripts/build-docs.py

## docs-repro: build twice and require byte-identical output
docs-repro:
	@if [ "$(PANDOC_FOUND)" != "$(PANDOC_PINNED)" ] || [ "$(TYPST_FOUND)" != "$(TYPST_PINNED)" ]; then \
	  printf '\n  refusing to check reproducibility on an unpinned toolchain.\n'; \
	  printf '  found   pandoc %s, typst %s\n' "$(PANDOC_FOUND)" "$(TYPST_FOUND)"; \
	  printf '  pinned  pandoc %s, typst %s\n\n' "$(PANDOC_PINNED)" "$(TYPST_PINNED)"; \
	  printf '  Byte-identical output is a claim about one toolchain. Comparing across\n'; \
	  printf '  versions would either fail for the wrong reason or pass by luck.\n\n'; \
	  exit 1; fi
	@$(PY) scripts/build-docs.py --check-reproducible

# ------------------------------------------------------------------ machine ----
## deps: create .venv with the pinned check dependencies
deps:
	@command -v uv >/dev/null 2>&1 || { printf '  uv is not installed. See docs/PREREQUISITES.md\n'; exit 1; }
	@uv venv .venv
	@uv pip install --python .venv/bin/python3 --quiet jsonschema==4.26.0 pyyaml==6.0.3
	@printf '\n  .venv ready. `make check` will use it automatically.\n\n'

## doctor: what this machine has, in a table worth pasting into a bug report
doctor:
	@./scripts/doctor.sh

## reverify: list claims past their re-verification interval, then check sources live
reverify:
	@$(PY) scripts/validate-manifests.py --strict-expiry || true
	@./scripts/link-check.sh --external

## clean: remove build output
clean:
	@rm -rf release .venv scripts/__pycache__
	@printf '  removed release/, .venv/ and __pycache__\n'

# ----------------------------------------------------------------- boundary ----
# The execution boundary. Without a container runtime these targets refuse rather
# than quietly doing something weaker under the same name — see
# docs/DECISIONS/0002-execution-boundary.md for the fallback and its residual risk.
## sandbox-build: build the disposable execution boundary image
sandbox-build:
	@if [ -z "$(RUNTIME)" ]; then \
	  printf '\n  No container runtime found (looked for docker, podman, finch, nerdctl).\n'; \
	  printf '  The scratch-HOME fallback is documented in docs/DECISIONS/0002-execution-boundary.md\n'; \
	  printf '  along with what it does not isolate. It is not this target.\n\n'; \
	  exit 1; fi
	@$(RUNTIME) build -f .devcontainer/Dockerfile -t daer-boundary .

## sandbox-shell: a shell inside the boundary, with only this repository mounted
sandbox-shell: sandbox-build
	@$(RUNTIME) run --rm -it \
	  --cap-drop ALL --security-opt no-new-privileges \
	  --read-only \
	  --tmpfs /tmp:rw,noexec,nosuid,size=512m \
	  --tmpfs /home/rails/.cache:rw,nosuid,size=1g \
	  --tmpfs /home/rails/.config:rw,nosuid,size=64m \
	  -e DATABRICKS_HOST \
	  -v "$(CURDIR)":/work -w /work \
	  -p 127.0.0.1:8020:8020 daer-boundary /bin/bash

## harness-verify-sandbox: authenticate and verify the harness inside the boundary
harness-verify-sandbox:
	@./harness/scripts/verify-in-sandbox.sh --profile $(PROFILE)

# ------------------------------------------------------------------ harness ----
## harness-generate: render every harness config from harness/shared/
harness-generate:
	@./harness/scripts/generate.sh

## harness-verify: fail if a generated harness config has been hand-edited
harness-verify:
	@./harness/scripts/verify.sh

# -------------------------------------------------------------------- tracks ---
## test: unit and contract tests for whichever track is present
test:
	@found=0; \
	for d in track-a-app track-b-service; do \
	  if [ -f "$$d/Makefile" ]; then found=1; $(MAKE) -C "$$d" test || exit 1; fi; \
	done; \
	if [ "$$found" = 0 ]; then \
	  printf '\n  No track has a Makefile yet, so there is nothing to test.\n'; \
	  printf '  Track A and Track B arrive in Phase 2. Exiting non-zero so this\n'; \
	  printf '  cannot be mistaken for a passing test run.\n\n'; exit 1; fi

## e2e: real end-to-end tests for whichever track is present
e2e:
	@found=0; \
	for d in track-a-app track-b-service; do \
	  if [ -f "$$d/Makefile" ]; then found=1; $(MAKE) -C "$$d" e2e || exit 1; fi; \
	done; \
	if [ "$$found" = 0 ]; then \
	  printf '\n  No track has a Makefile yet, so there is nothing to run end to end.\n'; \
	  printf '  Exiting non-zero: an e2e target that passes with no tests is the\n'; \
	  printf '  failure mode this pack exists to prevent.\n\n'; exit 1; fi
