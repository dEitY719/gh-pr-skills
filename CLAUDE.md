# gh-pr-skills — Contributor Guidelines

This file is the AI context document for this repo. `AGENTS.md` is a symlink to
it, so Claude Code, Codex, Gemini CLI, and every other harness read the same
text. Edit `CLAUDE.md`; never replace the symlink with a second copy.

## What this repo is

A single-plugin skill marketplace. The plugin is named `gh-pr` and it owns the
**branch half** of the GitHub workflow — everything from the moment there is
something to commit until the PR is merged and its branch is gone:

| Skill | Artifact it produces | Role |
|-------|----------------------|------|
| `commit` | a git commit | Writes one commit in the repo's own style and links the issue. Never pushes, never opens a PR. |
| `create` | a Pull Request | Opens the PR from every commit since the branch diverged from base — not just HEAD. No review, no merge. |
| `review` | one PR comment | Delegates a second opinion to one external AI CLI and posts a single aggregate comment. Submits no verdict. |
| `reply` | per-comment replies + fixes | Answers every review comment individually, bots included, and applies the fixes that hold up. |
| `approve` | a review verdict | The only skill that submits one. Blockers become `request changes`; the rest become follow-up issues. |
| `merge` | a merged PR | Rebase by default. Refuses un-approved PRs, red CI, drafts, conflicts. |
| `merge-emergency` | a merged PR + an incident issue | The audited admin override of that refusal. CI still gates. |
| `merge-train` | several merged PRs | Walks your own open PRs one at a time, routing each through the `gh-resolve` skills first. |

All eight write to a live GitHub repo — there is no read-only skill here, unlike
`gh-issue-skills` where `read` is the safe one. That is why every safety contract
below is a hard rule rather than a preference.

The skills were extracted from `dEitY719/dotfiles`
(`claude/skills/{gh-commit,gh-pr,gh-pr-review,gh-pr-reply,gh-pr-approve,gh-pr-merge,gh-pr-merge-emergency,gh-pr-merge-train}`)
as a content snapshot at source commit
`96c90bc8d961d51d9c3286dae730e8b928afdfc8` — no history rewriting. Those
directories are a historical origin, not a live path: `~/dotfiles/claude/skills/`
has since been deleted outright rather than kept until Phase 4 as
#1410 NF-1 / NF-3 planned, so nothing here may resolve against it (#14 C4).
This is Phase 3 of dotfiles #1410, alongside the two
sibling repos `gh-issue-skills` and `gh-flow-skills`; `packaging-skills` was
Phase 0 and `harness-skills` was Phase 1 and owns the shared assets.

## Layout: root manifests, one flat `skills/`

This repo deliberately does **not** use the nested `plugins/<name>/skills/`
"mono" layout. Every harness manifest sits at the repo root and points at a
single flat `./skills/` directory:

```
.claude-plugin/{marketplace,plugin}.json   Claude Code
.codex-plugin/plugin.json                  Codex
.kimi-plugin/plugin.json                   Kimi CLI
.hermes-plugin/{plugin.yaml,__init__.py}   Hermes Agent
.opencode/plugins/gh-pr.js                 OpenCode
.agents/plugins/marketplace.json           Antigravity
gemini-extension.json + GEMINI.md          Gemini CLI
skills/<name>/SKILL.md                     the skills themselves
```

Only Claude Code understands the nested mono layout. The other five harnesses
resolve manifests at the repo root and a skills tree at `./skills/`, so nesting
would silently cut this plugin down to Claude-Code-only. **Do not move the
manifests under a `plugins/` directory.**

## Shared assets live elsewhere — link, never copy

This repo owns none. Both belong to `dEitY719/harness-skills`:

**1. Per-harness tool mappings** (`references/*-tools.md` there, dotfiles #1410
F-5). Do not create a `references/` directory at this repo's root. If a doc here
needs a mapping, link to
`https://github.com/dEitY719/harness-skills/blob/main/references/<harness>-tools.md`.
One tool rename must stay one edit, not fifteen (NF-2). The single sanctioned
mirror is the condensed summary inside `.kimi-plugin/plugin.json`'s
`skillInstructions`, because Kimi CLI cannot read a reference file at load time;
keep it short and keep it pointing upstream.

**2. The reusable CI workflow** (`.github/workflows/skill-check.yml` there,
D-10). This repo's `validate.yml` calls it with `plugin-name: gh-pr`, a raised
`max-skill-lines`, and an `allow-emoji-paths` list. Do not fork it into a
standalone workflow — a check added upstream should apply here on the next run,
which is the whole point.

## Rules for changing skills

- **Skill directory name is the identity.** `skills/<name>/` must match the
  `name:` field in that skill's `SKILL.md` frontmatter, and that field is the
  **bare** name (`merge`), never namespaced (`gh-pr:merge`). CI fails on a `:`
  in the name. The harness supplies the `gh-pr:` prefix at invocation time.
- **The old `gh-pr-` / `gh-` prefixes are gone and stay gone.** They stuttered
  against the namespace (`/gh-pr:gh-pr-merge`), so the migration dropped them
  (#1410 F-4). Do not reintroduce them, and do not shorten the remaining names
  further — `merge-emergency`, not `emergency`.
- **`gh:pr` became `create`, not the empty string.** It is the one skill whose
  old directory name was identical to the plugin name, so the prefix rule had
  nothing left to strip. The name says what the skill does — open a PR — and
  pairs with `gh-issue:create` so the same verb means "file the thing" in both
  plugins (#1677 §3). Do not rename it to `open`, `pr`, or `pr-create`;
  `gh-flow-skills` writes `gh-pr:create` into its hooks.
- **Invocation form in prose is namespaced.** Body text referring to a skill as
  a command writes `/gh-pr:merge`. The old colon form (`gh:pr-merge`) and the
  dash-form aliases (`/gh-pr-merge`) were both dropped in the migration — do not
  reintroduce either.
- **Cross-repo references use the *new* namespace, not the old one.** Unlike the
  Phase 2 repos, this one was migrated after the Phase 3 names were fixed, so
  `gh-verify:review-all`, `gh-verify:post-merge-verify`, `gh-resolve:ci-fail` /
  `:conflict` / `:outdated`, `gh-setup:label-bootstrap`, `gh-issue:create`,
  `gh-flow:issue`, and `session:worktree-teardown` are written here in their
  final form (#1677 §2). Do not "correct" them back to `gh:pr-merge` /
  `devx:pr-review-all`.
- **Marker strings are a wire format, not an invocation form.** `create` prints
  `[step:gh-pr-create/<id>] OK` and `commit` prints `[step:gh-pr-commit/<id>] OK`.
  Those lines are matched verbatim by dotfiles'
  `claude/hooks/skill_completion_guard.py` against its `skill_step_catalog.yml`
  keys. Unlike `gh-issue-skills`, these **were** renamed here: `gh-pr` +
  `create` does not spell the old `gh-pr` key, so dotfiles #1677 F-8 added
  `gh-pr-create` and `gh-pr-commit` as new catalog keys alongside the old
  `gh-pr` / `gh-commit` ones, which still guard the un-deleted dotfiles
  originals until Phase 4. The step IDs inside the markers are unchanged, and
  NF-4 requires the new keys' `required` lists to match the old ones exactly.
  The `<!-- ai-metrics -->` footer markers are likewise an interop format shared
  with `gh-issue-skills`, not something to renamespace.
- **Progressive disclosure.** `SKILL.md` should stay under 100 lines and name
  which `references/` file to read and when. Four files arrived over that limit
  and CI is currently pinned to `max-skill-lines: 197` to admit them — see
  "Known migration debt" below. Do not add lines to those four.
- **Description budget.** CI sums every skill description and fails past 5,440
  characters — Codex's context budget. The current total is 1,814. Keep new
  descriptions tight anyway.

## Safety contracts

These are acceptance criteria carried over from dotfiles, not advice:

- **Every `gh` call carries `GH_HOST` and `--repo`, both resolved from the same
  remote URL.** A bare `gh pr view <N>` follows gh CLI's own
  `gh repo set-default`, not git's `origin`. On a dual-host login (github.com
  plus GHES) that succeeds silently against the wrong server (dotfiles #1403 /
  #1407). Never work around a surprising `gh` result by dropping `--repo` or
  switching remotes — verify the host first.
- **`commit` commits only.** It never pushes and never opens a PR. That split
  exists so a human can inspect the diff, squash attempts, and choose the commit
  style before anything leaves the machine.
- **`create` bundles the whole branch.** Every commit since the divergence from
  base, not just HEAD — a PR that silently drops earlier commits is the bug this
  rule prevents.
- **`review` submits no verdict.** No `--approve`, no `--request-changes`, no
  per-comment replies. One aggregate comment is its entire output surface;
  verdicts are `approve`'s job and per-comment work is `reply`'s.
- **`reply` answers each comment individually, bots included.** A single summary
  comment is not a reply pass. It applies the fixes that hold up and says so on
  the ones it rejects.
- **`approve` can never approve a self-authored PR.** GitHub refuses it and so
  does the skill, before the API call.
- **`merge` refuses rather than forces.** Un-approved, red CI, draft, or
  conflicted all stop it, and it never swaps merge strategy when the chosen one
  fails. `--delete-branch` always.
- **`merge-emergency` is the only bypass, and it pays for itself.** A written
  reason of at least 10 characters, a reason comment on the PR, and a follow-up
  incident issue. CI still gates — the override is of the approval requirement,
  not of the tests.
- **`merge-train` is serial.** One PR at a time, each through the same per-PR
  gates. It never merges something `merge` alone would have refused.

## Known migration debt

Items 1 and 2 came across verbatim because #1410's Non-Goals forbid changing
behaviour during a placement-and-naming migration; item 1 is still Phase 4 work
and item 2 is mitigated but not gone. Item 3 is settled, item 4 is a standing
decision, and item 5 is owned upstream — all kept here so the "what does this
repo still need from dotfiles" answer stays in one place:

1. **Four `SKILL.md` files exceed the 100-line progressive-disclosure limit**
   (`merge` 197, `merge-train` 148, `reply` 143, `review` 110). CI is pinned to
   197 to admit them. The fix is to extract detail into each skill's
   `references/`, not to raise the pin.
2. **Several skills source dotfiles' `shell-common/functions/*.sh`** —
   `gh_project_status.sh`, `gh_pr_review.sh`, `gh_host.sh`,
   `gh_pr_merge_train.sh`, `gh_pr_edit_safe.sh`, and others. #3 / PR #4 made
   every call site two-tier — live dotfiles first, then the copies under
   `lib/vendor/shell-common/functions/`, re-exporting `SHELL_COMMON` at the
   copy — so a standalone install degrades instead of failing. That fallback is
   only as complete as the vendor set: a vendored file that sources a
   *non*-vendored sibling misses silently once `SHELL_COMMON` points at
   `lib/vendor/`. `devx_pr_review_all.sh` was that hole
   (`gh_pr_reply_targeted_review.sh:273`, `:735`) and is now vendored too
   (#14 C2); `tests/vendor-sources-resolve.sh` is the regression guard — it
   asserts that closure and sources the verdict-label write path with `HOME`
   aimed away from any dotfiles checkout, so re-opening the hole fails loudly
   instead of silently. Anything still reached only from `$HOME/dotfiles` is
   listed in
   items 4 and 5; the one unvendorable case is
   `shell-common/tools/integrations/claude.sh`, which `review`'s
   `--ai claude --user` / `--ai opencode` / `--ai hermes` lanes now `[ -f ]`-test
   and refuse on rather than aborting the step.
3. **Settled (#13).** `merge`'s Step 5 used to read its dispatch block from
   `${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md`,
   on the premise that dotfiles kept its originals until Phase 4. It did not —
   `~/dotfiles/claude/skills/` is gone and the skill was renamed on the way out
   — so the `[ -r ]` guard silently skipped a 394-line verification gate on
   every merge. The block is now vendored at
   `lib/vendor/gh-verify/post-merge-verify/dispatch.sh.md` (SSOT:
   `gh-verify-skills` `skills/post-merge-verify/references/dispatch.sh.md`) and
   read through the same two-tier idiom as item 2, with `GH_VERIFY_ROOT` as the
   first tier. For a repo that IS in the watched-repos registry, a dispatch
   that will not stage or will not source is now a loud `[FAIL]`, not a
   `[WARN]`: it is a broken install, not an opt-out. An unregistered repo stays
   byte-silent, as designed. `tests/pmv-dispatch-resolves.sh` is the regression
   guard — run `sh tests/pmv-dispatch-resolves.sh` after touching either side of
   that path pair. CI shellchecks it but does not execute it: `validate.yml`
   owns no CI logic of its own, so a test *runner* has to land in
   `harness-skills`' reusable `skill-check.yml` before any repo here gets one.
4. **Two dotfiles files are still cited, deliberately un-vendored.**
   `shell-common/tools/custom/pr_merge_train_cron.sh` (`merge-train`'s
   unattended trigger) and `shell-common/functions/gh_audit_builtin_workflows.sh`
   (`merge/references/board-policy.md`'s "see also") appear only as prose. No
   skill sources or executes either, so neither can break a run the way item 3
   did; the cron script is host setup that belongs in dotfiles, and the audit
   function is a manual pointer. Revisit only if a skill starts executing one.
5. **One dead skill name survives in vendored code, and the fix is upstream.**
   `lib/vendor/shell-common/functions/gh_pr_lint.sh:239` prints
   `FAILED — fix lint errors and re-run /gh:pr` to the user; `/gh:pr` was
   renamed to `/gh-pr:create` in the split. It is the only old name in this repo
   that reaches a human. The file is vendored, SSOT
   `dEitY719/dotfiles shell-common/functions/gh_pr_lint.sh:235`, so correct it
   there and re-copy — hand-editing the vendored copy is reverted by the next
   sync. Message string only; nothing dispatches on it. Every other old name
   here is the rename-mapping documentation "Cross-repo references" above
   forbids "correcting".

## Emojis

Banned repo-wide, with one exception: the chart / person / robot glyphs of the
dotfiles ai-metrics footer (#317 F-2 / PR #320 / #367). That footer is a wire
format the skills emit, so the eight reference files that specify it have to
show the real glyphs. They are enumerated in `.github/workflows/validate.yml`
under `allow-emoji-paths`. Nothing else may carry one.

## Harness portability

These eight are `gh` CLI calls, `git` calls, and file writes, so they port
cleanly with two exceptions:

- **`Skill()` has no equivalent outside Claude Code.** `merge-train` chains the
  other skills through it. Elsewhere, run the per-PR skills directly —
  `gh-resolve:outdated` / `:conflict` / `:ci-fail`, then `gh-pr:merge` — one PR
  at a time.
- **Subagent dispatch.** `approve` and `review` hand a large diff to a subagent.
  Without one they read the diff inline: slower, same verdict.

If you add a step that depends on a Claude-Code-only capability, say so in
`README.md`'s harness-support matrix and open an issue against `harness-skills`
so its `references/*-tools.md` gain the fallback.

## Version bumps

The version appears in seven manifests: `.claude-plugin/marketplace.json`,
`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`,
`.kimi-plugin/plugin.json`, `.hermes-plugin/plugin.yaml`,
`gemini-extension.json`, and `package.json`. CI checks that they agree — bump
all of them together. Versioning is independent per repo (#1410 D-9); this repo
does not release in lockstep with its siblings.
