# gh-pr:merge-emergency — Step 1 argument rules

Positionals `<PR> <reason> [remote]`. `references/...` paths below are relative
to `skills/merge-emergency/`, the same way SKILL.md writes them.

- `remote` — default `origin`; bind `TARGET_REPO` + `TARGET_HOST` from that URL and export `GH_HOST` per `references/github-target.md` (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407) **first**, before any `gh` call below; missing → `git remote -v` and stop.
- `PR` — required; omitted → `GH_HOST="$TARGET_HOST" gh pr view --json number` on current branch, else stop. No `--repo` here: `gh` rejects it without a PR argument (`references/github-target.md` → "Exception").
- `reason` — **required**, ≥10 chars, citing an incident/ticket ID or concrete user impact; vague (`"urgent"`, `"fix"`) → refuse. Examples: `references/help.md`.
