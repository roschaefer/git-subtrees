set shell := ["bash", "-c"]

lint:
    shellcheck -x git-subtrees
    shellcheck playground/setup.sh playground/simulate-remote-change

fmt:
    shfmt -w -i 2 -ci git-subtrees lib/*.sh playground/setup.sh playground/simulate-remote-change

fmt-check:
    shfmt -d -i 2 -ci git-subtrees lib/*.sh playground/setup.sh playground/simulate-remote-change

test:
    bats --recursive test

ci: lint fmt-check test
