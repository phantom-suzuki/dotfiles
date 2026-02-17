# Global Claude Code Instructions

## Parallel Work — Agent Teams First

When the user requests parallel or concurrent work, **default to Agent Teams** (TeamCreate + Task tool with team_name).
Agent Teams spawns teammates as visible tmux split panes, allowing real-time monitoring.

### Tool selection rule

- **並列で開発・実装タスクを行う場合は、必ず Agent Teams（TeamCreate）を使用すること。**
  Task サブエージェント（team_name なし）は、調査・検索など可視性が不要な軽量タスクにのみ使用する。
- 2つ以上の実装系サブタスクを並列実行する場合、Task ツール単体ではなく TeamCreate → Task（team_name 付き）で teammate を生成すること。

### Decision flow

1. **Same branch, parallelizable subtasks** → **Agent Teams** (default)
   - e.g. "API とテストを並列で", "フロントとバックを同時に", "リファクタしながらテスト書いて"
   - Spawns teammates in tmux panes within the current window
   - Use this whenever subtasks share the same codebase and branch
   - **必ず TeamCreate を使い、tmux ペイン分割で可視化すること**

2. **Different branches required** → **git worktree** (shell functions)
   - e.g. "Issue #12 と #15 を別ブランチでやって", "main にはまだ入れたくない2つの機能を並行で"
   - Each worktree gets its own tmux window with isolated branch + Claude session
   - Use `wta <branch>` or `wti <issue-number>` (GitHub Issue → worktree)

3. **Hybrid** — worktree for branch isolation, Agent Teams within each worktree for subtask parallelism

### Critical constraint — branch isolation

**Agent Teams の全エージェントは同一ディレクトリ（cwd）を共有する。**
tmux ペイン分割はプロセスと画面の分離であり、ファイルシステム・ブランチの分離ではない。

- **同一ディレクトリで複数エージェントが異なる `git checkout` / `git switch` を実行してはならない**
  → ブランチ切り替えが互いの作業を破壊する
- 異なるブランチが必要なタスク（例: Issue ごとにブランチを切る）は、**必ず `git worktree` でディレクトリを分離**してから各 worktree 内で Agent Teams を使うこと
- Agent Teams 単体で完結するのは、**全エージェントが同一ブランチ上で作業する場合のみ**

### Worktree shell commands

| Command | Action |
|---------|--------|
| `wta <branch>` | Create worktree + tmux window + Claude |
| `wta <branch> -p "prompt"` | Same, with initial prompt (written to `.claude-prompt`) |
| `wti <issue#>` | Create worktree from GitHub Issue |
| `wtl` | List all worktrees |
| `wtm` | Merge current worktree branch + cleanup |
| `wtr` | Remove current worktree without merge |
| `wtprune` | Prune stale worktree references |

### Project init hook

If the repo has an executable `.worktree-init` at the root, it runs automatically when `wta` creates a new worktree. Use this for project-specific setup (e.g. `npm install`, `python -m venv .venv`, symlinks).

## Dotfiles — chezmoi 管理

個人設定ファイル（WezTerm, Neovim, zsh, tmux, Claude Code 等）は **chezmoi** で管理されている。

- **ソースディレクトリ**: `~/.local/share/chezmoi/`
- **リポジトリ**: `github.com/phantom-suzuki/dotfiles`
- **設定**: `~/.config/chezmoi/chezmoi.toml`

### 編集ワークフロー（重要）

chezmoi 管理下のファイルを変更する場合、**必ずソース側を編集**すること。

```bash
# 1. ソースファイルを編集（chezmoi edit がソースを開く）
chezmoi edit ~/.config/wezterm/appearance.lua

# 2. 差分確認
chezmoi diff

# 3. 適用
chezmoi apply
```

**ターゲットファイル（`~/.config/...` 等）を直接編集してはならない。**
次回 `chezmoi apply` で上書きされ、変更が失われる。

やむを得ずターゲットを編集した場合は、直後に `chezmoi re-add <file>` でソースに反映すること。

### テンプレートファイル

以下のファイルは Go template を使用しており、ソースでのみ編集可能:

| ターゲット | ソース | テンプレート変数 |
|-----------|--------|-----------------|
| `~/.gitconfig` | `dot_gitconfig.tmpl` | `{{ .name }}`, `{{ .email }}` |
| `~/.zshrc` | `dot_zshrc.tmpl` | なし（クリーンアップ済み、将来のマシン分岐用） |

### 変更後のコミット

dotfiles の変更後は chezmoi ソースディレクトリでコミット:

```bash
chezmoi cd  # → ~/.local/share/chezmoi/
git add -A && git commit -m "feat: update wezterm appearance"
git push
```

### 新しいファイルの追加

```bash
chezmoi add ~/.config/some/new-config.toml
```

### chezmoi 管理対象の確認

```bash
chezmoi managed          # 管理対象一覧
chezmoi source-path ~/.<file>  # ソースパスの確認
```
