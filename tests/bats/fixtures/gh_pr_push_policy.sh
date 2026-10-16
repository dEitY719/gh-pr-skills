#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_push_policy.sh
# Loads the shipped gh-pr:create Step 1b / Step 5 functions from
#   skills/create/lib/branch-state.sh
# without its dispatch tail (everything from "# --- Dispatch" on runs git and
# exits), so the pure string/set logic is tested with plain arguments.
# No hand copy of the functions lives here.
eval "$(sed '/^# --- Dispatch/,$d' "${REPO_ROOT}/skills/create/lib/branch-state.sh")"
