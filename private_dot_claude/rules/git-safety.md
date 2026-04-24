---
description: Git dangerous operation detection and conflict resolution guidelines
globs: "**"
---

# Git Safety Rules

## Dangerous Operations

The following operations MUST trigger a warning and require explicit user confirmation before execution:

- `git push --force` / `git push -f` (use `--force-with-lease` instead)
- `git reset --hard`
- `git clean -f` / `git clean -fd`
- `git checkout .` / `git restore .` (discards all uncommitted changes)
- `git branch -D` (force-deletes a branch)
- Direct push/commit to protected branches

## Protected Branches

Recognize these as protected branches — never push directly without user confirmation:
- `main`, `master`
- `develop`
- `release/*`

## Force Push Policy

When force push is genuinely required (e.g., after interactive rebase):
1. Always use `--force-with-lease` instead of `--force`
2. Explain the reason to the user before executing
3. Verify no one else has pushed to the branch: `git fetch && git log origin/<branch>..`

## Conflict Resolution Procedure

1. `git fetch origin`
2. `git rebase origin/<base-branch>`
3. Resolve conflicts manually for each file
4. `git add <resolved-files>`
5. `git rebase --continue`
6. Push with `git push --force-with-lease origin <branch>`

## PR Merge Policy

**PRのマージは、ユーザーが明示的に「マージして」「マージお願いします」等と指示した場合にのみ実行すること。**

以下の操作は明示的な指示なしに実行してはならない:
- `gh pr merge`（全オプション含む: `--merge`, `--squash`, `--rebase`）
- GitHub API 経由の PR マージ

「PRを作成してマージまで」「マージまで進めて」等の曖昧な表現では、PRの作成までを行い、マージの実行前にユーザーに確認すること。

## General Principles

- Investigate before destroying — unfamiliar files/branches may be in-progress work
- Prefer `git stash` over discarding uncommitted changes
- Never skip hooks (`--no-verify`) unless the user explicitly requests it
- Always create NEW commits rather than amending, unless explicitly asked
