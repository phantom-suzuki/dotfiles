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
# Exit: 判定完了時は 0、実行エラー時は 1、引数エラー時は 2。
# 判定結果は最終行の STATE=... で返す。
#   STATE=POSTED        レビュー結果（walkthrough / actionable comments 等）が投稿された
#   STATE=REVIEWING     レビュー実行中の応答を確認
#   STATE=RATE_LIMITED  制限中。RETRY_AFTER 行に解除目安
#   STATE=OTHER         CodeRabbit 応答はあるが分類外（本文を確認）
#   STATE=NO_RESPONSE   監視窓内に新規応答なし（未起動 or 遅延）
#   STATE=ERROR         引数、GitHub API、またはコマンドのエラー
set -uo pipefail

PR=""; MODE="full"; REPO=""; POLL=30; MAX=8; DO_TRIGGER=1

die() {
  local message="$1"
  local code="${2:-1}"
  echo "ERROR: $message" >&2
  echo "STATE=ERROR"
  exit "$code"
}

require_value() {
  [ "$#" -ge 2 ] || die "$1 requires a value" 2
  [ -n "$2" ] || die "$1 requires a value" 2
  case "$2" in
    --*) die "$1 requires a value" 2;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) require_value "$@"; REPO="$2"; shift 2;;
    --mode) require_value "$@"; MODE="$2"; shift 2;;
    --poll) require_value "$@"; POLL="$2"; shift 2;;
    --max) require_value "$@"; MAX="$2"; shift 2;;
    --no-trigger) DO_TRIGGER=0; shift;;
    -h|--help)
      sed -n '2,/^set -uo pipefail$/p' "$0" \
        | grep -E '^#( |$)' \
        | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) die "unknown option $1" 2;;
    *) PR="$1"; shift;;
  esac
done

case "$PR" in
  ''|*[!0-9]*) die "PR number must be an integer greater than or equal to 1" 2;;
esac
[ "$PR" -ge 1 ] || die "PR number must be an integer greater than or equal to 1" 2

case "$POLL" in
  ''|*[!0-9]*) die "--poll must be an integer greater than or equal to 1" 2;;
esac
[ "$POLL" -ge 1 ] || die "--poll must be an integer greater than or equal to 1" 2

case "$MAX" in
  ''|*[!0-9]*) die "--max must be an integer greater than or equal to 1" 2;;
esac
[ "$MAX" -ge 1 ] || die "--max must be an integer greater than or equal to 1" 2

case "$MODE" in
  full|incremental|inc) ;;
  *) die "--mode は full|incremental" 2;;
esac

if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) \
    || die "repository resolution failed"
  [ -n "$REPO" ] || die "repository resolution returned an empty value"
fi

CR="${CODERABBIT_BOT:-coderabbitai[bot]}"
API="repos/$REPO/issues/$PR/comments"
MAX_FETCH_FAILURES=3

# 全ページを 1 配列に束ねて最新の CodeRabbit コメントを取る。
# 注意: この gh では --slurp と --jq は併用不可。--slurp の出力をパイプで jq に渡す。
# jq -c で valid JSON を返すので、呼び出し側で .body を再パースしても制御文字で壊れない
# （body を生テキストで取り出して別 jq に食わせると U+0000-001F で parse error になる）。
fetch_latest() {
  gh api --paginate --slurp "$API" \
    | jq -c --arg bot "$CR" \
      '(add // []) | map(select(.user.login==$bot)) | sort_by(.id) | last // empty'
}

# baseline: トリガー前の最新 CodeRabbit コメント ID。
# これより大きい ID の応答を「トリガー後の応答」とみなす。
baseline_json=$(fetch_latest) || die "failed to fetch the baseline CodeRabbit comment"
if [ -z "$baseline_json" ]; then
  baseline=0
else
  baseline=$(printf '%s' "$baseline_json" | jq -r '.id') \
    || die "failed to parse the baseline CodeRabbit comment"
fi

if [ "$DO_TRIGGER" -eq 1 ]; then
  case "$MODE" in
    full) CMD="@coderabbitai full review";;
    incremental|inc) CMD="@coderabbitai review";;
  esac
  if ! gh pr comment "$PR" --repo "$REPO" --body "$CMD" >/dev/null; then
    die "failed to post the CodeRabbit review trigger"
  fi
  echo "TRIGGERED mode=$MODE pr=#$PR repo=$REPO cmd=\"$CMD\""
fi

classify() {
  local body="$1"
  if printf '%s' "$body" | grep -qiE 'rate limit|Review limit reached|available in [0-9]+ (minute|hour)'; then
    echo "RATE_LIMITED"
  elif printf '%s' "$body" | grep -qiE 'Actionable comments posted|Walkthrough|Full review finished|summarize by coderabbit'; then
    echo "POSTED"
  elif printf '%s' "$body" | grep -qiE 'currently reviewing|review in progress|Reviewing your|Review triggered|Full review triggered'; then
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
  echo "RETRY_AFTER: 約 ${mins} 分後（目安 ${eta}）。解除前に再トリガーしても実レビューは実行されないため、解除まで待つこと。"
}

# --no-trigger: baseline 比較や poll をせず、現在の最新コメントをそのまま分類して即返す
# （新規応答を待つ意味がないため。既にトリガー済みの「今どうなっているか」確認用）
if [ "$DO_TRIGGER" -eq 0 ]; then
  latest=$(fetch_latest) || die "failed to fetch the latest CodeRabbit comment"
  if [ -z "$latest" ]; then
    echo "DETAIL: CodeRabbit のコメントがまだ 1 件もない"
    echo "STATE=NO_RESPONSE"
    exit 0
  fi
  t=$(printf '%s' "$latest" | jq -r '.created_at') \
    || die "failed to parse the latest CodeRabbit comment timestamp"
  body=$(printf '%s' "$latest" | jq -r '.body') \
    || die "failed to parse the latest CodeRabbit comment body"
  state=$(classify "$body")
  echo "OBSERVED: at=$t (--no-trigger 現状確認)"
  [ "$state" = "RATE_LIMITED" ] && report_rate_limit "$body"
  echo "--- CodeRabbit 応答（先頭 15 行） ---"
  printf '%s\n' "$body" | head -15
  echo "STATE=$state"
  exit 0
fi

i=0
fetch_failures=0
last_state=""
last_time=""
last_body=""
while [ "$i" -lt "$MAX" ]; do
  sleep "$POLL"; i=$((i+1))
  if ! latest=$(fetch_latest); then
    fetch_failures=$((fetch_failures+1))
    echo "WARN: CodeRabbit コメントの取得に失敗しました (${fetch_failures}/${MAX_FETCH_FAILURES})" >&2
    if [ "$fetch_failures" -ge "$MAX_FETCH_FAILURES" ]; then
      die "failed to fetch CodeRabbit comments ${MAX_FETCH_FAILURES} consecutive times"
    fi
    continue
  fi
  fetch_failures=0
  [ -n "$latest" ] || continue
  comment_id=$(printf '%s' "$latest" | jq -r '.id') \
    || die "failed to parse the latest CodeRabbit comment ID"
  [ "$comment_id" -gt "$baseline" ] || continue
  t=$(printf '%s' "$latest" | jq -r '.created_at') \
    || die "failed to parse the latest CodeRabbit comment timestamp"
  body=$(printf '%s' "$latest" | jq -r '.body') \
    || die "failed to parse the latest CodeRabbit comment body"
  state=$(classify "$body")
  if [ "$state" = "REVIEWING" ]; then
    last_state="$state"
    last_time="$t"
    last_body="$body"
    continue
  fi
  echo "OBSERVED: at=$t (poll $i/$MAX)"
  [ "$state" = "RATE_LIMITED" ] && report_rate_limit "$body"
  echo "--- CodeRabbit 応答（先頭 15 行） ---"
  printf '%s\n' "$body" | head -15
  echo "STATE=$state"
  exit 0
done

if [ "$fetch_failures" -gt 0 ]; then
  die "monitoring ended after ${fetch_failures} consecutive fetch failure(s)"
fi

if [ "$last_state" = "REVIEWING" ]; then
  echo "OBSERVED: at=$last_time (監視窓の終了時点でレビュー実行中)"
  echo "--- CodeRabbit 応答（先頭 15 行） ---"
  printf '%s\n' "$last_body" | head -15
  echo "STATE=REVIEWING"
  exit 0
fi

echo "DETAIL: ${MAX}×${POLL}s の監視で baseline 以降の新規 CodeRabbit 応答なし"
echo "HINT: CodeRabbit は受領時にまず 👀 リアクションのみ付けることがある。--poll/--max を増やすか、少し置いて --no-trigger で再確認する。"
echo "STATE=NO_RESPONSE"
exit 0
