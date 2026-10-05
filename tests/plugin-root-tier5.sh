#!/bin/sh
# Regression guard for the plugin-root resolution convention (harness-skills#10,
# gh-pr-skills#16). SSOT:
# https://github.com/dEitY719/harness-skills/blob/main/references/plugin-root.md
#
# Two assertions, because the defect has a mechanical half and a behavioural one:
#
#   1. No tracked file splices a caller-controlled default into a path — an
#      expansion of CLAUDE_PLUGIN_ROOT with an empty default, or with $PWD,
#      immediately followed by a slash. With the variable unset the empty
#      default resolves to the filesystem root, and the export that followed it
#      poisoned every later SHELL_COMMON default in the same run
#      (gh-resolve-skills#8). The $PWD default is the retired tier 4
#      (harness-skills#22): these skills run inside the PR checkout under
#      review, so a pull request that adds lib/vendor/shell-common to its own
#      tree gets it sourced by the reviewer's tooling.
#
#      Three spellings of that cwd default, not one (harness-skills#35): a
#      $PWD-only alternation passed the dot and command-substitution forms,
#      which name the same caller-controlled directory — and the dot form is
#      the one that actually shipped, in claudecode-skills#5.
#
#      This file states the pattern in prose rather than quoting it, so the
#      gate needs no self-exclusion here. Only the convention's own page
#      carries one, because it has to show the literal.
#   2. A real resolution block, run with no override and a cwd outside any
#      checkout, stops at tier 5: non-zero, names the path it tried, and leaves
#      SHELL_COMMON unset rather than pointing at "/". It stops there even when
#      the cwd genuinely holds lib/vendor/shell-common/functions/gh_host.sh —
#      the negative case harness-skills#22 exists for.
#
#   sh tests/plugin-root-tier5.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SITE=skills/merge/lib/github-target.sh
fail=0

# 1. The gate grep, verbatim from the convention page. It has no false
#    positives: an empty default, or a $PWD default, immediately followed by "/"
#    is always the defect, and a guarded [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] does
#    not match it.
cd "$ROOT"
hits=$(git ls-files -z \
	| xargs -0 grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?-(\$PWD|\$\(pwd\)|\.)?\}/' || :)
if [ -n "$hits" ]; then
	printf 'FAIL  caller-controlled-default path splice still present:\n%s\n' "$hits"
	fail=1
fi

# 2. Run a real resolution site — merge's lib/github-target.sh, which prints the
#    bindings for the caller to eval and nothing else (#65) — as the skill does.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
cp "$ROOT/$SITE" "$TMP/block.sh"

# The hostile half of the negative case: a pull request under review can add
# lib/vendor/shell-common to its own tree, and $PWD is that checkout. Plant a
# working gh_host.sh in the cwd — the block must still refuse it.
mkdir -p "$TMP/lib/vendor/shell-common/functions"
printf '_gh_resolve_host() { printf %%s cwd-owned; }\n' \
	> "$TMP/lib/vendor/shell-common/functions/gh_host.sh"

# One binding for the tier-1 override both runs below aim away from, so the
# message assertion cannot drift from the value that produced it.
NOWHERE=/nonexistent
TIER1="$NOWHERE/shell-common"

# Pasted into a shell: no override, no plugin root, cwd outside the checkout.
set +e
err=$(cd "$TMP" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON \
	HOME="$NOWHERE" DOTFILES_ROOT="$NOWHERE" sh "$TMP/block.sh" 2>&1 >/dev/null)
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'FAIL  tier 5 did not stop: rc=0 for %s\n' "$SITE"; fail=1; }
case "$err" in
	*"$TMP/lib/vendor/shell-common"*)
		printf 'FAIL  tier 5 resolved from the cwd a PR could have planted: %s\n' "$err"
		fail=1 ;;
	*"$TIER1"*) ;;
	*) printf 'FAIL  tier 5 message does not name %s, the path it tried: %s\n' "$TIER1" "$err"; fail=1 ;;
esac

# Its stdout is what the caller evals: a tier-5 stop must print nothing, so the
# eval can never export SHELL_COMMON — never "/lib/vendor/shell-common".
# shellcheck disable=SC2016  # the inner shell expands these, not this one
sc=$(cd "$TMP" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON \
	HOME="$NOWHERE" DOTFILES_ROOT="$NOWHERE" \
	sh -c 'eval "$(sh "$1" 2>/dev/null)"; printf "%s" "${SHELL_COMMON-<unset>}"' \
	sh "$TMP/block.sh")
[ "$sc" = "<unset>" ] || {
	printf 'FAIL  SHELL_COMMON exported before the proof: %s\n' "$sc"
	fail=1
}

# 3. The proof compares command -v's OUTPUT to the bare name (harness-skills#36).
#    A tier-2 root whose helper loads but defines nothing must still stop, even
#    with a PATH executable of that exact name in the way: `command -v` answers
#    "is this name runnable", and the exit-status form it replaced passed that
#    in every shell. Anything less and a stray binary silently certifies a
#    shell-common that never defined the function.
mkdir -p "$TMP/root/lib/vendor/shell-common/functions" "$TMP/bin"
: > "$TMP/root/lib/vendor/shell-common/functions/gh_host.sh"
printf '#!/bin/sh\nprintf imposter\n' > "$TMP/bin/_gh_resolve_host"
chmod +x "$TMP/bin/_gh_resolve_host"
set +e
err=$(cd "$TMP" && env -u SHELL_COMMON HOME="$NOWHERE" DOTFILES_ROOT="$NOWHERE" \
	CLAUDE_PLUGIN_ROOT="$TMP/root" PATH="$TMP/bin:$PATH" sh "$TMP/block.sh" 2>&1 >/dev/null)
rc=$?
set -e
# The script would also stop later, at `git remote get-url` outside a checkout,
# so rc alone cannot tell the proof held: require the proof's own message.
case "$rc:$err" in
	[1-9]*:*'did not load a usable shell-common'*) ;;
	*) printf 'FAIL  a PATH executable named _gh_resolve_host satisfied the load proof (rc=%s): %s\n' "$rc" "$err"
	   fail=1 ;;
esac

# 4. That failure leaves SHELL_COMMON unset in the caller, although the script
#    exports it BEFORE the load (harness-skills#37): the export has to come
#    first — every vendored helper resolves its siblings through
#    ${SHELL_COMMON:-...} while it sources — and the tier-5 arm prints no eval
#    line, which keeps the contract "set if and only if a helper proved out".
#    Without it this is the poisoned export of gh-resolve-skills#8.
# shellcheck disable=SC2016  # the inner shell expands these, not this one
sc=$(cd "$TMP" && env -u SHELL_COMMON HOME="$NOWHERE" DOTFILES_ROOT="$NOWHERE" \
	CLAUDE_PLUGIN_ROOT="$TMP/root" PATH="$TMP/bin:$PATH" \
	sh -c 'eval "$(sh "$1" 2>/dev/null)"; printf "%s" "${SHELL_COMMON-<unset>}"' \
	sh "$TMP/block.sh")
[ "$sc" = "<unset>" ] || {
	printf 'FAIL  a tree that failed the proof stayed exported as SHELL_COMMON: %s\n' "$sc"
	fail=1
}

# 5. The SOFT warn-and-skip loader (harness-skills#60, harness-skills PR #61).
#    Six board-sync blocks here use it. Same proof and same export ordering as
#    above; what differs is the failure arm, which RESTORES SHELL_COMMON rather
#    than unsetting it — a soft block returns to its caller and is normally not
#    the first loader in the run, so an unconditional unset would let an
#    OPTIONAL step's failure knock out the value every required
#    ${SHELL_COMMON:-...} after it reads.
SOFT_SITES="skills/approve/lib/board-approved-sync.sh
skills/commit/lib/board-sync.sh
skills/create/lib/project-board-sync.sh
skills/merge/lib/post-merge-housekeeping.sh
skills/merge-emergency/references/project-board-sync.md
skills/reply/lib/step6-board-and-labels.sh"

# 5a. Mechanical, all six: the six steps in order. The whole sequence, not "X
#     before Y", so a dropped or duplicated step is caught too.
for f in $SOFT_SITES; do
	[ -f "$ROOT/$f" ] || { printf 'FAIL  %s is listed as a soft loader but does not exist\n' "$f"; fail=1; continue; }
	seq=$(sed -E \
		-e 's/^[[:space:]]*_sc_was=\$\{SHELL_COMMON\+set\} _sc_prev="\$\{SHELL_COMMON-\}".*$/SAVE/' \
		-e 's/^[[:space:]]*unset -f _gh_project_status_sync 2>\/dev\/null \|\| :$/UNSETF/' \
		-e 's/^[[:space:]]*unalias _gh_project_status_sync 2>\/dev\/null \|\| :$/UNALIAS/' \
		-e 's/^[[:space:]]*export SHELL_COMMON="\$\{_HELPER%.*$/EXPORT/' \
		-e 's/^[[:space:]]*\[ -r "\$_HELPER" \] && \. "\$_HELPER"$/LOAD/' \
		-e 's/^[[:space:]]*(if )?\[ "\$\(command -v _gh_project_status_sync 2>\/dev\/null\)" !?= _gh_project_status_sync \].*$/PROOF/' \
		-e 's/^[[:space:]]*if \[ -n "\$_sc_was" \]; then export SHELL_COMMON="\$_sc_prev"; else unset SHELL_COMMON; fi$/RESTORE/' \
		"$ROOT/$f" | grep -E '^(SAVE|UNSETF|UNALIAS|EXPORT|LOAD|PROOF|RESTORE)$' | tr '\n' ' ') || :
	want='SAVE UNSETF UNALIAS EXPORT LOAD PROOF RESTORE '
	[ "$seq" = "$want" ] || {
		printf 'FAIL  %s soft-loader steps are out of order or incomplete\n' "$f"
		printf '        want: %s\n        got:  %s\n' "$want" "${seq:-<none>}"
		fail=1
	}
done

# 5b. Behavioural, on one real site. commit/lib/board-sync.sh is the flattest
#     of the six, so what runs here is the shipped text rather than a paraphrase
#     — sourced into one shell, so the SHELL_COMMON hand-back is observable.
soft=$(awk '/^_HELPER="\$\{SHELL_COMMON:-/ { p = 1 } p { print } /^unset _sc_was _sc_prev$/ { exit }' \
	"$ROOT/skills/commit/lib/board-sync.sh")
case "$soft" in
	*RESTORE*|'') printf 'FAIL  could not extract the soft block from commit/lib/board-sync.sh\n'; fail=1 ;;
esac
printf 'ISSUE_NUMBER=1\n%s\nprintf "LEFT=%%s\\n" "${SHELL_COMMON-UNSET}"\n' "$soft" > "$TMP/soft.sh"

#     It must WARN and CONTINUE — exit 0, no silent skip, and the path named.
#     Before the conversion a missing helper fell straight through the outer
#     `if [ -r ]` and said nothing at all, which is the silent skip the soft
#     form's own contract (condition 4) forbids.
set +e
out=$(cd "$TMP" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON HOME="$NOWHERE" \
	sh "$TMP/soft.sh" 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || { printf 'FAIL  the soft loader stopped the run instead of skipping the step (rc=%s)\n' "$rc"; fail=1; }
case "$out" in
	*"board sync skipped"*) ;;
	*) printf 'FAIL  the soft loader skipped silently — no warning: %s\n' "$out"; fail=1 ;;
esac
case "$out" in
	*"$NOWHERE/dotfiles/shell-common/functions/gh_project_status.sh"*) ;;
	*) printf 'FAIL  the soft warning does not name the path it tried: %s\n' "$out"; fail=1 ;;
esac

#     Handed a value an earlier hard block proved, it must hand it back. A tree
#     without the board helper, so the block is forced down its failure arm
#     rather than loading from tier 1 and never reaching the restore.
mkdir -p "$TMP/proven/functions"
out=$(cd "$TMP" && env -u CLAUDE_PLUGIN_ROOT HOME="$NOWHERE" \
	SHELL_COMMON="$TMP/proven" sh "$TMP/soft.sh" 2>/dev/null) || :
case "$out" in
	"LEFT=$TMP/proven") ;;
	*) printf 'FAIL  the soft failure arm destroyed an earlier block\x27s proven SHELL_COMMON: %s\n' "$out"; fail=1 ;;
esac

#     Handed nothing, it must leave nothing — the half that keeps a tree which
#     failed to load from being exported (gh-resolve-skills#8).
out=$(cd "$TMP" && env -u CLAUDE_PLUGIN_ROOT -u SHELL_COMMON HOME="$NOWHERE" \
	sh "$TMP/soft.sh" 2>/dev/null) || :
[ "$out" = "LEFT=UNSET" ] || {
	printf 'FAIL  the soft failure arm left a tree exported: %s\n' "$out"
	fail=1
}

if [ "$fail" -eq 0 ]; then
	printf 'ok    no caller-controlled defaults; %s stops at tier 5 against a planted cwd copy, against a PATH imposter, and exports nothing either way\n' "$SITE"
	printf 'ok    6 soft board-sync loaders: six steps in order, warn-and-continue naming the path, and a failure arm that restores rather than clears\n'
fi
exit "$fail"
