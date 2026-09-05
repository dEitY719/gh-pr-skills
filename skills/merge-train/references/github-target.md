# gh-pr:merge-train — GitHub target binding (dEitY719/dotfiles#1403, dEitY719/dotfiles#1407)

Run this in Step 1, **before any `gh` call**.

## Bind the target

Resolve the host **and** the repo from one and the same remote URL, then export
the host so every sourced helper and every delegated atom skill inherits it:

```bash
REMOTE="${REMOTE:-origin}"
_SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
[ -f "$_SC/functions/gh_host.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_host.sh" ] || {
    printf '[gh-pr:merge-train] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_host.sh"
REMOTE_URL=$(git remote get-url "$REMOTE") || exit 1
TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
export GH_HOST="$TARGET_HOST"
export TARGET_REPO TARGET_HOST
```

- `gh_host.sh` is the SSOT for the URL to host mapping — never copy a regex or a
  domain list into this file.
- `_gh_resolve_host` (setup-mode to host) is the fallback used **only** when
  there is no remote URL to parse.
- An unknown remote stops the run with `git remote -v` — never a silent
  `origin` fallback, which would mask a typo and target the wrong repo.
- Never continue with an empty `TARGET_HOST` — that is exactly the silent
  misroute state of dEitY719/dotfiles#1403.

## When an explicit `owner/repo` is given

The cron dispatcher always passes one (`/gh-pr:merge-train acme/dotfiles`), so
that positional wins over the parsed slug:

```bash
TARGET_REPO="${1:-$TARGET_REPO}"
export TARGET_REPO
```

The **host is still read from the remote URL**, never from the slug — a slug
carries no host, which is the whole of dEitY719/dotfiles#1403. If the named repo does not live
on the resolved host, the run stops rather than guessing.

## Host targeting rule

Every `gh` call in this skill — SKILL.md and `references/` alike — runs as:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`gh api` is the one exception to the flag: it has no `--repo`, so the repo goes
into the path instead — `gh api "repos/$TARGET_REPO/..."`, never a literal
placeholder.

## Why it matters more here than in a single-PR skill

`gh-pr:merge` misrouted reads one PR from the wrong server and stops. This
skill misrouted would enumerate **another repo's** open PRs and then rebase and
merge against them, one after another, unattended. The binding is what makes
the queue in Step 2 and the merges in Step 4 provably the same repo.

## Threading it into the atom skills

The atoms (`gh-resolve:outdated`, `-conflict`, `-ci-fail`, `gh-pr:merge`)
each re-resolve their own target from their `[remote]` positional, exactly as
the `gh-flow:issue` chain does (dEitY719/dotfiles#1405). Pass `<remote>` explicitly whenever the
train was invoked with a non-default remote, so the whole train lands on one
server:

```
Skill(gh-pr:merge, "<N> rebase <remote>")
```

With the default `origin` the positional may be omitted — the atoms already
default to it.
