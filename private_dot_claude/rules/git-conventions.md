# Git Conventions

**適用範囲**: すべての git 操作（ブランチ作成 / コミット / Issue・PR 作成）に適用する。安全操作（force push・reset --hard 等）の制約は `~/.claude/rules/git-safety.md` を参照。

本ファイルは旧 `git-branching.md` / `github-conventions.md` / `commit-conventions.md` を 1 本に統合したもの。

## ブランチ戦略

- **戦略判定**: `develop` ブランチが有れば **GitFlow**、無ければ **GitHub Flow**（`git branch -a | grep -E '(^|/)develop$'`）
- **GitFlow**: `feature/*`（base=develop, merge=develop）/ `release/*`（base=develop, merge=main+develop）/ `hotfix/*`（base=main, merge=main+develop）
- **GitHub Flow**: `feature/*`・`hotfix/*`（base=main, merge=main via PR）
- **命名**: 小文字ハイフン区切り、Issue 番号を含める。例: `feature/123-add-user-auth`。有効 prefix: `feature/` `hotfix/` `release/` `bugfix/` `chore/`

## コミット

- **Conventional Commits**: `feat:` / `fix:` / `refactor:` / `docs:` / `test:` / `chore:`
- 件名は**英語・72 文字以内**
- `Co-Authored-By` トレイラーを必ず付与する
- 1 コミット = 1 論理変更（大きな変更は分割する）

## Issue / PR

- **言語**: Issue・PR のタイトルと本文は**日本語**が既定。英語にするのは英語圏 OSS・米国企業リポジトリへの投稿、またはユーザーが明示指定した場合のみ
- **PR フォーマット**: タイトルは変更内容を 70 文字以内で要約。本文は `## 概要` / `## テスト計画` のセクション構成
