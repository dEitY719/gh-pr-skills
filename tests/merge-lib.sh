#!/bin/sh
# Offline regression guard for skills/merge/lib/{github-target,post-merge-housekeeping}.sh
# (#65). A stub `gh` and a fake shell-common record every call — no network.
# tests/plugin-root-tier5.sh §2-4 covers github-target.sh's tier-5 behaviour.
#
#   (a) github-target: one eval line binding GH_HOST / TARGET_REPO / TARGET_HOST
#   (b) github-target: a non-GitHub remote URL stops with empty stdout
#   (c) housekeeping: board Done for the PR and its closing issue, review-passed
#       dropped, one ai-metrics POST carrying the gh-pr-merge marker
#   (d) GH_DISABLE_AI_METRICS=1 posts nothing
#   (e) failing gh / failing label drop: one [WARN] each, exit 0
#   (f) no shell-common anywhere, bad arguments: warnings, exit 0
#
#   sh tests/merge-lib.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
L="$ROOT/skills/merge/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
fail=0
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }

mkdir -p "$TMP/bin" "$TMP/sc/functions"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_LOG"
[ "${GH_STUB_FAIL:-0}" = 1 ] && { echo 'gh: Server Error (HTTP 500)' >&2; exit 1; }
exit 0
EOF
chmod +x "$TMP/bin/gh"
cat > "$TMP/sc/functions/gh_project_status.sh" <<'EOF'
_gh_project_status_sync() { printf 'sync %s\n' "$*" >> "$CALL_LOG"; }
_gh_pr_closing_issue_numbers() { echo 5; }
EOF
cat > "$TMP/sc/functions/gh_pr_edit_safe.sh" <<'EOF'
_gh_pr_edit_safe_label() { :; }
_gh_pr_drop_label() {
    printf 'drop %s\n' "$*" >> "$CALL_LOG"
    [ "${DROP_FAIL:-0}" = 1 ] && { echo 'HTTP 403' >&2; return 1; }
    return 0
}
EOF

git init -q "$TMP/repo"
git -C "$TMP/repo" remote add origin https://github.com/own/repo.git
git -C "$TMP/repo" remote add other https://gitlab.example/x/y.git

# r <env...>: clean env, cwd in the scratch repo; $out (stdout), $err, $rc.
r() {
    : > "$TMP/gh.log"; : > "$TMP/call.log"
    set +e
    out=$(cd "$TMP/repo" && env -u SHELL_COMMON -u CLAUDE_PLUGIN_ROOT HOME=/nonexistent \
        DOTFILES_ROOT=/nonexistent PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" \
        CALL_LOG="$TMP/call.log" TARGET_HOST=github.com START_TS=0 "$@" 2>"$TMP/err")
    rc=$?
    set -e
    err=$(cat "$TMP/err")
}

# (a)
r CLAUDE_PLUGIN_ROOT="$ROOT" sh "$L/github-target.sh"
# shellcheck disable=SC2016  # expanded by the inner shell after the eval
got=$(sh -c 'eval "$1"; printf "%s|%s|%s" "$GH_HOST" "$TARGET_REPO" "$TARGET_HOST"' sh "$out")
[ "$rc:$got" = "0:github.com|own/repo|github.com" ] || bad "(a) rc=$rc bound: $got $err"

# (b)
r CLAUDE_PLUGIN_ROOT="$ROOT" sh "$L/github-target.sh" other
[ "$rc:$out" = 1: ] || bad "(b) non-GitHub remote: rc=$rc stdout=$out"

H="$L/post-merge-housekeeping.sh"
# (c)
r SHELL_COMMON="$TMP/sc" bash "$H" 9 o/r feat/x
[ "$rc" -eq 0 ] || bad "(c) rc=$rc"
[ "$(cat "$TMP/call.log")" = 'sync pr 9 Done --repo o/r
sync issue 5 Done --only-from Backlog,In progress,In review --repo o/r
drop 9 review-passed o/r github.com' ] || bad "(c) calls: $(cat "$TMP/call.log")"
grep -q '^api repos/o/r/issues/9/comments -X POST -f body=' "$TMP/gh.log" || bad "(c) no ai-metrics POST: $(cat "$TMP/gh.log")"
grep -q 'ai-metrics:gh-pr-merge' "$TMP/gh.log" || bad "(c) ai-metrics marker missing"
[ -z "$out" ] || bad "(c) clean run printed: $out"

# (d)
r SHELL_COMMON="$TMP/sc" GH_DISABLE_AI_METRICS=1 bash "$H" 9 o/r feat/x
[ ! -s "$TMP/gh.log" ] || bad "(d) GH_DISABLE_AI_METRICS=1 still called gh: $(cat "$TMP/gh.log")"

# (e)
r SHELL_COMMON="$TMP/sc" GH_STUB_FAIL=1 DROP_FAIL=1 bash "$H" 9 o/r feat/x
[ "$rc" -eq 0 ] || bad "(e) rc=$rc"
case "$out" in *'review-passed'*'HTTP 403'*) ;; *) bad "(e) no review-passed [WARN]: $out" ;; esac
case "$out" in *'[WARN] ai-metrics comment failed'*) ;; *) bad "(e) no ai-metrics [WARN]: $out" ;; esac

# (f)
r bash "$H" 9 o/r feat/x
[ "$rc" -eq 0 ] || bad "(f) no helper: rc=$rc"
case "$err" in *'board sync skipped'*) ;; *) bad "(f) no board warning: $err" ;; esac
case "$out" in *'review-passed NOT cleaned up'*) ;; *) bad "(f) no review-passed warning: $out" ;; esac
for args in "" "x o/r h" "9"; do
    # shellcheck disable=SC2086  # word-splitting the argument list is the point
    r SHELL_COMMON="$TMP/sc" bash "$H" $args
    case "$rc:$out" in '0:[WARN]'*skipped*) ;; *) bad "(f) '$args': rc=$rc $out" ;; esac
    if [ -s "$TMP/call.log" ] || [ -s "$TMP/gh.log" ]; then bad "(f) '$args' still called out"; fi
done

[ "$fail" -eq 0 ] && printf 'ok    merge lib: target eval line and URL refusal; housekeeping order, metrics opt-out, soft warnings, always exit 0\n'
exit "$fail"
