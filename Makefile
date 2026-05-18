.PHONY: lint test check help

SHELL := /bin/bash

help:  ## Show this help.
	@awk -F':.*##' '/^[a-z][a-zA-Z_-]*:.*##/ {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

lint:  ## Run ShellCheck on bin/ppl and test helpers.
	shellcheck --shell=bash --severity=style bin/ppl test/helpers/common.bash test/helpers/stubs/*

test:  ## Run the bats-core test suite.
	bats test

check: lint test  ## Run lint + tests (what CI runs).
