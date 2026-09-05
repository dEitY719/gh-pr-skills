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

# 1. Closure. Every sibling the vendor set sources through SHELL_COMMON has to
#    be vendored as well, or the fallback tier resolves it to nothing.
for f in $(grep -rhoE '\$\{SHELL_COMMON:-[^}]*\}/functions/[A-Za-z0-9_]+\.sh' \
		"$VENDOR/functions" | sed -E 's#.*/functions/##' | sort -u); do
	n=$((n + 1))
	[ -f "$VENDOR/functions/$f" ] || {
		printf 'FAIL  vendored code sources %s, which is not vendored — it misses\n' "$f"
		printf '      silently once SHELL_COMMON points at lib/vendor/\n'
		fail=1
	}
done

[ "$n" -gt 0 ] || {
	printf 'FAIL  no ${SHELL_COMMON}/functions/*.sh sources found to check — the\n'
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
	printf 'ok    %s vendored cross-sources resolve inside lib/vendor, standalone\n' "$n"
fi
exit "$fail"
