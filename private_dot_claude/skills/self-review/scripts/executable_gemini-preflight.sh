#!/bin/bash
# Gemini CLI ヘルスチェック (プリフライト)
# - 軽量プローブで Gemini の可用性を事前確認する
# - クールダウンキャッシュで短時間の再実行時はプローブを省略する
#
# Usage:
#   status=$(bash gemini-preflight.sh)
#   # status: "available" | "flash-only" | "unavailable"
#
# Env:
#   GEMINI_COOLDOWN_FILE     クールダウン記録ファイル (default: ~/.claude/skills/self-review/.gemini-cooldown)
#   GEMINI_COOLDOWN_SECONDS  クールダウン秒数 (default: 900 = 15分)
#   GEMINI_PROBE_TIMEOUT     プローブ1回あたりのタイムアウト秒 (default: 10)
#
# Exit codes:
#   0 - available または flash-only (Gemini 利用可)
#   1 - unavailable (Gemini 利用不可)

set -uo pipefail

COOLDOWN_FILE="${GEMINI_COOLDOWN_FILE:-$HOME/.claude/skills/self-review/.gemini-cooldown}"
COOLDOWN_SECONDS="${GEMINI_COOLDOWN_SECONDS:-900}"
PROBE_TIMEOUT="${GEMINI_PROBE_TIMEOUT:-10}"

# mtime 取得（macOS / Linux 両対応）
file_mtime() {
  local f="$1"
  if stat -f %m "$f" >/dev/null 2>&1; then
    stat -f %m "$f"
  else
    stat -c %Y "$f"
  fi
}

# クールダウン中ならプローブを省略して unavailable を返す
if [[ -f "$COOLDOWN_FILE" ]]; then
  MTIME=$(file_mtime "$COOLDOWN_FILE" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  ELAPSED=$((NOW - MTIME))
  if [[ $ELAPSED -lt $COOLDOWN_SECONDS ]]; then
    REMAINING=$((COOLDOWN_SECONDS - ELAPSED))
    >&2 echo "[gemini-preflight] クールダウン中 (残り ${REMAINING}s)、Gemini をスキップ"
    echo "unavailable"
    exit 1
  fi
  # 期限切れなら削除
  rm -f "$COOLDOWN_FILE" 2>/dev/null
fi

if ! command -v gemini >/dev/null 2>&1; then
  >&2 echo "[gemini-preflight] gemini CLI が見つかりません"
  echo "unavailable"
  exit 1
fi

# クロスプラットフォーム timeout ラッパー
# GNU timeout (Linux) / gtimeout (macOS coreutils) / perl alarm (macOS 標準) の順で試す
_timeout() {
  local dur="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$dur" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$dur" "$@"
  else
    perl -e 'my $d=shift; alarm $d; exec @ARGV or die "exec failed: $!"' "$dur" "$@"
  fi
}

# 軽量プローブ: 1モデルに対して 1 ショットだけ投げる
# return: 0 成功 / 2 容量不足 (429) / 1 その他エラー
probe_model() {
  local model="$1"
  local tmp_stderr
  tmp_stderr=$(mktemp /tmp/gemini-preflight-stderr.XXXXXX)
  local result=""
  local exit_code=0

  result=$(_timeout "$PROBE_TIMEOUT" gemini -m "$model" -p "reply with the single word OK" --output-format json 2>"$tmp_stderr") || exit_code=$?

  local stderr_content
  stderr_content=$(cat "$tmp_stderr" 2>/dev/null || echo "")
  rm -f "$tmp_stderr"

  if [[ $exit_code -eq 0 ]] && [[ -n "$result" ]]; then
    return 0
  fi

  if echo "$stderr_content" | grep -qi "MODEL_CAPACITY_EXHAUSTED\|RESOURCE_EXHAUSTED\|429"; then
    >&2 echo "[gemini-preflight] $model: 容量不足 (429)"
    return 2
  fi

  # timeout の exit code は 124
  if [[ $exit_code -eq 124 ]]; then
    >&2 echo "[gemini-preflight] $model: タイムアウト (${PROBE_TIMEOUT}s)"
  else
    >&2 echo "[gemini-preflight] $model: エラー (exit=$exit_code)"
  fi
  if [[ -n "$stderr_content" ]]; then
    >&2 echo "  stderr: $(echo "$stderr_content" | head -2)"
  fi
  return 1
}

# pro を試す
PRO_RESULT=0
probe_model "gemini-2.5-pro" || PRO_RESULT=$?

if [[ $PRO_RESULT -eq 0 ]]; then
  echo "available"
  exit 0
fi

# pro がダメなら flash
FLASH_RESULT=0
probe_model "gemini-2.5-flash" || FLASH_RESULT=$?

if [[ $FLASH_RESULT -eq 0 ]]; then
  echo "flash-only"
  exit 0
fi

# 両方ダメ: 429 が絡んでいたらクールダウン記録
if [[ $PRO_RESULT -eq 2 ]] || [[ $FLASH_RESULT -eq 2 ]]; then
  mkdir -p "$(dirname "$COOLDOWN_FILE")"
  touch "$COOLDOWN_FILE"
  >&2 echo "[gemini-preflight] 両モデル容量不足、クールダウン記録: $COOLDOWN_FILE (${COOLDOWN_SECONDS}s)"
fi

echo "unavailable"
exit 1
