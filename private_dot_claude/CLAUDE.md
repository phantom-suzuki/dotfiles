# Global Claude Code Instructions

## Communication Style

- **技術的な説明は、まず簡潔な日常語で要点を伝える**。専門用語やフォーマット構造の詳細は後から補足する
- 問題を説明するときは「何が起きていて → なぜそうなって → どうすればいいか」の3点で構成する
- テーブルやコードブロックでの比較は有効だが、前提知識がないと読めない場合は先に1〜2文の平易な要約を入れる
- ユーザーが「わからない」と言った場合は、抽象度を下げて具体例ベースで再説明する
- **説明の冒頭で「何の話をしているか」を必ず明示する**。主語・前提を省略しない。いきなり専門用語や結論を出さず、「〇〇の件ですが」「前のステップで△△をしたので、次は〜」のように文脈を添える
- **選択肢や質問を提示する前に、なぜその判断が必要なのかを1文で説明する**。背景なしに「AとBどちらにしますか？」と聞かない
- **矛盾する提案をしない**。「Aで進めます」と言った直後に別の案を出すと混乱するので、方針を述べたらそれに沿って進める。補足や例外があるなら、方針と明確に区別して伝える
- **ユーザーに判断・選択を求める提示では、GitHub Issue / PR 番号には Markdown リンクを付ける**（例: `[#153](https://github.com/owner/repo/issues/153)`）。ユーザーが即座に Issue/PR を開いて内容を確認し、判断を下せるようにするため。単なる完了報告や文脈共有済みの参照ではリンクは不要

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

## Task Delegation — Codex First for Implementation

実装タスクは **原則 Codex CLI に委譲する**。Opus が直接実装するのは「設計判断が未完了」「コードベース横断の理解が必要」「ユーザー対話が必要」のいずれかに該当する場合のみ。

### 着手前チェック（実装タスク受領時に必ず実施）

実装着手前に以下を明示的に自問し、**ツール呼び出し前に判断結果を text で提示する**。このチェックを省略すると本ルール違反となる:

1. 設計は完了しているか？（ADR / Plan / 仕様書 / 先行 Issue に落ちているか）
   - No → **T1（Opus）** で設計を先に固める
2. コンテキストは限定的か？（対象ファイル + 関連インターフェース程度で収まるか）
   - No → **T1（Opus）** で横断分析
3. メカニカルな実装・テスト・リファクタか？
   - Yes → **T2（Codex CLI）に委譲する**
4. 検索・要約・フォーマット変換か？
   - Yes → **T3（Sonnet/Haiku サブエージェント）に委譲**

判断詳細は `~/.claude/rules/task-delegation.md` の Tier 定義・委譲条件・プロンプトテンプレート・安全制約を参照。

### デフォルトの転換

- 従来: 「委譲条件を満たす場合に Codex へ」
- **改訂: T2 条件を満たすなら委譲が default。Opus 直接実装は例外で、text に理由を明示する。**

### よくあるアンチパターン（実際に踏んだ）

- **「単発 Issue だから並列化不要 → Opus 直接」** ← 並列化要否と委譲要否は独立軸。単発でも T2 なら Codex
- **「設計読み込み完了 → 自分で書く」** ← 設計が固まったなら次は Codex へ渡すフェーズ
- **「400 行くらいなら自分で書いた方が速い」** ← Opus トークン浪費の典型。規模が大きいほど Codex 委譲の効果が大きい

### Codex 呼び出しの最小形

```bash
cd /path/to/project && codex exec --full-auto "$(cat <<'EOF'
## タスク
（何を実装するか）

## コンテキスト
（関連ファイル、インターフェース定義、依存関係。必要最小限）

## 制約
（コーディング規約、使用ライブラリ、避けるべきパターン、git commit/push は実行しないこと）

## 完了条件
（テストが通る、lint が通る、特定の動作をする等）
EOF
)"
```

結果は必ず Opus が `git diff` で検証してから受け入れる。コミット判断は常に Opus（= ユーザー承認フロー）に残す。

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
