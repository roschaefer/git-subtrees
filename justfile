set shell := ["bash", "-c"]

# Run shellcheck
lint:
    shellcheck -x git-subtrees
    shellcheck -x docs/last-synced-commit/walkthrough.sh
    shellcheck playground/setup.sh playground/simulate-remote-change
    shellcheck completions/git-subtrees.bash
    shellcheck bench/setup.sh bench/run.sh
    shellcheck docs/readme-demo-setup.sh

# Format with shfmt
fmt:
    shfmt -w -i 2 -ci git-subtrees lib/*.sh docs/last-synced-commit/walkthrough.sh playground/setup.sh playground/simulate-remote-change completions/git-subtrees.bash bench/setup.sh bench/run.sh docs/readme-demo-setup.sh

# Check formatting with shfmt
fmt-check:
    shfmt -d -i 2 -ci git-subtrees lib/*.sh docs/last-synced-commit/walkthrough.sh playground/setup.sh playground/simulate-remote-change completions/git-subtrees.bash bench/setup.sh bench/run.sh docs/readme-demo-setup.sh

# Run the bats tests
test:
    bats --recursive test

# Time commands on a synthetic monorepo; see `just bench --help`
[positional-arguments]
bench *args:
    @bench/run.sh "$@"

# Open a shell in a throwaway monorepo to try commands by hand; see `just playground --help`
[positional-arguments]
playground *args:
    @playground/setup.sh "$@"

# Check the README's example against real output; --write updates it
readme-demo flag="":
    @if [[ "{{flag}}" == --write ]]; then \
      scrut update --replace --assume-yes README.md; \
    elif [[ -n "{{flag}}" ]]; then \
      echo "usage: just readme-demo [--write]" >&2; exit 1; \
    elif ! scrut test README.md; then \
      echo "The README's example doesn't match real output. If only the output changed, run 'just readme-demo --write'." >&2; exit 1; \
    fi

# Everything CI runs: lint, fmt-check, test and readme-demo
ci: lint fmt-check test readme-demo
