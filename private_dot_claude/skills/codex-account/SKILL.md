---
name: codex-account
description: Codex CLI の複数アカウントを CODEX_HOME 方式で管理・切替する。「Codex のアカウント切替」「Codex を別アカウントで」「Codex のアカウント追加/設定」「ワークスペースごとに Codex アカウント」「codex-work セットアップ」「Codex のレートリミット退避」等の依頼時に使用。
---

# Codex Account Switch Skill

Codex CLI を複数アカウント（主 = `~/.codex` / もう一方 = `~/.codex-work`）で使い分ける。
設定ホームを `CODEX_HOME` で分離する方式。Claude Code が委譲で起動する Codex は親プロセスの
`CODEX_HOME` をそのまま引き継ぐため、**claude を起動したシェルの `CODEX_HOME` がそのまま委譲先 Codex のアカウントになる**。

正本ドキュメント（再現手順の詳細）: dotfiles の `docs/account-switching.md`

## 確定運用（この構成で管理する）

| 項目 | 方針 |
|---|---|
| 既定アカウント | `~/.codex`（主）。全リポでこれ。env 不要 |
| もう一方 | `~/.codex-work` |
| 別アカウントが要るリポ | そのリポで `.envrc` に `CODEX_HOME` を pin（git-exclude する） |
| 起動の習慣 | pin したリポは `cd <repo> && claude` で**中から起動**（委譲先 Codex が自動でそのアカウントになる） |
| レートリミット退避 | **手動**。`codex-work` で起動し直す。自動 failover ラッパーは作らない |
| 切替の粒度 | claude の起動単位。セッション中の `cd` では切替わらない（別アカウントなら起動し直す） |

## 重要な環境制約（必ず守る）

このマシンには「Bash でコマンド位置のトークン basename が `codex` のものを deny する」hook がある。

- ❌ **やってはいけない**: `codex login` 等を **Bash ツールで実行**（hook に deny される）
- ❌ **やってはいけない**: `grep -E 'a|codex|b'` のように `codex` を **パイプ区切りの裸トークン**として書く（hook の naive splitter が誤検知する）
- ✅ **OK**: `cp ~/.codex/config.toml ...` のように **パス引数に codex を含める**のは問題ない（コマンド位置ではない）
- ✅ **codex login は対話＆hook 対象のため、ユーザーに `!` プレフィックスで実行してもらう**（`!` はユーザー自身のシェルで走り、Bash ツール hook の対象外）

## 手順

ユーザーの意図に応じて、以下のいずれかを実施する。

### A. 初回セットアップ（もう一方のアカウントを追加する）

1. **前提チェック**（Bash 可）:
   ```bash
   command -v direnv >/dev/null && echo "direnv: OK" || echo "direnv: 未導入（brew install direnv が必要）"
   [[ -d ~/.codex ]] && echo "主アカウント: OK" || echo "主アカウント: 未ログイン"
   [[ -f ~/.codex-work/auth.json ]] && echo "work: ログイン済" || echo "work: 未ログイン"
   ```

2. **work が未ログインなら、ユーザーにログインを依頼**（Claude は実行しない）。
   次の一行をプロンプトに貼って実行してもらう:
   ```
   ! CODEX_HOME=~/.codex-work codex login
   ```
   > 対話ログインのため Claude では代行不可。`!` プレフィックスでユーザーのシェルで実行する。

3. **ログイン確認後、設定を共有**（Bash 可）:
   ```bash
   cp ~/.codex/config.toml ~/.codex-work/config.toml
   ln -sf ~/.codex/AGENTS.md ~/.codex-work/AGENTS.md
   ```
   > config.toml はコピー（codex の atomic write で symlink が壊れるため）。AGENTS.md は codex が書き換えないので symlink で共有。

### B. リポジトリを work アカウントに pin する

カレント git リポを `~/.codex-work` に固定する。zsh 関数 `codex-use-work` と同等の処理を Bash で行う:

```bash
root=$(git rev-parse --show-toplevel) || { echo "git リポ外"; exit 1; }
echo 'export CODEX_HOME=$HOME/.codex-work' > "$root/.envrc"
grep -qxF '.envrc' "$root/.git/info/exclude" 2>/dev/null || echo '.envrc' >> "$root/.git/info/exclude"
command -v direnv >/dev/null && direnv allow "$root"
echo "pinned $(basename "$root") -> ~/.codex-work (.envrc は git-excluded)"
```

pin 後は、そのリポで **`cd <repo> && claude`** と中から起動するようユーザーに伝える
（claude 起動時に `CODEX_HOME` が確定するため）。

### C. 状態確認 / ヘルスチェック

```bash
echo "主 (~/.codex):       $([[ -f ~/.codex/auth.json ]] && echo logged-in || echo none)"
echo "work (~/.codex-work): $([[ -f ~/.codex-work/auth.json ]] && echo logged-in || echo none)"
echo "現在の CODEX_HOME: ${CODEX_HOME:-(未設定 = 主アカウント)}"
```

pin 済みリポを探す:
```bash
find ~/work -maxdepth 3 -name .envrc -exec grep -l 'CODEX_HOME' {} + 2>/dev/null
```

## レートリミット退避（B 軸・手動）

主アカウントが上限に達したら、別アカウントで起動し直すだけ:
```bash
# シェルで（エイリアスは zshrc 定義済み）
codex-work
```
自動 failover（429 検知で別アカウント再試行するラッパー）は、委譲先 Codex の常駐プロセスへの
割り込みが壊れやすいため**作らない**。

## アンチパターン

| ❌ NG | ✅ OK |
|---|---|
| `codex login` を Bash ツールで実行 | ユーザーに `! CODEX_HOME=~/.codex-work codex login` を依頼 |
| `grep 'x|codex|y'` のように codex を裸トークンで書く | パターンから codex を外す / 別語で grep |
| config.toml を symlink 共有 | config.toml はコピー、AGENTS.md のみ symlink |
| 自動レートリミット failover ラッパーを作る | 手動で `codex-work` 起動し直す |
| セッション中に cd で切替わると期待 | 別アカウントなら claude を起動し直す |

## 関連

- `~/.config`（dotfiles）の `docs/account-switching.md` — 再現手順の正本
- `~/.zshrc` の `codex-work` エイリアス / `codex-use-work` 関数 / direnv hook
- `~/.claude/hooks/block-codex-direct.py` — codex 直叩きブロック hook
