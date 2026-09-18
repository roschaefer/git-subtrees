set shell := ["bash", "-c"]

lint:
    shellcheck -x git-subtrees
    shellcheck -x docs/last-synced-commit/walkthrough.sh
    shellcheck playground/setup.sh playground/simulate-remote-change
    shellcheck completions/git-subtrees.bash

fmt:
    shfmt -w -i 2 -ci git-subtrees lib/*.sh docs/last-synced-commit/walkthrough.sh playground/setup.sh playground/simulate-remote-change completions/git-subtrees.bash

fmt-check:
    shfmt -d -i 2 -ci git-subtrees lib/*.sh docs/last-synced-commit/walkthrough.sh playground/setup.sh playground/simulate-remote-change completions/git-subtrees.bash

test:
    bats --recursive test

ci: lint fmt-check test
