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

技術的説明・設計議論・「なぜ」「理由」を問われた場面、およびユーザーが「わからない」「論点を外している」「同じ話」「おちょくって」等の不満サインを発した場面では **`explain-discipline` スキル** を必ず起動し、結論ファースト / 同義反復回避 / 質問意図の再言語化 / 矛盾自己 check を強制する。

## Parallel Work

並列作業の依頼を受けたら **`parallel-work-decision` スキル** を起動し、worktree × Agent Teams のパターン S/B を判定してから実行する。判定をスキップした起動はアンチパターン。

**原則: Agent Teams × git worktree が default**。tmux 並列（`wta`/`wti`）はユーザーが明示的に要求した場合のみ採用する。

- パターン S（同一ブランチ並列）: `TeamCreate` + Agent（`team_name` 付き、`isolation` なし）
- パターン B（Issue 別ブランチ並列）: team-lead が `git worktree add` ×N → `TeamCreate` + Agent（`team_name` 付き、prompt で worktree path を固定）。連携の有無を問わず default

詳細・起動コマンド早見表・アンチパターンは `~/.claude/skills/parallel-work-decision/SKILL.md` を参照。

### Worktree shell commands（オプション、tmux 並列を明示要求された場合のみ）

| Command | Action |
|---------|--------|
| `wta <branch>` | Create worktree + tmux window + Claude |
| `wta <branch> -p "prompt"` | Same, with initial prompt |
| `wti <issue#>` | Create worktree from GitHub Issue |
| `wtl` / `wtm` / `wtr` / `wtprune` | List / merge+cleanup / remove / prune |

リポジトリ root に executable な `.worktree-init` があれば `wta` 作成時に自動実行される。

## Task Delegation

実装・修正・リファクタ・レビュー対応・ドキュメント文章化等を依頼されたら **`task-delegation` スキル** を起動し、T1 Opus / T2 Codex / T3 Sonnet/Haiku の委譲先を判定してから実行する。判定スキップで Edit/Write/Bash に入るのはアンチパターン。

- **デフォルトは T2 Codex 委譲**（規模問わず、レビュー対応・ドキュメント文章化も含む）
- Opus 直接実装は **対話を伴う場合のみ**（要件確認・ADR 議論中・複数案比較）
- diff 検証とコミット判断は Opus に残す（git-safety.md）

着手前必須チェック・Tier 定義・Codex 呼び出しテンプレート・アンチパターンは `~/.claude/skills/task-delegation/SKILL.md` を参照。

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
