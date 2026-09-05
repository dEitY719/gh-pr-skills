# gh-pr — provenance

Where these skills came from, what was deliberately held fixed in the move, and
which migration phase this repo belongs to. Summarised in
[`README.md`](../README.md) under "Provenance".

These skills were extracted from
[`dEitY719/dotfiles`](https://github.com/dEitY719/dotfiles)
(`claude/skills/{gh-commit,gh-pr,gh-pr-review,gh-pr-reply,gh-pr-approve,gh-pr-merge,gh-pr-merge-emergency,gh-pr-merge-train}`)
as a content snapshot — no history rewriting. That directory list records where
the skills came from; it is not a live path. `~/dotfiles/claude/skills/` was
deleted outright rather than kept until Phase 4 as dEitY719/dotfiles#1410 NF-1 / NF-3 planned, so
nothing in this repo may resolve against it. Behaviour is unchanged from the
snapshot; only the namespace moved, from `gh:` to `gh-pr:`, and the directory
names lost their now-redundant prefixes.

Because behaviour was held fixed, some coupling to the dotfiles checkout came
across with it — several skills source `shell-common/functions/*.sh`, and `merge`
reads a post-merge dispatch block. Both are enumerated in
[`CLAUDE.md`](CLAUDE.md) → "Known migration debt"; the dispatch block is settled
(vendored under `lib/vendor/`), the `shell-common` coupling is Phase 4 work.

This is Phase 3 of the dEitY719/dotfiles#1410 migration, shared with `gh-issue-skills`
and `gh-flow-skills`. `packaging-skills` was Phase 0, and `harness-skills` was
Phase 1 and is the sibling that owns the shared assets this repo links to.
