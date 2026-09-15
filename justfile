set shell := ["bash", "-c"]

lint:
    shellcheck -x git-subtrees
    shellcheck playground/setup.sh

fmt:
    shfmt -w -i 2 -ci git-subtrees lib/*.sh playground/setup.sh

fmt-check:
    shfmt -d -i 2 -ci git-subtrees lib/*.sh playground/setup.sh

test:
    bats --recursive test

ci: lint fmt-check test
