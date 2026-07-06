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
# モデル判定について（重要）:
#   Case A / Case B の分類フレームはモデル非依存の普遍的な知見であり、どのモデルでも成立する。
#   一方「どのモデルで Case B が多いか」はモデル・環境で変わる。よって本スクリプトは特定モデル名を
#   ハードコードせず、transcript から実際の実行モデルを抽出してモデル別に集計する。
#   既知の高リスク構成は下の KNOWN_RISK_PATTERNS にデータとして持ち、照合結果を注記するだけにする。
#   未知モデル（例: claude-fable-5）は unknown 扱いで集計だけ出す。比率の解釈は実測を見て判断する。
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

# --- 既知の高リスク構成テーブル（データ）------------------------------------
# 形式: "モデル名の正規表現|ラベル|根拠メモ"
# ここに列挙したモデルは risk モードで [risk] として注記する。ここに無いモデルは unknown 扱い。
# 新しいモデルの実測が集まったら、このテーブルに 1 行追加するだけで判定に反映される。
KNOWN_RISK_PATTERNS=(
  'claude-opus-4-7|Opus 4.7|2026-05〜06 実測: extended thinking + 1M context で Case B (tool_use 欠落) 多発'
  'claude-opus-4-8|Opus 4.8|2026-05〜06 実測: extended thinking + 1M context で Case B (tool_use 欠落) 多発'
)
# risk モードで「長尺」とみなす行数しきい値（長尺ほど empty-thinking の累積が起きやすい）
RISK_LINES="${RISK_LINES:-800}"

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

# 1 ファイルで使われた実行モデル名（<synthetic> を除く）を一意に列挙する
models_in_file() {
  jq -rc 'select(.type=="assistant") | .message.model // empty' "$1" 2>/dev/null \
    | grep -v '^<synthetic>$' | sort -u || true
}

# 与えたモデル名が既知高リスクパターンに一致すればラベルを返す（無ければ空）
risk_label_for() {
  local m="$1" entry pat rest lbl
  for entry in "${KNOWN_RISK_PATTERNS[@]}"; do
    pat="${entry%%|*}"; rest="${entry#*|}"; lbl="${rest%%|*}"
    if printf '%s' "$m" | grep -Eq "$pat"; then printf '%s' "$lbl"; return 0; fi
  done
  return 1
}

# 1 ファイルを走査し、モデル別に "M\t<model>\t<inj>\t<caseB>\t<caseA>\t<final>" を返す。
# 直前の real-model assistant ターンに tool_use が有れば Case A、無ければ Case B。
# inject は直前の実行モデルに帰属させる（追えない場合は unknown）。
classify_file() {
  jq -rc '
    if (.type=="assistant")
       and ((.message.model // "") | (. != "" and . != "<synthetic>"))
    then "A\t" + (.message.model) + "\t" + (if (any(.message.content[]?; .type=="tool_use")) then "1" else "0" end)
    elif (.type=="assistant") and ((.message.model // "")=="<synthetic>")
       and (((.message.content[0].text) // "") | test("retry also failed"))
    then "FIN"
    elif (.type=="user")
       and ((.message.content|type)=="string")
       and (.message.content | test("malformed and could not be parsed"))
    then "INJ"
    else empty end
  ' "$1" 2>/dev/null | awk -F'\t' '
    $1=="A"   { last_has=$3; last_model=$2; have_last=1 }
    $1=="INJ" {
      m = (last_model!="") ? last_model : "unknown"
      inj[m]++
      if (have_last && last_has=="1") ca[m]++; else cb[m]++
      have_last=0
    }
    $1=="FIN" { m = (last_model!="") ? last_model : "unknown"; fin[m]++ }
    END {
      for (m in inj) seen[m]=1
      for (m in fin) seen[m]=1
      for (m in seen) printf "M\t%s\t%d\t%d\t%d\t%d\n", m, inj[m]+0, cb[m]+0, ca[m]+0, fin[m]+0
    }
  '
}

# --- risk モード ------------------------------------------------------------
if [ "$MODE" = "risk" ]; then
  echo "== 高リスク条件のセッション（既知高リスクモデル + 長尺 + 直近更新） =="
  echo "  しきい値: 行数 >= ${RISK_LINES}。既知高リスクモデルは以下（KNOWN_RISK_PATTERNS）:"
  for entry in "${KNOWN_RISK_PATTERNS[@]}"; do
    _rest="${entry#*|}"
    echo "    - ${entry%%|*}  ${_rest%%|*}: ${_rest#*|}"
  done
  echo "  未知モデルは [unknown] として集計のみ表示（比率は実測で判断する）。"
  echo "  根拠: 長尺セッションほど empty-thinking ストリーム不全が累積しやすい（resume 回避の判断材料）"
  echo
  files=$(ls -t "$PROJECTS_DIR"/*/*.jsonl 2>/dev/null | head -n 30 || true)
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    lines=$(wc -l < "$f" | tr -d ' ')
    [ "$lines" -ge "$RISK_LINES" ] || continue
    mods=$(models_in_file "$f")
    [ -n "$mods" ] || continue
    file_risk="unknown"; model_desc=""
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      if lbl=$(risk_label_for "$m"); then
        file_risk="known"; model_desc="${model_desc} ${m}(${lbl},known)"
      else
        model_desc="${model_desc} ${m}(unknown)"
      fi
    done <<EOF
$mods
EOF
    finj=0; fcb=0
    while IFS=$'\t' read -r tag _model inj cb _ca _fin; do
      [ "$tag" = "M" ] || continue
      finj=$((finj+inj)); fcb=$((fcb+cb))
    done <<EOF
$(classify_file "$f")
EOF
    label=$([ "$file_risk" = "known" ] && echo "[risk]" || echo "[unknown]")
    printf '  %-9s %-38s lines=%-6s inject=%-3s caseB=%-3s models:%s\n' \
      "$label" "$(basename "$f")" "$lines" "$finj" "$fcb" "$model_desc"
  done <<< "$files"
  echo
  echo "対処: 高リスクセッションは resume を避け新規開始を検討。/effort medium 一時切替も有効。"
  echo "      未知モデルで inject/caseB が高い場合は、そのモデルを KNOWN_RISK_PATTERNS に追記して運用に反映する。"
  exit 0
fi

# --- 通常モード -------------------------------------------------------------
TOT_INJ=0; TOT_B=0; TOT_A=0; TOT_FIN=0; HIT=0
ALL_MODEL_LINES=""
printf '%-42s %8s %8s %8s %8s\n' "session" "inject" "caseB" "caseA" "final"
printf '%s\n' "--------------------------------------------------------------------------------"
while read -r f; do
  [ -f "$f" ] || continue
  out="$(classify_file "$f")"
  [ -n "$out" ] || continue
  finj=0; fcb=0; fca=0; ffin=0
  while IFS=$'\t' read -r tag model inj cb ca fin; do
    [ "$tag" = "M" ] || continue
    finj=$((finj+inj)); fcb=$((fcb+cb)); fca=$((fca+ca)); ffin=$((ffin+fin))
    ALL_MODEL_LINES="${ALL_MODEL_LINES}${model}\t${inj}\t${cb}\t${ca}\t${fin}\n"
  done <<EOF
$out
EOF
  [ "$finj" -eq 0 ] && [ "$ffin" -eq 0 ] && continue
  printf '%-42s %8s %8s %8s %8s\n' "$(basename "$f")" "$finj" "$fcb" "$fca" "$ffin"
  TOT_INJ=$((TOT_INJ+finj)); TOT_B=$((TOT_B+fcb)); TOT_A=$((TOT_A+fca)); TOT_FIN=$((TOT_FIN+ffin)); HIT=$((HIT+1))
done < <(list_files)

echo
echo "== サマリ（全モデル合算） =="
echo "  発生セッション数        : $HIT"
echo "  retry 注入総数(inject)  : $TOT_INJ"
echo "  └ Case B(tool_use 欠落) : $TOT_B"
echo "  └ Case A(引数破損候補)  : $TOT_A"
echo "  最終ハード失敗(final)   : $TOT_FIN"
echo

if [ -n "$ALL_MODEL_LINES" ]; then
  echo "== モデル別内訳 =="
  echo "  （Case B 比率はモデル・環境で変わる。特定モデルの断定はせず、実測値として読む）"
  printf '%b' "$ALL_MODEL_LINES" | awk -F'\t' '
    NF>=5 { inj[$1]+=$2; cb[$1]+=$3; ca[$1]+=$4; fin[$1]+=$5 }
    END {
      for (m in inj) {
        ratio = (inj[m]>0) ? int(cb[m]*100/inj[m]) : 0
        printf "  %-26s inject=%-4d caseB=%-4d caseA=%-4d final=%-4d  (Case B %d%%)\n", \
          m, inj[m], cb[m], ca[m], fin[m], ratio
      }
    }'
  echo
fi

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
  echo "  ※ この比率は上記「モデル別内訳」の実測に基づく。モデルや環境が変われば再度このスクリプトで取り直す。"
fi
