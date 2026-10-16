#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_stacked_detect.sh
# Loads the shipped gh-pr:create Step 1a stacked-PR detection functions from
#   skills/create/lib/stacked-pr.sh
# without its dispatch tail (everything from "# --- Dispatch" on calls gh and
# exits). Stage-2 inputs come through the script's own test seams:
# FAKE_OPEN_PRS, FAKE_ANCESTOR_REFS, FAKE_NONDEFAULT_REFS, FAKE_PARENT_STATE,
# FAKE_PARENT_BODY. No hand copy of the functions lives here.
eval "$(sed '/^# --- Dispatch/,$d' "${REPO_ROOT}/skills/create/lib/stacked-pr.sh")"
