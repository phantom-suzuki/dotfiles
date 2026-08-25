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
# - codex exec の呼び出しは lib-timeout.sh の _timeout でラップする（macOS に timeout
#   コマンドは無いため、素の timeout を直接使わないこと）。既定 300 秒、環境変数
#   CODEX_REVIEW_TIMEOUT で上書き可能。
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
# 環境変数:
#   CODEX_REVIEW_MODEL    codex exec に渡すモデル（default: gpt-5.6-terra）
#   CODEX_REVIEW_TIMEOUT  codex exec のタイムアウト秒数（default: 300）
#
# 出力:
#   stdout - codex の --output-last-message 内容（finding-schema.json 準拠 JSON を想定）
#            codex exec 自身が最終メッセージを stdout にも書くため、そちらは /dev/null へ
#            捨てて二重出力を防いでいる（本体は $TMP から cat する 1 回だけ）
#   stderr - 進行ログ
#
# Exit codes:
#   0 - 成功
#   1 - 依存コマンド不足 / 引数不足 / codex 実行失敗 / タイムアウト

set -uo pipefail

LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${LIB_DIR}/lib-timeout.sh"

CODEX_MODEL="${CODEX_REVIEW_MODEL:-gpt-5.6-terra}"
CODEX_REVIEW_TIMEOUT="${CODEX_REVIEW_TIMEOUT:-300}"

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
} | _timeout "$CODEX_REVIEW_TIMEOUT" codex exec \
  -c model="$CODEX_MODEL" \
  -c model_reasoning_effort=high \
  --output-schema "$SCHEMA" \
  --output-last-message "$TMP" \
  --sandbox read-only \
  ${CODEX_REPRO_FLAGS[@]+"${CODEX_REPRO_FLAGS[@]}"} \
  - \
  >/dev/null
# codex exec は最終メッセージを自身の stdout にも書くため、ここで /dev/null へ捨てる。
# 捨てないと --output-last-message ($TMP) の内容と合わせて同じ JSON が 2 回出力される
# （呼び出し側の validate-findings.sh が「JSON オブジェクトが複数連結されています」で
# 検出する不具合だった）。stderr は進行ログ・エラー診断に使うため捨てない。

EXIT_CODE=$?

# タイムアウト時の終了コードは _timeout がどの実装に落ちたかで変わる。
#   GNU timeout / gtimeout → 124
#   perl の alarm（timeout も gtimeout も無い macOS 標準環境）→ 142（128 + SIGALRM 14）
# macOS では 142 になるため、124 だけを見るとタイムアウト分岐が死にコードになる。
if [[ $EXIT_CODE -eq 124 || $EXIT_CODE -eq 142 ]]; then
  >&2 echo "[self-review] Codex がタイムアウトしました（${CODEX_REVIEW_TIMEOUT}秒）"
  exit 1
fi

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
