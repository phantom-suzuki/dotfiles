# Git Conventions

ブランチ作成・コミット・Issue / PR 作成に適用する。危険な操作の扱いは `git-safety.md`。

## ブランチ戦略

- `develop` ブランチが有れば GitFlow、無ければ GitHub Flow。判定は `git for-each-ref --format='%(refname)' refs/heads/develop 'refs/remotes/*/develop' | grep -q .` で行う（`git branch -a` の grep は `feature/develop` を誤判定する）
- GitFlow: `feature/*`（develop から切り develop へ）/ `release/*`（develop から切り main と develop へ）/ `hotfix/*`（main から切り main と develop へ）
- GitHub Flow: `feature/*` と `hotfix/*` は main から切り、PR で main へ
- 分岐元（ブランチを切る元）とマージ先（PR のベース）を混同しない。`release/*` だけ両者が異なる
- 命名は小文字ハイフン区切り。Issue があれば番号を含める。例: `feature/123-add-user-auth`。補助 prefix の `bugfix/` `chore/` は `feature/` と同じ流れに従う

## コミット

- Conventional Commits（`feat:` / `fix:` / `refactor:` / `docs:` / `test:` / `chore:`）。件名は英語で 72 文字以内
- 1 コミット 1 論理変更。`Co-Authored-By` トレイラーを付ける

## Issue / PR

- タイトルと本文は日本語が既定。英語圏の OSS や米国企業のリポジトリ、またはユーザーの指定があるときだけ英語
- PR タイトルは変更内容を 70 文字以内で要約。本文は `## 概要` と `## テスト計画`。AI が実行できない人手の工程（権限付与・実機確認など）があれば節を立てて書く
- PR は必ず 1 つ以上の Issue を `Closes` で閉じる。`Refs` で逃げない。PR で AC を満たしきれない Issue は分割し、Feature なら Task を Sub-issues にして PR はその Task を閉じる。マージ後にしかできない AC（実データ投入・実機確認）も別 Task に切り出す
