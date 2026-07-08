# Global Claude Code Instructions

## Communication Style

毎ターン効く行動規範のコアだけをここに置く。各規範の Do/Don't・言い換え例・詳細フォーマットは詳細版（`~/.claude/rules/communication-style.md`）を参照。

- **概要ファースト**: まず結論を1行、続けて表 / 箇条書きで全体像を出す。長い前提を冒頭にだらだら書かない
- **技術説明は日常語から**: まず平易な要点を伝え、専門用語・構造の詳細は後から補足する
- **説明の冒頭で「何の話か」を明示する**: 主語・前提を省略しない
- **番号・記号だけで人間に言及しない（最重要）**: Issue/PR 番号・Step 番号・章節番号は必ず「何を指すか」を言葉で添える
- **質問・選択肢の前に、判断が必要な理由を1文添える**。方針を述べたら矛盾する別案を出さず、それに沿って進める
- **作業の節目で現状サマリを出す**: スコープ / 直近の進捗 / 残作業・次の一手（`AskUserQuestion` 直前・長いサブタスク完了時・方針転換時）
- **`AskUserQuestion` で質問したら回答まで待つ（ブロッキング）**。タイムアウトを離席・省略の許可と解釈しない。正本は `~/.claude/rules/question-blocking.md`
- **日本語出力は「やさしい日本語」規律に従う**（一文を短く / 主語明示 / 二重否定回避 等）。正本は `~/.claude/rules/easy-japanese.md`

技術的説明・設計議論・「なぜ」「理由」を問われた場面、およびユーザーが「わからない」「同じ話」等の不満サインを発した場面では **`explain-discipline` スキル** を必ず起動する（詳細は `~/.claude/rules/communication-style.md`）。

## Parallel Work

並列作業の依頼を受けたら **`parallel-work-decision` スキル** を起動し、パターン S/B を判定してから実行する。判定スキップの起動はアンチパターン。

**原則: Agent Teams × git worktree が default**。パターン S は同一ブランチ並列（`TeamCreate` + Agent、`isolation` なし）、パターン B は Issue 別ブランチ並列（team-lead が `git worktree add` ×N してから Agent に path を渡す）。tmux 並列（`wta`/`wti`）はユーザーが明示要求した場合のみ。

判定フロー・起動コマンド早見表・tmux 並列の worktree shell commands・アンチパターンは `~/.claude/skills/parallel-work-decision/SKILL.md` を参照。

## Task Delegation

実装・修正・リファクタ・レビュー対応・ドキュメント文章化等を依頼されたら **`task-delegation` スキル** を起動し、役割ベース（T1 司令塔 / T2 外部 CLI 委譲 = Codex / T3 実行サブエージェント）で委譲先を判定してから実行する。判定スキップで Edit/Write/Bash に入るのはアンチパターン。

委譲マトリクスの実体（司令塔のモデル、実行役が Codex か実行サブエージェントか）は環境によって変わる。着手前必須チェック・役割ベースの Tier 定義・Codex 未導入時のフォールバック分岐・Codex 呼び出しテンプレート・アンチパターンはすべて `~/.claude/skills/task-delegation/SKILL.md`（委譲体系の正本）を参照。

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
| `~/.claude/settings.json` | `private_dot_claude/settings.json.tmpl` | `data.claude.model`, `data.claude.effortLevel`, `data.claude.disable1m`, `data.claude.autoCompactWindow`, `data.claude.autoCompactPct`, `data.claude.mcpServers`, `data.claude.enabledPlugins` |

> **重要（tmpl の落とし穴）**: tmpl 管理ファイルは `chezmoi re-add` では更新されない（テンプレート構造を壊さないよう実ファイルの差分が取り込まれない）。tmpl の内容を変えるときは **ソースの `*.tmpl` を直接編集 → `chezmoi apply`** で反映すること。`settings.json` のように変数を含まない tmpl でも同様。

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

> **新規ファイル追加直後の apply の落とし穴**: ソース側に新規ファイルを作った直後、ターゲットを個別指定して `chezmoi apply ~/.claude/skills/foo/SKILL.md` のように適用すると、ターゲットの親ディレクトリがまだ無い場合に `stat ...: no such file or directory` で失敗する。引数なしの `chezmoi apply`（全体適用、親ディレクトリも作る）を使うか、先に `mkdir -p` でターゲット親ディレクトリを作ってから個別 apply すること。

### chezmoi 管理対象の確認

```bash
chezmoi managed          # 管理対象一覧
chezmoi source-path ~/.<file>  # ソースパスの確認
```
