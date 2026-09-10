# アカウント切り替え運用（Codex / Claude Code）

Codex CLI を複数アカウントで使い分け、Claude Code は rate limit 接近時にアカウント切替を示唆する仕組みのセットアップ手順。dotfiles(chezmoi) で全マシンに配布される。

- **Codex**: `CODEX_HOME` で設定ディレクトリごとアカウントを分離（2 アカウント: 個人 / 仕事）
- **Claude Code**: 認証は macOS Keychain 単一エントリのため設定ディレクトリ分離では切替不可。代わりに statusLine で rate limit 残量を監視し、上限接近時に通知で切替を促す

---

## 前提

| 項目 | 値 |
|---|---|
| Codex 設定ホーム | `~/.codex`（既定）/ `CODEX_HOME` で変更 |
| Codex 認証ファイル | `<CODEX_HOME>/auth.json` |
| Claude 認証 | macOS Keychain（service=`Claude Code-credentials`, account=OS ユーザー名）。`CLAUDE_CONFIG_DIR` では分離されない |
| direnv | `eval "$(direnv hook zsh)"` を zshrc 末尾で読み込み（chezmoi 配布済み） |

---

## A. Codex — 2 アカウント切替

### 命名（割当はユーザー判断）

| ディレクトリ | 位置づけ |
|---|---|
| `~/.codex` | 現在ログイン中の主アカウント（既存。env 不要） |
| `~/.codex-work` | 追加するもう一方のアカウント |

> どちらを個人/仕事に割り当てるかは自由。`~/.codex` は今ログインしている方をそのまま使う。

### セットアップ（各マシンで初回のみ・手動）

`codex login` は対話ログインのため自動化不可。手動で実行する。

```bash
# 1) もう一方のアカウントでログイン（新しい CODEX_HOME に独立して作られる）
CODEX_HOME=~/.codex-work codex login

# 2) 共有したい設定を反映
#    - config.toml はコピー（codex が atomic write で symlink を壊すため symlink にしない）
#    - AGENTS.md は symlink（codex が書き換えないので安全）
cp ~/.codex/config.toml ~/.codex-work/config.toml
ln -sf ~/.codex/AGENTS.md ~/.codex-work/AGENTS.md
```

> プロジェクトの trust は config.toml をコピーすれば引き継がれる。以後に新しく trust したディレクトリは各アカウント別管理になる（初回プロンプトで承認すればよい）。

### 使い方

```bash
# 主アカウント（既定）
codex

# work アカウント（レートリミット時の退避先など）— zsh エイリアス
codex-work
```

### ワークスペースごとの自動切替（direnv）

特定リポジトリで常に work アカウントを使いたいとき:

```bash
# リポジトリ root で 1 回だけ実行（.envrc 生成 + git-exclude + direnv allow）
codex-use-work
```

`codex-use-work`（zsh 関数）は次を行う:

1. リポ root に `.envrc`（`export CODEX_HOME=$HOME/.codex-work`）を生成
2. `.git/info/exclude` に `.envrc` を追記（コミットされない＝同僚に影響しない）
3. `direnv allow` を実行

以後そのリポに `cd` すると自動で `~/.codex-work` に切替わり、出ると主アカウントに戻る。

> 雛形: `docs/templates/codex-work.envrc`

---

## B. Claude Code — rate limit 接近の示唆だし

`~/.claude/statusline.sh`（chezmoi: `private_dot_claude/executable_statusline.sh`）が statusLine の JSON から rate limit 残量を読み、ステータスラインに表示しつつ上限接近時に通知する。

### 挙動

| 使用率 | 表示 | ローカル制御への通知依頼 |
|---|---|---|
| < 80% | 緑ゲージ（wide/medium のみ。`5h:NN%`） | なし |
| 80–94% | 黄ゲージ | `prepare`（切替準備） |
| 95–99% | 赤太字 `⚠ NN%` | `switch`（切替） |
| 100% | 赤太字 `⚠ NN%` | `stop`（停止） |

- 5 時間枠（`five_hour`）と 7 日枠（`seven_day`）の高い方を表示。通知依頼は枠ごとに出す
- `rate_limits` は **Claude.ai Pro/Max のみ**・最初の API レスポンス後に出現。無い場合は従来表示のまま
- statusline 自身は macOS 通知を出さない。アカウント管理の作業ツリー（既定 `~/work/claude-code-account-manager`、環境変数 `CLAUDE_ACCOUNT_MANAGER_DIR` で変更可）にフラグファイル `state/auto-event-enabled` があるときだけ、同ツリーの `rotation-local notify` を背景で 1 回呼ぶ。通知の表示と重複抑制（アカウント・リセット時刻・段階ごと）はそのローカル制御が担う。フラグが無いマシンでは色の変化だけになる
- statusline 側は、同じ枠・リセット時刻・段階の呼び出しを 15 秒間だけ間引く（描画のたびに同じプロセスを起こさないため）。枠が変わっても呼び出しを抑え込む長期のマーカーは持たない
- 通知値にはアカウントidentityがない。通知ではアカウントを断定せず、手動切替の開始後にCLIとUIで本人を照合する
- Fableなどstatuslineに含まれない限定枠は検知できず、値の欠落を「制限なし」と扱わない

### しきい値の変更

環境変数で上書き可能（既定 80 / 95）:

```bash
export CLAUDE_RL_WARN=80
export CLAUDE_RL_CRIT=95
```

### Claude のアカウント切替（手動）

通知が出たら、このCodexタスクへ「Claude切替して」と依頼する。Codexが対象アカウントをUIで照合してから切替える。Claude Codeだけで手動切替する場合は:

```
/login   # Claude Code 内で別アカウントにログインし直す（Keychain が入れ替わる）
```

> Claude は Keychain 単一エントリのため、Codex のような同時並行のディレクトリ別運用はできない。切替は「ログインし直し」になる点に注意。

---

## 他マシンでの再現

chezmoi apply で自動反映されるもの:

- `dot_zshrc.tmpl` → `codex-work` / `codex-use-work` / direnv hook
- `private_dot_claude/executable_statusline.sh` → rate limit 監視
- `.chezmoiignore` に `docs/` 追記（このドキュメントが `~/docs/` に展開されないように）

各マシンで手動が必要なもの（自動化不可）:

- `CODEX_HOME=~/.codex-work codex login`（対話ログイン）
- `config.toml` のコピー / `AGENTS.md` の symlink（上記 A のセットアップ）
- direnv 未導入なら `brew install direnv`
