---
description: ADR (Architecture Decision Record) を論理一貫性・既存ADRとの矛盾・抜け漏れ・軸選定の妥当性・表記整合の観点でレビューする軽量スキル。外部LLM 1回、修正は提案のみで自動編集なし。「ADRレビュー」「review-adr」「ADR を見て」等の依頼時に使用。
argument-hint: "[adr-file-path] [--skip-codex] [--with-gemini] [--scope this|all]"
---

# Skill: /review-adr

## 概要

`peer-review` が PR 全体の俯瞰レビュー（コンテキスト広域収集 + 行コメント分離 + PR 投稿）を担当するのに対し、`review-adr` は **単一 ADR の論理レビュー特化**。コードではなく文書を対象とし、修正は提案のみで自動編集しない。

| | self-review | peer-review | **review-adr** |
|---|---|---|---|
| 対象 | コード（自分） | PR（他者） | **ADR（単一 .md）** |
| 修正 | 自動コミット | なし（PR コメント投稿） | **なし（提案のみ）** |
| 外部 LLM | 1〜N | 2 | **1（オプション 0 or 1）** |
| 想定時間 | 3〜5 分 / 〜20 分（deep） | 5〜8 分 | **1〜2 分** |
| 観点 | 品質・バグ | 5 軸俯瞰 | **論理 4 軸 + 表記** |

## パラメータ

| パラメータ | デフォルト | 説明 |
|-----------|----------|------|
| `adr-file-path` | (省略可) | 対象 ADR のパス。省略時は最新変更の `docs/adr/*.md` を自動検出 |
| `--skip-codex` | false | L2 Codex をスキップ（L1 Claude のみ） |
| `--with-gemini` | false | Gemini を追加（opt-in） |
| `--scope` | `this` | `this` = 対象 ADR のみ / `all` = 全 ADR 横断インデックスと突合（推奨） |

## 前提条件

- 対象リポジトリに `docs/adr/` ディレクトリが存在する
- `--skip-codex` でなければ `codex` CLI が利用可能
- `--with-gemini` 指定時のみ `gemini` CLI が利用可能（Gemini は opt-in）
- `jq` がインストール済み

## 観点（5 軸固定）

詳細は [references/adr-checklist.md](references/adr-checklist.md) を初回のみ Read で取得する。

| # | 観点 | 概要 |
|---|------|------|
| L | 論理一貫性 | コンテキスト → 検討選択肢 → 決定 → 理由 → 影響 の鎖が崩れていないか |
| C | 既存 ADR との矛盾 | 参照 ADR の方針と矛盾していないか、上書きする場合に明示しているか |
| G | 抜け漏れ | スコープ明示、検討選択肢 ≥2、ネガティブ影響の記載、関連 Issue/ADR リンク |
| A | 軸選定の妥当性 | 比較軸が決定理由と整合しているか、軸選定の根拠が示されているか |
| N | 表記・整合（軽量） | ADR 番号の整合、リンク切れ、用語ゆれ、見出し階層 |

**N（表記）は CodeRabbit と重複しがちなので、初出のみ指摘し、繰り返し指摘は避ける。**

## 実行手順

### Step 0: 対象 ADR 特定

1. `adr-file-path` 引数が与えられていればそれを使用
2. 省略されている場合、`git status --porcelain docs/adr/*.md` および `git log -1 --name-only --pretty=format: -- docs/adr/*.md` から最新変更の ADR を検出
3. 候補が複数ある場合は AskUserQuestion で選択を求める

### Step 1: 軽量 ADR 横断インデックス構築

`--scope all`（推奨デフォルト）の場合のみ、`docs/adr/*.md` を `grep` ベースで軽量走査する:

```bash
# ADR 番号 + タイトル + ステータス + 参照関係の抽出
for f in docs/adr/[0-9]*.md; do
  num=$(head -1 "$f" | grep -oE 'ADR-[0-9]+' | head -1)
  title=$(head -1 "$f" | sed -E 's/^# //')
  st=$(awk '/^## ステータス/{getline; getline; print; exit}' "$f")  # zsh では $status が read-only のため別名を使用
  refs=$(grep -oE 'ADR-[0-9]+' "$f" | sort -u | grep -v "^${num}$" | tr '\n' ',' | sed 's/,$//')
  echo "$num | $st | $title | refs: $refs"
done
```

**注意**: zsh で実行する場合、`status` は read-only 変数のため `st` 等の別名を使うこと。

ファイル本文の Read は **対象 ADR のみ**。他 ADR は frontmatter 相当（番号・ステータス・参照関係）のみで矛盾検出する。

### Step 2: L1 Claude 論理レビュー

対象 ADR ファイルを Read で取得し、[references/adr-checklist.md](references/adr-checklist.md) の 5 軸で評価する。

- 軸ごとに `findings` を列挙: `{axis, severity, title, description, suggestion}`
- severity: `must-fix` / `should-fix` / `nit`
- 既存 ADR との矛盾は Step 1 のインデックスと突合
- 出力先: `/tmp/review-adr-l1.json`

### Step 3: L2 Codex セカンドオピニオン（デフォルト、オプションで Gemini）

`--skip-codex` でなければ、Codex を L2 として実行する（デフォルト経路）。Codex は ADR ディレクトリ全体を grep して既存 ADR との矛盾を機械検証できる。

```bash
codex exec \
  --full-auto \
  --sandbox read-only \
  --ignore-user-config \
  --ignore-rules \
  --output-last-message /tmp/review-adr-codex.txt \
  "$(cat <<EOF
## タスク
以下の ADR を review-adr 観点でレビューし、L1 とは独立したセカンドオピニオンとして指摘を返してください。

## 観点
- 論理一貫性 / 既存 ADR との矛盾 / 抜け漏れ / 軸選定の妥当性 / 表記整合
- `docs/adr/*.md` を grep し、既存 ADR との矛盾や参照ミスを機械検証する

## 出力形式
以下の JSON を 1 つ返してください（コードブロックなし、純粋な JSON のみ）:
{
  "findings": [{"category": "must-fix|should-fix|nit", "axis": "L|C|G|A|N", "title": "...", "description": "...", "suggestion": "..."}],
  "overall_summary": "..."
}

## 対象 ADR
<ADR_CONTENT>
EOF
)"
```

`--with-gemini` 指定時のみ、`references/adr-prompt.md` を使って Gemini を追加実行する（opt-in）。

```bash
PROMPT_FILE=$(mktemp)
{
  cat ${CLAUDE_SKILL_DIR}/references/adr-prompt.md
  echo "---"
  echo "## 対象 ADR ($ADR_PATH)"
  cat "$ADR_PATH"
  if [[ -n "$ADR_INDEX" ]]; then
    echo "---"
    echo "## 既存 ADR インデックス"
    echo "$ADR_INDEX"
  fi
} > "$PROMPT_FILE"

cat "$PROMPT_FILE" | bash ~/.claude/skills/peer-review/scripts/gemini-review.sh \
  > /tmp/review-adr-gemini.json
```

Codex が失敗した場合は L1 のみで続行し、`--with-gemini` 指定時のみ Gemini 結果を補助的に使う。

**注意**: 上記 `codex exec` ブロックの `<ADR_CONTENT>` は呼び出し時に Opus 側でプレースホルダ展開する（対象 ADR の本文 + 既存 ADR インデックスを差し込む）。シェルが展開する変数ではない。

### Step 4: 統合と提示

L1 / L2 の `findings` を統合し、severity でソートしてユーザーに提示する。

- 重複除去: 同一 axis + 同一対象は 1 件にマージ
- 出力フォーマット:
  ```
  [must-fix / L1] 論理一貫性: コンテキストで論点 X を提起したが「決定」セクションで言及がない
    → 決定セクションに論点 X への言及を追加するか、コンテキストで論点を絞ることを推奨
  ```
- **ファイル編集は実施しない**（合意済み記録の保護）

### Step 5: 反映方針の対話

ユーザーに以下を提示し、判断を仰ぐ:

1. 各 finding について「反映する / 反映しない / 保留」を確認
2. 反映する場合のみ、Edit 候補を 1 件ずつ diff 形式で提示してから Edit を実行
3. ステータスが `承認済み` の ADR は警告を出してから編集に進む（合意済み記録の改変リスク）

レビュー結果は `/tmp/review-adr-summary.md` にも書き出し、後で参照可能にする。

## エラーハンドリング

| エラー | 原因 | 対応 |
|--------|------|------|
| `docs/adr/` 未検出 | 対象リポジトリが ADR を採用していない | スキル中断、ユーザーに通知 |
| ADR ファイル形式不一致 | 見出しが `# ADR-XXXX:` でない | パース失敗箇所を報告して L1 のみ続行 |
| Codex 実行失敗 | CLI エラー / タイムアウト | L1 のみで続行。`--with-gemini` 指定時のみ Gemini 結果を補助として利用 |
| 対象 ADR が複数候補 | git status が複数 ADR を返す | AskUserQuestion で選択 |

## 注意事項

- **ファイル編集は提案のみ**: ADR は合意済み記録のため、自動編集はしない。Edit はユーザーの明示承認後に 1 件ずつ実行
- **CodeRabbit との棲み分け**: 表記・リンク切れの指摘は CodeRabbit に任せ、本スキルは論理・矛盾・軸選定にフォーカス
- **対話型判断**: finding 一覧を出して「全部対応」ではなく、1 件ずつ判断を仰ぐ方が ADR の合意性を保てる
- **`scope=this` の使い所**: 既存 ADR との矛盾を検出する必要がない初稿レビューや、軽量に回したい場合
- **対象は ADR のみ**: 通常の Markdown ドキュメントのレビューには使わない（peer-review / self-review の領域）

## 関連スキル

- `/peer-review`: PR 全体レビュー（広域）
- `/self-review`: コード変更のセルフレビュー
- `/adr`: ADR 作成スキル（本スキルとペア）
