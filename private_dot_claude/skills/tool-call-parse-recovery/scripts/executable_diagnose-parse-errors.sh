#!/usr/bin/env bash
# diagnose-parse-errors.sh
# "The model's tool call could not be parsed (retry also failed)." の発生を
# セッション transcript (.jsonl) から走査し、原因を Case A / Case B に分類する診断ツール。
#
# 分類の考え方:
#   各 "malformed and could not be parsed" 注入(retry 要求)の「直前の assistant ターン」を見る。
#     - 直前ターンに tool_use ブロックが無い  -> Case B（空thinking/欠落＝サーバー/ストリーミング側バグ）
#     - 直前ターンに tool_use ブロックが有る  -> Case A 候補（引数が壊れた＝hygiene で緩和可能）
#   ※「空 thinking ブロック単独」のターンは大半が正常な interleaved thinking のログであり、
#     直後に注入が無ければ失敗ではない。だから単独カウントせず、必ず注入とペアで判定する。
#
# 信頼できる失敗指標:
#   inject = retry 注入の回数（モデルが malformed を 1 回出すたびに 1）
#   final  = "retry also failed" の最終ハード失敗（isApiErrorMessage の合成メッセージのみ計上）
#
# Usage:
#   diagnose-parse-errors.sh                 # 全 project の transcript を走査
#   diagnose-parse-errors.sh <file.jsonl>    # 単一 transcript を走査
#   diagnose-parse-errors.sh --recent N      # 直近 N 個の transcript を走査 (default 10)
#   diagnose-parse-errors.sh --risk          # 失敗していなくても高リスク条件のセッションを列挙
#
# 依存: jq, awk

set -euo pipefail

PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

err() { printf '%s\n' "$*" >&2; }
command -v jq  >/dev/null 2>&1 || { err "jq が必要です";  exit 1; }
command -v awk >/dev/null 2>&1 || { err "awk が必要です"; exit 1; }

# --- 引数処理 ---------------------------------------------------------------
MODE="all"; RECENT_N=10; SINGLE=""
case "${1:-}" in
  --recent) MODE="recent"; RECENT_N="${2:-10}" ;;
  --risk)   MODE="risk" ;;
  "")       MODE="all" ;;
  -*)       err "unknown option: $1"; exit 2 ;;
  *)        MODE="single"; SINGLE="$1" ;;
esac

list_files() {
  case "$MODE" in
    single) printf '%s\n' "$SINGLE" ;;
    recent) ls -t "$PROJECTS_DIR"/*/*.jsonl 2>/dev/null | head -n "$RECENT_N" ;;
    *)      ls -t "$PROJECTS_DIR"/*/*.jsonl 2>/dev/null ;;
  esac
}

# 1 ファイルを走査し "inject caseB caseA final" を返す
classify_file() {
  jq -rc '
    if (.type=="assistant")
       and ((.message.model // "") | (. != "" and . != "<synthetic>"))
    then "A\t" + (if (any(.message.content[]?; .type=="tool_use")) then "1" else "0" end)
    elif (.type=="assistant") and ((.message.model // "")=="<synthetic>")
       and (((.message.content[0].text) // "") | test("retry also failed"))
    then "FIN"
    elif (.type=="user")
       and ((.message.content|type)=="string")
       and (.message.content | test("malformed and could not be parsed"))
    then "INJ"
    else empty end
  ' "$1" 2>/dev/null | awk '
    $1=="A"   { last_has=$2; have_last=1 }
    $1=="INJ" { inj++; if (have_last && last_has=="1") caseA++; else caseB++; have_last=0 }
    $1=="FIN" { fin++ }
    END { printf "%d %d %d %d\n", inj+0, caseB+0, caseA+0, fin+0 }
  '
}

# --- risk モード ------------------------------------------------------------
if [ "$MODE" = "risk" ]; then
  echo "== 高リスク条件のセッション（Opus 4.8 使用 + 長尺 + 直近更新） =="
  echo "  しきい値: model=claude-opus-4-8 を含む かつ 行数 >= 800"
  echo "  根拠: 長尺セッションほど empty-thinking ストリーム不全が累積しやすい（resume 回避の判断材料）"
  echo
  files=$(ls -t "$PROJECTS_DIR"/*/*.jsonl 2>/dev/null | head -n 30 || true)
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    uses_opus=$(grep -c '"model":"claude-opus-4-8"' "$f" 2>/dev/null || true); uses_opus=${uses_opus:-0}
    [ "${uses_opus%%$'\n'*}" -gt 0 ] 2>/dev/null || continue
    lines=$(wc -l < "$f" | tr -d ' ')
    if [ "$lines" -ge 800 ]; then
      read -r inj cb ca fin < <(classify_file "$f") || true
      printf '  [risk] %-40s lines=%-6s inject=%-3s caseB=%-3s\n' "$(basename "$f")" "$lines" "$inj" "$cb"
    fi
  done <<< "$files"
  echo
  echo "対処: 高リスクセッションは resume を避け新規開始を検討。/effort medium 一時切替も有効。"
  exit 0
fi

# --- 通常モード -------------------------------------------------------------
TOT_INJ=0; TOT_B=0; TOT_A=0; TOT_FIN=0; HIT=0
printf '%-42s %8s %8s %8s %8s\n' "session" "inject" "caseB" "caseA" "final"
printf '%s\n' "--------------------------------------------------------------------------------"
while read -r f; do
  [ -f "$f" ] || continue
  read -r inj cb ca fin < <(classify_file "$f") || true
  [ "$inj" -eq 0 ] && [ "$fin" -eq 0 ] && continue
  printf '%-42s %8s %8s %8s %8s\n' "$(basename "$f")" "$inj" "$cb" "$ca" "$fin"
  TOT_INJ=$((TOT_INJ+inj)); TOT_B=$((TOT_B+cb)); TOT_A=$((TOT_A+ca)); TOT_FIN=$((TOT_FIN+fin)); HIT=$((HIT+1))
done < <(list_files)

echo
echo "== サマリ =="
echo "  発生セッション数        : $HIT"
echo "  retry 注入総数(inject)  : $TOT_INJ"
echo "  └ Case B(tool_use 欠落) : $TOT_B"
echo "  └ Case A(引数破損候補)  : $TOT_A"
echo "  最終ハード失敗(final)   : $TOT_FIN"
echo
if [ "$TOT_INJ" -gt 0 ]; then
  ratio=$(( TOT_B * 100 / TOT_INJ ))
  echo "  → 失敗の ${ratio}% が Case B（サーバー側・ストリーミングバグ）"
  if [ "$ratio" -ge 70 ]; then
    echo "  → 主因は Case B。hygiene ルール(引数の書き方)では緩和不可。"
    echo "    対処: claude update / 新規セッション / /effort medium 一時切替 / /bug 報告。"
  elif [ "$ratio" -le 30 ]; then
    echo "  → 主因は Case A。tool-call-hygiene.md(引数の単純化)で緩和を。"
  else
    echo "  → Case A/B 混在。両方の対処を併用。"
  fi
fi
