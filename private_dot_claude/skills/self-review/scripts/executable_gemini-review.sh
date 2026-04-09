#!/bin/bash
# Gemini CLI レビューラッパー
# - stdin から diff を受け取り、Gemini でレビューし JSON を stdout に出力
# - モデルフォールバック: gemini-2.5-pro → gemini-2.5-flash
# - リトライ: exponential backoff (30s → 60s → 120s)
#
# Usage: echo "$DIFF" | bash gemini-review.sh
# Exit codes:
#   0 - 成功（JSON を stdout に出力）
#   1 - 全モデル・全リトライ失敗

set -uo pipefail
trap 'rm -f /tmp/gemini-review-stderr-$$.log' EXIT

# jq は必須（JSON パース・レビュアー名追加に使用）
if ! command -v jq >/dev/null 2>&1; then
  >&2 echo "[gemini-review] jq が必要です。brew install jq 等でインストールしてください"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_FILE="$SCRIPT_DIR/../references/review-prompt-template.md"

MODELS=("gemini-2.5-pro" "gemini-2.5-flash")
MAX_RETRIES=3
BASE_WAIT=5

# 共有プロンプトテンプレートを読み込み
if [[ -f "$PROMPT_FILE" ]]; then
  REVIEW_PROMPT=$(cat "$PROMPT_FILE")
else
  >&2 echo "[gemini-review] プロンプトテンプレートが見つかりません: $PROMPT_FILE"
  exit 1
fi

# stdin から diff を読み取り
DIFF_INPUT=$(cat)

if [[ -z "$DIFF_INPUT" ]]; then
  echo '{"findings": [], "summary": "diff が空です"}'
  exit 0
fi

for model in "${MODELS[@]}"; do
  retry=0
  while [[ $retry -lt $MAX_RETRIES ]]; do
    wait_time=$(( BASE_WAIT * (2 ** retry) ))

    # Gemini CLI を非対話モードで実行
    RESULT=$(echo "$DIFF_INPUT" | gemini -m "$model" -p "$REVIEW_PROMPT" --output-format json 2>/tmp/gemini-review-stderr-$$.log) && EXIT_CODE=0 || EXIT_CODE=$?

    if [[ $EXIT_CODE -eq 0 ]] && [[ -n "$RESULT" ]]; then
      # JSON として有効か検証
      if echo "$RESULT" | jq -e '.findings' >/dev/null 2>&1; then
        # 成功: レビュアー名を追加して出力
        echo "$RESULT" | jq --arg reviewer "gemini ($model)" '. + {reviewer: $reviewer}'
        exit 0
      fi

      # JSON パースに失敗した場合、response フィールドから抽出を試みる
      EXTRACTED=$(echo "$RESULT" | jq -r '.response // empty' 2>/dev/null)
      if [[ -n "$EXTRACTED" ]]; then
        # response 内の JSON ブロックを抽出
        JSON_BLOCK=$(echo "$EXTRACTED" | sed -n '/^{/,/^}/p' | head -100)
        if echo "$JSON_BLOCK" | jq -e '.findings' >/dev/null 2>&1; then
          echo "$JSON_BLOCK" | jq --arg reviewer "gemini ($model)" '. + {reviewer: $reviewer}'
          exit 0
        fi
      fi

      # JSON 抽出失敗 → リトライ
      >&2 echo "[gemini-review] $model: JSON パース失敗、リトライ $((retry + 1))/$MAX_RETRIES"
    else
      # エラー内容を確認
      STDERR_CONTENT=$(cat /tmp/gemini-review-stderr-$$.log 2>/dev/null || echo "")

      if echo "$STDERR_CONTENT" | grep -qi "MODEL_CAPACITY_EXHAUSTED\|RESOURCE_EXHAUSTED\|429"; then
        >&2 echo "[gemini-review] $model: 容量不足 (429)、${wait_time}秒後にリトライ $((retry + 1))/$MAX_RETRIES"
      elif echo "$STDERR_CONTENT" | grep -qi "RATE_LIMIT\|rate.limit"; then
        >&2 echo "[gemini-review] $model: レート制限、${wait_time}秒後にリトライ $((retry + 1))/$MAX_RETRIES"
      else
        >&2 echo "[gemini-review] $model: エラー (exit=$EXIT_CODE)、${wait_time}秒後にリトライ $((retry + 1))/$MAX_RETRIES"
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

  >&2 echo "[gemini-review] $model: 全リトライ失敗、次のモデルへフォールバック"
done

# 全モデル失敗（temp file は trap EXIT で自動削除）
>&2 echo "[gemini-review] 全モデル・全リトライ失敗"
exit 1
