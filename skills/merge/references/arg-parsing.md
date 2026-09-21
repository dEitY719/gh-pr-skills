# gh-pr:merge — Step 1 argument rules

Positionals `<pr-number> [rebase|squash|merge] [remote]`. `references/...` paths
below are relative to `skills/merge/`, the same way SKILL.md writes them.

- `pr-number` — required, positive integer. Missing/invalid → usage pointer, stop.
- `strategy` — default `rebase`; one of `rebase`/`squash`/`merge`. Other → print allowed values, stop.
- `remote` — default `origin`. Bind `TARGET_REPO` **and** `TARGET_HOST` from
  that one remote URL and `export GH_HOST` per `references/github-target.md`
  (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407). Missing remote → list `git remote -v`, stop (no silent fallback).
