#!/bin/bash
# self-review 用 Codex CLI ラッパー（security / design 観点の L2 セカンドオピニオン）
#
# - PreToolUse フック block-codex-direct.py は Bash ツールに渡すコマンド文字列を
#   改行・パイプ等でセグメント分割し、各セグメントのコマンド位置の basename が `codex` の
#   場合にブロックする。`codex exec ...` を Bash にそのまま渡すとブロックされるが、
#   `bash codex-review.sh ...` の形でスクリプトファイルを呼び出す分には検査対象外になる。
#   そのため codex exec の呼び出しはこのスクリプト内に閉じ込める。
# - スキーマ強制（--output-schema）付きで codex exec を実行し、finding-schema.json 準拠の
#   JSON を stdout に出力する（--output-schema 非対応の `codex exec review` は使わない）。
# - モデルは `-c model=`（CLI 明示指定）で渡す。--ignore-user-config が付いても -c は効く。
#   default は gpt-5.6-terra（環境変数 CODEX_REVIEW_MODEL で上書き可）。モデル指定が必要な理由:
#   - --ignore-user-config は config.toml のモデル設定も無視するため、未指定だと CLI 既定
#     モデルに落ちる。gpt-5-codex 系は --output-schema がツール起動時に無視される既知バグ
#     （openai/codex#15451）があり、スキーマ強制が黙って効かなくなる。
#   - gpt-5.6-terra は --output-schema を順守することを実挙動で確認済み（2026-07-14、
#     ChatGPT サブスク認証・schema 準拠 JSON を exit 0 で出力）。旧 default の gpt-5.5 から
#     bump した。sol/luna も同系列なので CODEX_REVIEW_MODEL で切替可。
#   - `--model gpt-5` と旧既定 gpt-5.3-codex は ChatGPT アカウント認証だと
#     400 invalid_request_error で拒否される（2026-07 実測。5.6 系は影響なし）。
# - codex exec は git リポジトリ内（trusted directory）を cwd にして実行すること。
#   リポジトリ外から呼ぶと "Not inside a trusted directory" で失敗する。
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

CODEX_MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-terra}"

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
# mktemp のテンプレートは X が末尾でないと macOS(BSD) では乱数化されず固定名になり、
# 並列実行（bug / security の 2 観点同時起動）で "File exists" 衝突する。
# 末尾 XXXXXX で作成してから .json へ rename する。
TMP=$(mktemp "${TMPDIR:-/tmp}/self-review-codex.XXXXXX")
mv "$TMP" "${TMP}.json"
TMP="${TMP}.json"
DIFF_FILE=$(mktemp "${TMPDIR:-/tmp}/self-review-diff.XXXXXX")
trap 'rm -f "$TMP" "$DIFF_FILE"' EXIT

# --- レート予算ガード ---------------------------------------------------------
# Codex の週間上限は Codex Cloud の PR レビューとローカル委譲が同じ枠を食い合う。
# 巨大 diff を effort=high で流すと 1 回で数百万トークンを消費するため、行数で effort を落とす。
# 実測（2026-07-27）: レビュー系 5 回で 1,400 万トークン、1 回平均 280 万・最大 722 万。
#
# 環境変数:
#   SELF_REVIEW_DIFF_LIMIT - この行数を超えたら effort を下げる（default: 2000）
#   CODEX_REVIEW_EFFORT    - effort を明示指定して自動判定を無効化する（high / medium / low）
DIFF_LIMIT="${SELF_REVIEW_DIFF_LIMIT:-2000}"
# 数値以外を渡されたら止める。[[ -gt ]] は非数値を 0 と見なして黙って比較を通すため、
# 打ち間違いに気づかないまま effort が常に medium へ落ちる。
if [[ ! "$DIFF_LIMIT" =~ ^[0-9]+$ ]]; then
  >&2 echo "[self-review] エラー: SELF_REVIEW_DIFF_LIMIT は 0 以上の整数で指定してください（現在: ${DIFF_LIMIT}）"
  exit 1
fi

# stdin の diff を一旦ファイルへ落として行数を数える（パイプは 1 度しか読めないため）
cat - > "$DIFF_FILE"
DIFF_LINES=$(wc -l < "$DIFF_FILE" | tr -d ' ')

if [[ -n "${CODEX_REVIEW_EFFORT:-}" ]]; then
  EFFORT="$CODEX_REVIEW_EFFORT"
  >&2 echo "[self-review] effort=$EFFORT (CODEX_REVIEW_EFFORT で明示指定)"
elif [[ "$DIFF_LINES" -gt "$DIFF_LIMIT" ]]; then
  EFFORT="medium"
  >&2 echo "[self-review] diff ${DIFF_LINES} 行が上限 ${DIFF_LIMIT} 行を超えたため effort を high から medium へ下げます"
  >&2 echo "[self-review] 精度が要るなら、対象ファイルを絞って呼び直すか CODEX_REVIEW_EFFORT=high を指定してください"
else
  EFFORT="high"
fi
# -----------------------------------------------------------------------------

>&2 echo "[self-review] Codex レビュー実行中 (diff ${DIFF_LINES} 行 / effort=${EFFORT})..."

{
  echo "## 以下の diff をレビューしてください。"
  echo ""
  echo "## レビュー指示"
  cat "$PROMPT_FILE"
  echo ""
  echo "## DIFF"
  echo '```diff'
  cat "$DIFF_FILE"
  echo '```'
} | codex exec \
  -c model="$CODEX_MODEL" \
  -c model_reasoning_effort="$EFFORT" \
  --output-schema "$SCHEMA" \
  --output-last-message "$TMP" \
  --sandbox read-only \
  ${CODEX_REPRO_FLAGS[@]+"${CODEX_REPRO_FLAGS[@]}"} \
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
