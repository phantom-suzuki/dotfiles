# Codex CLI 設定・Effort 運用ルール

Codex CLI (`~/.codex/`) の設定管理方針と reasoning effort の使い分けの正本。

## dotfiles 管理方針

| 対象 | 実体 | chezmoi 管理 | 理由 |
|---|---|---|---|
| Codex 共通指示 | `~/.codex/AGENTS.md` | ✅ `dot_codex/AGENTS.md` | クリーン・ポータブル。委譲時のグローバル指針 |
| ポータブル設定 seed | `~/.codex/config.seed.toml` | ✅ `dot_codex/config.seed.toml` | model / effort / features の 3 設定のみ切り出し |
| config 本体 | `~/.codex/config.toml` | ❌ 管理外 | 大半が Codex.app の自動生成・マシン固有（下記） |
| 認証情報 | `~/.codex/auth.json` | ❌ 管理外 | 秘密情報。dotfiles に絶対に入れない |

### config.toml を丸ごと追跡しない理由

`~/.codex/config.toml` はポータブルな設定が `model` / `model_reasoning_effort` / `[features]` の **3 つだけ**で、残りは Codex.app が自動管理する内容:

- `[projects.*]` … 各リポの絶対パス + trust_level（起動のたび自動蓄積）
- `notify` / `[mcp_servers.node_repl]` … `/Applications/Codex.app/...` のパス・SHA256・app バージョン（別マシンで動かない）
- `[marketplaces.*]` / `[plugins.*]` / `[notice]` … timestamp・ローカルキャッシュパス（常時 churn）

丸ごと `chezmoi add` すると `chezmoi diff` が常時差分まみれになり、かつマシン固有パスが別マシンで有害になるため、ポータブルな 3 設定だけを `config.seed.toml` として切り出している。新マシンでは Codex.app に config.toml を自動生成させた後、seed の値を手で反映する。

## reasoning effort 制御マップ

`model_reasoning_effort` は **呼び出しパスによって config.toml を尊重するか無視するかが分かれる**。effort を変えても効かない／意図せず重い、という混乱を避けるための制御マップ。

### config.toml を尊重するパス

- **委譲パス**（task-delegation の T2 default 委譲、`/codex:rescue`）: codex-companion → `codex app-server` 経由。`app-server.mjs` の `spawn("codex", ["app-server"])` に `--ignore-user-config` が **付かない** ため config.toml を **尊重する**。companion は `--effort` 未指定時 `effort: null` を渡し、app-server が config.toml の default（現状 `medium`）にフォールバックする。**ここがレート消費の本丸**（実行量が多い）。

### config.toml を無視するパス

- **review 系スキル**（peer-review の `codex-review.sh`、self-review の `codex exec`）: `--ignore-user-config` を付けるため config.toml を **無視する**。effort を狙った値にするには `-c model_reasoning_effort=<x>` の **明示指定が必須**（`-c` は CLI 明示なので `--ignore-user-config` があっても効く）。低頻度なので質優先で `high` 固定にしてある。

## 実務上の含意

- Codex のレートが急増したら、まず `config.toml` の `model_reasoning_effort`（`xhigh` だと最重）を疑う。委譲パスの大量実行に効く。seed の値も合わせて更新する。
- review 系の effort を変えたいときに config.toml をいじっても効かない。該当スクリプトの `-c model_reasoning_effort=` を直接編集する。
- 運用方針は「普段は medium で節約、レビュー系だけ high 固定」のメリハリ（2026-06-04 導入、dotfiles PR #7）。実装は `~/.claude/skills/peer-review/scripts/codex-review.sh` と `~/.claude/skills/self-review/references/review-prompts.md` のインラインコメント参照。

## 関連

- `~/.claude/skills/task-delegation/SKILL.md` — T2 Codex 委譲の判定（委譲パスの effort はここ経由）
- `~/.claude/rules/task-delegation.md`
- `~/.codex/config.seed.toml` — ポータブル設定の seed
