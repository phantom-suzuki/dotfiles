# Global Claude Code Instructions

## Communication Style

文体規範の正本は `~/.claude/rules/communication-style.md`（報告・説明の型 / やさしい日本語 R1〜R8 / 質問モードのブロッキングを 1 本に統合）。**すべての日本語出力に常時適用する**。毎ターン効くコアだけを以下に置く。詳細・言い換え例は正本を参照。

- **概要ファースト**: まず結論 1 行、続けて表 / 箇条書きで全体像を出す。長い前提を冒頭に書かない
- **技術説明は日常語から**: まず平易な要点、専門用語・構造の詳細は後から補足する
- **番号・記号だけで人間に言及しない（最重要）**: Issue/PR 番号・Step 番号・章節番号は必ず「何を指すか」を言葉で添える
- **質問・選択肢の前に判断が必要な理由を 1 文**添える。方針を述べたら矛盾する別案を出さない
- **`AskUserQuestion` で質問したら回答まで待つ（ブロッキング）**。タイムアウトを離席・省略の許可と解釈しない
- **日本語は「やさしい日本語」規律に従う**（一文を短く / 主語明示 / 二重否定回避 / 動作名詞の連結回避）
- **作業の節目で現状サマリを出す**（スコープ / 直近の進捗 / 残作業・次の一手）

## Parallel Work

並列作業の依頼を受けたら **`parallel-work-decision` スキル** を起動し、パターン S/B を判定してから実行する。判定スキップの起動はアンチパターン。

**原則: Agent Teams × git worktree が default**。パターン S は同一ブランチ並列（`TeamCreate` + Agent、`isolation` なし）、パターン B は Issue 別ブランチ並列（team-lead が `git worktree add` ×N してから Agent に path を渡す）。tmux 並列（`wta`/`wti`）はユーザーが明示要求した場合のみ。

判定フロー・起動コマンド早見表・tmux 並列の worktree shell commands・アンチパターンは `~/.claude/skills/parallel-work-decision/SKILL.md` を参照。

## Task Delegation

実装・修正・リファクタ・レビュー対応・ドキュメント文章化等を依頼されたら **`task-delegation` スキル** を起動し、役割ベース（T1 司令塔 / T2 外部 CLI 委譲 = Codex / T3 実行サブエージェント）で委譲先を判定してから実行する。判定スキップで Edit/Write/Bash に入るのはアンチパターン。

委譲マトリクスの実体（司令塔のモデル、実行役が Codex か実行サブエージェントか）は環境によって変わる。着手前必須チェック・役割ベースの Tier 定義・Codex 未導入時のフォールバック分岐・Codex 呼び出しテンプレート・アンチパターンはすべて `~/.claude/skills/task-delegation/SKILL.md`（委譲体系の正本）を参照。

## Markdown ドキュメント作成 — doc-polish 必須

リポジトリに残す Markdown ドキュメント（docs/ 配下・README・ADR・計画文書・ガイド等）を新規作成、または大幅に改稿したら、完成報告の前に必ず **`doc-polish` スキル**を通して表現を研磨する（観点: 一般的でない表現 / 難しい言い回し / 造語・略語 / 図の不足）。スキップして完成報告するのはアンチパターン。

対象外: scratchpad の一時ファイル / メモリファイル / コミットメッセージ / Issue・PR 本文（これらは communication-style のやさしい日本語規律のみ適用）。

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

> **重要（`data.claude.mcpServers` / `enabledPlugins` の安全な運用）**: これらは `chezmoi.toml` の値をそのまま `settings.json` に出力する。①`mcpServers` の `command` / `args` / `env` に API キー・トークンを直書きしない（秘密は環境変数参照や外部 secret manager 経由にする）。②生成済みの `~/.claude/settings.json` を `chezmoi add` / `re-add` しない（秘密が混入した実ファイルをリポジトリに取り込まないため。tmpl 側だけを編集する）。③`enabledPlugins` は信頼済みの marketplace / plugin ID のみ指定する。

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
