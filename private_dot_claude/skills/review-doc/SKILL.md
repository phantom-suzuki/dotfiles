---
description: 通常の Markdown ドキュメント（README / マイグレーションガイド / spec / RFC / 技術記事 等、ADR を除く）を、可読性・前後整合・参照リンク・更新漏れの観点でレビューする軽量スキル。修正は提案のみで自動編集なし。「ドキュメントレビュー」「Markdown レビュー」「review-doc」「ガイドを見て」等の依頼時に使用。
argument-hint: "[doc-file-path-or-glob] [--skip-codex] [--with-gemini] [--scope this|related]"
---

# Skill: /review-doc

## 概要

`review-adr` が単一 ADR の論理レビュー特化（合意済み記録の保護）であるのに対し、`review-doc` は **ADR 以外の通常 Markdown ドキュメント** を可読性・整合性の観点でレビューする。コードではなく文書を対象とし、修正は提案のみで自動編集しない。

| | self-review | peer-review | review-adr | **review-doc** |
|---|---|---|---|---|
| 対象 | コード（自分） | PR（他者） | ADR (.md, docs/adr/) | **通常 Markdown（自分）** |
| 修正 | 自動コミット | なし（PR 投稿） | なし（提案のみ） | **なし（提案のみ）** |
| 外部 LLM | 1〜N | 2 | 1（オプション 0 or 1） | **1（オプション 0 or 1）** |
| 想定時間 | 3〜5 分 | 5〜8 分 | 1〜2 分 | **1〜3 分** |
| 観点 | 品質・バグ | 5 軸俯瞰 | 論理 5 軸 | **文書 4 軸** |

## パラメータ

| パラメータ | デフォルト | 説明 |
|-----------|----------|------|
| `doc-file-path-or-glob` | (省略可) | 対象ドキュメントのパス or glob。省略時は最新変更の Markdown を自動検出（`docs/adr/` 配下を除外） |
| `--skip-codex` | false | L2 Codex をスキップ（L1 Claude のみ） |
| `--with-gemini` | false | Gemini を追加（opt-in） |
| `--scope` | `this` | `this` = 対象ドキュメントのみ / `related` = 同ディレクトリ・親ディレクトリの関連ファイルもインデックス化（推奨） |

## 前提条件

- `--skip-codex` でなければ `codex` CLI が利用可能
- `--with-gemini` 指定時のみ `gemini` CLI が利用可能（Gemini は opt-in）
- `jq` がインストール済み

## 観点（4 軸固定）

| # | 観点 | 概要 |
|---|------|------|
| R | 可読性 | 見出し階層、段落構成、用語、対象読者の前提と認知負荷、冒頭の文脈提示 |
| C | 前後整合 | Step 番号、表の整合、同一文書内の矛盾、表現の揺れ |
| L | 参照リンク | リンク切れ、内部相対パス、Issue/PR/ADR 番号、外部 URL の妥当性 |
| U | 更新漏れ | 同ディレクトリの README / 目次、対比表、関連ガイド・spec の追従更新 |

**review-adr / CodeRabbit との棲み分け**:
- ADR の論理一貫性・既存矛盾は review-adr に委ねる
- 表記レベルの細かい指摘（typo、リンク文字列）は CodeRabbit と重複しがち。初出のみ指摘し、繰り返さない

## 対象判定（ADR 除外ルール）

以下は本スキルの対象外:
- `docs/adr/` 配下の `.md` → **review-adr に誘導**
- README に近い軽量ファイル（< 50 行で見出しが 1〜2 個）→ 警告して続行可否を確認
- スキル/プラグインの SKILL.md → self-review もしくは skill-design の領域
- コードを含む PR の Markdown 部分のみをレビューしたい場合 → peer-review が PR 全体を見るほうが筋が良い

## 実行手順

### Step 0: 対象ドキュメント特定

1. `doc-file-path-or-glob` 引数が与えられていればそれを使用
2. 省略されている場合、以下から最新変更の Markdown を検出:
   ```bash
   git status --porcelain '*.md' | awk '{print $2}' | grep -v '^docs/adr/'
   git log -1 --name-only --pretty=format: -- '*.md' | grep -v '^docs/adr/'
   ```
3. 候補が複数ある場合は AskUserQuestion で選択を求める
4. 対象が `docs/adr/` 配下なら警告し、review-adr の起動を提案して終了

### Step 1: 関連ファイルインデックス（`--scope related` のみ）

対象ドキュメントの同ディレクトリ + 親ディレクトリの README / 目次を `grep` ベースで軽量走査:

```bash
DOC_DIR=$(dirname "$DOC_PATH")
# 同ディレクトリの他 .md（自身を除く、最大 10 件）
related=$(find "$DOC_DIR" -maxdepth 1 -name "*.md" ! -path "$DOC_PATH" | head -10)
# 親ディレクトリの README / 目次
parent_idx="$DOC_DIR/../README.md"
# 対象ファイル中で参照されている内部リンク
referenced=$(grep -oE '\[[^]]*\]\(([^)]+\.md)\)' "$DOC_PATH" | sed -E 's/.*\(([^)]+)\).*/\1/' | sort -u)
```

ファイル本文の Read は **対象ドキュメントのみ**。関連ファイルは見出し（`grep -E '^#'`）と先頭 30 行程度のみ抽出して矛盾検出する。

### Step 2: L1 Claude 文書レビュー

対象ドキュメントを Read で取得し、4 軸で評価する。

- 軸ごとに `findings` を列挙: `{axis, severity, title, description, suggestion}`
- severity: `must-fix` / `should-fix` / `nit`
- 関連ファイルとの整合は Step 1 のインデックスと突合
- 出力先: `/tmp/review-doc-l1.json`

### Step 3: L2 Codex セカンドオピニオン（デフォルト、オプションで Gemini）

`--skip-codex` でなければ、Codex を L2 として実行する（デフォルト経路）。`peer-review/scripts/codex-review.sh` は PR 専用のため流用しない。

```bash
codex exec \
  --full-auto \
  --sandbox read-only \
  --ignore-user-config \
  --ignore-rules \
  --output-last-message /tmp/review-doc-codex.txt \
  "$(cat <<EOF
## タスク
以下のドキュメントを review-doc 観点でレビューし、L1 とは独立したセカンドオピニオンとして指摘を返してください。

## 観点
- 可読性 / 前後整合 / 参照リンク / 更新漏れ
- 既存ドキュメントや実装との矛盾（リポジトリ内を grep して確認可能）

## 出力形式
以下の JSON を 1 つ返してください（コードブロックなし、純粋な JSON のみ）:
{
  "findings": [{"category": "must-fix|should-fix|nit", "axis": "...", "title": "...", "description": "...", "suggestion": "..."}],
  "overall_summary": "..."
}

## 対象ドキュメント
<DOC_CONTENT>
EOF
)"
```

`--with-gemini` 指定時のみ、Gemini を追加で実行する（opt-in）。Gemini が失敗しても Codex/L1 の経路で続行する。

```bash
PROMPT_FILE=$(mktemp)
{
  echo "## タスク"
  echo "以下の Markdown ドキュメントを 4 軸（可読性 R / 前後整合 C / 参照リンク L / 更新漏れ U）でレビューしてください。"
  echo "出力は JSON 形式の findings を返してください。"
  echo "---"
  echo "## 対象ドキュメント ($DOC_PATH)"
  cat "$DOC_PATH"
} > "$PROMPT_FILE"

cat "$PROMPT_FILE" | bash ~/.claude/skills/peer-review/scripts/gemini-review.sh \
  > /tmp/review-doc-gemini.json
```


Codex が失敗した場合は L1 のみで続行し、`--with-gemini` 指定時のみ Gemini 結果を補助的に使う。

**注意**: 上記 `codex exec` ブロックの `<DOC_CONTENT>` は呼び出し時に Opus 側でプレースホルダ展開する（対象ドキュメントの本文 + 必要なら関連ファイル見出しを差し込む）。シェルが展開する変数ではない。

### Step 4: 統合と提示

L1 / L2 の `findings` を統合し、severity でソートしてユーザーに提示する。

- 重複除去: 同一 axis + 同一対象は 1 件にマージ
- 出力フォーマット:
  ```
  [must-fix / R] 可読性: Step 5 と Step 6 の前提が逆転しており、読者が混乱する
    → Step 順序を入れ替えるか、明示的に「先に Step 6 を完了してから Step 5」と注記する
  ```
- **ファイル編集は実施しない**

### Step 5: 反映方針の対話

ユーザーに以下を提示し、判断を仰ぐ:

1. 各 finding について「反映する / 反映しない / 保留」を確認
2. 反映する場合のみ、Edit 候補を 1 件ずつ diff 形式で提示してから Edit を実行

レビュー結果は `/tmp/review-doc-summary.md` にも書き出し、後で参照可能にする。

## エラーハンドリング

| エラー | 原因 | 対応 |
|--------|------|------|
| 対象ファイルが ADR | `docs/adr/` 配下を指定 | review-adr に誘導して終了 |
| 対象が極小（< 50 行・見出し 1-2 個） | README 等の軽量ファイル | 警告し、続行可否を AskUserQuestion で確認 |
| Codex 実行失敗 | CLI エラー / タイムアウト | L1 のみで続行。`--with-gemini` 指定時のみ Gemini 結果を補助として利用 |
| 対象が複数候補 | git status が複数 .md を返す | AskUserQuestion で選択 |

## 注意事項

- **ファイル編集は提案のみ**: ドキュメントの自動編集は行わず、ユーザーの明示承認後に 1 件ずつ Edit
- **CodeRabbit との棲み分け**: 表記・リンク切れの細部は CodeRabbit に任せ、本スキルは可読性・整合・更新漏れにフォーカス
- **対話型判断**: finding 一覧で「全部対応」ではなく、1 件ずつ判断を仰ぐ
- **`--scope related` の使い所**: 関連ファイルとの更新漏れ（同ディレクトリの README、対比表など）を検出したいとき
- **対象は ADR 以外の Markdown のみ**: ADR は review-adr、コード変更は self-review、他者 PR は peer-review

## 関連スキル

- `/review-adr`: ADR (.md, docs/adr/) 専用レビュー
- `/peer-review`: PR 全体の俯瞰レビュー（他者 PR）
- `/self-review`: コード変更のセルフレビュー（自分のブランチ）
- `/review-dispatch`: どのレビュースキルを使うか迷ったときの判定ガイド
