#!/bin/bash
# Codex の 2 つ目のアカウント（~/.codex-work）を使える状態にするセットアップスクリプト。
#
# 何をするか:
#   1. 前提（direnv / 主アカウントのログイン / 2 つ目のログイン）を確認する
#   2. 主アカウントの config.toml を初回だけコピーし、AGENTS.md をシンボリックリンクで共有する
#   3. 使い方を表示する
#
# 何をしないか:
#   - ログインは代行しない。対話操作であり、このマシンの PreToolUse フック
#     block-codex-direct.py が Bash ツール経由の codex 実行をブロックするため。
#     未ログインならログイン用の 1 行を案内して終了する。
#   - 自動フェイルオーバー（上限検知で自動的にアカウントを切り替える仕組み）は作らない。
#     委譲先 Codex の常駐プロセスへの割り込みが壊れやすいため、切替は手動に留める。
#
# Usage:
#   bash setup-work-account.sh              # セットアップを実行する
#   bash setup-work-account.sh --check      # 状態を確認するだけ（変更しない）
#   bash setup-work-account.sh --pin        # カレント git リポを 2 つ目のアカウントに固定する（direnv が必要）
#
# Exit codes:
#   0 - 完了（--check は状態表示のみで 0）
#   1 - 前提を満たしていない（主アカウント未ログイン等）
#   2 - 2 つ目のアカウントが未ログイン。案内を表示済み

set -uo pipefail

MAIN_HOME="$HOME/.codex"
WORK_HOME="$HOME/.codex-work"
MODE="${1:-setup}"

# 認証済みかどうかを判定する。codex は auth.json に認証情報を書く。
is_logged_in() {
  [[ -f "$1/auth.json" ]]
}

print_status() {
  echo "現在の状態:"
  echo "  主アカウント   ($MAIN_HOME):      $(is_logged_in "$MAIN_HOME" && echo 'ログイン済' || echo '未ログイン')"
  echo "  2 つ目         ($WORK_HOME): $(is_logged_in "$WORK_HOME" && echo 'ログイン済' || echo '未ログイン')"
  echo "  CODEX_HOME:                       ${CODEX_HOME:-（未設定 = 主アカウント）}"
  if command -v direnv >/dev/null 2>&1; then
    echo "  direnv:                           導入済（リポジトリ単位の固定が使える）"
  else
    echo "  direnv:                           未導入（brew install direnv でリポジトリ単位の固定が使える）"
  fi
}

print_login_hint() {
  echo ""
  echo "2 つ目のアカウントにログインしてください。Claude Code からは代行できません。"
  echo "Claude Code のプロンプトに次の 1 行を貼るか、ターミナルで直接実行します。"
  echo ""
  echo "  ! CODEX_HOME=$WORK_HOME codex login"
  echo ""
  echo "ログイン後にこのスクリプトを再実行すると、設定の共有まで済みます。"
}

# --- リポジトリ固定モード -----------------------------------------------------
if [[ "$MODE" == "--pin" ]]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "エラー: git リポジトリの中で実行してください" >&2
    exit 1
  }
  # .envrc は direnv 専用のファイルで、direnv が無いと読まれない。未導入のまま書いても
  # 固定は効かないので、先に失敗させる。
  if ! command -v direnv >/dev/null 2>&1; then
    echo "エラー: --pin には direnv が必要です。brew install direnv で導入してください" >&2
    exit 1
  fi
  # $HOME はここでは展開しない。.envrc の中に文字列のまま置き、direnv の読み込み時に展開させる。
  # shellcheck disable=SC2016
  pin_line='export CODEX_HOME=$HOME/.codex-work'
  if [[ ! -e "$root/.envrc" ]]; then
    printf '%s\n' "$pin_line" > "$root/.envrc"
  elif ! grep -qxF "$pin_line" "$root/.envrc"; then
    # 既存の .envrc には他の設定が入っている可能性がある。上書きせず手動追記に委ねる。
    echo "エラー: 既存の $root/.envrc を上書きしません。次の 1 行を手動で追記してください" >&2
    echo "" >&2
    echo "  $pin_line" >&2
    exit 1
  fi
  if ! grep -qxF '.envrc' "$root/.git/info/exclude" 2>/dev/null; then
    echo '.envrc' >> "$root/.git/info/exclude"
  fi
  direnv allow "$root"
  echo "固定しました: $(basename "$root") → $WORK_HOME"
  echo ""
  echo "このリポジトリでは 'cd $root && claude' と中から起動してください。"
  echo "claude の起動時に CODEX_HOME が決まるため、起動後の cd では切り替わりません。"
  exit 0
fi

# --- 状態確認モード -----------------------------------------------------------
if [[ "$MODE" == "--check" ]]; then
  print_status
  if ! is_logged_in "$WORK_HOME"; then
    print_login_hint
  fi
  exit 0
fi

# --- セットアップ本体 ---------------------------------------------------------
print_status
echo ""

if ! is_logged_in "$MAIN_HOME"; then
  echo "エラー: 主アカウントが未ログインです。先に次を実行してください。" >&2
  echo "" >&2
  echo "  ! codex login" >&2
  exit 1
fi

if ! is_logged_in "$WORK_HOME"; then
  print_login_hint
  exit 2
fi

# config.toml はコピーする。codex が書き込むとき atomic write でシンボリックリンクを
# 置き換えてしまうため、リンクでは共有できない。
# コピーは初回だけにする。再実行で上書きすると、work 側で codex が書いた設定
# （config.toml は chezmoi 管理外なので直接編集が正）が確認なしに消えるため。
if [[ -e "$WORK_HOME/config.toml" ]]; then
  echo "保持しました: 既存の work 側 config.toml（主アカウントの内容で上書きしません）"
  echo "  主アカウントの設定へ揃え直すなら、次を手動で実行します。" >&2
  echo "    cp $MAIN_HOME/config.toml $WORK_HOME/config.toml" >&2
elif [[ -f "$MAIN_HOME/config.toml" ]]; then
  cp "$MAIN_HOME/config.toml" "$WORK_HOME/config.toml"
  echo "コピーしました: config.toml"
else
  echo "警告: $MAIN_HOME/config.toml が見つかりません。コピーを飛ばします" >&2
fi

# AGENTS.md は codex が書き換えないのでシンボリックリンクで共有できる。
if [[ -f "$MAIN_HOME/AGENTS.md" ]]; then
  ln -sf "$MAIN_HOME/AGENTS.md" "$WORK_HOME/AGENTS.md"
  echo "リンクしました: AGENTS.md → $MAIN_HOME/AGENTS.md"
else
  echo "警告: $MAIN_HOME/AGENTS.md が見つかりません。リンクを飛ばします" >&2
fi

echo ""
echo "セットアップが完了しました。使い方は次のとおりです。"
echo ""
echo "  1. 2 つ目のアカウントで Codex を使う:"
echo "       codex-work                      # zshrc のエイリアス"
echo ""
echo "  2. 2 つ目のアカウントで Claude Code を起動する（委譲先 Codex も切り替わる）:"
echo "       CODEX_HOME=$WORK_HOME claude"
echo ""
echo "  3. 特定のリポジトリを 2 つ目のアカウントに固定する:"
echo "       bash $0 --pin                   # そのリポジトリの中で実行する"
echo ""
echo "主アカウントが週間上限に達したら、2 で起動し直して退避します。"
exit 0
