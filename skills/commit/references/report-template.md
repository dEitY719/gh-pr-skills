# gh-pr:commit — Step 6 Report Format

성공 시:

```
[OK] Committed <short-hash>: <subject line>
[OK] Closes #<N>
[OK] Board sync: issue #<N> -> "In progress" (or [SKIP]: <why>)
Next: /gh-pr:create
```

Drop the `Closes` row when Step 2 resolved no issue number, and drop the
`Board sync:` row with it — Step 5 skips the sync entirely when no issue footer
was written. The `[SKIP]` reasons are the ones `references/board-sync.md`
already enumerates: no projectV2 board, helper unavailable, or a Status already
outside `Backlog`.

The `Board sync:` row mirrors `gh-pr:create`'s and serves the same purpose — a
defense-in-depth visual checklist (issue dEitY719/dotfiles#747). Its absence from a
transcript is the regression signal that Step 5 was silently skipped.

`Next:` is `/gh-pr:commit` again, not `/gh-pr:create`, when the Constraints
split rule left uncommitted changes behind.

실패 시 — a Step 4 secret-looking file, a split the user declined, or a commit
hook that failed:

```
[FAIL] <reason>
Next: <the single command that clears it>
```

Nothing is committed on a `[FAIL]`, and the working tree is left as it was
found. `--no-verify` is never the way out of a failing hook (Step 4).
