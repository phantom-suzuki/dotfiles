#!/usr/bin/env bash
# CodeRabbit review trigger + startup monitor.
#
# CodeRabbit へレビューをトリガーし、その後の応答コメントを poll して
# 「起動した / rate limit で制限中 / 結果投稿済み / 応答なし」を判定する。
# rate limit の場合は "available in N minutes/hours" をパースし解除目安を出す。
# approve は本スクリプトの範囲外（coderabbit-approve スキルへ）。
#
# Usage:
#   trigger-and-watch.sh <PR> [--repo owner/repo] [--mode full|incremental]
#                        [--poll SECONDS] [--max COUNT] [--no-trigger]
#
# Options:
#   --repo        owner/repo（省略時は `gh repo view` から解決）
#   --mode        full=全体再レビュー(既定) / incremental=増分レビュー
#   --poll        poll 間隔秒（既定 30）
#   --max         poll 最大回数（既定 8。既定で最大 4 分監視）
#   --no-trigger  トリガーせず監視のみ（既にトリガー済みの状態確認に使う）
#
# Exit: 常に 0。判定結果は最終行の STATE=... で返す。
#   STATE=POSTED        レビュー結果（walkthrough / actionable comments 等）が投稿された
#   STATE=REVIEWING     レビュー実行中の応答を確認
#   STATE=RATE_LIMITED  制限中。RETRY_AFTER 行に解除目安
#   STATE=OTHER         CodeRabbit 応答はあるが分類外（本文を確認）
#   STATE=NO_RESPONSE   監視窓内に新規応答なし（未起動 or 遅延）
set -uo pipefail

PR=""; MODE="full"; REPO=""; POLL=30; MAX=8; DO_TRIGGER=1
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2;;
    --mode) MODE="${2:-}"; shift 2;;
    --poll) POLL="${2:-}"; shift 2;;
    --max) MAX="${2:-}"; shift 2;;
    --no-trigger) DO_TRIGGER=0; shift;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    -*) echo "ERROR: unknown option $1" >&2; exit 2;;
    *) PR="$1"; shift;;
  esac
done

[ -n "$PR" ] || { echo "ERROR: PR number required" >&2; exit 2; }
[ -n "$REPO" ] || REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

CR="coderabbitai[bot]"
API="repos/$REPO/issues/$PR/comments"

# 全ページを 1 配列に束ねて最新の CodeRabbit コメントを取る。
# 注意: この gh では --slurp と --jq は併用不可。--slurp の出力をパイプで jq に渡す。
# jq -c で valid JSON を返すので、呼び出し側で .body を再パースしても制御文字で壊れない
# （body を生テキストで取り出して別 jq に食わせると U+0000-001F で parse error になる）。
fetch_latest() {
  gh api --paginate --slurp "$API" 2>/dev/null \
    | jq -c 'add | map(select(.user.login=="coderabbitai[bot]")) | sort_by(.created_at) | last // empty' 2>/dev/null
}

# baseline: トリガー前の最新 CodeRabbit コメント時刻。これより後の応答を「トリガー後の応答」とみなす。
baseline=$(fetch_latest | jq -r '.created_at // ""' 2>/dev/null || echo "")

if [ "$DO_TRIGGER" -eq 1 ]; then
  case "$MODE" in
    full) CMD="@coderabbitai full review";;
    incremental|inc) CMD="@coderabbitai review";;
    *) echo "ERROR: --mode は full|incremental" >&2; exit 2;;
  esac
  gh pr comment "$PR" --repo "$REPO" --body "$CMD" >/dev/null \
    && echo "TRIGGERED mode=$MODE pr=#$PR repo=$REPO cmd=\"$CMD\""
fi

classify() {
  local body="$1"
  if printf '%s' "$body" | grep -qiE 'rate limit|Review limit reached|available in [0-9]+ (minute|hour)'; then
    echo "RATE_LIMITED"
  elif printf '%s' "$body" | grep -qiE 'Actionable comments posted|Walkthrough|Full review finished|summarize by coderabbit'; then
    echo "POSTED"
  elif printf '%s' "$body" | grep -qiE 'currently reviewing|review in progress|Reviewing your'; then
    echo "REVIEWING"
  else
    echo "OTHER"
  fi
}

report_rate_limit() {
  local body="$1"
  local phrase num unit mins eta
  phrase=$(printf '%s' "$body" | grep -oiE 'available in [0-9]+ (minutes?|hours?)' | head -1 || true)
  echo "RATE_LIMIT_DETAIL: ${phrase:-（解除時刻の明記なし。本文を確認）}"
  num=$(printf '%s' "$phrase" | grep -oE '[0-9]+' | head -1 || true)
  unit=$(printf '%s' "$phrase" | grep -oiE 'minute|hour' | head -1 || true)
  [ -n "$num" ] || return 0
  case "$unit" in hour*) mins=$((num*60));; *) mins=$num;; esac
  # BSD date(macOS) → GNU date の順で解除目安時刻を算出（best-effort）
  eta=$(date -u -v+"${mins}"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d "+${mins} minutes" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "?")
  echo "RETRY_AFTER: 約 ${mins} 分後（目安 ${eta}）。解除前の再トリガーは再び skip されるだけなので待つこと。"
}

# --no-trigger: baseline 比較や poll をせず、現在の最新コメントをそのまま分類して即返す
# （新規応答を待つ意味がないため。既にトリガー済みの「今どうなっているか」確認用）
if [ "$DO_TRIGGER" -eq 0 ]; then
  latest=$(fetch_latest)
  if [ -z "$latest" ]; then
    echo "STATE=NO_RESPONSE  (CodeRabbit のコメントがまだ 1 件もない)"
    exit 0
  fi
  t=$(printf '%s' "$latest" | jq -r '.created_at')
  body=$(printf '%s' "$latest" | jq -r '.body')
  state=$(classify "$body")
  echo "STATE=$state  at=$t  (--no-trigger 現状確認)"
  [ "$state" = "RATE_LIMITED" ] && report_rate_limit "$body"
  echo "--- CodeRabbit 応答（先頭 15 行） ---"
  printf '%s\n' "$body" | head -15
  exit 0
fi

i=0
while [ "$i" -lt "$MAX" ]; do
  sleep "$POLL"; i=$((i+1))
  latest=$(fetch_latest)
  [ -n "$latest" ] || continue
  t=$(printf '%s' "$latest" | jq -r '.created_at')
  newer=0
  if [ -z "$baseline" ]; then newer=1
  elif [[ "$t" > "$baseline" ]]; then newer=1
  fi
  [ "$newer" -eq 1 ] || continue
  body=$(printf '%s' "$latest" | jq -r '.body')
  state=$(classify "$body")
  echo "STATE=$state  at=$t  (poll $i/$MAX)"
  [ "$state" = "RATE_LIMITED" ] && report_rate_limit "$body"
  echo "--- CodeRabbit 応答（先頭 15 行） ---"
  printf '%s\n' "$body" | head -15
  exit 0
done

echo "STATE=NO_RESPONSE  (${MAX}×${POLL}s 監視で baseline 以降の新規 CodeRabbit 応答なし)"
echo "HINT: CodeRabbit は受領時にまず 👀 リアクションのみ付けることがある。--poll/--max を増やすか、少し置いて --no-trigger で再確認する。"
exit 0
