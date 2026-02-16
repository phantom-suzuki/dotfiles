# dotfiles

[chezmoi](https://www.chezmoi.io/) で管理する dotfiles リポジトリ。

## 含まれる設定

| ツール | 説明 |
|--------|------|
| WezTerm | モジュラー構成のターミナルエミュレータ設定（7ファイル） |
| Neovim | LazyVim ベースの設定 |
| zsh + Prezto | シェル設定 + Prezto フレームワーク |
| Starship | プロンプト設定 |
| tmux | ターミナルマルチプレクサ設定 |
| Git | エイリアス・ユーザー設定（テンプレート） |
| GitHub CLI | gh コマンド設定 |
| SSH | クライアント設定 |
| Claude Code | グローバル指示・コーディング規約・hooks |

## 新マシンへのセットアップ

### 1コマンドでセットアップ

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply phantom-suzuki
```

Git ユーザー名・メールアドレスの入力を求められます。

### 手動セットアップ

```bash
# chezmoi インストール
brew install chezmoi

# 初期化 & 適用
chezmoi init phantom-suzuki
chezmoi apply
```

## 日常の操作

```bash
# 設定ファイルの変更を取り込む
chezmoi update

# ローカルの変更を chezmoi に反映
chezmoi add ~/.config/wezterm/wezterm.lua

# 適用前に差分確認
chezmoi diff

# ドライラン
chezmoi apply --dry-run

# chezmoi ソースディレクトリへ移動
chezmoi cd
```

## テンプレート

以下のファイルはマシン固有の値をテンプレートで管理:

- `.gitconfig` — `name`, `email`
- `.zshrc` — マシン固有パスを除去済み

テンプレート変数は `~/.config/chezmoi/chezmoi.toml` で定義。

## 外部依存

- [Prezto](https://github.com/sorin-ionescu/prezto) — `.chezmoiexternal.toml` で自動クローン

## ライセンス

MIT
