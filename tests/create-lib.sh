#!/bin/sh
# Offline regression guard for skills/create/lib/*.sh (#65). Scratch git repos
# (one with a bare "remote"), a stub `gh`, the scripts' own FAKE_* seams and a
# fake shell-common stand in for the network.
#
#   github-target.sh      eval line binds GH_REPO; tier 5 leaves stdout empty
#   stacked-pr.sh         rc contract 0/2/3/4/5/6 and the eval line
#   branch-state.sh       push-action rows; dispatch on/off the base branch
#   lint-guard.sh         bypass passes, broken install / no base stops
#   project-board-sync.sh hook auto-skip, call shape, soft skip
#   pr-tokens.sh          floor 1000, round to 500, no-issue, gh soft-fail
#
#   sh tests/create-lib.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
L="$ROOT/skills/create/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
fail=0
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }

mkdir -p "$TMP/bin" "$TMP/sc/functions" "$TMP/home"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${GH_LOG:-/dev/null}"
case "$*" in
    "repo view"*) echo main ;;
    "issue view"*) [ -z "${GH_FAIL-}" ] || exit 1; printf '%s\n' "${FAKE_ISSUE_BODY-}" ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"
cat > "$TMP/sc/functions/gh_project_status.sh" <<'EOF'
_gh_project_status_sync() { printf 'sync %s\n' "$*" >> "$SYNC_LOG"; }
_gh_pr_closing_issue_numbers() { echo 5; }
EOF

G() { git -C "$TMP/w" "$@"; }
git init -q --bare "$TMP/remote.git"
git init -q -b main "$TMP/w"
G config user.email t@t; G config user.name t
G remote add origin "$TMP/remote.git"
G commit -q --allow-empty -m init
G push -q origin main 2>/dev/null

# r <env...>: run in the work repo with a clean env; $out (stdout), $err, $rc.
r() {
    set +e
    out=$(cd "$TMP/w" && env -u SHELL_COMMON -u CLAUDE_PLUGIN_ROOT HOME="$TMP/home" \
        DOTFILES_ROOT=/nonexistent PATH="$TMP/bin:$PATH" TARGET_HOST=github.com \
        GH_REPO=o/r REMOTE=origin SYNC_LOG="$TMP/sync.log" "$@" 2>"$TMP/err")
    rc=$?
    set -e
    err=$(cat "$TMP/err")
}

# --- github-target.sh ---------------------------------------------------------
G remote add gh git@github.com:own/repo.git
r CLAUDE_PLUGIN_ROOT="$ROOT" sh "$L/github-target.sh" gh
# shellcheck disable=SC2016  # expanded by the inner shell after the eval
got=$(sh -c 'eval "$1"; printf "%s|%s|%s|%s" "$GH_HOST" "$GH_REPO" "$TARGET_HOST" "$REMOTE"' sh "$out")
[ "$rc:$got" = "0:github.com|own/repo|github.com|gh" ] || bad "github-target bound: rc=$rc $got $err"
r sh "$L/github-target.sh" gh
[ "$rc:$out" = 1: ] || bad "github-target tier 5: rc=$rc stdout=$out"

# --- stacked-pr.sh --------------------------------------------------------------
# shellcheck disable=SC2016  # expanded by the inner shell after the eval
ev() { sh -c 'eval "$1"; printf "%s|%s|%s" "$BASE_BRANCH" "$PARENT_PR" "$ISSUE_NUMBER"' sh "$out"; }
r bash "$L/stacked-pr.sh" 65 gh --no-stack
[ "$rc:$(ev)" = "0:main||65" ] || bad "stacked --no-stack: rc=$rc $(ev) $err"
r bash "$L/stacked-pr.sh" --base rel/v2
[ "$rc:$(ev)" = "0:rel/v2||" ] || bad "stacked --base: rc=$rc $(ev)"
r bash "$L/stacked-pr.sh" --no-stack --base x
[ "$rc:$out" = 2: ] || bad "stacked both flags: rc=$rc"
r bash "$L/stacked-pr.sh" --base
[ "$rc:$out" = 3: ] || bad "stacked bare --base: rc=$rc"
r bash "$L/stacked-pr.sh"
[ "$rc:$(ev)" = "0:main||" ] || bad "stacked solo repo: rc=$rc $(ev)"
printf 'We use stacked PR here.\n' > "$TMP/w/CLAUDE.md"
set -- FAKE_ANCESTOR_REFS="origin/feat/a origin/feat/b" FAKE_NONDEFAULT_REFS="origin/feat/a origin/feat/b"
r "$@" FAKE_OPEN_PRS="12 feat/a" FAKE_PARENT_STATE=OPEN FAKE_PARENT_BODY='' bash "$L/stacked-pr.sh"
[ "$rc:$(ev)" = "0:feat/a|12|" ] || bad "stacked 1 candidate: rc=$rc $(ev) $err"
case "$err" in *'Stacking on PR #12'*) ;; *) bad "stacked: notice not on stderr: $err" ;; esac
r "$@" FAKE_OPEN_PRS="12 feat/a" FAKE_PARENT_STATE=MERGED bash "$L/stacked-pr.sh"
[ "$rc:$out" = 5: ] || bad "stacked parent not open: rc=$rc"
r "$@" FAKE_OPEN_PRS="12 feat/a" FAKE_PARENT_STATE=OPEN FAKE_PARENT_BODY='Depends on #3' bash "$L/stacked-pr.sh"
[ "$rc:$out" = 6: ] || bad "stacked multi-stack: rc=$rc"
r "$@" FAKE_OPEN_PRS="12 feat/a
13 feat/b" bash "$L/stacked-pr.sh"
[ "$rc:$out" = 4: ] || bad "stacked ambiguous: rc=$rc"
rm "$TMP/w/CLAUDE.md"

# --- branch-state.sh ------------------------------------------------------------
pa() { bash "$L/branch-state.sh" push-action "$@"; }
[ "$(pa f '' '')" = 'push -u origin HEAD' ] || bad "push-action: no upstream"
[ "$(pa f refs/remotes/origin/main '' up)" = 'push -u up HEAD' ] || bad "push-action: mispaired"
[ "$(pa f refs/remotes/origin/f diverged)" = STOP ] || bad "push-action: diverged"
[ "$(pa f refs/remotes/origin/f '')" = push ] || bad "push-action: plain"
r env BASE_BRANCH=main ISSUE_NUMBER=65 bash "$L/branch-state.sh" dispatch
[ "$rc:$out" = "0:BRANCH_STATE=nothing-to-pr" ] || bad "dispatch nothing-to-pr: rc=$rc $out"
G commit -q --allow-empty -m 'feat(x): 한글 제목'
G branch -q feat/issue-65
r env BASE_BRANCH=main ISSUE_NUMBER=65 bash "$L/branch-state.sh" dispatch
if [ "$rc" -ne 1 ] || [ "$(G rev-parse main)" = "$(G rev-parse origin/main)" ]; then
    bad "dispatch existing branch: rc=$rc, base must not be rewound"
fi
G branch -q -D feat/issue-65
r env BASE_BRANCH=main ISSUE_NUMBER=65 bash "$L/branch-state.sh" dispatch
case "$rc:$out" in 0:*"Local 'main' rewound"*BRANCH_STATE=auto-branch-and-rewind) ;; *) bad "dispatch auto-branch: rc=$rc $out" ;; esac
[ "$(G rev-parse --abbrev-ref HEAD)" = feat/issue-65 ] || bad "dispatch did not switch branch"
[ "$(G rev-parse main)" = "$(G rev-parse origin/main)" ] || bad "dispatch did not rewind main"
r env BASE_BRANCH=main bash "$L/branch-state.sh" dispatch
[ "$rc:$out" = "0:BRANCH_STATE=not-on-base" ] || bad "dispatch not-on-base: rc=$rc $out"

# --- lint-guard.sh --------------------------------------------------------------
r CLAUDE_PLUGIN_ROOT="$ROOT" GH_PR_LINT_BYPASS=1 bash "$L/lint-guard.sh" main
[ "$rc" -eq 0 ] || bad "lint-guard bypass: rc=$rc $err"
r bash "$L/lint-guard.sh" main
case "$rc:$err" in 1:*'/nonexistent/shell-common'*) ;; *) bad "lint-guard tier 5: rc=$rc $err" ;; esac
r CLAUDE_PLUGIN_ROOT="$ROOT" bash "$L/lint-guard.sh"
[ "$rc" -eq 1 ] || bad "lint-guard without a base: rc=$rc"

# --- project-board-sync.sh ------------------------------------------------------
: > "$TMP/sync.log"
r SHELL_COMMON="$TMP/sc" bash "$L/project-board-sync.sh" 9
[ "$rc" -eq 0 ] || bad "board sync rc=$rc $err"
[ "$(cat "$TMP/sync.log")" = 'sync pr 9 In review --repo o/r
sync issue 5 In progress --only-from Backlog,Ready,In review' ] || bad "board sync calls: $(cat "$TMP/sync.log")"
: > "$TMP/sync.log"
r bash "$L/project-board-sync.sh" 9
case "$rc:$err" in 0:*'board sync skipped'*) ;; *) bad "board sync soft skip: rc=$rc $err" ;; esac
mkdir -p "$TMP/home/.claude/hooks"
printf '#!/bin/sh\n' > "$TMP/home/.claude/hooks/post-gh-pr-create.sh"
chmod +x "$TMP/home/.claude/hooks/post-gh-pr-create.sh"
r SHELL_COMMON="$TMP/sc" bash "$L/project-board-sync.sh" 9
case "$rc:$err" in 0:*'delegated to PostToolUse hook'*) ;; *) bad "board sync hook skip: rc=$rc $err" ;; esac
[ ! -s "$TMP/sync.log" ] || bad "board sync ran despite the hook"

# --- pr-tokens.sh ---------------------------------------------------------------
# The work repo is on feat/issue-65, one empty commit over main: a log of a few
# dozen chars, so the issue body decides the count.
: > "$TMP/gh.log"
r GH_LOG="$TMP/gh.log" bash "$L/pr-tokens.sh" "" main
[ "$rc:$out" = 0:1000 ] || bad "pr-tokens floor, no issue: rc=$rc out=$out $err"
[ ! -s "$TMP/gh.log" ] || bad "pr-tokens called gh without an issue: $(cat "$TMP/gh.log")"
big=$(printf '%7000s' '' | tr ' ' x)
r GH_LOG="$TMP/gh.log" FAKE_ISSUE_BODY="$big" bash "$L/pr-tokens.sh" 72 main
[ "$rc:$out" = 0:2000 ] || bad "pr-tokens round to 500 (~7000 chars -> 2000): rc=$rc out=$out $err"
grep -q '^issue view 72 --repo o/r ' "$TMP/gh.log" || bad "pr-tokens gh call shape: $(cat "$TMP/gh.log")"
r GH_FAIL=1 FAKE_ISSUE_BODY="$big" bash "$L/pr-tokens.sh" 72 main
case "$rc:$out:$err" in 0:1000:*'[WARN]'*) ;; *) bad "pr-tokens gh soft-fail: rc=$rc out=$out $err" ;; esac
r bash "$L/pr-tokens.sh" 72
[ "$rc:$out" = 1: ] || bad "pr-tokens without a base: rc=$rc out=$out"

[ "$fail" -eq 0 ] && printf 'ok    create lib: target eval line, stacked rc contract 0/2-6, push policy rows, base-branch dispatch, lint guard, board sync shape and skips, pr token floor/rounding/soft-fail\n'
exit "$fail"
