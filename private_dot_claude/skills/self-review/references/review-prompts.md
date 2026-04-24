# レビュアー別プロンプト・呼び出し方法

各外部レビュアーの呼び出しコマンドとプロンプトテンプレートを定義する。

---

## 目次

1. [共通: diff の取得](#共通-diff-の取得)
2. [観点別プロンプトの組み立て](#観点別プロンプトの組み立て)
3. [観点別呼び出し (parallel-by-aspect)](#観点別呼び出し-parallel-by-aspect)
4. [Claude Code (claude -p)](#claude-code-claude--p)
5. [Codex CLI (codex review)](#codex-cli-codex-review)
6. [Gemini CLI](#gemini-cli)
7. [レビュー結果の統合](#レビュー結果の統合)

---

## 共通: diff の取得

レビュー対象の diff を取得する。scope パラメータに応じて切り替える。

```bash
# changed (ベースブランチからの差分)
BASE_BRANCH=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD develop 2>/dev/null || echo "HEAD~1")
DIFF=$(git diff "$BASE_BRANCH"..HEAD)

# staged
DIFF=$(git diff --cached)

# all (全トラッキングファイルをヘッダ付きで連結)
DIFF=$(git ls-files | while read f; do echo "=== $f ==="; git show "HEAD:$f" 2>/dev/null; echo; done)
```

---

## 観点別プロンプトの組み立て

`parallel-by-aspect` モード（および任意のレビュアーに観点を指定する場合）では、
共通テンプレートと観点別テンプレートを結合してプロンプトを作る。

### ファイル構成

```
references/
  review-prompt-template.md   # 共通: 出力 JSON スキーマ、category 分類、共通ルール
  review-prompt-bug.md        # バグ・ロジック観点
  review-prompt-security.md   # セキュリティ観点
  review-prompt-design.md     # 設計・アーキ観点
```

共通テンプレートには 2 つのプレースホルダがある:

- `<ASPECT_FOCUS>` — 観点別テンプレートの内容を差し込む場所
- `<REVIEW_ASPECT>` — `bug` / `security` / `design` / `all` の識別子
- `<ATTACHED_FILES>` — B-1 の対象ファイル添付内容（未使用時は削除）

### 組み立てアルゴリズム（擬似コード）

```text
build_prompt(aspect, attached_files):
  common     = read("review-prompt-template.md")
  if aspect == "all":
    focus = <全観点の既存プロンプト>   # 後方互換: 現 review-prompt-template.md の「レビュー観点」章を内蔵
  else:
    focus = read(f"review-prompt-{aspect}.md")

  prompt = common
    .replace("<ASPECT_FOCUS>", focus)
    .replace("<REVIEW_ASPECT>", aspect)
    .replace("<ATTACHED_FILES>", attached_files or "（なし）")
  return prompt
```

### 対象ファイル添付（B-1）

大規模 diff では「diff にない既存実装を誤認する」誤検知を抑えるため、
以下の条件で対象ファイル全体をプロンプトに添付する:

- `parallel-by-aspect` モードで有効
- 対象ファイルのうち **変更行数 ≥ 50** のファイルを対象
- 添付は **最大 5 ファイル**（プロンプト肥大化防止）
- 各ファイルは `=== <path> ===\n<file content>\n` 形式で連結

```bash
# 抽出例
git diff --numstat "$BASE_BRANCH"..HEAD | \
  awk '$1 + $2 >= 50 {print $3}' | head -5 | \
  while read f; do
    echo "=== $f ==="
    git show "HEAD:$f" 2>/dev/null
    echo
  done
```

---

## 観点別呼び出し (parallel-by-aspect)

各観点に対して primary レビュアーを選び、失敗時は fallback に切り替える。

| 観点 | primary | fallback (順) |
|-----|---------|--------------|
| bug | Claude-p | Gemini → Codex |
| security | Codex | Claude-p → Gemini |
| design | Gemini | Claude-p → Codex |

### 呼び出し例（bug 観点を Claude-p に投げる）

```bash
ASPECT=bug
ATTACHED=$(...上記の対象ファイル添付ブロックを生成...)
PROMPT=$(build_prompt "$ASPECT" "$ATTACHED")  # 下記「観点別プロンプトの組み立て」参照

echo "$DIFF" | claude -p \
  --model sonnet \
  --output-format json \
  --max-budget-usd 2.00 \
  --permission-mode dontAsk \
  --allowedTools "Read" \
  --append-system-prompt "あなたは ${ASPECT} 観点に特化したコードレビュアーです。$PROMPT"
```

### 呼び出し例（security 観点を Codex に投げる）

```bash
ASPECT=security
ATTACHED=$(...)
codex exec review --base "$BASE_BRANCH" --json -o /tmp/codex-review-$$.txt \
  "$(build_prompt "$ASPECT" "$ATTACHED")"
cat /tmp/codex-review-$$.txt
rm -f /tmp/codex-review-$$.txt
```

### 呼び出し例（design 観点を Gemini に投げる）

```bash
REVIEW_ASPECT=design \
ATTACHED_FILES="$(...対象ファイル添付...)" \
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" <<< "$DIFF"
```

`gemini-review.sh` は環境変数 `REVIEW_ASPECT` と `ATTACHED_FILES` を読み、
内部で観点別テンプレートを結合する。未設定時は `REVIEW_ASPECT=all` として
従来どおり全観点プロンプトで動作する（後方互換）。

### Fallback の回し方

```text
for reviewer in [primary, *fallbacks]:
  result = invoke(reviewer, aspect)
  if result.success:
    return result
return {"findings": [], "summary": f"{aspect} 観点: 全レビュアー失敗", "failed": true}
```

- 同じ diff に対して同じレビュアーを 2 回以上走らせない
  （例: bug の fallback = Gemini、design の primary = Gemini の場合、
  design 結果が既にあれば再実行しない。ただし aspect が異なるのでプロンプトは別）
- 3 観点すべてで失敗した場合は、SKILL.md「レビュアーが全滅した場合」に従う

---

## Claude Code (claude -p)

### 呼び出しコマンド

```bash
echo "$DIFF" | claude -p \
  --model sonnet \
  --output-format json \
  --max-budget-usd 2.00 \
  --permission-mode dontAsk \
  --allowedTools "Read" \
  --append-system-prompt "あなたはコードレビューの専門家です。以下の diff をレビューし、JSON 形式で結果を返してください。$(cat "${CLAUDE_SKILL_DIR}/references/review-prompt-template.md")"
```

### タイムアウト

120秒。超過したらフォールバック。

### エラー時

終了コード非0 の場合、次のレビュアーへフォールバック。

---

## Codex CLI (codex review)

### 呼び出しコマンド

```bash
# ブランチ差分からレビュー
codex exec review --base "$BASE_BRANCH" --json -o /tmp/codex-review-$$.txt

# レビュー結果を読み取り
cat /tmp/codex-review-$$.txt
rm -f /tmp/codex-review-$$.txt
```

### 補足プロンプト付きの場合

```bash
codex exec review --base "$BASE_BRANCH" --json -o /tmp/codex-review-$$.txt \
  "以下の観点でレビューしてください: バグ、セキュリティ、エラーハンドリング、エッジケース。全ての問題を網羅的にリストアップしてください。"
```

### 出力フォーマット

Codex review は以下の構造で JSON を返す:
```json
{
  "findings": [
    {
      "title": "問題の要約",
      "body": "詳細な説明",
      "confidence": 0.0-1.0,
      "priority": "P1-P4",
      "filepath": "ファイルパス",
      "line_start": 行番号,
      "line_end": 行番号
    }
  ],
  "overall_correctness": "patch is correct" | "patch is incorrect",
  "overall_explanation": "全体評価",
  "overall_confidence_score": 0.0-1.0
}
```

### Codex → 共通フォーマットへの変換ルール

| Codex フィールド | 共通フォーマット | 変換ルール |
|----------------|---------------|-----------|
| priority P1-P2 | severity: critical | |
| priority P3 | severity: warning | |
| priority P4 | severity: info | |
| confidence ≥ 0.8 + P1-P2 | category: auto-fix | 高信頼度 + 高優先度 |
| confidence ≥ 0.6 + P2-P3 | category: judgment | 中信頼度 or 中優先度 |
| その他 | category: info | |

### タイムアウト

180秒（Codex は Gemini より応答が遅い傾向）。

### エラー時

終了コード非0 の場合、次のレビュアーへフォールバック。

---

## Gemini CLI

### 呼び出しコマンド

Gemini は専用スクリプト経由で実行する。リトライとモデルフォールバックが内蔵されている。

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" <<< "$DIFF"
```

スクリプトの詳細は `scripts/gemini-review.sh` を参照。

### 出力フォーマット

スクリプトが共通 JSON フォーマットで出力する（Claude-p と同じ構造）。

### Gemini 固有の注意事項

- **「最初の問題で止まる」問題**: プロンプトで「全ての問題を網羅的にリストアップ」を明示指示している
- **変更していない行への提案**: プロンプトで「変更された行のみ」を明示指示している
- **MODEL_CAPACITY_EXHAUSTED**: スクリプトが gemini-2.5-pro → gemini-2.5-flash の順でフォールバック

---

## レビュー結果の統合

### parallel モードでの重複除去

複数レビュアーの結果をマージする際、以下のルールで重複を判定する:

1. **同一ファイル + 同一行（±5行以内）+ 同一カテゴリ** → 重複とみなす
2. 重複の場合、**severity が高いほうを採用**する
3. レビュアー名を記録し、サマリで「どのレビュアーが指摘したか」を表示する

### cascade モードでの結果処理

最初に成功したレビュアーの結果をそのまま使用する。フォールバックが発生した場合は、
サマリにどのレビュアーが使用されたかを記録する。
