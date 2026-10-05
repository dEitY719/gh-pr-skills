#!/bin/sh
# Offline regression guard for skills/commit/lib/*.sh (#65). A scratch git repo
# supplies the remotes, a fake shell-common records the board helper's call —
# no network, no gh.
#
#   github-target.sh
#     (a) origin: one eval-able line binding GH_HOST / TARGET_* / REMOTE
#     (b) a named remote binds that remote's host and repo, not origin's
#     (c) unknown remote: rc 1, empty stdout, the available-remotes list
#     (d) no shell-common anywhere: rc 1, empty stdout, tier-1 path named
#   board-sync.sh
#     (e) asks for `issue <N> "In progress" --only-from Backlog`
#     (f) bad argument / no shell-common: exit 0 with one warning
#
#   sh tests/commit-lib.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
L="$ROOT/skills/commit/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
fail=0
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }

git init -q "$TMP/repo"
git -C "$TMP/repo" remote add origin git@ghe.example:own/repo.git
git -C "$TMP/repo" remote add upstream https://github.com/up/stream.git
mkdir -p "$TMP/sc/functions"
cat > "$TMP/sc/functions/gh_project_status.sh" <<'EOF'
_gh_project_status_sync() { printf 'args=%s\n' "$*" >> "$SYNC_LOG"; }
EOF

# gt <env...>: run github-target.sh from the scratch repo; $out, $err, $rc.
gt() {
    set +e
    out=$(cd "$TMP/repo" && env -u SHELL_COMMON -u CLAUDE_PLUGIN_ROOT HOME=/nonexistent \
        DOTFILES_ROOT=/nonexistent DOTFILES_GHES_HOST=ghe.example "$@" 2>"$TMP/err")
    rc=$?
    set -e
    err=$(cat "$TMP/err")
}

# (a)
gt CLAUDE_PLUGIN_ROOT="$ROOT" sh "$L/github-target.sh"
[ "$rc" -eq 0 ] || bad "(a) rc=$rc: $err"
[ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] || bad "(a) stdout is not one line: $out"
# shellcheck disable=SC2016  # expanded by the inner shell after the eval
got=$(sh -c 'eval "$1"; printf "%s|%s|%s|%s|%s" "$GH_HOST" "$TARGET_REPO" "$TARGET_HOST" "$REMOTE" "$SHELL_COMMON"' sh "$out")
[ "$got" = "ghe.example|own/repo|ghe.example|origin|$ROOT/lib/vendor/shell-common" ] || bad "(a) eval bound: $got"

# (b)
gt CLAUDE_PLUGIN_ROOT="$ROOT" sh "$L/github-target.sh" upstream
# shellcheck disable=SC2016  # expanded by the inner shell after the eval
got=$(sh -c 'eval "$1"; printf "%s|%s|%s" "$GH_HOST" "$TARGET_REPO" "$REMOTE"' sh "$out")
[ "$got" = "github.com|up/stream|upstream" ] || bad "(b) named remote bound: $got"

# (c)
gt CLAUDE_PLUGIN_ROOT="$ROOT" sh "$L/github-target.sh" nope
[ "$rc:$out" = 1: ] || bad "(c) unknown remote: rc=$rc stdout=$out"
case "$err" in *"remote 'nope' not found. Available remotes:"*origin*upstream*) ;; *) bad "(c) no remotes list: $err" ;; esac

# (d)
gt sh "$L/github-target.sh"
[ "$rc:$out" = 1: ] || bad "(d) tier 5: rc=$rc stdout=$out"
case "$err" in *'/nonexistent/shell-common'*) ;; *) bad "(d) tier-1 path not named: $err" ;; esac

# bs <env...>: run board-sync.sh outside any checkout; $out (2>&1), $rc.
bs() {
    : > "$TMP/sync.log"
    set +e
    out=$(cd "$TMP" && env -u SHELL_COMMON -u CLAUDE_PLUGIN_ROOT HOME=/nonexistent \
        SYNC_LOG="$TMP/sync.log" "$@" 2>&1)
    rc=$?
    set -e
}

# (e)
bs SHELL_COMMON="$TMP/sc" bash "$L/board-sync.sh" 7
[ "$rc" -eq 0 ] || bad "(e) rc=$rc"
[ "$(cat "$TMP/sync.log")" = 'args=issue 7 In progress --only-from Backlog' ] || bad "(e) helper call: $(cat "$TMP/sync.log")"

# (f)
bs SHELL_COMMON="$TMP/sc" bash "$L/board-sync.sh" x
case "$rc:$out" in '0:[gh-commit]'*skipped*) ;; *) bad "(f) bad arg: rc=$rc $out" ;; esac
[ ! -s "$TMP/sync.log" ] || bad "(f) bad arg still synced"
bs bash "$L/board-sync.sh" 7
case "$rc:$out" in '0:[gh-commit] no usable shell-common at /nonexistent/dotfiles/shell-common/'*) ;; *) bad "(f) no helper: rc=$rc $out" ;; esac

[ "$fail" -eq 0 ] && printf 'ok    commit lib: target binds from the named remote as one eval line, fails closed with empty stdout; board sync call shape and soft skips\n'
exit "$fail"
