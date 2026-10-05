#!/bin/sh
# Offline regression guard for skills/reply/lib/step6-board-and-labels.sh (#63).
# A stub `gh` on PATH logs every call and fails on demand, so no network is used.
#
#   (a) --phase pre-gate with PUSHED_FIXES=0 makes no gh call at all
#   (b) a failing gh still exits 0, with a [WARN] line, in both phases
#   (c) --phase post-gate removes reply-pending and nothing else
#   (d) bad arguments exit 0 with one [WARN] and no gh call
#   (e) no shell-common anywhere: both pre-gate steps WARN, exit 0
#
#   sh tests/reply-step6.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
S6="$ROOT/skills/reply/lib/step6-board-and-labels.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
fail=0

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_LOG"
if [ "${GH_STUB_FAIL:-0}" = 1 ]; then
    echo 'gh: Server Error (HTTP 500)' >&2
    exit 1
fi
exit 0
EOF
chmod +x "$TMP/bin/gh"

# run <log> <env...> -- <args...>: run the script in a clean env, cwd outside
# any checkout, stdout+stderr captured in $out, exit status in $rc.
run() {
    _log="$1"; shift
    : > "$_log"
    set +e
    out=$(cd "$TMP" && env -u SHELL_COMMON -u CLAUDE_PLUGIN_ROOT HOME=/nonexistent \
        PATH="$TMP/bin:$PATH" GH_LOG="$_log" TARGET_HOST=github.com \
        TARGET_REPO=o/r "$@" 2>&1)
    rc=$?
    set -e
}
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }

# (a)
run "$TMP/a.log" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$S6" --phase pre-gate 7 0
[ "$rc" -eq 0 ] || bad "(a) rc=$rc"
[ ! -s "$TMP/a.log" ] || bad "(a) PUSHED_FIXES=0 still called gh: $(cat "$TMP/a.log")"
case "$out" in *'[OK]'*) ;; *) bad "(a) no [OK] line: $out" ;; esac

# (b) pre-gate, helpers loaded from the vendored tier 2
run "$TMP/b1.log" CLAUDE_PLUGIN_ROOT="$ROOT" GH_STUB_FAIL=1 bash "$S6" --phase pre-gate 7 2
[ "$rc" -eq 0 ] || bad "(b) pre-gate rc=$rc on gh failure"
case "$out" in *"[WARN] \`review-passed\`"*) ;; *) bad "(b) pre-gate: no review-passed [WARN]: $out" ;; esac
grep -q 'labels/review-passed' "$TMP/b1.log" || bad "(b) pre-gate never tried to drop review-passed"
grep -q 'reply-pending' "$TMP/b1.log" && bad "(b) pre-gate touched reply-pending"
# (b) post-gate
run "$TMP/b2.log" GH_STUB_FAIL=1 bash "$S6" --phase post-gate 7
[ "$rc" -eq 0 ] || bad "(b) post-gate rc=$rc on gh failure"
case "$out" in *'[WARN]'*'HTTP 500'*) ;; *) bad "(b) post-gate: no [WARN] with the gh error: $out" ;; esac

# (c)
run "$TMP/c.log" bash "$S6" --phase post-gate 7
[ "$rc" -eq 0 ] || bad "(c) rc=$rc"
[ "$(cat "$TMP/c.log")" = "api -X DELETE repos/o/r/issues/7/labels/reply-pending" ] ||
    bad "(c) post-gate made other calls: $(cat "$TMP/c.log")"
case "$out" in *'[OK]'*) ;; *) bad "(c) no [OK] line: $out" ;; esac

# (d)
for args in "--phase bogus 7" "--phase pre-gate x 1" "--phase pre-gate 7 y" "7 0"; do
    # shellcheck disable=SC2086  # word-splitting the argument list is the point
    run "$TMP/d.log" bash "$S6" $args
    [ "$rc" -eq 0 ] || bad "(d) '$args' rc=$rc"
    case "$out" in '[WARN]'*) ;; *) bad "(d) '$args' no [WARN]: $out" ;; esac
    [ ! -s "$TMP/d.log" ] || bad "(d) '$args' called gh"
done
run "$TMP/d.log" env -u TARGET_REPO bash "$S6" --phase post-gate 7
case "$rc:$out" in '0:[WARN]'*) ;; *) bad "(d) unset TARGET_REPO: rc=$rc $out" ;; esac

# (e)
run "$TMP/e.log" bash "$S6" --phase pre-gate 7 1
[ "$rc" -eq 0 ] || bad "(e) rc=$rc"
[ "$(printf '%s\n' "$out" | grep -c '^\[WARN\] no usable shell-common at /nonexistent/')" -eq 2 ] ||
    bad "(e) want two loader [WARN]s naming the tier-1 path: $out"

[ "$fail" -eq 0 ] && printf 'ok    reply step6 lib: no-push is call-free, gh failures warn and exit 0, post-gate drops only reply-pending, bad args and missing helpers warn\n'
exit "$fail"
