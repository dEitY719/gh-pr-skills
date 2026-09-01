# gh-pr:create — Step 8 Report Format

성공 시:

```
[OK] PR: https://github.com/owner/repo/pull/<N>
[OK] Board sync: PR card -> "In review" (or [SKIP]: hook auto-skip / no projectV2 / helper unavailable)
Next: /gh-pr:reply (after CI green) — replies to review comments
```

The `Board sync:` row is a defense-in-depth visual checklist (issue
#747) — its absence in conversation transcripts is a regression signal
that Step 7 was silently skipped.

After printing the report block, emit the report step-completion
marker so the step-skip guard recognizes the skill finished:
`printf '[step:gh-pr-create/report] OK\n'`.

Step 1b empty-range / on-base-branch stops, Step 1a `rc=2`/`rc=3`, or
Step 4.5 lint failure:

```
[FAIL] <one-line reason>
Next: <recovery — e.g. switch branch, fix lint, drop conflicting flag>
```

No additional summary — the user opens GitHub directly from the URL.
