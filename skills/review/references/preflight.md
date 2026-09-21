# Pre-flight Checks — for gh-pr:review

Read from `SKILL.md` Step 2, before any expensive work. Each bullet is a
hard gate: fail it and the run stops with the `exit 1` line quoted.

- PR state must be `OPEN` AND not draft → else exit 1 `PR #<N> is <state>; aborting`.
- `command -v <ai-bin>` for the chosen `--ai` → else exit 1 `Required CLI '<name>' not found in PATH`.
- `--ai opencode` and `--ai hermes` each require `_dotfiles_setup_mode == internal`; otherwise
  exit 1 `--ai <name> is internal-PC only (~/.dotfiles-setup-mode != internal)`.
- `gh auth status` returns 0 → else exit 1 with the gh error line.

CI status is not a gate; self-authored PRs are allowed because no decision is submitted.
