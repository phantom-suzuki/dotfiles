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

## Squash Merge 後のローカル Main 同期

PR を squash merge すると、ローカルの `main` が `origin/main` と「分岐している」と表示される（squash 前の複数コミットと squash 後の 1 コミットで、内容は同じだがハッシュが異なるため）。この状態を解消するときの手順:

1. **内容が一致しているかを先に確認する**: `git diff origin/main..main --stat` が空であることを確認する。空でなければ別の変更が混ざっている可能性があるため、`git reset` を実行しない
2. **`git reset --hard` は使わない**。`--mixed`（既定）を使う: `git checkout main && git reset --mixed origin/main`。`--mixed` は HEAD とインデックスだけを更新し、作業ツリーのファイルには触れないため、追跡ファイルの変更を問答無用で失う `--hard` のリスクを避けられる
3. squash マージ元の feature ブランチは `git branch -d` が「未マージ」と誤検知して失敗する（squash で祖先関係が切れるため）。手順 1 で内容一致を確認済みなら `git branch -D` で削除してよい（Dangerous Operations の確認は依然必要）

## PR Merge Policy

**PRのマージは、ユーザーが明示的に「マージして」「マージお願いします」等と指示した場合にのみ実行すること。**

以下の操作は明示的な指示なしに実行してはならない:
- `gh pr merge`（全オプション含む: `--merge`, `--squash`, `--rebase`）
- GitHub API 経由の PR マージ

「PRを作成してマージまで」「マージまで進めて」等の曖昧な表現では、PRの作成までを行い、マージの実行前にユーザーに確認すること。

**マージ実行前に、ローカルに未 push のコミットが残っていないか必ず確認する**: `git status` で作業ツリーが clean であること、`git log @{u}..HEAD` （追跡先ブランチとの差分）が空であることを確認する。未 push のコミットが残っている状態でマージすると、squash マージの内容からその変更が抜け落ちる（2026-07-08 の実インシデント: self-review の修正コミットを push する前に PR がマージされ、squash コミットに反映されず、git reflog からの復旧が必要になった）。

## General Principles

- Investigate before destroying — unfamiliar files/branches may be in-progress work
- Prefer `git stash` over discarding uncommitted changes
- Never skip hooks (`--no-verify`) unless the user explicitly requests it
- Always create NEW commits rather than amending, unless explicitly asked
