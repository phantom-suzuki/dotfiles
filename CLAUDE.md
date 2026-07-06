# dotfiles — chezmoi ソースディレクトリ

このリポジトリは chezmoi で管理する dotfiles のソースディレクトリ。
ここでの編集が `chezmoi apply` で `~/` 配下に展開される。

## chezmoi 命名規約

| プレフィックス | 意味 | 例 |
|--------------|------|-----|
| `dot_` | `.` で始まるファイル/ディレクトリ | `dot_config/` → `~/.config/` |
| `private_dot_` | パーミッション 0700 のドットディレクトリ | `private_dot_claude/` → `~/.claude/` |
| `executable_` | 実行権限を付与 | `executable_statusline.sh` → `statusline.sh` (chmod +x) |
| `symlink_` | シンボリックリンク | `symlink_dot_zlogin` → `~/.zlogin` (symlink) |
| `.tmpl` サフィックス | Go template として処理 | `dot_gitconfig.tmpl` → `~/.gitconfig` |

## テンプレートファイル

Go template 構文（`{{ .variable }}`）を使用するファイル:

| ソース | ターゲット | 変数 |
|--------|-----------|------|
| `dot_gitconfig.tmpl` | `~/.gitconfig` | `{{ .name }}`, `{{ .email }}` |
| `dot_zshrc.tmpl` | `~/.zshrc` | なし（将来のマシン分岐用に `.tmpl` 維持） |
| `.chezmoi.toml.tmpl` | `~/.config/chezmoi/chezmoi.toml` | `promptStringOnce` で初回入力 |
| `private_dot_claude/settings.json.tmpl` | `~/.claude/settings.json` | `data.claude.*`（省略時は default 値。下表参照） |
| `run_once_install-packages.sh.tmpl` | (実行のみ) | `{{ .chezmoi.sourceDir }}` |

変数は `~/.config/chezmoi/chezmoi.toml` で定義:

```toml
[data]
    name = "phantom-suzuki"
    email = "h.suzuki@sorenalab.com"
```

### Claude Code settings の上書き変数（`data.claude.*`）

`private_dot_claude/settings.json.tmpl`（`~/.claude/settings.json` を生成する chezmoi テンプレート）のマシン固有・個人固有になり得る値は、`data.claude.*` で上書きできる。`dig` 関数で「未定義なら default」にフォールバックするため、`[data.claude]` を書かなくても現状と同一の JSON が生成される（後方互換）。default 値は settings.json のモデル・1M コンテキスト設定を再設計した Issue #22 の決定値。

| 変数 | 意味 | default |
|------|------|---------|
| `data.claude.model` | モデル名 | `claude-opus-4-8` |
| `data.claude.effortLevel` | reasoning effort | `medium` |
| `data.claude.disable1m` | 1M コンテキスト無効化（`"1"`=無効 / `"0"`=有効） | `"1"` |
| `data.claude.autoCompactWindow` | auto-compact のコンテキスト窓 | `200000` |
| `data.claude.autoCompactPct` | auto-compact 発火閾値 % | `65` |

マシンごとに変えたいときは `~/.config/chezmoi/chezmoi.toml` の `[data.claude]` に値を書く（例は `.chezmoi.toml.tmpl` のコメント参照）:

```toml
[data.claude]
    model = "claude-opus-4-8"
    effortLevel = "medium"
    disable1m = "1"
    autoCompactWindow = "200000"
    autoCompactPct = "65"
```

> **注意（1M と auto-compact の依存）**: `disable1m` を `"0"`（1M 有効）に戻す場合、`autoCompactWindow` / `autoCompactPct` も 1M 前提の値に見直すこと。理由は `settings.json.tmpl` 内の `{{/* */}}` コメントに記載。

## 外部リポジトリ

`.chezmoiexternal.toml` で管理:
- `~/.zprezto` — [sorin-ionescu/prezto](https://github.com/sorin-ionescu/prezto)（recursive clone）

## ファイル編集フロー

```bash
# 通常のファイル → ソースを直接編集して apply
vim dot_config/wezterm/appearance.lua
chezmoi apply

# テンプレートファイル → .tmpl を編集して apply
vim dot_gitconfig.tmpl
chezmoi apply

# 新規ファイル追加
chezmoi add ~/.config/some/new-config.toml
# → ソースに自動配置される

# 差分確認（apply 前に必ず実行）
chezmoi diff

# ドライラン
chezmoi apply --dry-run
```

## コミット規約

- Conventional Commits: `feat:` / `fix:` / `refactor:` / `chore:`
- 件名は英語、72文字以内
- 例: `feat: add telescope keymap for nvim`, `fix: correct starship worktree indicator`

## 管理対象外（.chezmoiignore）

`README.md`, `LICENSE`, `Brewfile`, `Brewfile.lock.json`, `CLAUDE.md` はデプロイ対象外。

## 注意事項

- **ターゲットファイル（`~/.config/...` 等）を直接編集しない** — 次回 `chezmoi apply` で上書きされる
- シンボリックリンクファイル（`symlink_dot_z*`）の中身はリンク先パスの文字列
- `private_dot_claude/settings.json` には認証トークンは含まれないが、パーミッション設定に注意
