# gh-pr:merge — Step 1 argument rules

Positionals `<pr-number> [rebase|squash|merge] [remote]`. `references/...` paths
below are relative to `skills/merge/`, the same way SKILL.md writes them.

- `pr-number` — required, positive integer. Missing/invalid → usage pointer, stop.
- `strategy` — default `rebase`; one of `rebase`/`squash`/`merge`. Other → print allowed values, stop.
- `remote` — default `origin`. Bind `TARGET_REPO` **and** `TARGET_HOST` from
  that one remote URL and `export GH_HOST` per `references/github-target.md`
  (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407). Missing remote → list `git remote -v`, stop (no silent fallback).
- `--auto` / `--finalize` — optional flags, any position after the positionals
  (dEitY719/dotfiles#1707). Semantics and the mutual-exclusion refusal:
  `references/merge-queue.md`.
- `--no-post-verify` — optional flag, any position after the positionals (#90).
  The caller owns post-merge verification (e.g. `gh-flow:wave`'s coordinator
  runs `gh-verify:merged` itself): Step 5 dispatches nothing and prints
  `post-merge verify skipped (caller owns verification)`. Combines with
  `--finalize`; with `--auto` it only covers an immediate merge — a `[QUEUED]`
  PR is finalized later by `gh-pr:merge-train`, which never passes it. Detail:
  `references/post-merge-verify.md`.
