#!/bin/bash
# Gemini CLI レビューラッパー
# - stdin から diff を受け取り、Gemini でレビューし JSON を stdout に出力
# - モデルフォールバック: gemini-2.5-pro → gemini-2.5-flash
# - 429 検知時はクールダウンファイルに記録（以降はプリフライト側でスキップされる）
#
# Usage:
#   echo "$DIFF" | bash gemini-review.sh
#   REVIEW_ASPECT=design ATTACHED_FILES="$(...)" echo "$DIFF" | bash gemini-review.sh
#   GEMINI_STATUS=flash-only echo "$DIFF" | bash gemini-review.sh  # flash のみ使用
#
# Env:
#   REVIEW_ASPECT            bug | security | design | all (default: all)
#   ATTACHED_FILES           対象ファイル全体の連結（B-1: 誤検知防止用、オプション）
#   GEMINI_STATUS            available | flash-only（プリフライト結果、flash-only なら flash のみ試行）
#   GEMINI_MAX_RETRIES       1モデルあたりのリトライ回数 (default: 1、初回試行のみ)
#   GEMINI_BASE_WAIT         リトライ時の基底待機秒数 (default: 3)
#   GEMINI_COOLDOWN_FILE     429 検知時にクールダウンを記録するファイル
#
# Exit codes:
#   0 - 成功（JSON を stdout に出力）
#   1 - 全モデル・全リトライ失敗

set -uo pipefail
STDERR_TMPFILE=$(mktemp /tmp/gemini-review-stderr.XXXXXX)
trap 'rm -f "$STDERR_TMPFILE"' EXIT

COOLDOWN_FILE="${GEMINI_COOLDOWN_FILE:-$HOME/.claude/skills/self-review/.gemini-cooldown}"
CAPACITY_EXHAUSTED=0

# jq は必須（JSON パース・レビュアー名追加に使用）
if ! command -v jq >/dev/null 2>&1; then
  >&2 echo "[gemini-review] jq が必要です。brew install jq 等でインストールしてください"
  exit 1
fi

# gemini CLI は必須（レビュー実行に使用）
if ! command -v gemini >/dev/null 2>&1; then
  >&2 echo "[gemini-review] gemini CLI が必要です。インストール後に再実行してください"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REFS_DIR="$SCRIPT_DIR/../references"
COMMON_PROMPT_FILE="$REFS_DIR/review-prompt-template.md"

if [[ "${GEMINI_STATUS:-}" == "flash-only" ]]; then
  MODELS=("gemini-2.5-flash")
else
  MODELS=("gemini-2.5-pro" "gemini-2.5-flash")
fi
MAX_RETRIES="${GEMINI_MAX_RETRIES:-1}"
BASE_WAIT="${GEMINI_BASE_WAIT:-3}"

# 観点指定（デフォルト: all、後方互換）
REVIEW_ASPECT="${REVIEW_ASPECT:-all}"
case "$REVIEW_ASPECT" in
  bug|security|design|all) ;;
  *)
    >&2 echo "[gemini-review] 不正な REVIEW_ASPECT: $REVIEW_ASPECT (bug|security|design|all のいずれか)"
    exit 1
    ;;
esac

ASPECT_PROMPT_FILE="$REFS_DIR/review-prompt-${REVIEW_ASPECT}.md"

# 共通テンプレートを読み込み
if [[ ! -f "$COMMON_PROMPT_FILE" ]]; then
  >&2 echo "[gemini-review] プロンプトテンプレートが見つかりません: $COMMON_PROMPT_FILE"
  exit 1
fi
COMMON_PROMPT=$(cat "$COMMON_PROMPT_FILE")

# 観点別テンプレートを読み込み（ASPECT_FOCUS に差し込む内容）
if [[ ! -f "$ASPECT_PROMPT_FILE" ]]; then
  >&2 echo "[gemini-review] 観点別テンプレートが見つかりません: $ASPECT_PROMPT_FILE"
  exit 1
fi
ASPECT_FOCUS=$(cat "$ASPECT_PROMPT_FILE")

# ATTACHED_FILES（B-1: 対象ファイル全体の添付、省略時は「（なし）」）
ATTACHED_BLOCK="${ATTACHED_FILES:-（なし）}"

# プレースホルダを展開して最終プロンプトを組み立て
# bash パラメータ展開は複数行文字列をそのまま扱えるためメタ文字エスケープ不要
REVIEW_PROMPT="$COMMON_PROMPT"
REVIEW_PROMPT="${REVIEW_PROMPT//<ASPECT_FOCUS>/$ASPECT_FOCUS}"
REVIEW_PROMPT="${REVIEW_PROMPT//<REVIEW_ASPECT>/$REVIEW_ASPECT}"
REVIEW_PROMPT="${REVIEW_PROMPT//<ATTACHED_FILES>/$ATTACHED_BLOCK}"

# stdin から diff を読み取り
DIFF_INPUT=$(cat)

if [[ -z "$DIFF_INPUT" ]]; then
  jq -n --arg aspect "$REVIEW_ASPECT" '{findings: [], summary: "diff が空です", reviewer: "gemini (skipped: empty diff)", aspect: $aspect}'
  exit 0
fi

for model in "${MODELS[@]}"; do
  retry=0
  while [[ $retry -lt $MAX_RETRIES ]]; do
    wait_time=$(( BASE_WAIT * (2 ** retry) ))

    # Gemini CLI を非対話モードで実行
    RESULT=$(echo "$DIFF_INPUT" | gemini -m "$model" -p "$REVIEW_PROMPT" --output-format json 2>"$STDERR_TMPFILE") && EXIT_CODE=0 || EXIT_CODE=$?

    if [[ $EXIT_CODE -eq 0 ]] && [[ -n "$RESULT" ]]; then
      # JSON として有効か検証
      if echo "$RESULT" | jq -e 'type=="object" and (.findings|type=="array") and (.summary|type=="string")' >/dev/null 2>&1; then
        # 成功: レビュアー名を追加して出力
        echo "$RESULT" | jq --arg reviewer "gemini ($model)" --arg aspect "$REVIEW_ASPECT" '. + {reviewer: $reviewer, aspect: $aspect}'
        exit 0
      fi

      # JSON パースに失敗した場合、response フィールドから抽出を試みる
      EXTRACTED=$(echo "$RESULT" | jq -r '.response // empty' 2>/dev/null)
      if [[ -n "$EXTRACTED" ]]; then
        # response 内の JSON を jq で安全にパース
        JSON_BLOCK=$(echo "$EXTRACTED" | jq -e 'type=="object" and (.findings|type=="array") and (.summary|type=="string")' 2>/dev/null && echo "$EXTRACTED" | jq '.')
        if [[ -n "$JSON_BLOCK" ]] && echo "$JSON_BLOCK" | jq -e 'type=="object"' >/dev/null 2>&1; then
          echo "$JSON_BLOCK" | jq --arg reviewer "gemini ($model)" '. + {reviewer: $reviewer}'
          exit 0
        fi
      fi

      # JSON 抽出失敗 → リトライ
      >&2 echo "[gemini-review] $model: JSON パース失敗、リトライ $((retry + 1))/$MAX_RETRIES"
    else
      # エラー内容を確認
      STDERR_CONTENT=$(cat "$STDERR_TMPFILE" 2>/dev/null || echo "")

      if echo "$STDERR_CONTENT" | grep -qi "MODEL_CAPACITY_EXHAUSTED\|RESOURCE_EXHAUSTED\|429"; then
        CAPACITY_EXHAUSTED=1
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
if [[ $CAPACITY_EXHAUSTED -eq 1 ]]; then
  mkdir -p "$(dirname "$COOLDOWN_FILE")"
  touch "$COOLDOWN_FILE"
  >&2 echo "[gemini-review] 容量不足でクールダウン記録: $COOLDOWN_FILE"
fi
>&2 echo "[gemini-review] 全モデル・全リトライ失敗"
exit 1
