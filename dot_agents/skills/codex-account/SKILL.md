---
name: codex-account
description: Codex CLI のアカウント切替・レート制限時の手動退避に使い、CODEX_HOME で設定と認証を分離する。既定アカウントだけで完結する通常のコーディング作業には使わない。
---

# Codex Account Switch Skill

Codex CLI の設定ホームを `CODEX_HOME` で分離します。主アカウントは `~/.codex`、もう一方は `~/.codex-work` を使います。
Claude Code から起動する場合も、委譲先 Codex は親プロセスの `CODEX_HOME` を引き継ぎます。**claude を起動したシェルの `CODEX_HOME` が委譲先 Codex のアカウントを決めます**。

正本ドキュメント（再現手順の詳細）: dotfiles の `docs/account-switching.md`

`~/.codex/config.toml` は chezmoi 管理外です。直接編集した内容は永続し、dotfiles リポジトリには含まれません。

## 確定運用（この構成で管理する）

| 項目 | 方針 |
|---|---|
| 既定アカウント | `~/.codex`（主）。全リポでこれ。env 不要 |
| もう一方 | `~/.codex-work` |
| 別アカウントが要るリポ | そのリポで `.envrc` に `CODEX_HOME` を pin（git-exclude する） |
| 起動の習慣 | Claude Code 経由では、pin したリポは `cd <repo> && claude` で**中から起動**（委譲先 Codex が自動でそのアカウントになる） |
| レートリミット退避 | **手動**。`codex-work` で起動し直す。自動 failover ラッパーは作らない |
| 切替の粒度 | プロセスの起動単位。Claude Code 経由では claude を起動し直す。セッション中の `cd` では切替わらない（別アカウントなら起動し直す） |

## 手順

ユーザーの意図に応じて、以下のいずれかを実施します。

### 0. セットアップスクリプト（推奨。手順 A・B をまとめて実行する）

このスクリプトは前提チェックと設定の共有を行います。ログインは代行せず、未ログインならログイン用の 1 行を表示して終了します。

```bash
bash ~/.agents/skills/codex-account/scripts/setup-work-account.sh --check   # 状態を見るだけ
bash ~/.agents/skills/codex-account/scripts/setup-work-account.sh           # セットアップを実行
bash ~/.agents/skills/codex-account/scripts/setup-work-account.sh --pin     # カレントリポを固定
```

スクリプトには Claude Code 向けの案内が残っています。Codex では、ログイン用コマンドの先頭の `!` を外し、ユーザーのターミナルで実行してもらいます。
その後スクリプトを再実行すると、`config.toml` のコピーと `AGENTS.md` のシンボリックリンクまで済みます。

以下の A・B は、スクリプト内部の処理です。手作業で追う場合に参照します。

### A. 初回セットアップ（もう一方のアカウントを追加する）

1. **前提チェック**:
   ```bash
   command -v direnv >/dev/null && echo "direnv: OK" || echo "direnv: 未導入（brew install direnv が必要）"
   [[ -d ~/.codex ]] && echo "主アカウント: OK" || echo "主アカウント: 未ログイン"
   [[ -f ~/.codex-work/auth.json ]] && echo "work: ログイン済" || echo "work: 未ログイン"
   ```

2. **work が未ログインなら、ユーザーにログインを依頼**（対話ログインは代行しない）。
   次の一行をユーザーのターミナルで実行してもらう:
   ```
   CODEX_HOME=~/.codex-work codex login
   ```

3. **ログイン確認後、設定を共有**:
   ```bash
   cp ~/.codex/config.toml ~/.codex-work/config.toml
   ln -sf ~/.codex/AGENTS.md ~/.codex-work/AGENTS.md
   ```
   > config.toml はコピー（codex の atomic write で symlink が壊れるため）。AGENTS.md は codex が書き換えないので symlink で共有。

### B. リポジトリを work アカウントに pin する

カレント git リポを `~/.codex-work` に固定します。以下は zsh 関数 `codex-use-work` と同等の処理です。

```bash
root=$(git rev-parse --show-toplevel) || { echo "git リポ外"; exit 1; }
echo 'export CODEX_HOME=$HOME/.codex-work' > "$root/.envrc"
grep -qxF '.envrc' "$root/.git/info/exclude" 2>/dev/null || echo '.envrc' >> "$root/.git/info/exclude"
command -v direnv >/dev/null && direnv allow "$root"
echo "pinned $(basename "$root") -> ~/.codex-work (.envrc は git-excluded)"
```

Claude Code 経由で使う場合は、pin 後にそのリポで **`cd <repo> && claude`** と起動するよう案内します。claude 起動時に `CODEX_HOME` が確定します。

### C. 状態確認 / ヘルスチェック

```bash
echo "主 (~/.codex):       $([[ -f ~/.codex/auth.json ]] && echo logged-in || echo none)"
echo "work (~/.codex-work): $([[ -f ~/.codex-work/auth.json ]] && echo logged-in || echo none)"
echo "現在の CODEX_HOME: ${CODEX_HOME:-(未設定 = 主アカウント)}"
```

pin 済みリポの検索は `~/work` の深さ 3 までとします。
```bash
find ~/work -maxdepth 3 -name .envrc -exec grep -l 'CODEX_HOME' {} + 2>/dev/null
```

## レートリミット退避（手動）

主アカウントが上限に達したら、ユーザーが別アカウントで起動し直します。
```bash
# シェルで（エイリアスは zshrc 定義済み）
codex-work
```
自動 failover（429 検知で別アカウント再試行するラッパー）は作りません。委譲先 Codex の常駐プロセスへの割り込みが壊れやすいためです。

## アンチパターン

| ❌ NG | ✅ OK |
|---|---|
| config.toml を symlink 共有 | config.toml はコピー、AGENTS.md のみ symlink |
| 自動レートリミット failover ラッパーを作る | 手動で `codex-work` 起動し直す |
| セッション中に cd で切替わると期待 | 別アカウントなら起動し直す。Claude Code 経由では claude を再起動 |

## 認証が切れているときの見分け方

この構成では Codex CLI の認証を `~/.codex/auth.json`（または `$CODEX_HOME/auth.json`）に保存します。
このファイルが無ければ CLI は未認証です。委譲もレビュー系スクリプトも `401 Unauthorized: Missing bearer or basic authentication in header` で失敗します。

確認時の注意点は次のとおりです。

- **Codex デスクトップアプリや Web の ChatGPT にログインしていても、CLI の認証とは別物**である。
  アプリ側でアカウントを切り替えても `auth.json` は作られない
- 週間上限に達したときのエラーは 401 ではなく利用制限のメッセージになる。
  401 が出たら上限ではなく**ログイン切れ**を疑う

復旧時はログインし直します。ユーザーにターミナルで `codex login`（2 つ目なら `CODEX_HOME=$HOME/.codex-work codex login`）の実行を依頼します。

## 関連

- `~/.agents/skills/codex-account/scripts/setup-work-account.sh` — セットアップ・状態確認・リポジトリ固定を行うスクリプト
- `~/.config`（dotfiles）の `docs/account-switching.md` — 再現手順の正本
- `~/.zshrc` の `codex-work` エイリアス / `codex-use-work` 関数 / direnv hook
