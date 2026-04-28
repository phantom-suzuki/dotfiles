---
description: Dependabot / Renovate の bot 作成 PR を専用観点でレビューするスキル。バージョン bump で必要な追従更新が行われているか（go.mod / CI workflow / Makefile / docs 等の version 文字列ドリフト）を決定論的に grep し、レポートコメントを PR に upsert する。任意で release notes / breaking changes も要約。「dependabot レビュー」「renovate レビュー」「bot PR チェック」「依存性 PR を見て」等の依頼時に使用。
---

# Skill: /dependabot-review

## 概要

Dependabot / Renovate の bot 作成 PR を専用観点でレビューする軽量スキル。
**主目的は「単一ファイル更新で済むはずがない bump で追従漏れが起きていないか」を決定論的に検知すること**。

LLM レビュー（CodeRabbit）と棲み分け、確定的な grep ベースの検知を提供する。
追従更新が必要なら、**ユーザー承認後** に **別ブランチで** 追従 PR を作成する（元 bot PR には触らない — rebase で消える/競合するリスク回避）。

## パラメータ

| パラメータ | デフォルト | 説明 |
|-----------|----------|------|
| `<PR番号>` | なし | レビュー対象の PR 番号。未指定なら open な dependabot PR を列挙して選択させる |
| `--release-notes` | false | リリースノート / breaking changes を取得して要約する |
| `--repo <owner/repo>` | カレントリポジトリ | gh CLI に渡すリポジトリ |
| `--no-comment` | false | PR にコメント投稿しない（dry-run） |

## 前提条件

- `gh` CLI が認証済み
- `jq` が利用可能
- カレントディレクトリがレビュー対象リポジトリの clone（ローカル grep のため）
- bot 作成 PR が対象。サポートする bot author:
  - **Dependabot**: `app/dependabot` / `dependabot[bot]`
  - **Renovate**: `app/renovate-bot` / `renovate[bot]`

## 実行手順

### Step 0: 初期化

1. `gh auth status` で認証確認
2. `git rev-parse --git-dir` でリポジトリ内であることを確認
3. PR 番号未指定なら open な bot PR を列挙:
   ```bash
   gh pr list --search "is:open author:app/dependabot author:app/renovate-bot" \
     --json number,title,headRefName,author
   ```
   結果が複数なら AskUserQuestion で選ばせる、1 件なら自動採用、0 件なら終了

### Step 1: PR メタ取得・bump 抽出

`gh pr view <PR>` で title / files / body を取得し、以下を判定:

- **エコシステム判定**: branch 名 prefix から決定
  - Dependabot: `dependabot/docker/...` / `dependabot/go_modules/...` / `dependabot/npm_and_yarn/...` / `dependabot/github_actions/...`
  - Renovate: `renovate/<manager>-...` （`renovate/docker-`, `renovate/go-`, `renovate/npm-`, `renovate/github-actions-` 等。Renovate は config 依存で命名が変わる）
- **bump 内容抽出**: title から package / from / to を regex で抽出
  - Dependabot 例: `Bump golang from 1.24-bookworm to 1.26-bookworm in /apps/backend`
  - Renovate 例: `Update dependency golang Docker tag to v1.26-bookworm` / `chore(deps): update golang docker tag to v1.26-bookworm`
  - 抽出: `package=golang`, `from=1.24-bookworm` (Renovate は title に from がない場合があり、その時は `gh pr diff` から推定), `to=1.26-bookworm`

抽出できない場合は AskUserQuestion で確認。

### Step 2: ドリフト検知（決定論的 grep）

エコシステム別の検知レシピで横断 grep を実行する。

詳細は [references/drift-detection.md](references/drift-detection.md) を参照して実行する。

検知ロジックの大枠:

1. **検索対象パターン**を構築（例: docker `golang:X.Y` bump なら `Go X.Y`, `go X.Y.0`, `go-version: 'X.Y'` 等）
2. リポジトリ全体に grep し、ヒットしたファイル一覧を取得
3. PR の `gh pr diff` で変更ファイル一覧を取得
4. **「ヒットしたが PR 差分に含まれていないファイル」** を ドリフト候補として抽出
5. 各候補の妥当性を Claude の判断で精査（false positive 除去）

出力: `findings = [{file, line, current_value, suggested_value, severity}]`

### Step 3: リリースノート要約（任意、`--release-notes` 指定時のみ）

詳細は [references/release-notes.md](references/release-notes.md) を参照して実行する。

エコシステムごとに取得元が異なる:
- docker: GitHub Releases（image の upstream repo）
- gomod: `go doc` または GitHub Releases
- npm: `npm view <pkg> --json` または GitHub Releases
- github-actions: GitHub Releases

取得後、`from` から `to` の間の release を ChangeLog 風に要約。breaking change / security fix を強調。

### Step 4: レポートコメント投稿

[references/report-template.md](references/report-template.md) を参照してレポートを組み立てる。

ポイント:
- 固定マーカー `<!-- dependabot-review:report -->` で **upsert**（重複コメント回避）
- 既存コメントがあれば update、なければ create
- `--no-comment` 指定時は標準出力に表示するのみ

```bash
# upsert ロジック例
existing=$(gh api repos/$REPO/issues/$PR/comments --paginate \
  --jq '.[] | select(.body | startswith("<!-- dependabot-review:report -->")) | .id' | head -1)
if [ -n "$existing" ]; then
  gh api repos/$REPO/issues/comments/$existing --method PATCH -f body="$BODY"
else
  gh pr comment $PR --body "$BODY"
fi
```

### Step 5: 追従 PR 作成（ユーザー承認後のみ）

ドリフトが検出された場合、AskUserQuestion で「追従 PR を作成しますか？」と確認する。

**承認された場合のみ** 以下を実行:

1. `git switch -c feature/dependabot-followup-<PR番号>` で新ブランチ作成（main から）
2. ドリフト検知箇所のみを修正（version 文字列を `to` に置換）
3. 必要なら関連ファイル（go.sum 等）を再生成
4. コミット: `chore(deps): sync version references for #<PR>`
5. push & PR 作成。本文に以下を含める:
   - `Refs #<元PR>` リンク
   - 検知した drift findings の一覧
   - 元 PR とのマージ順序の指示（通常は元 PR を先にマージ）
6. 元 PR にも追従 PR へのリンクをコメント追加

**マージは絶対に実行しない**（git-safety.md PR Merge Policy に従う）。

## エラーハンドリング

| エラー | 原因 | 対応 |
|--------|------|------|
| `gh: not authenticated` | gh CLI 未認証 | `gh auth login` を促して終了 |
| 対象 PR が bot 作成ではない | 通常の人間 PR | 警告して終了。peer-review / review-pr 推奨 |
| エコシステム判定不能 | branch 名が標準フォーマット外 | AskUserQuestion で手動指定 |
| bump 抽出失敗 | title が複雑（複数 package 同時 bump 等） | findings なしで Step 4 に進む（リリースノート要約のみ提供） |
| ドリフト候補ゼロ | 健全な PR | レポートに「追従更新は不要」と明記して投稿 |

## 関連スキル

| スキル | 役割 | 本スキルとの境界 |
|--------|------|-----------------|
| peer-review | 他者 PR の俯瞰レビュー（外部 LLM 利用） | dependabot PR は本スキル優先（軽量・特化） |
| self-review | 自ブランチの diff レビュー | 別軸（bot PR ではない） |
| review-pr | レビューコメントへの返信 | 本スキル投稿後のコメント対応に使用 |

## 設計原則

- **決定論的検知を優先**: LLM 判断は false positive 除去にのみ使う
- **非破壊**: 追従 PR 作成は必ずユーザー承認後（self-review / review-adr と同じ原則）
- **コメント upsert**: 固定マーカーで重複防止
- **冪等**: 同じ PR で複数回実行しても不整合が起きない

## 注意事項

- 本スキルは Dependabot / Renovate / 同等の bot 作成 PR が対象。手動 PR には使わない
- ドリフト検知は **書いたパターン範囲しか見ない**。新しいエコシステムは references/drift-detection.md に追記して拡張する
- リリースノート要約は ネット呼び出しを伴うため、デフォルト OFF
