# Git Conventions

**適用範囲**: すべての git 操作（ブランチ作成 / コミット / Issue・PR 作成）に適用する。安全操作（force push・reset --hard 等）の制約は `~/.claude/rules/git-safety.md` を参照。

本ファイルは旧 `git-branching.md` / `github-conventions.md` / `commit-conventions.md` を 1 本に統合したもの。

## ブランチ戦略

- **戦略判定**: `develop` ブランチが有れば **GitFlow**、無ければ **GitHub Flow**（`git for-each-ref --format='%(refname)' refs/heads/develop 'refs/remotes/*/develop' | grep -q .`）。`git branch -a` を grep する方式は使わない。行頭の空白や worktree の `+` に左右されるうえ、`feature/develop` のような枝を GitFlow と誤判定する
- **GitFlow**: `feature/*`（分岐元=develop, マージ先=develop）/ `release/*`（分岐元=develop, マージ先=main+develop）/ `hotfix/*`（分岐元=main, マージ先=main+develop）
- **GitHub Flow**: `feature/*`・`hotfix/*`（分岐元=main, マージ先=main、PR 経由）
- **「分岐元」と「マージ先」を混同しない**: ブランチを切るときに使うのが分岐元、PR のベースに指定するのがマージ先。`release/*` は develop から切って main へ PR するため、両者が食い違う唯一のケースになる
- **命名**: 小文字ハイフン区切り。簡潔かつ内容が分かる名前にし、**Issue があれば**番号を含める。例: `feature/123-add-user-auth`
- **有効 prefix**: 戦略が定義するのは `feature/` `hotfix/`（`release/` は GitFlow のみ）。補助 prefix `bugfix/` `chore/` は分岐元とマージ先を `feature/` と同じフローに従わせる

## コミット

- **Conventional Commits**: `feat:` / `fix:` / `refactor:` / `docs:` / `test:` / `chore:`
- 件名は**英語・72 文字以内**
- `Co-Authored-By` トレイラーを必ず付与する
- 1 コミット = 1 論理変更（大きな変更は分割する）

## Issue / PR

- **言語**: Issue・PR のタイトルと本文は**日本語**が既定。英語にするのは英語圏 OSS・米国企業リポジトリへの投稿、またはユーザーが明示指定した場合のみ
- **PR フォーマット**: タイトルは変更内容を 70 文字以内で要約。本文は `## 概要` / `## テスト計画` のセクション構成
