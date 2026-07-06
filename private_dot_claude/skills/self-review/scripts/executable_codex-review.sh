#!/bin/bash
# self-review 用 Codex CLI ラッパー（security / design 観点の L2 セカンドオピニオン）
#
# - PreToolUse フック block-codex-direct.py は Bash ツールに渡すコマンド文字列の
#   「先頭トークン」だけを検査してブロックする。`codex exec ...` を Bash にそのまま渡すと
#   ブロックされるが、`bash codex-review.sh ...` の形でスクリプトファイルを呼び出す分には
#   検査対象外になる。そのため codex exec の呼び出しはこのスクリプト内に閉じ込める。
# - スキーマ強制（--output-schema）付きで codex exec を実行し、finding-schema.json 準拠の
#   JSON を stdout に出力する（--output-schema 非対応の `codex exec review` は使わない）。
#
# Usage:
#   cat <<'EOF' | bash codex-review.sh <schema-path> <prompt-body-file>
#   （diff 本文）
#   EOF
#
# 引数:
#   $1 - finding-schema.json への絶対パス
#   $2 - 観点別プロンプト本文を書いたファイル（review-prompt-template.md 組み立て済み）
#
# 標準入力:
#   diff 本文（git diff の出力）
#
# 出力:
#   stdout - codex の --output-last-message 内容（finding-schema.json 準拠 JSON を想定）
#   stderr - 進行ログ
#
# Exit codes:
#   0 - 成功
#   1 - 依存コマンド不足 / 引数不足 / codex 実行失敗

set -uo pipefail

if ! command -v codex >/dev/null 2>&1; then
  >&2 echo "[self-review] codex CLI が見つかりません。security/design 観点は他レビュアーにフォールバックしてください"
  exit 1
fi

SCHEMA="${1:-}"
PROMPT_FILE="${2:-}"

if [[ -z "$SCHEMA" || -z "$PROMPT_FILE" ]]; then
  >&2 echo "[self-review] Usage: codex-review.sh <schema-path> <prompt-body-file>"
  exit 1
fi

if [[ ! -f "$SCHEMA" ]]; then
  >&2 echo "[self-review] schema ファイルが見つかりません: $SCHEMA"
  exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  >&2 echo "[self-review] プロンプト本文ファイルが見つかりません: $PROMPT_FILE"
  exit 1
fi

# --ignore-user-config / --ignore-rules 可否判定（codex >= 0.122 で導入。古い codex では空にする）
if codex exec --help 2>&1 | grep -q -- "--ignore-user-config"; then
  CODEX_REPRO_FLAGS=(--ignore-user-config --ignore-rules)
else
  CODEX_REPRO_FLAGS=()
fi

umask 077
TMP=$(mktemp "${TMPDIR:-/tmp}/self-review-codex.XXXXXX.json")
trap 'rm -f "$TMP"' EXIT

>&2 echo "[self-review] Codex レビュー実行中..."

{
  echo "## 以下の diff をレビューしてください。"
  echo ""
  echo "## レビュー指示"
  cat "$PROMPT_FILE"
  echo ""
  echo "## DIFF"
  echo '```diff'
  cat -
  echo '```'
} | codex exec \
  -c model_reasoning_effort=high \
  --output-schema "$SCHEMA" \
  --output-last-message "$TMP" \
  --sandbox read-only \
  "${CODEX_REPRO_FLAGS[@]}" \
  -

EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  >&2 echo "[self-review] Codex 実行失敗 (exit=$EXIT_CODE)"
  exit 1
fi

if [[ ! -s "$TMP" ]]; then
  >&2 echo "[self-review] Codex から出力を取得できませんでした"
  exit 1
fi

cat "$TMP"
exit 0
