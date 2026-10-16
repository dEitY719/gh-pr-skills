#!/usr/bin/env bash
# tests/bats/fixtures/helper_fallback_nf1.sh
# dEitY719/dotfiles#644 NF-1 — a missing shell-common helper must never abort
# the calling skill. The hand-copied `[ -r "$_HELPER" ]` block this used to
# mirror is gone from every skill here: they now ship the soft tier-ladder
# loader (harness-skills#60). This fixture runs one shipped instance of it,
#   skills/approve/lib/board-approved-sync.sh
# so the NF-1 guarantee is tested on real code.

# Usage: nf1_canonical_block <pr> — the shipped loader + call, then the line
# the calling skill would print next. SHELL_COMMON comes from the test.
nf1_canonical_block() {
    TARGET_HOST=github.com TARGET_REPO=o/r \
        bash "${REPO_ROOT}/skills/approve/lib/board-approved-sync.sh" "$1" 2>&1 &&
        echo "BLOCK_COMPLETED"
}

# Synthesise a minimal helper file at the given path. Its stub
# _gh_project_status_sync proves it ran by printing BLOCK_RAN.
nf1_install_fake_helper() {
    local _path="$1"
    mkdir -p "$(dirname "$_path")"
    cat >"$_path" <<'SC'
_gh_project_status_sync() {
    printf 'BLOCK_RAN sync_called with: %s\n' "$*"
    return 0
}
SC
}
