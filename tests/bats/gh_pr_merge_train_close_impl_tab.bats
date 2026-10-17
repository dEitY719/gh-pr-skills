#!/usr/bin/env bats
# tests/bats/gh_pr_merge_train_close_impl_tab.bats
# Verify the step-7 impl-tab close of gh-pr:merge-train — the shipped block in
# skills/merge-train/references/train-loop.md, fence-extracted by
# fixtures/gh_pr_merge_train_close_impl_tab.sh. Moved from dEitY719/dotfiles
# tests/bats/skills/ by dEitY719/dotfiles#2200; the hand copy is gone.
#
# dEitY719/dotfiles#1565: gh-pr:merge Step 5's post-merge-verify dispatch
# executed 0/10 times inside the train loop. The impl tabs of 10 merged PRs
# stayed open, dotfiles' issue-watcher counted their worktrees as running, and
# `_IW_MAX_PER_REPO=3` stopped it after ~3 merges.
#
# Cases:
#   1. idle agent on the merged branch's worktree -> tab closed, one [INFO]
#   2. agent_status == working / blocked           -> NEVER closed, no output
#   3. no worktree / no herdr / dead herdr          -> silent skip, rc 0
#   4. two agents on one cwd                       -> first wins, closed once
#   5. herdr tab close fails                       -> [WARN], never fatal
#   6. anti-starvation regression: the live count does not grow across N merges
#   7. the shipped block carries no inline match predicate (dEitY719/dotfiles#1569)
# The predicate itself (cwd OR foreground_cwd, path boundary, physical path)
# belongs to dotfiles' shell-common/lib/herdr_agent_lookup.sh and is
# tested there; this suite runs against fixtures/herdr_agent_lookup_stub.sh.

load 'test_helper'

setup() {
    setup_isolated_home
    # shellcheck source=fixtures/gh_pr_merge_train_close_impl_tab.sh
    source "${FIXTURES}/gh_pr_merge_train_close_impl_tab.sh"
    install_herdr_lookup_stub "${TEST_TEMP_HOME}/dotfiles"

    WT_DIR="/home/dev/wt/issue-1565"
    export WT_DIR

    FAKE_WORKTREE_LIST="worktree /home/dev/dotfiles
HEAD 1111111111111111111111111111111111111111
branch refs/heads/main

worktree ${WT_DIR}
HEAD 2222222222222222222222222222222222222222
branch refs/heads/wt/issue-1565/1
"
    export FAKE_WORKTREE_LIST

    FAKE_CALL_LOG="${TEST_TEMP_HOME}/calls.log"
    export FAKE_CALL_LOG
    : >"$FAKE_CALL_LOG"

    # Shadow `git` so `git worktree list --porcelain` reads a fixed table
    # instead of this repo's real worktrees.
    git() {
        printf 'git %s\n' "$*" >>"$FAKE_CALL_LOG"
        if [ "$1" = "worktree" ] && [ "$2" = "list" ]; then
            printf '%s' "${FAKE_WORKTREE_LIST-}"
            return 0
        fi
        command git "$@"
    }

    # Shadow `herdr`. `agent list` is canned and steerable; `tab close` records
    # the tab it was asked to close so the tests assert on calls made, not only
    # on printed text. FAKE_CLOSE_RC simulates a refusal.
    herdr() {
        printf 'herdr %s\n' "$*" >>"$FAKE_CALL_LOG"
        if [ "$1" = "agent" ] && [ "$2" = "list" ]; then
            [ "${FAKE_AGENT_RC:-0}" -eq 0 ] || return "$FAKE_AGENT_RC"
            printf '%s' "${FAKE_AGENT_JSON-}"
            return 0
        fi
        if [ "$1" = "tab" ] && [ "$2" = "close" ]; then
            [ "${FAKE_CLOSE_RC:-0}" -eq 0 ] || return "$FAKE_CLOSE_RC"
            printf '%s\n' "$3" >>"${FAKE_CLOSED_LOG:-/dev/null}"
            return 0
        fi
        return 1
    }

    FAKE_CLOSED_LOG="${TEST_TEMP_HOME}/closed.log"
    export FAKE_CLOSED_LOG
    : >"$FAKE_CLOSED_LOG"
}

teardown() {
    teardown_isolated_home
    unset -f git herdr 2>/dev/null || true
    unset WT_DIR FAKE_WORKTREE_LIST FAKE_AGENT_JSON FAKE_AGENT_RC FAKE_CALL_LOG \
        FAKE_CLOSE_RC FAKE_CLOSED_LOG
}

# Build an agent-list payload from `cwd|tab_id|status` specs.
_agents_json() {
    local spec sep="" out='{"result":{"agents":['
    local cwd tab st
    for spec in "$@"; do
        IFS='|' read -r cwd tab st <<<"$spec"
        out+="${sep}{\"cwd\":\"${cwd}\",\"foreground_cwd\":\"${cwd}\",\"tab_id\":\"${tab}\",\"agent_status\":\"${st}\"}"
        sep=","
    done
    printf '%s]}}' "$out"
}

# Same, but `cwd` and `foreground_cwd` are set independently:
# `cwd|foreground_cwd|tab_id|status`. `cwd` is where the pane was opened,
# `foreground_cwd` where its shell stands now — they diverge the moment the
# session `cd`s, which is the case _iw_live_agents already counts as live.
_agents_json_fg() {
    local spec sep="" out='{"result":{"agents":['
    local cwd fg tab st
    for spec in "$@"; do
        IFS='|' read -r cwd fg tab st <<<"$spec"
        out+="${sep}{\"cwd\":\"${cwd}\",\"foreground_cwd\":\"${fg}\",\"tab_id\":\"${tab}\",\"agent_status\":\"${st}\"}"
        sep=","
    done
    printf '%s]}}' "$out"
}

# --- 1. the happy path ----------------------------------------------------

@test "close-impl-tab: an idle agent on the merged worktree gets its tab closed" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    assert_output --partial '[INFO] gh-pr:merge-train: closed implementation tab tab-7'
    assert_output --partial "(${WT_DIR})"
    [ "${#lines[@]}" -eq 1 ]
}

@test "close-impl-tab: the close really is invoked, with that tab id" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    run cat "$FAKE_CLOSED_LOG"
    assert_output "tab-7"
}

@test "close-impl-tab: the branch decides the worktree, not the directory name" {
    # Two worktrees, one agent each; only the merged branch's tab may close.
    FAKE_WORKTREE_LIST="worktree /home/dev/wt/issue-1000
HEAD aaaa
branch refs/heads/wt/issue-1000/1

worktree ${WT_DIR}
HEAD bbbb
branch refs/heads/wt/issue-1565/1
"
    FAKE_AGENT_JSON="$(_agents_json \
        "/home/dev/wt/issue-1000|tab-other|idle" \
        "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    run cat "$FAKE_CLOSED_LOG"
    assert_output "tab-7"
}

# --- 1b. the symlinked path (PR dEitY719/dotfiles#1567 review) ------------
#
# The block hands the lookup `herdr_agent_physical_path "$PMT_WT"`, so a
# worktree reached through a symlink still resolves. The subdir / foreground /
# prefix-sibling cases test the lookup SSOT itself and stayed with it in
# dotfiles (tests/bats/functions/herdr_agent_lookup.bats).

@test "close-impl-tab: a symlinked worktree path still resolves to the agent" {
    # `git worktree list` answers the path as it was created; herdr answers
    # where the pane really stands. One symlinked component made the old
    # string compare miss, and the tab silently survived the merge.
    local real="${TEST_TEMP_HOME}/real/wt-issue-1565"
    local link="${TEST_TEMP_HOME}/link-wt"
    mkdir -p "$real"
    ln -sfn "$real" "$link"

    FAKE_WORKTREE_LIST="worktree ${link}
HEAD cccc
branch refs/heads/wt/issue-1565/1
"
    # The agent reports the physical path — the two strings are not equal.
    FAKE_AGENT_JSON="$(_agents_json "$(cd -P "$real" && pwd -P)|tab-7|idle")"
    [ "$link" != "$real" ]

    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    run cat "$FAKE_CLOSED_LOG"
    assert_output "tab-7"
}

@test "close-impl-tab: an unresolvable worktree path falls back to the raw string" {
    # `cd -P` fails for a path that no longer exists on disk; the lookup must
    # degrade to the literal path rather than to an empty prefix that matches
    # every agent.
    FAKE_AGENT_JSON="$(_agents_json \
        "/home/dev/somewhere-else|tab-other|idle" \
        "${WT_DIR}|tab-7|idle")"
    [ ! -e "$WT_DIR" ]
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    run cat "$FAKE_CLOSED_LOG"
    assert_output "tab-7"
}

# --- 2. non-idle is never closed (the decision that keeps work alive) ------

@test "close-impl-tab: agent_status=working is NEVER closed and prints nothing" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|working")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: agent_status=blocked is NEVER closed" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|blocked")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: an unknown future status is treated as not-idle" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|compacting")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: a null agent_status is treated as not-idle" {
    FAKE_AGENT_JSON="{\"result\":{\"agents\":[{\"cwd\":\"${WT_DIR}\",\"tab_id\":\"tab-7\"}]}}"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: no herdr call is made at all for a working tab beyond the list" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|working")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    run bash -c "grep -c 'herdr tab close' '$FAKE_CALL_LOG' || true"
    assert_output "0"
}

# --- 3. the silent skips --------------------------------------------------

@test "close-impl-tab: no local worktree for the merged branch → silent skip" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "feature/merged-elsewhere"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: an empty head branch → silent skip" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab ""
    assert_success
    [ -z "$output" ]
}

@test "close-impl-tab: herdr not installed → silent skip, rc=0" {
    local bin="${TEST_TEMP_HOME}/nobin"
    mkdir -p "$bin"
    local tool
    for tool in awk jq cut head; do
        ln -sf "$(command -v "$tool")" "$bin/$tool"
    done
    unset -f herdr
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"

    local old_path="$PATH"
    PATH="$bin"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    PATH="$old_path"
    assert_success
    [ -z "$output" ]
}

@test "close-impl-tab: herdr agent list fails → silent skip, nothing closed" {
    FAKE_AGENT_RC=1
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: an empty agent set → silent skip" {
    FAKE_AGENT_JSON='{"result":{"agents":[]}}'
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
}

@test "close-impl-tab: garbage from herdr agent list → silent skip" {
    FAKE_AGENT_JSON='not json at all'
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: agents exist but none sit on the worktree → silent skip" {
    FAKE_AGENT_JSON="$(_agents_json "/home/dev/somewhere-else|tab-9|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
}

# The gh-pr:merge Step 5 dispatch closes this tab first when it ran. Finding
# nothing is therefore the EXPECTED outcome of a healthy pipeline, not an error.
@test "close-impl-tab: a tab gh-pr:merge already closed is a quiet no-op" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    FAKE_AGENT_JSON='{"result":{"agents":[]}}'
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
}

# --- 4/5. abnormal states -------------------------------------------------

@test "close-impl-tab: two agents on one cwd → first wins, closed once" {
    FAKE_AGENT_JSON="$(_agents_json \
        "${WT_DIR}|tab-first|idle" \
        "${WT_DIR}|tab-second|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ "${#lines[@]}" -eq 1 ]
    assert_output --partial 'tab-first'
    refute_output --partial 'tab-second'
    run cat "$FAKE_CLOSED_LOG"
    assert_output "tab-first"
}

@test "close-impl-tab: a failing herdr tab close warns and never fails the merge" {
    FAKE_CLOSE_RC=1
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    assert_output --partial '[WARN] gh-pr:merge-train: herdr tab close tab-7 failed'
}

# --- 6. the anti-starvation regression gate -------------------------------
#
# The failure #1565 describes is not a missing [INFO] line: it is that
# `_iw_live_agents` counts a `wt/issue-*` worktree as running whenever a herdr
# agent sits on it, so merged-but-open tabs fill `_IW_MAX_PER_REPO` and
# issue-watcher stops dispatching. This drives N merges against a mutable
# registry and asserts the live count never grows — the pre-fix train left it
# pinned at N.

# Count the worktrees `_iw_live_agents` would call live: a `wt/issue-*`
# worktree with a herdr agent standing on it (same predicate, same jq shape).
_live_count() {
    printf '%s' "$FAKE_AGENT_JSON" |
        jq -r '[.result.agents[]? | (.cwd // empty)
               | select(test("/wt/issue-"))] | length'
}

# Drop the agent whose tab_id was just closed, the way a real herdr does.
_forget_closed_tab() {
    FAKE_AGENT_JSON=$(printf '%s' "$FAKE_AGENT_JSON" |
        jq -c --arg t "$1" '.result.agents |= map(select(.tab_id != $t))')
}

@test "close-impl-tab: the live worktree count does not grow across N merges" {
    local n=5 i specs=() wt_list="" counts=""

    for ((i = 1; i <= n; i++)); do
        wt_list+="worktree /home/dev/wt/issue-${i}
HEAD ${i}${i}${i}${i}
branch refs/heads/wt/issue-${i}/1

"
        specs+=("/home/dev/wt/issue-${i}|tab-${i}|idle")
    done
    FAKE_WORKTREE_LIST="$wt_list"
    FAKE_AGENT_JSON="$(_agents_json "${specs[@]}")"

    # Before the train runs, all N merged PRs are counted as live sessions —
    # this is the state that starved issue-watcher.
    [ "$(_live_count)" -eq "$n" ] || fail "expected ${n} live worktrees to start"

    local prev="$n" now
    for ((i = 1; i <= n; i++)); do
        run gh_pr_merge_train_close_impl_tab "wt/issue-${i}/1"
        assert_success
        assert_output --partial "closed implementation tab tab-${i}"
        _forget_closed_tab "tab-${i}"
        now="$(_live_count)"
        counts+="${now} "
        [ "$now" -le "$prev" ] \
            || fail "live count grew from ${prev} to ${now} at merge ${i}"
        prev="$now"
    done

    [ "$prev" -eq 0 ] || fail "after ${n} merges ${prev} tabs are still live (${counts})"
}

@test "close-impl-tab: a working tab keeps its slot — starvation is not traded for lost work" {
    # The counter-case to the test above: the count staying flat must come from
    # closing idle tabs, never from closing tabs that still have work in them.
    FAKE_WORKTREE_LIST="worktree /home/dev/wt/issue-1
HEAD aaaa
branch refs/heads/wt/issue-1/1

worktree /home/dev/wt/issue-2
HEAD bbbb
branch refs/heads/wt/issue-2/1
"
    FAKE_AGENT_JSON="$(_agents_json \
        "/home/dev/wt/issue-1|tab-1|idle" \
        "/home/dev/wt/issue-2|tab-2|working")"

    run gh_pr_merge_train_close_impl_tab "wt/issue-1/1"
    assert_success
    _forget_closed_tab "tab-1"

    run gh_pr_merge_train_close_impl_tab "wt/issue-2/1"
    assert_success
    [ -z "$output" ]

    [ "$(_live_count)" -eq 1 ] || fail "the working session must still be counted live"
    run cat "$FAKE_CLOSED_LOG"
    assert_output "tab-1"
}

# --- 7. shipped-block guards -----------------------------------------------

@test "close-impl-tab: the shipped block carries no inline match predicate (dEitY719/dotfiles#1569)" {
    # The unification's acceptance criterion: the cwd/foreground_cwd boundary
    # match exists in exactly one file (dotfiles' herdr_agent_lookup.sh), and
    # it is not this block.
    run bash -c "$(declare -f fence_block close_impl_tab_block); REPO_ROOT='${REPO_ROOT}'; close_impl_tab_block | grep -n -e 'def under(' -e 'startswith(' -e 'result.agents'"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "close-impl-tab: the extracted block is the step-7 close, not another fence" {
    run close_impl_tab_block
    assert_output --partial 'herdr_agent_tab_for_cwd'
    assert_output --partial 'herdr tab close "$PMT_TAB"'
}

@test "close-impl-tab: an unreadable lookup SSOT is a silent skip, not a fallback" {
    # NF-1: this runs after the merge, so a missing helper must cost nothing —
    # and it must NOT degrade to a hand-rolled match, which is what #1569
    # removed. Pointing DOTFILES_ROOT at an empty tree is the whole test.
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    DOTFILES_ROOT="${TEST_TEMP_HOME}/empty-root" run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}
