set shell := ["bash", "-c"]

lint:
    shellcheck -x git-subtrees
    shellcheck -x docs/last-synced-commit/walkthrough.sh
    shellcheck playground/setup.sh playground/simulate-remote-change
    shellcheck completions/git-subtrees.bash
    shellcheck bench/setup.sh bench/run.sh

fmt:
    shfmt -w -i 2 -ci git-subtrees lib/*.sh docs/last-synced-commit/walkthrough.sh playground/setup.sh playground/simulate-remote-change completions/git-subtrees.bash bench/setup.sh bench/run.sh

fmt-check:
    shfmt -d -i 2 -ci git-subtrees lib/*.sh docs/last-synced-commit/walkthrough.sh playground/setup.sh playground/simulate-remote-change completions/git-subtrees.bash bench/setup.sh bench/run.sh

test:
    bats --recursive test

# Times the commands on a synthetic monorepo; see bench/run.sh --help.
bench *args:
    bench/run.sh {{args}}

ci: lint fmt-check test
