#!/bin/bash
# peer-review 用 Codex CLI ラッパー
# - `codex exec review --base <branch>` で対象 PR のレビューを実施し、
#   最終 agent_message を抽出して stdout に出力する
# - Codex は実コードへの grep/sed を即時実行できるため、L2 の独立セカンドオピニオン
#   として使う（実装整合・コード変更の論理整合に強い）
#
# Usage:
#   bash codex-review.sh <PR番号> [base-branch]
#
#   - base-branch を省略した場合は `gh pr view <PR> --json baseRefName` から自動取得
#
# 出力:
#   stdout: 抽出した agent_message のテキスト（最終レビュー結論）
#   stderr: 進行ログ
#
# Exit codes:
#   0 - 成功（agent_message を stdout に出力）
#   1 - Codex 実行失敗 or agent_message が見つからず
#
# 内部仕様:
#   - `--base` と PROMPT は併用不可（codex CLI の引数排他）。よって PROMPT は渡さず、
#     codex review の標準観点に任せる。プロジェクト固有のコンテキストは L1 Claude 側で扱う
#   - `--ignore-user-config --ignore-rules` でユーザー設定の差異を排除
#   - `--json` で JSONL 出力。最終 `agent_message` を jq で抽出
#   - `-o <file>` の `output-last-message` は agent_message が空の場合も発生するため、
#     JSONL 側の抽出を primary、`-o` ファイルを fallback とする

set -uo pipefail

# 依存確認
if ! command -v jq >/dev/null 2>&1; then
  >&2 echo "[peer-review] jq が必要です。brew install jq 等でインストールしてください"
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  >&2 echo "[peer-review] codex CLI が必要です。インストール後に再実行してください"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  >&2 echo "[peer-review] gh CLI が必要です"
  exit 1
fi

PR_NUMBER="${1:-}"
BASE_BRANCH="${2:-}"

if [[ -z "$PR_NUMBER" ]]; then
  >&2 echo "[peer-review] Usage: bash codex-review.sh <PR番号> [base-branch]"
  exit 1
fi

# base branch を自動取得（明示指定がなければ）
if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH=$(gh pr view "$PR_NUMBER" --json baseRefName --jq .baseRefName 2>/dev/null || echo "")
  if [[ -z "$BASE_BRANCH" ]]; then
    >&2 echo "[peer-review] PR #$PR_NUMBER の base branch を取得できませんでした"
    exit 1
  fi
  >&2 echo "[peer-review] base branch: $BASE_BRANCH (auto-detected)"
fi

JSONL_FILE=$(mktemp /tmp/peer-review-codex-XXXXXX.jsonl)
LAST_FILE=$(mktemp /tmp/peer-review-codex-last-XXXXXX.txt)
trap 'rm -f "$JSONL_FILE" "$LAST_FILE"' EXIT

# --- レート予算ガード ---------------------------------------------------------
# Codex の週間上限は Codex Cloud の PR レビューとローカル委譲が同じ枠を食い合う。
# 巨大 PR を effort=high でレビューすると 1 回で数百万トークンを消費するため、
# 変更行数（additions + deletions）で effort を落とす。
# 実測（2026-07-27）: レビュー系 5 回で 1,400 万トークン、1 回平均 280 万・最大 722 万。
#
# 環境変数:
#   PEER_REVIEW_DIFF_LIMIT - この行数を超えたら effort を下げる（default: 2000）
#   CODEX_REVIEW_EFFORT    - effort を明示指定して自動判定を無効化する（high / medium / low）
DIFF_LIMIT="${PEER_REVIEW_DIFF_LIMIT:-2000}"
# 数値以外を渡されたら止める。[[ -gt ]] は非数値を 0 と見なして黙って比較を通すため、
# 打ち間違いに気づかないまま effort が常に medium へ落ちる。
if [[ ! "$DIFF_LIMIT" =~ ^[0-9]+$ ]]; then
  >&2 echo "[peer-review] エラー: PEER_REVIEW_DIFF_LIMIT は 0 以上の整数で指定してください（現在: ${DIFF_LIMIT}）"
  exit 1
fi

CHANGED_LINES=$(gh pr view "$PR_NUMBER" --json additions,deletions \
  --jq '.additions + .deletions' 2>/dev/null || echo "")

if [[ -n "${CODEX_REVIEW_EFFORT:-}" ]]; then
  EFFORT="$CODEX_REVIEW_EFFORT"
  >&2 echo "[peer-review] effort=$EFFORT (CODEX_REVIEW_EFFORT で明示指定)"
elif [[ -z "$CHANGED_LINES" ]]; then
  EFFORT="high"
  >&2 echo "[peer-review] 変更行数を取得できませんでした。effort=high で続行します"
elif [[ "$CHANGED_LINES" -gt "$DIFF_LIMIT" ]]; then
  EFFORT="medium"
  >&2 echo "[peer-review] 変更 ${CHANGED_LINES} 行が上限 ${DIFF_LIMIT} 行を超えたため effort を high から medium へ下げます"
  >&2 echo "[peer-review] 精度が要るなら PR を分割するか CODEX_REVIEW_EFFORT=high を指定してください"
else
  EFFORT="high"
fi
# -----------------------------------------------------------------------------

>&2 echo "[peer-review] Codex review 実行中 (base=$BASE_BRANCH / 変更 ${CHANGED_LINES:-?} 行 / effort=${EFFORT})..."

# Codex を非対話で実行。PROMPT は渡さない（--base と排他のため）
# -c model_reasoning_effort: L2 セカンドオピニオンは質が命なので既定は high。
#   ただし巨大 PR ではレート枠を守るため上のガードが medium へ落とす。
#   --ignore-user-config で config.toml を無視するため、-c 明示指定で effort を上書きする
#   （委譲パスのグローバル default は medium に下げてレートを節約しているが、低頻度な
#    レビューだけは high を選ぶメリハリ運用）
codex exec review \
  -c model_reasoning_effort="$EFFORT" \
  --base "$BASE_BRANCH" \
  --json \
  --ignore-user-config \
  --ignore-rules \
  -o "$LAST_FILE" \
  > "$JSONL_FILE" 2>/dev/null

EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  >&2 echo "[peer-review] Codex 実行失敗 (exit=$EXIT_CODE)"
  exit 1
fi

# JSONL から最終 agent_message を抽出（primary）
AGENT_MESSAGE=$(jq -r 'select(.type=="item.completed" and .item.type=="agent_message") | .item.text' "$JSONL_FILE" 2>/dev/null | tail -1)

# Fallback: --output-last-message ファイル
if [[ -z "$AGENT_MESSAGE" ]] && [[ -s "$LAST_FILE" ]]; then
  AGENT_MESSAGE=$(cat "$LAST_FILE")
fi

if [[ -z "$AGENT_MESSAGE" ]]; then
  >&2 echo "[peer-review] Codex から agent_message を取得できませんでした"
  >&2 echo "[peer-review] JSONL イベント種別:"
  jq -r '.type' "$JSONL_FILE" 2>/dev/null | sort | uniq -c >&2
  exit 1
fi

# 実行した command_execution 数（参考情報として stderr に出力）
CMD_COUNT=$(jq -c 'select(.type=="item.completed" and .item.type=="command_execution")' "$JSONL_FILE" 2>/dev/null | wc -l | tr -d ' ')
>&2 echo "[peer-review] Codex 完了 (実コード探索: ${CMD_COUNT} コマンド)"

echo "$AGENT_MESSAGE"
exit 0
