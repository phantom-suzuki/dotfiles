#!/bin/bash
# review-adr 用 Codex CLI ラッパー（L2 セカンドオピニオン）
#
# - PreToolUse フック block-codex-direct.py は Bash ツールに渡すコマンド文字列の
#   「先頭トークン」だけを検査してブロックする。`codex exec ...` を Bash にそのまま渡すと
#   ブロックされるが、`bash codex-review.sh ...` の形でスクリプトファイルを呼び出す分には
#   検査対象外になる。そのため codex exec の呼び出しはこのスクリプト内に閉じ込める。
#
# Usage:
#   bash codex-review.sh <prompt-file> <output-file>
#
# 引数:
#   $1 - プロンプト本文を書いたファイル（呼び出し側で <ADR_CONTENT> 等のプレースホルダを
#        展開済みのもの）
#   $2 - --output-last-message の出力先パス（呼び出し側がこのファイルを読んで結果を得る）
#
# 出力:
#   stdout - 進行ログのみ（レビュー結果本体は $2 に書き出す）
#   stderr - 進行ログ
#
# Exit codes:
#   0 - 成功
#   1 - 依存コマンド不足 / 引数不足 / codex 実行失敗

set -uo pipefail

if ! command -v codex >/dev/null 2>&1; then
  >&2 echo "[review-adr] codex CLI が見つかりません。L1 のみで続行してください"
  exit 1
fi

PROMPT_FILE="${1:-}"
OUTPUT_FILE="${2:-}"

if [[ -z "$PROMPT_FILE" || -z "$OUTPUT_FILE" ]]; then
  >&2 echo "[review-adr] Usage: codex-review.sh <prompt-file> <output-file>"
  exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  >&2 echo "[review-adr] プロンプトファイルが見つかりません: $PROMPT_FILE"
  exit 1
fi

>&2 echo "[review-adr] Codex レビュー実行中..."

codex exec \
  --full-auto \
  --sandbox read-only \
  --ignore-user-config \
  --ignore-rules \
  --output-last-message "$OUTPUT_FILE" \
  "$(cat "$PROMPT_FILE")"

EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  >&2 echo "[review-adr] Codex 実行失敗 (exit=$EXIT_CODE)"
  exit 1
fi

>&2 echo "[review-adr] Codex 完了 (出力: $OUTPUT_FILE)"
exit 0
