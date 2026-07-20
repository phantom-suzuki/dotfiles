# chezmoi 運用ワークフロー（詳細）

CLAUDE.md の「Dotfiles — chezmoi 管理」節のコア規範に対する詳細リファレンス。ワークフロー例・テンプレート一覧・落とし穴の解説を置く。常時注入はされないので、dotfiles を編集するときに読む。

- **ソースディレクトリ**: `~/.local/share/chezmoi/`
- **リポジトリ**: `github.com/phantom-suzuki/dotfiles`
- **設定**: `~/.config/chezmoi/chezmoi.toml`

## 編集ワークフロー

chezmoi 管理下のファイルを変更する場合、**必ずソース側を編集**する。

```bash
# 1. ソースファイルを編集（chezmoi edit がソースを開く）
chezmoi edit ~/.config/ghostty/config

# 2. 差分確認
chezmoi diff

# 3. 適用
chezmoi apply
```

**ターゲットファイル（`~/.config/...` 等）を直接編集してはならない。** 次回 `chezmoi apply` で上書きされ、変更が失われる。やむを得ずターゲットを編集した場合は、直後に `chezmoi re-add <file>` でソースに反映する。

## テンプレートファイル

以下のファイルは Go template を使用しており、ソースでのみ編集可能:

| ターゲット | ソース | テンプレート変数 |
|-----------|--------|-----------------|
| `~/.gitconfig` | `dot_gitconfig.tmpl` | `{{ .name }}`, `{{ .email }}` |
| `~/.zshrc` | `dot_zshrc.tmpl` | なし（クリーンアップ済み、将来のマシン分岐用） |
| `~/.claude/settings.json` | `private_dot_claude/settings.json.tmpl` | `data.claude.model`, `data.claude.effortLevel`, `data.claude.disable1m`, `data.claude.autoCompactWindow`, `data.claude.autoCompactPct`, `data.claude.mcpServers`, `data.claude.enabledPlugins` |

> **重要（`data.claude.mcpServers` / `enabledPlugins` の安全な運用）**: これらは `chezmoi.toml` の値をそのまま `settings.json` に出力する。①`mcpServers` の `command` / `args` / `env` に API キー・トークンを直書きしない（秘密は環境変数参照や外部 secret manager 経由にする）。②生成済みの `~/.claude/settings.json` を `chezmoi add` / `re-add` しない（秘密が混入した実ファイルをリポジトリに取り込まないため。tmpl 側だけを編集する）。③`enabledPlugins` は信頼済みの marketplace / plugin ID のみ指定する。
>
> **重要（tmpl の落とし穴）**: tmpl 管理ファイルは `chezmoi re-add` では更新されない（テンプレート構造を壊さないよう実ファイルの差分が取り込まれない）。tmpl の内容を変えるときは **ソースの `*.tmpl` を直接編集 → `chezmoi apply`** で反映する。`settings.json` のように変数を含まない tmpl でも同様。

## 変更後のコミット

dotfiles の変更後は chezmoi ソースディレクトリでコミット:

```bash
chezmoi cd  # → ~/.local/share/chezmoi/
git status                       # 意図しない変更が混ざっていないか確認する
git add dot_config/ghostty/config  # 変更したパスだけを個別に stage する（git add -A は避ける）
git diff --cached                # stage 内容を確認してからコミットする
git commit -m "feat: update ghostty appearance"
git branch --show-current        # push 先が保護ブランチでないか確認する（git-safety.md 参照）
git push
```

## 新しいファイルの追加

```bash
chezmoi add ~/.config/some/new-config.toml
```

> **新規ファイル追加直後の apply の落とし穴**: ソース側に新規ファイルを作った直後、ターゲットを個別指定して `chezmoi apply ~/.claude/skills/foo/SKILL.md` のように適用すると、ターゲットの親ディレクトリがまだ無い場合に `stat ...: no such file or directory` で失敗する。引数なしの `chezmoi apply`（全体適用、親ディレクトリも作る）を使うか、先に `mkdir -p` でターゲット親ディレクトリを作ってから個別 apply する。

## chezmoi 管理対象の確認

```bash
chezmoi managed          # 管理対象一覧
chezmoi source-path ~/.<file>  # ソースパスの確認
```
