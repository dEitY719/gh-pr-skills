#!/bin/sh
# Regression guard for #14 C2 — the gap inside #3 / PR #4.
#
# The two-tier fallback re-exports SHELL_COMMON at lib/vendor/ when the box has
# no dotfiles checkout. From that moment every `${SHELL_COMMON:-...}` source
# *inside* a vendored file resolves against lib/vendor/ too — so a vendored file
# that sources a sibling nobody vendored misses silently. It is `|| :`-suppressed
# at gh_pr_reply_targeted_review.sh:273 and :735, which is how devx_pr_review_all.sh
# stayed missing without a single error line. Same failure shape as #13: the
# guard fired, so nothing looked wrong.
#
#   sh tests/vendor-sources-resolve.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
VENDOR="$ROOT/lib/vendor/shell-common"
fail=0
n=0

[ -d "$VENDOR/functions" ] || {
	printf 'FAIL  no vendor directory at %s\n' "$VENDOR/functions"
	exit 1
}

# 1. Closure. Every file the vendor set reaches through SHELL_COMMON has to be
#    vendored as well, or the fallback tier resolves it to nothing. That covers
#    every subtree and every source shape — `${SHELL_COMMON:-...}/x.sh`,
#    `$SHELL_COMMON/x.sh`, and guarded ones like `[ -r "$f" ] && . "$f"` with
#    `f=${SHELL_COMMON:-...}/util/x.sh` (#78: gh_host.sh's [ -r ]-guarded
#    util/setup_mode_read.sh went unvendored and this check never saw it).
#    Intentionally dotfiles-only targets, never to be vendored:
#      env/internal.local.sh         per-host config, parsed (not sourced) and
#                                    [ -r ]-guarded; public PCs have none
#      tools/integrations/claude.sh  unvendorable; review's claude --user lane
#                                    [ -f ]-tests it (CLAUDE.md migration debt 2)
ALLOW='env/internal.local.sh tools/integrations/claude.sh'
refs=$(grep -rnoE '\$\{?SHELL_COMMON(:-[^}]*)?\}?/[A-Za-z0-9_./-]+\.sh' "$VENDOR" || :)
while IFS= read -r hit; do
	[ -n "$hit" ] || continue
	loc=${hit%%:\$*}                      # <file>:<line>
	rel=$(printf '%s\n' "$hit" | sed -E 's#.*SHELL_COMMON(:-[^}]*)?\}?/##')
	case " $ALLOW " in *" $rel "*) continue ;; esac
	n=$((n + 1))
	[ -f "$VENDOR/$rel" ] || {
		printf 'FAIL  %s sources %s, which is not vendored — it misses\n' "${loc#"$ROOT"/}" "$rel"
		printf '      silently once SHELL_COMMON points at lib/vendor/\n'
		fail=1
	}
done <<EOF_REFS
$refs
EOF_REFS

[ "$n" -gt 0 ] || {
	# shellcheck disable=SC2016  # literal pattern name, not an expansion
	printf 'FAIL  no ${SHELL_COMMON}/*.sh sources found to check — the\n'
	printf '      pattern has drifted from the vendored code\n'
	fail=1
}

# 2. Standalone install, for real. HOME aimed away from any dotfiles checkout and
#    SHELL_COMMON at the vendor tier exactly as the fallback sets it, so only
#    lib/vendor/ can answer. This is the write path the verdict labels go through.
out=$(HOME=/nonexistent SHELL_COMMON="$VENDOR" sh -c '
	. "$SHELL_COMMON/functions/gh_pr_reply_targeted_review.sh" 2>/dev/null || :
	. "$SHELL_COMMON/functions/devx_pr_review_all.sh" 2>/dev/null || :
	command -v devx_pr_review_all_write_label >/dev/null 2>&1 && echo resolved
' 2>/dev/null) || :
[ "$out" = resolved ] || {
	printf 'FAIL  devx_pr_review_all_write_label unreachable with SHELL_COMMON at the\n'
	printf '      vendor tier — the verdict-label write path is a silent no-op\n'
	fail=1
}

if [ "$fail" -eq 0 ]; then
	printf 'ok    %s vendored SHELL_COMMON source sites resolve inside lib/vendor, standalone\n' "$n"
fi
exit "$fail"
