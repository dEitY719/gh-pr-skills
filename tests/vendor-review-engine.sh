#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir "$tmp/bin"
printf '#!/bin/sh\ncat >/dev/null\nprintf "Verdict: LGTM\\n"\n' > "$tmp/bin/codex"
chmod +x "$tmp/bin/codex"
printf 'review prompt\n' > "$tmp/prompt"
export PATH="$tmp/bin:$PATH" DOTFILES_ROOT="$tmp/no-dotfiles" CLAUDE_PLUGIN_ROOT="$root"
export SHELL_COMMON="$root/lib/vendor/shell-common" DOTFILES_FORCE_INIT=1
export TEST_REVIEW_PROMPT="$tmp/prompt"
bash -c '
set -eu
. "$SHELL_COMMON/functions/gh_pr_review.sh"
. "$SHELL_COMMON/lib/devx_pr_review_all.sh"
command -v gh_pr_review >/dev/null
command -v ai_fanout_run >/dev/null
command -v devx_pr_review_all_fanout >/dev/null
result=$(ai_fanout_run "" 30 codex:thorough bash -c '\'' . "$SHELL_COMMON/lib/ai_cli_run.sh"; _ai_cli_run codex "$TEST_REVIEW_PROMPT" '\'')
[ "$result" = codex:thorough:ok ]
CLAUDE_ENABLED_ACCOUNTS=example
export CLAUDE_ENABLED_ACCOUNTS
[ "$(_ai_cli_resolve_claude_account example)" = "$HOME/.claude-example" ]
'
printf 'ok    standalone review engine loads and executes a stub CLI lane\n'
for symbol in _ai_cli_run _ai_cli_mktemp_prompt _ai_cli_estimate_tokens _ai_cli_argv_prompt_or_fail _ai_cli_opencode_model; do
    grep -q "^${symbol}\\(\\)" "$SHELL_COMMON/lib/ai_cli_run.sh"
done
if grep -REn '_gh_pr_review_(run_ai|mktemp_prompt|estimate_tokens|argv_prompt_or_fail|opencode_model)' "$root/skills/review"; then
    printf '%s\n' 'review skill still names removed engine helpers' >&2
    exit 1
fi
