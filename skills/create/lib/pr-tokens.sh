#!/usr/bin/env bash
# gh-pr:create Step 4 — token estimate for the ai-metrics footer (#72).
#
#   TOKENS=$(TARGET_HOST=<host> GH_REPO=<owner/repo> \
#       bash skills/create/lib/pr-tokens.sh <ISSUE_NUMBER|""> <BASE_BRANCH>)
#
# stdout: ONE line, the token count. Input is (linked-issue body) +
# (`git log <base>..HEAD --format=%B` + `git diff <base>...HEAD`), never the
# drafted PR body `$BODY` (dEitY719/dotfiles#326). Formula: chars / 4, rounded
# to the nearest 500, floor 1000. A failed `gh issue view` warns on stderr and
# counts an empty issue body (soft-fail; the commit log alone usually clears
# the floor). Rationale and fixtures: references/metrics-helper.md.
# Guard: tests/create-lib.sh.

compute_pr_tokens() {
    local _issue_body="$1" _commit_log="$2"
    local _total _t
    _total=$((
        $(printf '%s' "$_issue_body" | wc -m) +
        $(printf '%s' "$_commit_log" | wc -m)
    ))
    _t=$(( (_total / 4 + 250) / 500 * 500 ))
    [ "$_t" -lt 1000 ] && _t=1000
    printf '%s\n' "$_t"
}

ISSUE_NUMBER="${1-}"
BASE_BRANCH="${2-}"
[ -n "$BASE_BRANCH" ] || {
    printf '[FAIL] pr-tokens.sh: usage: pr-tokens.sh <ISSUE_NUMBER|""> <BASE_BRANCH>\n' >&2
    exit 1
}

ISSUE_BODY=""
if [ -n "$ISSUE_NUMBER" ]; then
    # Host + repo both explicit (dEitY719/dotfiles#1403): a bare
    # `gh issue view <N>` follows gh's own repo default, and on a dual-host
    # login reads another server's #N — an empty body that under-reports.
    ISSUE_BODY=$(GH_HOST="$TARGET_HOST" gh issue view "$ISSUE_NUMBER" \
        --repo "$GH_REPO" --json body --jq '.body? // empty' 2>/dev/null) || {
        printf '[WARN] pr-tokens.sh: gh issue view #%s failed on %s/%s - counting an empty issue body\n' \
            "$ISSUE_NUMBER" "${TARGET_HOST:-unset}" "${GH_REPO:-unset}" >&2
        ISSUE_BODY=""
    }
fi
COMMIT_LOG=$( { git log "$BASE_BRANCH..HEAD" --format=%B; \
                git diff "$BASE_BRANCH...HEAD"; } 2>/dev/null )

compute_pr_tokens "$ISSUE_BODY" "$COMMIT_LOG"
