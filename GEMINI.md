# gh-pr — skill index

Eight skills for the GitHub commit-to-merge lifecycle. Each lives in this
extension's `skills/` directory. They are explicitly invoked, never ambient:
load the one that matches the request by reading its `SKILL.md`, then follow it.
Do not load all eight.

| Skill | Read | Use when |
|-------|------|----------|
| `commit` | `@./skills/commit/SKILL.md` | Turning the current changes into one commit in the repo's style, linked to an issue. Never pushes, never opens a PR. |
| `create` | `@./skills/create/SKILL.md` | Opening the PR for this branch — every commit since it diverged from base, not just HEAD. No review, no merge. |
| `review` | `@./skills/review/SKILL.md` | Getting a second opinion on a PR from an external AI CLI, posted as one aggregate comment. Submits no verdict. |
| `reply` | `@./skills/reply/SKILL.md` | Answering every review comment on a PR individually, bots included, and applying the fixes that hold up. |
| `approve` | `@./skills/approve/SKILL.md` | Deciding a PR. The only skill that submits a verdict — and never on a PR you authored. |
| `merge` | `@./skills/merge/SKILL.md` | Merging an approved PR. Rebase by default; refuses un-approved, red CI, drafts, conflicts. |
| `merge-emergency` | `@./skills/merge-emergency/SKILL.md` | Overriding that approval gate in an incident, with a written reason and a follow-up incident issue. CI still gates. |
| `merge-train` | `@./skills/merge-train/SKILL.md` | Walking your own open PRs one at a time, each routed through the `gh-resolve` skills before merging. |

Each skill's `references/` directory holds the detail it loads on demand.
`SKILL.md` says which file to read and when. Do not read `references/` up front.

## What each skill needs

- **All eight** — an authenticated `gh` CLI. Every call carries `GH_HOST` **and**
  `--repo`: `--repo` alone names no server, and on a dual-host login (github.com
  plus a GHES instance) a bare call silently queries the wrong one
  (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407).
- **There is no read-only skill here.** All eight write to a live repo — a
  commit, a PR, a comment, a verdict, a merge. Treat every invocation as a
  mutation.
- **`commit`, `create`** — a feature branch, never the default branch.
- **`review`** — the external AI CLI named by its required `--ai` flag must be
  on `PATH` (`codex`, `agy`, `claude`, `opencode`, `hermes`). The skill
  delegates the reading; it does not review the diff itself.
- **`approve`, `merge`, `merge-emergency`** — permission to submit reviews and
  merge. `merge-emergency` additionally needs admin rights and files an incident
  issue.

## Tool mapping for Gemini CLI

The skills speak in actions. On Gemini CLI these resolve to:

- "Read a file" -> `read_file` / `read_many_files`
- "Create a file" / "edit a file" -> `write_file`, `replace`
- "Run a shell command" -> `run_shell_command` (this is how every `gh` and `git`
  call is made)
- "Search file contents" -> `grep_search`
- "Find files by name" -> `glob`
- "Create a todo" -> `write_todos`
- "Ask the user" -> `ask_user`
- "Dispatch a subagent" -> `invoke_agent` with `agent_name: "generalist"`

The full mapping, including every capability gap and its workaround, lives in
the sibling repo: `https://github.com/dEitY719/harness-skills/blob/main/references/gemini-tools.md`.
This repo owns no copy. Read it when a skill names a tool you do not recognise.
On Antigravity read `antigravity-tools.md` in that same directory instead —
`agy` shares `~/.gemini` but not Gemini CLI's tool names.

## Capability gaps on Gemini CLI

- **`Skill()` has no equivalent.** `merge-train` chains the other skills through
  it. Without a skill-invocation tool, drive the per-PR skills yourself, one PR
  at a time: `gh-resolve:outdated` / `:conflict` / `:ci-fail`, then
  `gh-pr:merge`. The gates are per-PR, so nothing is skipped by doing it by
  hand — only the walking is.
- **Large-diff subagent dispatch.** `approve` and `review` hand a large diff to
  a subagent on Claude Code. Use `invoke_agent`, or read the diff inline. Same
  verdict, more tokens in one context.
- `merge-train` tracks its per-PR progress as todos. Use `write_todos`.

## Safety rules

- **`commit` commits only** — no push, no PR. That split exists so a human can
  inspect the diff before anything leaves the machine.
- **`create` bundles the whole branch**, every commit since it diverged from
  base. A PR that silently drops earlier commits is the bug this prevents.
- **`review` submits no verdict** — no `--approve`, no `--request-changes`, and
  no per-comment replies. One aggregate comment is its entire output surface.
- **`reply` answers each comment individually**, bots included. A single summary
  comment is not a reply pass. It says so on the comments whose fix it rejects.
- **`approve` can never approve a self-authored PR.** GitHub refuses it and so
  does the skill, before the API call.
- **`merge` refuses rather than forces** — un-approved, red CI, draft, or
  conflicted all stop it, and it never swaps merge strategy when the chosen one
  fails.
- **`merge-emergency` is the only bypass, and it pays for itself**: a written
  reason of at least 10 characters, a reason comment on the PR, and a follow-up
  incident issue. It overrides the approval requirement, never the tests.
- **`merge-train` is serial** — one PR at a time, each through the same per-PR
  gates. It never merges something `merge` alone would have refused.
