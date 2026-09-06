#!/bin/sh
# Regression guard for #13.
#
# lib/post-merge-verify-dispatch.sh (run by gh-pr:merge Step 5) sources its
# post-merge verification dispatch from a file it resolves at run time. When
# that path went stale the `[ -r ]` guard skipped a 394-line gate on every merge
# and said nothing. This asserts the two things
# that failure needed: the path resolves on a machine with no dotfiles checkout,
# and the file it resolves to still holds a non-empty first `bash` fence.
#
# Since harness-skills#22 there is a third: with no plugin root at all the tier
# must decline rather than fall back to $PWD. gh-pr:merge runs inside the PR
# checkout under review, so a pull request can plant its own dispatch.sh.md and
# have the script source it — case 4 below plants exactly that and requires a miss.
#
#   sh tests/pmv-dispatch-resolves.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
VENDORED=lib/vendor/gh-verify/post-merge-verify/dispatch.sh.md
DISPATCH="$ROOT/lib/post-merge-verify-dispatch.sh"
fail=0
n=0

# 1. The dispatch script still names the vendored path as its second tier, and
#    Step 5 still calls the script. Renaming one side only is exactly how this
#    rotted the first time.
grep -qF "\$CLAUDE_PLUGIN_ROOT/$VENDORED" "$DISPATCH" || {
	printf 'FAIL  %s no longer points at $CLAUDE_PLUGIN_ROOT/%s\n' "$DISPATCH" "$VENDORED"
	fail=1
}
grep -qF 'lib/post-merge-verify-dispatch.sh' "$ROOT/skills/merge/SKILL.md" || {
	printf 'FAIL  skills/merge/SKILL.md Step 5 no longer calls lib/post-merge-verify-dispatch.sh\n'
	fail=1
}

# 2. Standalone install: HOME and DOTFILES_ROOT aimed away from any dotfiles
#    checkout and no GH_VERIFY_ROOT, so only CLAUDE_PLUGIN_ROOT can answer.
unset GH_VERIFY_ROOT 2>/dev/null || :
HOME=/nonexistent
DOTFILES_ROOT=/nonexistent
CLAUDE_PLUGIN_ROOT="$ROOT"
export HOME DOTFILES_ROOT CLAUDE_PLUGIN_ROOT

PMV_BLOCK="${GH_VERIFY_ROOT:+$GH_VERIFY_ROOT/skills/post-merge-verify/references/dispatch.sh.md}"
[ -r "$PMV_BLOCK" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || PMV_BLOCK="$CLAUDE_PLUGIN_ROOT/$VENDORED"

if [ -r "$PMV_BLOCK" ]; then
	# 3. Positive signal. A zero-line extraction is the same bug in another mask
	#    (right file, wrong fence) and would be sourced silently.
	F=$(printf '\140\140\140')
	n=$(awk -v f="$F" '$0 == f "bash" && !b { b = 1; next } $0 == f && b { exit } b' \
		"$PMV_BLOCK" | wc -l | tr -d "[:space:]")
	[ "$n" -gt 300 ] || {
		printf 'FAIL  first bash fence of %s is %s lines (expected the ~394-line dispatch)\n' \
			"$PMV_BLOCK" "$n"
		fail=1
	}
else
	printf 'FAIL  dispatch unreadable on a standalone install: %s\n' "$PMV_BLOCK"
	fail=1
fi

# 4. The negative half of the same tier (harness-skills#22). With no plugin root
#    the guard must decline, even when the cwd genuinely holds the file a $PWD
#    fallback would have found — that cwd is the repo under review.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/$(dirname "$VENDORED")"
cp "$ROOT/$VENDORED" "$TMP/$VENDORED"

unset CLAUDE_PLUGIN_ROOT
PMV_BLOCK="${GH_VERIFY_ROOT:+$GH_VERIFY_ROOT/skills/post-merge-verify/references/dispatch.sh.md}"
cd "$TMP"
[ -r "$PMV_BLOCK" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || PMV_BLOCK="$CLAUDE_PLUGIN_ROOT/$VENDORED"
cd "$ROOT"

case "$PMV_BLOCK" in
	"$TMP"/*)
		printf 'FAIL  dispatch resolved from the cwd a PR could have planted: %s\n' "$PMV_BLOCK"
		fail=1 ;;
	'') ;;
	*)
		printf 'FAIL  dispatch resolved to %s with no plugin root — expected no resolution\n' \
			"$PMV_BLOCK"
		fail=1 ;;
esac
if [ -r "$PMV_BLOCK" ]; then
	printf 'FAIL  the dispatch script would source %s with no plugin root\n' "$PMV_BLOCK"
	fail=1
fi

# 5. The argument validator, testable now that Step 5 is a real script (#5).
#    A placeholder, a blank and a whitespace-only value must all be named; a
#    fully-bound call for an unregistered repo must stay byte-silent.
out=$(IW_WATCHED_REPOS=/nonexistent/watched.json sh "$DISPATCH" 42 '<owner/repo' '' ' ' origin 2>&1) || :
case "$out" in
	'[WARN]'*TARGET_REPO*HEAD_BRANCH*BASE_BRANCH*) ;;
	*) printf 'FAIL  validator did not name every unbound value: %s\n' "$out"; fail=1 ;;
esac
out=$(IW_WATCHED_REPOS=/nonexistent/watched.json sh "$DISPATCH" 42 o/r head base origin 2>&1) || :
[ -z "$out" ] || { printf 'FAIL  unregistered repo was not silent: %s\n' "$out"; fail=1; }

# 6. The non-Claude harness path (PR #33 review, codex BLOCKER). With no plugin
#    root the gate must stay LOUD for a registered repo, never degrade to a
#    silent skip — both halves: Step 5's own guard, and the script's [FAIL]
#    should the script be reached some other way.
grep -qF 'CLAUDE_PLUGIN_ROOT is unset' "$ROOT/skills/merge/SKILL.md" || {
	printf 'FAIL  Step 5 no longer fails loudly when CLAUDE_PLUGIN_ROOT is unset\n'
	fail=1
}
#    Loud, but never FAILING: Step 5 runs after the merge has already landed,
#    so a non-Claude harness must not see successful housekeeping report a
#    nonzero status (PR #33 review, codex BLOCKER). Extract Step 5's bash fence
#    and require it to carry no nonzero `return`/`exit`.
step5=$(awk '/^```bash$/ { b = 1; buf = ""; next }
	/^```$/ { if (b && buf ~ /post-merge-verify-dispatch\.sh/) { printf "%s", buf; exit } b = 0; next }
	b { buf = buf $0 "\n" }' "$ROOT/skills/merge/SKILL.md")
case "$step5" in
	'') printf 'FAIL  could not find Step 5 dispatch block in skills/merge/SKILL.md\n'; fail=1 ;;
	*'return 1'* | *'exit 1'*)
		printf 'FAIL  Step 5 exits nonzero after a completed merge:\n%s\n' "$step5"
		fail=1 ;;
esac
printf '[{"repo":"o/r","verify_skill":"gh-verify:merged"}]\n' > "$TMP/watched.json"

#    Run the SNIPPET, not just the wrapper (PR #33 review, codex BLOCKER): the
#    guard that decides whether the wrapper is reached at all lives in SKILL.md,
#    so a test that only ever calls $DISPATCH cannot see it. Substitute the five
#    placeholders exactly as the skill does and execute it.
printf '%s' "$step5" | sed \
	-e 's|<N>|42|g' -e 's|<owner/repo>|o/r|g' -e 's|<headRefName>|head|g' \
	-e 's|<baseRefName>|base|g' -e 's|<remote>|origin|g' > "$TMP/step5.sh"
#    6a. No plugin root and the repo is NOT registered: byte-silent, exit 0. A
#        blanket [FAIL] here would spam every non-Claude merge of an unwatched
#        repo, which is the wrapper's documented no-op case.
if out=$(env -u CLAUDE_PLUGIN_ROOT -u GH_VERIFY_ROOT \
	IW_WATCHED_REPOS=/nonexistent/watched.json sh "$TMP/step5.sh" 2>&1)
then rc=0
else rc=$?
fi
[ "$rc" -eq 0 ] && [ -z "$out" ] || {
	printf 'FAIL  Step 5 was not silent for an unregistered repo with no plugin root (rc=%s): %s\n' \
		"$rc" "$out"
	fail=1
}
#    6b. No plugin root but the repo IS registered: loud [FAIL], still exit 0.
if out=$(env -u CLAUDE_PLUGIN_ROOT -u GH_VERIFY_ROOT \
	IW_WATCHED_REPOS="$TMP/watched.json" sh "$TMP/step5.sh" 2>&1)
then rc=0
else rc=$?
fi
[ "$rc" -eq 0 ] || {
	printf 'FAIL  Step 5 exited %s for a registered repo with no plugin root\n' "$rc"
	fail=1
}
case "$out" in
	*'[FAIL]'*) ;;
	*) printf 'FAIL  Step 5 was not loud for a REGISTERED repo with no plugin root: %s\n' "$out"
		fail=1 ;;
esac
out=$(env -u CLAUDE_PLUGIN_ROOT -u GH_VERIFY_ROOT \
	IW_WATCHED_REPOS="$TMP/watched.json" sh "$DISPATCH" 42 o/r head base origin 2>&1) || :
case "$out" in
	'[FAIL]'*) ;;
	*) printf 'FAIL  registered repo with no plugin root was not loud: %s\n' "$out"; fail=1 ;;
esac

# 7. The wrapper always exits 0, even when the dispatch it sources calls `exit`
#    (PR #33 review, codex BLOCKER). The real dispatch block returns early and
#    can exit outright; sourced flat that would terminate the wrapper nonzero,
#    after the merge has already landed. Plant a block that exits 3 and require
#    both a zero status and the [FAIL] line — the exit must be contained, not
#    silently treated as a successful source.
mkdir -p "$TMP/root/lib/vendor/gh-verify/post-merge-verify"
cat > "$TMP/root/$VENDORED" <<'PLANT'
```bash
printf 'planted dispatch ran\n'
exit 3
```
PLANT
if out=$(env -u GH_VERIFY_ROOT CLAUDE_PLUGIN_ROOT="$TMP/root" \
	IW_WATCHED_REPOS="$TMP/watched.json" sh "$DISPATCH" 42 o/r head base origin 2>&1)
then rc=0
else rc=$?
fi
[ "$rc" -eq 0 ] || {
	printf 'FAIL  a dispatch that exited 3 propagated out of the wrapper (rc=%s)\n' "$rc"
	fail=1
}
case "$out" in
	*'planted dispatch ran'*) ;;
	*) printf 'FAIL  planted dispatch never ran: %s\n' "$out"; fail=1 ;;
esac
case "$out" in
	*'[FAIL]'*) ;;
	*) printf 'FAIL  a dispatch that exited nonzero was reported as a good source: %s\n' "$out"; fail=1 ;;
esac

if [ "$fail" -eq 0 ]; then
	printf 'ok    post-merge dispatch resolves standalone (%s-line bash fence), declines a planted cwd copy, validates its five arguments, and stays loud with no plugin root\n' "$n"
fi
exit "$fail"
