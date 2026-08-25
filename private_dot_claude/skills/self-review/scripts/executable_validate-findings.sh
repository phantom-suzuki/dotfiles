#!/bin/bash
# self-review 用: 外部レビュアー出力の検証・正規化ゲート。
#
# 背景: claude -p / codex exec はシェルの終了コードが 0 でも、出力が空・壊れた
# JSON・スキーマ違反であることがある。呼び出し側（司令塔）がこれを見分けずに
# 「指摘 0 件」と誤報告する事故が起きたため、専用の検証ステップを設ける。
# 検証を通過していない出力は「失敗」として扱い、fallback レビュアーへ進むこと。
#
# claude -p と codex exec（scripts/codex-review.sh）は出力の形が異なる:
#   - claude -p --output-format json: ラッパー形式。
#       .is_error / .subtype / .structured_output（本体） / .result（人間向けテキスト）
#   - scripts/codex-review.sh: {"findings":[...], "summary":"..."} を裸で返す
# 本スクリプトはこの差異を吸収し、どちらの形式でも同じ正規化済み JSON を返す。
#
# Usage:
#   validate-findings.sh <出力ファイルのパス>
#
# 標準出力:
#   検証を通過した場合、正規化した単一 JSON オブジェクト（findings 配列 + summary）
#
# 標準エラー:
#   失敗理由（[self-review] 接頭辞）
#
# Exit codes:
#   0 - 検証通過
#   1 - 検証失敗

set -uo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
  >&2 echo "[self-review] Usage: validate-findings.sh <output-file-path>"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  >&2 echo "[self-review] jq が見つかりません"
  exit 1
fi

# 1. ファイルが存在し、サイズが 0 でないこと
if [[ ! -s "$FILE" ]]; then
  >&2 echo "[self-review] レビュアーが出力を返しませんでした（ファイルが存在しないか空です）: $FILE"
  exit 1
fi

# 2〜3. jq -s でスラープし、妥当な JSON か・オブジェクトが何個連結されているかを同時に見る
#       （codex-review.sh が codex exec 自身の stdout 出力と --output-last-message の
#       内容を両方吐いて JSON が 2 個連結される、といった二重出力を検出する）
SLURPED=$(jq -s -c '.' "$FILE" 2>/dev/null)
if [[ $? -ne 0 || -z "$SLURPED" ]]; then
  >&2 echo "[self-review] 妥当な JSON としてパースできませんでした: $FILE"
  exit 1
fi

COUNT=$(echo "$SLURPED" | jq 'length')

if [[ "$COUNT" -eq 0 ]]; then
  >&2 echo "[self-review] JSON オブジェクトが見つかりませんでした: $FILE"
  exit 1
fi

if [[ "$COUNT" -gt 1 ]]; then
  >&2 echo "[self-review] JSON オブジェクトが複数連結されています（${COUNT} 個）。レビュアー呼び出し側の二重出力を疑ってください: $FILE"
  exit 1
fi

RAW=$(echo "$SLURPED" | jq -c '.[0]')

# 4. 形を判定して正規化する
#    claude -p のラッパー形式は is_error キーの有無で見分ける（.structured_output の型では
#    見分けない。エラー時は structured_output が null になり得るため、型だけで判定すると
#    is_error: true の実エラーを「findings を含む JSON ではありません」に誤分類してしまう）。
IS_WRAPPER=$(echo "$RAW" | jq -c 'has("is_error")' 2>/dev/null)
HAS_TOPLEVEL_FINDINGS=$(echo "$RAW" | jq -c '(.findings? | type) == "array"' 2>/dev/null)

if [[ "$IS_WRAPPER" == "true" ]]; then
  # claude -p のラッパー形式
  # 5. is_error が true なら失敗として扱う（理由に .result の先頭 200 文字を添える）
  IS_ERROR=$(echo "$RAW" | jq -r '.is_error // false')
  if [[ "$IS_ERROR" == "true" ]]; then
    RESULT_HEAD=$(echo "$RAW" | jq -r '.result // ""' | cut -c1-200)
    >&2 echo "[self-review] claude -p がエラーを返しました（is_error: true）: ${RESULT_HEAD}"
    exit 1
  fi
  # structured_output が無い/オブジェクトでない異常系は、下の findings 配列チェック（手順 6）で捕捉する
  NORMALIZED=$(echo "$RAW" | jq -c '.structured_output')
elif [[ "$HAS_TOPLEVEL_FINDINGS" == "true" ]]; then
  # Codex 形式（トップレベルに findings をそのまま持つ）
  NORMALIZED="$RAW"
else
  >&2 echo "[self-review] findings を含む JSON ではありません（claude -p の structured_output も、トップレベルの findings 配列も見つかりません）: $FILE"
  exit 1
fi

# 6. 採用したオブジェクトの .findings が配列であることを確認する
FINDINGS_IS_ARRAY=$(echo "$NORMALIZED" | jq -c '(.findings? | type) == "array"' 2>/dev/null)
if [[ "$FINDINGS_IS_ARRAY" != "true" ]]; then
  >&2 echo "[self-review] findings が配列ではありません: $FILE"
  exit 1
fi

echo "$NORMALIZED"
exit 0
