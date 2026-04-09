# レビュアー別プロンプト・呼び出し方法

各外部レビュアーの呼び出しコマンドとプロンプトテンプレートを定義する。

---

## 目次

1. [共通: diff の取得](#共通-diff-の取得)
2. [Claude Code (claude -p)](#claude-code-claude--p)
3. [Codex CLI (codex review)](#codex-cli-codex-review)
4. [Gemini CLI](#gemini-cli)
5. [レビュー結果の統合](#レビュー結果の統合)

---

## 共通: diff の取得

レビュー対象の diff を取得する。scope パラメータに応じて切り替える。

```bash
# changed (ベースブランチからの差分)
BASE_BRANCH=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD develop 2>/dev/null || echo "HEAD~1")
DIFF=$(git diff "$BASE_BRANCH"..HEAD)

# staged
DIFF=$(git diff --cached)

# all (直前コミットとの差分)
DIFF=$(git diff HEAD~1..HEAD)
```

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
  --append-system-prompt "あなたはコードレビューの専門家です。以下の diff をレビューし、JSON 形式で結果を返してください。$(cat '${CLAUDE_SKILL_DIR}/references/review-prompt-template.md')"
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
