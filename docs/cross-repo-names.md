# gh-pr — cross-repo names

The Phase 3 rename mapping this repo was migrated against, and the step-marker
wire format that moved with it. Summarised in [`README.md`](../README.md) under
"Cross-repo names".

Like `gh-issue-skills` and unlike the Phase 2 repos, this one was migrated
**after** the Phase 3 names were fixed, so every reference to a sibling repo is
written in its final form (#1677 §2):

| Old | New | Lives in |
|-----|-----|----------|
| `gh:commit` | `gh-pr:commit` | this repo |
| `gh:pr` | `gh-pr:create` | this repo |
| `gh:pr-review` / `-reply` / `-approve` | `gh-pr:review` / `:reply` / `:approve` | this repo |
| `gh:pr-merge` / `-merge-emergency` / `-merge-train` | `gh-pr:merge` / `:merge-emergency` / `:merge-train` | this repo |
| `devx:pr-review-all` | `gh-verify:review-all` | `gh-verify-skills` |
| `gh:pr-post-merge-verify` | `gh-verify:post-merge-verify` | `gh-verify-skills` |
| `gh:pr-resolve-ci-fail` / `-conflict` / `-outdated` | `gh-resolve:ci-fail` / `:conflict` / `:outdated` | `gh-resolve-skills` |
| `gh:label-bootstrap` | `gh-setup:label-bootstrap` | `gh-setup-skills` |
| `gh:issue-create` | `gh-issue:create` | `gh-issue-skills` |
| `gh:issue-flow` | `gh-flow:issue` | `gh-flow-skills` |
| `ai-worktree:teardown` | `session:worktree-teardown` | `session-skills` |

The last two rows are references to repos that did not exist when this migration
ran. Writing them in final form now is cheaper than a second pass later, and
`gh-flow-skills` reads `gh-pr:create` / `gh-pr:commit` straight out of this
repo's decision.

Unlike `gh-issue-skills`, the step-marker wire format **did** move here. `create`
prints `[step:gh-pr-create/<id>] OK` and `commit` prints
`[step:gh-pr-commit/<id>] OK`; dotfiles #1677 F-8 added matching
`skill_step_catalog.yml` keys alongside the old `gh-pr` / `gh-commit` ones,
which stay to guard the un-deleted dotfiles originals until Phase 4. The step
IDs inside the markers are unchanged.
