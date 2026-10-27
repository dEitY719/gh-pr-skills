#!/bin/sh
# gh-pr:merge Step 5 — post-merge verification gate and dispatch.
#
#   sh lib/post-merge-verify-dispatch.sh <pr> <owner/repo> <head> <base> <remote> [--no-post-verify]
#
# Contract (skills/merge/references/post-merge-verify.md):
#   - always exits 0 — the merge already happened and nothing here may undo it
#   - with a 6th argument `--no-post-verify`, one skip line and no dispatch: the
#     caller owns verification (#90) — printed even for an unregistered repo;
#     any other 6th argument is one [WARN], then the usual path
#   - one [WARN] and no dispatch when an argument is blank, whitespace-only, or
#     still an unsubstituted <placeholder>
#   - complete silence when the repo is absent from the issue-watcher registry
#   - one [FAIL] when the repo IS registered but the dispatch will not stage or
#     will not source: that is a broken install, not an opt-out
#
# Regression guard: tests/pmv-dispatch-resolves.sh

# --- 0. Caller opt-out (#90) -----------------------------------------------
# gh-flow:wave's coordinator runs gh-verify:merged itself, so a dispatch here
# would verify the same PR twice and open a tab nobody asked for.
case "${6-}" in
    '') ;;
    --no-post-verify)
        printf 'post-merge verify skipped (caller owns verification)\n'
        exit 0 ;;
    # A typo'd opt-out must not be silent; dispatching stays the safe default.
    *) printf '[WARN] gh-pr:merge: unrecognised 6th argument %s ignored (only --no-post-verify is accepted) — dispatching as usual.\n' "$6" ;;
esac

# --- 1. Validate the five inputs -------------------------------------------
# A blank, whitespace-only or still-unsubstituted argument passes `[ -n ]` and
# is then indistinguishable from an unwatched repo at the registry lookup —
# the silent half-bound run of dEitY719/dotfiles#1576 (PR dEitY719/dotfiles#1603
# review, agy + codex). Name every offender instead; the dispatch closes tabs
# and rebases main.
PMV_MISSING=""
_pmv_need() {
    case "$2" in
    # Any angle bracket at all, not just a well-formed `<foo>`: a half-typed
    # `<owner/repo` is just as unsubstituted, and no PR number, slug, branch or
    # remote name this skill produces contains one (PR #33 review, agy).
    '' | *'<'* | *'>'*) PMV_MISSING="${PMV_MISSING:+$PMV_MISSING, }$1" ;;
    # `[![:space:]]`, not `[!" "]`: a tab- or newline-only argument contains a
    # non-SPACE character and so passed the old test as "bound", which is the
    # same silent half-bound dispatch the space case exists to stop (PR #33
    # review, codex BLOCKER; agy FOLLOW-UP).
    *[![:space:]]*) ;;
    *) PMV_MISSING="${PMV_MISSING:+$PMV_MISSING, }$1" ;;
    esac
}
_pmv_need PR_NUMBER "${1-}"
_pmv_need TARGET_REPO "${2-}"
_pmv_need HEAD_BRANCH "${3-}"
_pmv_need BASE_BRANCH "${4-}"
_pmv_need REMOTE "${5-}"
if [ -n "$PMV_MISSING" ]; then
    printf '[WARN] gh-pr:merge: post-merge verification gate has unbound values (%s) — pass all five arguments (no placeholders, no blanks) and re-run.\n' \
        "$PMV_MISSING"
    exit 0
fi

# The dispatch block is sourced, not executed: it reads these by name.
# shellcheck disable=SC2034
PR_NUMBER=$1
TARGET_REPO=$2
# shellcheck disable=SC2034
HEAD_BRANCH=$3
# shellcheck disable=SC2034
BASE_BRANCH=$4
# shellcheck disable=SC2034
REMOTE=$5

# --- 2. Registry gate ------------------------------------------------------
# Empty VERIFY_SKILL with all five values bound — repo not registered, no
# registry, no jq, or `post_merge_verify` false/absent — means do nothing at
# all: no output, no dispatch, and no [WARN] either. An unwatched repo stays
# byte-identical to how it behaved before dEitY719/dotfiles#1511.
#
# Schema (dEitY719/gh-verify-skills#93): `post_merge_verify` (JSON bool, absent
# = false) is the switch, `post_merge_verify_skill` picks the skill (default
# gh-verify:merged). `has()`, not `//`: `false // x` would read an explicit
# false as missing. An entry with no `post_merge_verify` but the retired
# `verify_skill` still dispatches that value — tagged `legacy ` so the one
# migration [WARN] below can fire. Remove the fallback once every registry is
# migrated (follow-up of #93).
WATCHED_FILE="${IW_WATCHED_REPOS:-${HOME}/.avatars/issue-watcher/watched-repos.json}"
VERIFY_SKILL=""
if command -v jq >/dev/null 2>&1 && [ -r "$WATCHED_FILE" ]; then
    VERIFY_SKILL=$(jq -r --arg r "$TARGET_REPO" \
        '(if type == "array" then . else (.repos // []) end) | .[] | select(.repo == $r)
         | if has("post_merge_verify") then
               (if .post_merge_verify == true then (.post_merge_verify_skill // "gh-verify:merged") else empty end)
           elif (.verify_skill // "") != "" then "legacy " + (.verify_skill | tostring)
           else empty end' \
        "$WATCHED_FILE" 2>/dev/null)
fi
[ -n "$VERIFY_SKILL" ] || exit 0
case "$VERIFY_SKILL" in
legacy\ *)
    VERIFY_SKILL=${VERIFY_SKILL#legacy }
    printf '[WARN] gh-pr:merge: %s uses the retired registry key verify_skill in %s — dispatching it as post_merge_verify: true, post_merge_verify_skill: "%s". Migrate the entry (avatar-watched-repos) (dEitY719/gh-verify-skills#93).\n' \
        "$TARGET_REPO" "$WATCHED_FILE" "$VERIFY_SKILL"
    # The sourced dispatch reads the same entry; this keeps it to ONE [WARN].
    # shellcheck disable=SC2034
    PMV_LEGACY_WARNED=1 ;;
esac

# --- 3. Stage the dispatch from its SSOT and source it ---------------------
# Two tiers as everywhere here: GH_VERIFY_ROOT's live gh-verify checkout, else
# the copy vendored under this plugin. No cwd tier — gh-pr:merge runs inside
# the PR checkout under review (harness-skills#22).
PMV_BLOCK="${GH_VERIFY_ROOT:+$GH_VERIFY_ROOT/skills/post-merge-verify/references/dispatch.sh.md}"
[ -r "$PMV_BLOCK" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] ||
    PMV_BLOCK="$CLAUDE_PLUGIN_ROOT/lib/vendor/gh-verify/post-merge-verify/dispatch.sh.md"

# Only the FIRST bash fence is taken — the file's later snippets are
# documentation, not steps.
PMV_FENCE='```'
PMV_OK=""
# `mktemp` with no template is a GNU extension; BSD/macOS needs -t.
if [ -r "$PMV_BLOCK" ] && PMV_SH=$(mktemp 2>/dev/null || mktemp -t pmv); then
    # The staged file must not outlive this run: the sourced dispatch returns
    # early on most paths and can exit outright, so cleanup is armed first and
    # cleared on success.
    trap 'rm -f "$PMV_SH"' EXIT INT TERM
    awk -v f="$PMV_FENCE" \
        '$0 == f "bash" && !b { b = 1; next } $0 == f && b { exit } b' \
        "$PMV_BLOCK" >"$PMV_SH"
    # An empty extraction is the same bug masked (right file, wrong fence) and
    # an unparseable body a third — PMV_OK is earned, never assumed. It is
    # earned by STAGING, though, not by the dispatch's own exit status: PMV_OK
    # gates the "[FAIL] broken install" line below, and a dispatch that ran but
    # returned nonzero for its own reasons is the opposite of a broken install
    # (PR #33 review, agy BLOCKER). `sh -n` is what separates the two — a body
    # that will not parse is the "would not source" case the [FAIL] means; a
    # body that parses will source, whatever it then returns.
    #
    # Sourced in a SUBSHELL: the dispatch block is written to be sourced by
    # Step 5 itself and calls `exit` on several of its own early-return paths.
    # Sourced flat, that `exit` terminates THIS wrapper — nonzero, past the
    # `exit 0` below — breaking the "always exits 0" contract at the one moment
    # it matters, after the merge has already landed (PR #33 review, codex
    # BLOCKER). A subshell inherits every PR_NUMBER/TARGET_REPO/... value the
    # block reads by name, and the block's side effects are all external (gh
    # calls), so nothing is lost by containing it.
    if [ -s "$PMV_SH" ] && sh -n "$PMV_SH" 2>/dev/null; then
        PMV_OK=1
        # shellcheck source=/dev/null
        ( . "$PMV_SH" ) || printf '[WARN] gh-pr:merge: post-merge verification dispatched for %s but returned nonzero. The gate is soft-fail and the merge already landed, so nothing was undone; re-run /gh-verify:post-merge-verify %s by hand if the housekeeping matters.\n' \
            "$TARGET_REPO" "$PR_NUMBER"
    fi
    rm -f "$PMV_SH"
    trap - EXIT INT TERM
fi

# A registered repo that cannot stage or run the dispatch is a broken install,
# not an opt-out: loud, never the silent unregistered skip.
[ -n "$PMV_OK" ] || printf '[FAIL] gh-pr:merge: post-merge verification did NOT run for %s (registered) — %s did not stage or would not source. Broken install, not an opt-out: repair the gh-pr plugin or point GH_VERIFY_ROOT at a gh-verify checkout, then run /gh-verify:post-merge-verify %s by hand.\n' \
    "$TARGET_REPO" "$PMV_BLOCK" "$PR_NUMBER"
exit 0
