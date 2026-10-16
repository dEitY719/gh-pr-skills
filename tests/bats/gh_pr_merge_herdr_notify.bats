#!/usr/bin/env bats
# tests/bats/gh_pr_merge_herdr_notify.bats
# Verify the gh-pr:merge Step 4 herdr idle-tab hint: step 2 of the shipped
# skills/merge/lib/post-merge-housekeeping.sh (spec:
# skills/merge/references/herdr-tab-notify.sh.md), run through
# fixtures/gh_pr_merge_herdr_notify.sh. Moved from dEitY719/dotfiles
# tests/bats/skills/ by dEitY719/dotfiles#2200; the hand copy is gone.
#
# Cases drawn from dEitY719/dotfiles#1508's acceptance criteria:
#   1. local worktree + idle agent      -> one [INFO] line, label/tab/path filled
#   2. agent_status == "working"        -> no [INFO] line (F-4: silence)
#   3. no worktree on the merged branch -> empty output, rc=0
#   4. herdr not installed              -> empty output, rc=0
#   5. herdr agent list empty / no cwd match -> empty output, rc=0
#   6. two agents on the same cwd       -> first wins, printed once, no error
#   7. read-only (NF-2)                 -> the shipped block holds no
#                                         state-changing invocation
# The match predicate itself (cwd OR foreground_cwd, path boundary, physical
# path — dEitY719/dotfiles#1569) belongs to dotfiles'
# shell-common/functions/herdr_agent_lookup.sh and is tested there
# (tests/bats/functions/herdr_agent_lookup.bats); this suite runs the hint
# against fixtures/herdr_agent_lookup_stub.sh, an exact-match double.

load 'test_helper'

setup() {
    setup_isolated_home
    # shellcheck source=fixtures/gh_pr_merge_herdr_notify.sh
    source "${FIXTURES}/gh_pr_merge_herdr_notify.sh"
    herdr_notify_setup

    WT_DIR="/home/dev/wt/issue-1508"
    export WT_DIR

    # Shadow `git` so the fixture's `git worktree list --porcelain` reads a
    # fixed table instead of this repo's real worktrees. Function definitions
    # win over PATH lookups in the same shell, which is all the fixture uses.
    FAKE_WORKTREE_LIST="worktree /home/dev/dotfiles
HEAD 1111111111111111111111111111111111111111
branch refs/heads/main

worktree ${WT_DIR}
HEAD 2222222222222222222222222222222222222222
branch refs/heads/wt/issue-1508/1
"
    export FAKE_WORKTREE_LIST

    # Every stubbed subcommand is appended here, so NF-2 can be asserted on the
    # calls actually made rather than only on the source text (cf.
    # gh_pr_merge_board_gate.bats' FAKE_HELPER_LOG).
    FAKE_CALL_LOG="${TEST_TEMP_HOME}/calls.log"
    export FAKE_CALL_LOG
    : >"$FAKE_CALL_LOG"

    git() {
        printf 'git %s\n' "$*" >>"$FAKE_CALL_LOG"
        if [ "$1" = "worktree" ] && [ "$2" = "list" ]; then
            printf '%s' "${FAKE_WORKTREE_LIST-}"
            return 0
        fi
        command git "$@"
    }

    # Shadow `herdr` with the two read-only enumerations the fixture calls.
    # FAKE_AGENT_RC lets a test simulate a dead local herdr server.
    herdr() {
        printf 'herdr %s\n' "$*" >>"$FAKE_CALL_LOG"
        if [ "$1" = "agent" ] && [ "$2" = "list" ]; then
            [ "${FAKE_AGENT_RC:-0}" -eq 0 ] || return "$FAKE_AGENT_RC"
            printf '%s' "${FAKE_AGENT_JSON-}"
            return 0
        fi
        if [ "$1" = "workspace" ] && [ "$2" = "list" ]; then
            printf '%s' "${FAKE_WORKSPACE_JSON-}"
            return 0
        fi
        return 1
    }

    FAKE_WORKSPACE_JSON='{"result":{"workspaces":[
        {"workspace_id":"ws-1","label":"dotfiles"},
        {"workspace_id":"ws-2","label":"other"}
    ]}}'
    export FAKE_WORKSPACE_JSON
}

teardown() {
    teardown_isolated_home
    unset -f git herdr 2>/dev/null || true
    unset WT_DIR FAKE_WORKTREE_LIST FAKE_AGENT_JSON FAKE_WORKSPACE_JSON FAKE_AGENT_RC FAKE_CALL_LOG
}

# Build an agent-list JSON payload from one or more `cwd|tab_id|status|ws_id`
# specs, so each test states only the fields it cares about.
_agents_json() {
    local spec sep="" out='{"result":{"agents":['
    local cwd tab st ws
    for spec in "$@"; do
        IFS='|' read -r cwd tab st ws <<<"$spec"
        out+="${sep}{\"cwd\":\"${cwd}\",\"tab_id\":\"${tab}\",\"agent_status\":\"${st}\",\"workspace_id\":\"${ws}\"}"
        sep=","
    done
    printf '%s]}}' "$out"
}

# Same, but `cwd` and `foreground_cwd` are set independently:
# `cwd|foreground_cwd|tab_id|status|ws_id`. `cwd` is where the pane was opened,
# `foreground_cwd` where its shell stands now — they diverge the moment the
# session `cd`s, which before #1569 made this hint lose the tab entirely.
_agents_json_fg() {
    local spec sep="" out='{"result":{"agents":['
    local cwd fg tab st ws
    for spec in "$@"; do
        IFS='|' read -r cwd fg tab st ws <<<"$spec"
        out+="${sep}{\"cwd\":\"${cwd}\",\"foreground_cwd\":\"${fg}\",\"tab_id\":\"${tab}\",\"agent_status\":\"${st}\",\"workspace_id\":\"${ws}\"}"
        sep=","
    done
    printf '%s]}}' "$out"
}

@test "herdr-notify: idle agent on the merged branch's worktree → one [INFO] hint" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle|ws-1")"
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    assert_output --partial '[INFO] herdr tab dotfiles/tab-7 is idle'
    assert_output --partial "(${WT_DIR})"
    assert_output --partial 'session:worktree-teardown'
    # Exactly one line — this step is a single informational line, never a block.
    [ "${#lines[@]}" -eq 1 ]
}

@test "herdr-notify: unlabeled/unknown workspace falls back to the raw workspace id" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle|ws-missing")"
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    assert_output --partial '[INFO] herdr tab ws-missing/tab-7 is idle'
}

@test "herdr-notify: workspace record exists with a JSON null label → falls back to raw id, not the string 'null'" {
    # `jq -r '.label'` on a null value prints the literal text "null", which
    # is neither unset nor empty — so `${WS_LABEL:-$WS_ID}` alone would not
    # catch it. The `// empty` in the jq filter is what makes the fallback
    # actually fire here. Workspace id deliberately avoids containing "null"
    # itself, so the assertion below isn't a false negative on the raw id.
    FAKE_WORKSPACE_JSON='{"result":{"workspaces":[{"workspace_id":"ws-3","label":null}]}}'
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle|ws-3")"
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    assert_output --partial '[INFO] herdr tab ws-3/tab-7 is idle'
    refute_output --partial 'null/tab-7'
}

# --- dEitY719/dotfiles#1569: the hint sources the shared lookup -----------
#
# The predicate cases (subdir cd, foreground_cwd, path boundary, prefix
# sibling) test the SSOT itself and stayed with it in dotfiles. What stays here
# is what the hint owns: it hands the lookup the PHYSICAL path, prints the
# spelling `git worktree list` reported, and degrades to silence when the
# lookup is unreadable.

@test "herdr-notify (#1569): a symlinked worktree path still resolves to the agent" {
    # `git worktree list` answers the path as it was created; herdr answers
    # where the pane really stands. One symlinked component made the old
    # string compare miss it entirely.
    local real="${TEST_TEMP_HOME}/real/wt-issue-1508"
    local link="${TEST_TEMP_HOME}/link-wt"
    mkdir -p "$real"
    ln -sfn "$real" "$link"

    FAKE_WORKTREE_LIST="worktree ${link}
HEAD cccc
branch refs/heads/wt/issue-1508/1
"
    FAKE_AGENT_JSON="$(_agents_json "$(cd -P "$real" && pwd -P)|tab-7|idle|ws-1")"
    [ "$link" != "$real" ]

    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    assert_output --partial 'herdr tab dotfiles/tab-7 is idle'
    # The path in the hint is the one the human will recognise — the spelling
    # `git worktree list` reported, not its resolved twin.
    assert_output --partial "(${link})"
}

@test "herdr-notify (#1569): an unreadable lookup SSOT is a silent skip" {
    # NF-1: the hint degrades to silence, never to a hand-rolled copy of the
    # predicate — the duplication #1569 removed.
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle|ws-1")"
    DOTFILES_ROOT="${TEST_TEMP_HOME}/empty-root" run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    [ -z "$output" ]
}

@test "herdr-notify: agent_status=working → no hint at all (F-4)" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|working|ws-1")"
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    # Empty output is the stronger assertion — it subsumes "no [INFO] line".
    [ -z "$output" ]
}

@test "herdr-notify: agent_status=blocked → no hint (any non-idle is silent)" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|blocked|ws-1")"
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    [ -z "$output" ]
}

@test "herdr-notify: no local worktree for the merged branch → silent skip" {
    # The usual case when the PR was implemented on another machine.
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle|ws-1")"
    run gh_pr_merge_herdr_notify "feature/merged-elsewhere"
    assert_success
    [ -z "$output" ]
}

@test "herdr-notify: empty HEAD_REF → silent skip" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle|ws-1")"
    run gh_pr_merge_herdr_notify ""
    assert_success
    [ -z "$output" ]
}

@test "herdr-notify: herdr not installed → silent skip, rc=0" {
    # `herdr` is a real binary on some dev machines, so removing the shell
    # function is not enough — PATH is narrowed to a dir holding only the
    # externals the script actually needs (awk/jq/cut/head/date).
    local bin="${TEST_TEMP_HOME}/nobin"
    mkdir -p "$bin"
    local tool
    for tool in awk jq cut head date; do
        ln -sf "$(command -v "$tool")" "$bin/$tool"
    done
    unset -f herdr
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle|ws-1")"

    local old_path="$PATH"
    PATH="$bin"
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    PATH="$old_path"
    assert_success
    [ -z "$output" ]
}

@test "herdr-notify: herdr agent list returns an empty agent set → silent skip" {
    FAKE_AGENT_JSON='{"result":{"agents":[]}}'
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    [ -z "$output" ]
}

@test "herdr-notify: agents exist but none match the worktree cwd → silent skip" {
    FAKE_AGENT_JSON="$(_agents_json "/home/dev/somewhere-else|tab-9|idle|ws-1")"
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    [ -z "$output" ]
}

@test "herdr-notify: herdr agent list fails → silent skip, merge report unaffected" {
    FAKE_AGENT_RC=1
    export FAKE_AGENT_RC
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle|ws-1")"
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    [ -z "$output" ]
}

@test "herdr-notify: herdr agent list emits non-JSON garbage → silent skip" {
    FAKE_AGENT_JSON='not json at all'
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    [ -z "$output" ]
}

@test "herdr-notify: two agents on the same cwd → first wins, printed once" {
    # Abnormal state; documented behavior is take-the-first, ignore the rest,
    # no warning and no double-print.
    FAKE_AGENT_JSON="$(_agents_json \
        "${WT_DIR}|tab-first|idle|ws-1" \
        "${WT_DIR}|tab-second|working|ws-2")"
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    [ "${#lines[@]}" -eq 1 ]
    assert_output --partial 'herdr tab dotfiles/tab-first is idle'
    refute_output --partial 'tab-second'
}

# --- NF-2: read-only verification -----------------------------------------

# `tab close` / `worktree remove` legitimately appear once in the block,
# inside the F-3 printf's advisory text (a command suggested to a human, never
# executed) — that line is excluded and nothing else may match.
@test "herdr-notify (NF-2): the shipped block contains no state-changing invocation" {
    run bash -c "$(declare -f herdr_notify_block); herdr_notify_block | grep -n -e 'tab close' -e 'worktree remove' | grep -v printf"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "herdr-notify (NF-2): every herdr/git call in the shipped block is a read-only list" {
    # Comment lines are dropped (the rationale legitimately says things like
    # "herdr could not be asked"), and so is the F-3 printf's advisory text.
    # The lookup SSOT's own enumeration is guarded in dotfiles
    # (tests/bats/functions/herdr_agent_lookup_readonly.bats).
    run bash -c "$(declare -f herdr_notify_block); herdr_notify_block | grep -v '^[[:space:]]*#' | grep -v printf | grep -oE 'herdr [a-z]+ [a-z]+' | sort -u"
    assert_output 'herdr workspace list'
    run bash -c "$(declare -f herdr_notify_block); herdr_notify_block | grep -v '^[[:space:]]*#' | grep -oE 'git [a-z]+ [a-z]+' | sort -u"
    assert_output 'git worktree list'
}

@test "herdr-notify (NF-2): a full idle run invokes only read-only subcommands" {
    # Runtime counterpart to the two static greps above: whatever the source
    # text looks like, every call this step actually made must be an
    # enumeration — a mutating call built through indirection would show up
    # here even though it matches no literal grep.
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle|ws-1")"
    run gh_pr_merge_herdr_notify "wt/issue-1508/1"
    assert_success
    run bash -c "cut -d' ' -f1-3 '$FAKE_CALL_LOG' | sort -u"
    assert_output 'git worktree list
herdr agent list
herdr workspace list'
}
