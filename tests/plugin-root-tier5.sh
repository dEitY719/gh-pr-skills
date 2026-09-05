#!/bin/sh
# Regression guard for the plugin-root resolution convention (harness-skills#10,
# gh-pr-skills#16). SSOT:
# https://github.com/dEitY719/harness-skills/blob/main/references/plugin-root.md
#
# Two assertions, because the defect has a mechanical half and a behavioural one:
#
#   1. No tracked file splices an explicitly-empty default into a path — an
#      expansion of CLAUDE_PLUGIN_ROOT with an empty default, immediately
#      followed by a slash. With the variable unset that resolves to the
#      filesystem root, and the export that followed it poisoned every later
#      SHELL_COMMON default in the same run (gh-resolve-skills#8).
#
#      This file states the pattern in prose rather than quoting it, so the
#      gate needs no self-exclusion here. Only the convention's own page
#      carries one, because it has to show the literal.
#   2. A real resolution block, run with no override and a cwd outside any
#      checkout, stops at tier 5: non-zero, names the path it tried, and leaves
#      SHELL_COMMON unset rather than pointing at "/".
#
#   sh tests/plugin-root-tier5.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SITE=skills/merge/references/github-target.md
fail=0

# 1. The gate grep. It has no false positives: an explicitly empty default
#    immediately followed by "/" is always the defect.
cd "$ROOT"
hits=$(git ls-files -z \
	| xargs -0 grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?-\}/' || :)
if [ -n "$hits" ]; then
	printf 'FAIL  empty-default path splice still present:\n%s\n' "$hits"
	fail=1
fi

# 2. Extract the resolution preamble of a real site — the first bash fence up to
#    and including its export — and run it as the harness would paste it.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
F=$(printf '\140\140\140')
awk -v f="$F" '$0 == f "bash" && !b { b = 1; next } $0 == f && b { exit }
	b { print } b && /^export SHELL_COMMON=/ { exit }' \
	"$ROOT/$SITE" > "$TMP/block.sh"
[ -s "$TMP/block.sh" ] || { printf 'FAIL  no bash fence extracted from %s\n' "$SITE"; exit 1; }

# Pasted into a shell: no override, no plugin root, cwd outside the checkout.
set +e
err=$(cd "$TMP" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON \
	HOME=/nonexistent DOTFILES_ROOT=/nonexistent sh "$TMP/block.sh" 2>&1 >/dev/null)
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'FAIL  tier 5 did not stop: rc=0 for %s\n' "$SITE"; fail=1; }
case "$err" in
	*"$TMP/lib/vendor/shell-common"*) ;;
	*) printf 'FAIL  tier 5 message does not name the resolved path: %s\n' "$err"; fail=1 ;;
esac

# Sourced instead of run: `return 1 2>/dev/null || exit 1` must not kill the
# caller, and SHELL_COMMON must still be unset — never "/lib/vendor/shell-common".
# shellcheck disable=SC2016  # the inner shell expands these, not this one
sc=$(cd "$TMP" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON \
	HOME=/nonexistent DOTFILES_ROOT=/nonexistent \
	sh -c '. "$1" >/dev/null 2>&1; printf "%s" "${SHELL_COMMON-<unset>}"' \
	sh "$TMP/block.sh")
[ "$sc" = "<unset>" ] || {
	printf 'FAIL  SHELL_COMMON exported before the proof: %s\n' "$sc"
	fail=1
}

if [ "$fail" -eq 0 ]; then
	printf 'ok    no empty-default splices; %s stops at tier 5 and exports nothing\n' "$SITE"
fi
exit "$fail"
