#!/bin/sh
# Drift guard for the large-diff delegation threshold (#36).
#
# `gh-pr:approve` Step 2 and `gh-pr:review` Step 4 branch on the same number,
# and it used to be written out independently in five places: review's SKILL.md,
# review's ai-cli-invocation.md, approve's large-diff-delegation.md and both
# Korean skill guides. A magic number stated five times is not a single source
# of truth, and these two skills MUST move together — changing one alone
# desyncs the pair (#6 finding B2).
#
# So the value lives in exactly one file and every consumer cites the path.
# This asserts that, in three parts:
#
#   1. the definition site declares it exactly once,
#   2. every file that branches on it cites that path and states no number,
#   3. the published Pages guides, which do render the number, render the
#      current one.
#
#   sh tests/large-diff-threshold.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

DEF=skills/approve/references/large-diff-delegation.md

# Every file whose text branches on the threshold. Listed, not discovered: the
# check below is "does this file state a number", and a repo-wide scan for a
# bare integer is only ever clean by luck — at 1000 it would collide with the
# unrelated ai-metrics token floor in four other references and hand whoever
# moves the threshold a screen of false failures. A named list is wrong only if
# a NEW file starts branching, which is what CLAUDE.md's rule is for.
CITERS="skills/approve/SKILL.md
skills/review/SKILL.md
skills/review/references/ai-cli-invocation.md
docs/skill-guides/approve.md
docs/skill-guides/review.md"

# The published guides render it as a number on purpose: a stat card exists to
# show one, and citing a file path there would make the page worse. Nothing
# executes them, so they cannot desync the skills — for these the invariant is
# staleness, not duplication.
RENDERED="docs/skill-guides/approve.html
docs/skill-guides/review.html"

fail=0

[ -f "$DEF" ] || {
	printf 'FAIL  the definition site %s is gone\n' "$DEF"
	exit 1
}

# Exactly one: two declarations here would be the same defect moved indoors.
decls=$(grep -cE '^`THRESHOLD_LINES = [0-9]+`' "$DEF" || :)
[ "$decls" = 1 ] || {
	printf 'FAIL  %s declares THRESHOLD_LINES %s time(s); it must declare it exactly once\n' \
		"$DEF" "$decls"
	exit 1
}
N=$(sed -nE 's/^`THRESHOLD_LINES = ([0-9]+)`.*/\1/p' "$DEF")

for f in $CITERS; do
	[ -f "$f" ] || {
		printf 'FAIL  %s is listed as a threshold citer but does not exist\n' "$f"
		fail=1
		continue
	}
	# Cite, or the branch was deleted — either way this file no longer agrees
	# with the definition site by construction.
	grep -qF 'large-diff-delegation.md' "$f" || {
		printf 'FAIL  %s branches on the threshold but no longer cites %s\n' "$f" "$DEF"
		fail=1
	}
	# ...and cite INSTEAD of restating. Not a digit on either side, so an issue
	# or version number containing N does not fire.
	hits=$(grep -nE "(^|[^0-9])$N([^0-9]|\$)" "$f" || :)
	[ -z "$hits" ] || {
		printf 'FAIL  %s restates the threshold instead of citing %s:\n' "$f" "$DEF"
		printf '%s\n' "$hits" | sed 's/^/        /'
		fail=1
	}
done

for f in $RENDERED; do
	# Anchored on the Korean unit, not the bare digits: these pages carry
	# `font-weight: 800` and a Google Fonts `wght@...;800;900`, so a
	# bare-number check would pass vacuously forever.
	grep -qF "$N줄" "$f" || {
		printf 'FAIL  %s no longer renders the threshold as %s줄; the published guide is stale\n' \
			"$f" "$N"
		fail=1
	}
done

[ "$fail" -ne 0 ] || printf 'ok    large-diff threshold (%s) declared once in %s, cited by %s file(s), rendered current in %s guide(s)\n' \
	"$N" "$DEF" "$(printf '%s\n' "$CITERS" | wc -l | tr -d ' ')" \
	"$(printf '%s\n' "$RENDERED" | wc -l | tr -d ' ')"
exit "$fail"
