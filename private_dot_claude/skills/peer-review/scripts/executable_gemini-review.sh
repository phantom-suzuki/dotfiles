#!/bin/bash
# peer-review 用 Gemini CLI ラッパー
# - stdin からプロンプト全体（コンテキスト + diff 含む）を受け取り、Gemini で俯瞰レビューし JSON を stdout に出力
# - モデルフォールバック: gemini-2.5-pro → gemini-2.5-flash
# - リトライ: exponential backoff (5s → 10s → 20s)
#
# Usage: cat prompt.md | bash gemini-review.sh
#
# Exit codes:
#   0 - 成功（JSON を stdout に出力）
#   1 - 全モデル・全リトライ失敗
#
# 期待する出力 JSON 構造:
#   {
#     "findings": [{"category": "...", "axis": "...", "title": "...", "description": "...", "suggestion": "..."}],
#     "overall_judgment": "approve" | "comment" | "request-changes",
#     "overall_summary": "..."
#   }

set -uo pipefail
STDERR_TMPFILE=$(mktemp /tmp/peer-review-gemini-stderr.XXXXXX)
trap 'rm -f "$STDERR_TMPFILE"' EXIT

# 依存確認
if ! command -v jq >/dev/null 2>&1; then
  >&2 echo "[peer-review] jq が必要です。brew install jq 等でインストールしてください"
  exit 1
fi

if ! command -v gemini >/dev/null 2>&1; then
  >&2 echo "[peer-review] gemini CLI が必要です。インストール後に再実行してください"
  exit 1
fi

MODELS=("gemini-2.5-pro" "gemini-2.5-flash")
MAX_RETRIES=3
BASE_WAIT=5

# stdin からプロンプト全体を読み取り（peer-review はコンテキスト + diff を含む大きなプロンプト）
PROMPT_INPUT=$(cat)

if [[ -z "$PROMPT_INPUT" ]]; then
  >&2 echo "[peer-review] stdin からプロンプトが渡されていません"
  exit 1
fi

# peer-review 用 JSON 構造の検証関数
validate_peer_review_json() {
  local input="$1"
  echo "$input" | jq -e '
    type=="object"
    and (.findings | type=="array")
    and (.overall_judgment | type=="string")
    and (.overall_judgment | test("^(approve|comment|request-changes)$"))
    and (.overall_summary | type=="string")
  ' >/dev/null 2>&1
}

for model in "${MODELS[@]}"; do
  retry=0
  while [[ $retry -lt $MAX_RETRIES ]]; do
    wait_time=$(( BASE_WAIT * (2 ** retry) ))

    # Gemini CLI を非対話モードで実行（プロンプトは stdin）
    RESULT=$(echo "$PROMPT_INPUT" | gemini --model "$model" 2>"$STDERR_TMPFILE") && EXIT_CODE=0 || EXIT_CODE=$?

    if [[ $EXIT_CODE -eq 0 ]] && [[ -n "$RESULT" ]]; then
      # 出力から JSON ブロックを抽出（```json ... ``` で囲まれている or 直接 JSON）
      JSON_BLOCK=$(echo "$RESULT" | sed -n '/^```json/,/^```/p' | sed '1d;$d')
      if [[ -z "$JSON_BLOCK" ]]; then
        # コードブロックで囲まれていない場合、素直に全体を試す
        JSON_BLOCK="$RESULT"
      fi

      if validate_peer_review_json "$JSON_BLOCK"; then
        # 成功: レビュアー名を追加して出力
        echo "$JSON_BLOCK" | jq --arg reviewer "gemini ($model)" '. + {reviewer: $reviewer}'
        exit 0
      fi

      >&2 echo "[peer-review] $model: JSON 検証失敗、リトライ $((retry + 1))/$MAX_RETRIES"
    else
      # エラー内容を確認
      STDERR_CONTENT=$(cat "$STDERR_TMPFILE" 2>/dev/null || echo "")

      if echo "$STDERR_CONTENT" | grep -qi "MODEL_CAPACITY_EXHAUSTED\|RESOURCE_EXHAUSTED\|429\|exhausted your capacity"; then
        >&2 echo "[peer-review] $model: 容量不足、${wait_time}秒後にリトライ $((retry + 1))/$MAX_RETRIES"
      elif echo "$STDERR_CONTENT" | grep -qi "RATE_LIMIT\|rate.limit"; then
        >&2 echo "[peer-review] $model: レート制限、${wait_time}秒後にリトライ $((retry + 1))/$MAX_RETRIES"
      else
        >&2 echo "[peer-review] $model: エラー (exit=$EXIT_CODE)、${wait_time}秒後にリトライ $((retry + 1))/$MAX_RETRIES"
        if [[ -n "$STDERR_CONTENT" ]]; then
          >&2 echo "  stderr: $(echo "$STDERR_CONTENT" | head -3)"
        fi
      fi
    fi

    retry=$((retry + 1))
    if [[ $retry -lt $MAX_RETRIES ]]; then
      sleep "$wait_time"
    fi
  done

  >&2 echo "[peer-review] $model: 全リトライ失敗、次のモデルへフォールバック"
done

>&2 echo "[peer-review] 全モデル・全リトライ失敗"
exit 1
