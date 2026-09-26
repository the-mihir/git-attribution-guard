# Developer tasks. Requires: git, sh, awk. Optional: shellcheck, git-filter-repo.
SHELL   := /bin/sh
NAME    := git-attribution-guard
VERSION := $(shell cat VERSION)
DIST    := dist
SCRIPTS := scripts/attribution scripts/core.sh scripts/patterns.sh \
           scripts/hooks/_passthrough scripts/hooks/commit-msg scripts/hooks/pre-commit \
           scripts/hooks/pre-push install.sh tests/run.sh tests/lib.sh $(wildcard tests/test_*.sh)

.PHONY: help test lint check dist install uninstall clean version-check

help: ## Show this help
	@awk -F ':.*## ' '/^[a-z-]+:.*## / { printf "  %-14s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

test: ## Run the test suite
	sh tests/run.sh

lint: ## ShellCheck every script
	shellcheck -x $(SCRIPTS)

check: lint test ## Lint + test (run before every PR)

install: ## Install for the current user (same as ./install.sh)
	sh install.sh

uninstall: ## Remove the user install
	sh install.sh --uninstall

version-check: ## Fail unless TAG (e.g. v1.2.3) matches VERSION
	@test -n "$(TAG)" || { echo "usage: make version-check TAG=v$(VERSION)"; exit 1; }
	@test "v$(VERSION)" = "$(TAG)" || { echo "tag $(TAG) != VERSION v$(VERSION)"; exit 1; }
	@grep -q "^## \[$(VERSION)\]" CHANGELOG.md || { echo "CHANGELOG.md has no [$(VERSION)] section"; exit 1; }
	@echo "ok: $(TAG)"

dist: ## Build release archives + SHA256SUMS from the committed tree (HEAD)
	@test -z "$$(git status --porcelain --untracked-files=no)" || { echo "commit your changes first"; exit 1; }
	rm -rf $(DIST) && mkdir -p $(DIST)
	git archive --format=tar.gz --prefix=$(NAME)-$(VERSION)/ -o $(DIST)/$(NAME)-$(VERSION).tar.gz HEAD
	git archive --format=zip    --prefix=$(NAME)-$(VERSION)/ -o $(DIST)/$(NAME)-$(VERSION).zip HEAD
	cd $(DIST) && { command -v sha256sum >/dev/null && sha256sum *.tar.gz *.zip || shasum -a 256 *.tar.gz *.zip; } > SHA256SUMS
	@cat $(DIST)/SHA256SUMS

clean: ## Remove build output
	rm -rf $(DIST) tests/.tmp
