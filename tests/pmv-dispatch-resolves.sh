#!/bin/sh
# Regression guard for #13.
#
# gh-pr:merge Step 5 sources its post-merge verification dispatch from a file it
# resolves at run time. When that path went stale the `[ -r ]` guard skipped a
# 394-line gate on every merge and said nothing. This asserts the two things
# that failure needed: the path resolves on a machine with no dotfiles checkout,
# and the file it resolves to still holds a non-empty first `bash` fence.
#
#   sh tests/pmv-dispatch-resolves.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
VENDORED=lib/vendor/gh-verify/post-merge-verify/dispatch.sh.md
SKILL="$ROOT/skills/merge/SKILL.md"
# Step 5's fence parser, verbatim: held once and asserted against SKILL.md
# below, so editing one side alone fails here instead of silently testing a
# stale copy of the algorithm.
FENCE_AWK='$0 == f "bash" && !b { b = 1; next } $0 == f && b { exit } b'
fail=0

# 1. Step 5 still names the vendored path as its second tier, and still parses
#    the fence the way this test does. Changing one side only is exactly how
#    this rotted the first time.
grep -qF "\${CLAUDE_PLUGIN_ROOT:-}/$VENDORED" "$SKILL" || {
	printf 'FAIL  %s no longer points at $CLAUDE_PLUGIN_ROOT/%s\n' "$SKILL" "$VENDORED"
	fail=1
}
grep -qF "$FENCE_AWK" "$SKILL" || {
	printf 'FAIL  %s no longer uses the fence parser this test extracts with\n' "$SKILL"
	fail=1
}

# 2. Standalone install: no GH_VERIFY_ROOT and no dotfiles checkout in the
#    formula at all, so only CLAUDE_PLUGIN_ROOT can answer.
unset GH_VERIFY_ROOT 2>/dev/null || :
CLAUDE_PLUGIN_ROOT="$ROOT"

PMV_BLOCK="${GH_VERIFY_ROOT:-}/skills/post-merge-verify/references/dispatch.sh.md"
[ -r "$PMV_BLOCK" ] || PMV_BLOCK="${CLAUDE_PLUGIN_ROOT:-}/$VENDORED"

if [ -r "$PMV_BLOCK" ]; then
	# 3. Positive signal. A zero-line extraction is the same bug in another mask
	#    (right file, wrong fence) and would be sourced silently.
	F=$(printf '\140\140\140')
	n=$(awk -v f="$F" "$FENCE_AWK" "$PMV_BLOCK" | wc -l | tr -d "[:space:]")
	[ "$n" -gt 300 ] || {
		printf 'FAIL  first bash fence of %s is %s lines (expected the ~394-line dispatch)\n' \
			"$PMV_BLOCK" "$n"
		fail=1
	}
else
	printf 'FAIL  dispatch unreadable on a standalone install: %s\n' "$PMV_BLOCK"
	fail=1
fi

if [ "$fail" -eq 0 ]; then
	printf 'ok    post-merge dispatch resolves standalone, %s-line bash fence\n' "$n"
fi
exit "$fail"
