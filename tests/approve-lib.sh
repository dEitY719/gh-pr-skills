#!/bin/sh
# Offline regression guard for skills/approve/lib/board-approved-sync.sh (#65).
# A stub `gh` on PATH logs every call and fails on demand, and a fake
# shell-common records exactly what the helper was asked to do — no network.
#
#   (a) the plain path asks for Approved with the --only-from guard, no bypass
#   (b) --self-record adds the one-call #393 bypass and says so on stderr
#   (c) bad arguments / unset target: exit 0, one warning, no gh call
#   (d) no shell-common anywhere: warn naming the tier-1 path, exit 0
#   (e) the real vendored helper with a failing gh still exits 0
#
#   sh tests/approve-lib.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
S="$ROOT/skills/approve/lib/board-approved-sync.sh"
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
_gh_project_status_sync() {
    printf 'args=%s bypass=%s host=%s\n' "$*" "${_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS-}" "$GH_HOST" >> "$SYNC_LOG"
}
EOF

# run <env...> -- clean env, cwd outside any checkout; $out (2>&1), $rc.
run() {
    : > "$TMP/gh.log"; : > "$TMP/sync.log"
    set +e
    out=$(cd "$TMP" && env -u SHELL_COMMON -u CLAUDE_PLUGIN_ROOT HOME=/nonexistent \
        PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" SYNC_LOG="$TMP/sync.log" \
        TARGET_HOST=ghe.example TARGET_REPO=o/r "$@" 2>&1)
    rc=$?
    set -e
}

# (a)
run SHELL_COMMON="$TMP/sc" bash "$S" 7
[ "$rc" -eq 0 ] || bad "(a) rc=$rc"
[ "$(cat "$TMP/sync.log")" = 'args=pr 7 Approved --only-from Backlog,In progress,In review --repo o/r bypass= host=ghe.example' ] ||
    bad "(a) wrong helper call: $(cat "$TMP/sync.log")"

# (b)
run SHELL_COMMON="$TMP/sc" bash "$S" 7 --self-record
[ "$rc" -eq 0 ] || bad "(b) rc=$rc"
grep -q 'bypass=1' "$TMP/sync.log" || bad "(b) --self-record did not set the bypass: $(cat "$TMP/sync.log")"
case "$out" in *'self-record: bypassing #393'*) ;; *) bad "(b) no bypass notice: $out" ;; esac

# (c)
for args in "" "x" "7 --bogus"; do
    # shellcheck disable=SC2086  # word-splitting the argument list is the point
    run SHELL_COMMON="$TMP/sc" bash "$S" $args
    [ "$rc" -eq 0 ] || bad "(c) '$args' rc=$rc"
    case "$out" in '[gh-pr-approve]'*skipped*) ;; *) bad "(c) '$args' no warning: $out" ;; esac
    if [ -s "$TMP/sync.log" ] || [ -s "$TMP/gh.log" ]; then bad "(c) '$args' still called out"; fi
done
run SHELL_COMMON="$TMP/sc" env -u TARGET_REPO bash "$S" 7
case "$rc:$out" in 0:*'TARGET_REPO'*) ;; *) bad "(c) unset TARGET_REPO: rc=$rc $out" ;; esac

# (d)
run bash "$S" 7
[ "$rc" -eq 0 ] || bad "(d) rc=$rc"
case "$out" in *'no usable shell-common at /nonexistent/dotfiles/shell-common/'*) ;; *) bad "(d) no tier-1 warning: $out" ;; esac

# (e)
run CLAUDE_PLUGIN_ROOT="$ROOT" GH_STUB_FAIL=1 bash "$S" 7
[ "$rc" -eq 0 ] || bad "(e) rc=$rc with a failing gh"

[ "$fail" -eq 0 ] && printf 'ok    approve lib: Approved call shape, --self-record bypass, bad args and missing helpers warn, gh failure exits 0\n'
exit "$fail"
