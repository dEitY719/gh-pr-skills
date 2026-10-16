#!/usr/bin/env bash
# tests/bats/test_helper.bash — shared setup for every tests/bats/*.bats file.
#
# bats-support / bats-assert come from BATS_LIB_PATH (CI: .github/workflows/bats.yml).
# Locally: BATS_LIB_PATH=<dir holding bats-support and bats-assert> bats -r tests/bats
# shellcheck disable=SC2034,SC1091  # vars are read by the eval'd shipped blocks or the .bats; sources resolve at run time
bats_load_library bats-support
bats_load_library bats-assert

# Repo root, so a test can reach the shipped skills/*/lib, skills/*/references
# and lib/vendor files it pins its fixture to.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT
FIXTURES="${REPO_ROOT}/tests/bats/fixtures"

# A throwaway HOME: nothing a test runs may reach the developer's real
# ~/dotfiles, ~/.claude* or XDG dirs. The skill libs default SHELL_COMMON to
# $HOME/dotfiles/shell-common, so this also keeps a local dotfiles checkout
# from shadowing the vendored copy under test.
setup_isolated_home() {
    TEST_TEMP_HOME="$(mktemp -d)"
    export HOME="$TEST_TEMP_HOME"
    unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_ROOT SHELL_COMMON DOTFILES_ROOT
    export XDG_CONFIG_HOME="$TEST_TEMP_HOME"
    export XDG_CACHE_HOME="$TEST_TEMP_HOME"
    export XDG_DATA_HOME="$TEST_TEMP_HOME"
    export TERM=dumb
}

teardown_isolated_home() {
    if [ -n "${TEST_TEMP_HOME-}" ] && [ -d "$TEST_TEMP_HOME" ]; then
        rm -rf "$TEST_TEMP_HOME"
    fi
}

# Print the body of the Nth ```bash fence (1-based, default 1) in a markdown
# file, so a test runs the text the skill actually ships instead of a copy.
fence_block() {
    awk -v want="${2:-1}" '
        /^```bash[[:space:]]*$/ { n++; if (n == want) { on = 1; next } }
        on && /^```[[:space:]]*$/ { exit }
        on { print }
    ' "$1"
}
