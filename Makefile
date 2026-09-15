SHELL := bash
FMT_FILES := git-subtrees $(wildcard lib/*.sh) playground/setup.sh

.PHONY: lint fmt fmt-check test ci

lint:
	shellcheck -x git-subtrees
	shellcheck playground/setup.sh

fmt:
	shfmt -w -i 2 -ci $(FMT_FILES)

fmt-check:
	shfmt -d -i 2 -ci $(FMT_FILES)

test:
	bats --recursive test

ci: lint fmt-check test
