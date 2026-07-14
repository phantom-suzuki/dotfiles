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

## AGENTS.md のスコープ（グローバル + プロジェクト階層）

Codex は AGENTS.md を「グローバル + プロジェクト階層」で読み込み、近い方が後勝ちで上書き連結する。

| 層 | パス | 役割 |
|---|---|---|
| グローバル | `~/.codex/AGENTS.md`（`dot_codex/AGENTS.md`） | 全プロジェクト共通の委譲実行指針 |
| プロジェクト階層 | repo root から cwd までの各ディレクトリの `AGENTS.md`（順に連結） | リポジトリ固有・サブディレクトリ固有の規約 |

- 競合したら **cwd に近い側が優先**（近い方が後勝ち）。
- 読み込み合計サイズは `project_doc_max_bytes`（config.toml、デフォルト 32KiB）で制御する。
  グローバル AGENTS.md は Codex の context 上限を意識して短く保ち、固有規約はプロジェクト側に置く。
- config 全体の優先順位: `CLI/--config > project > profile > user(~/.codex/config.toml) > system(/etc/codex) > defaults`。

## Codex 拡張機構（skills / hooks / MCP）

Codex は Claude Code の拡張機構に 1:1 対応する仕組みを公式に持つ（Issue #14 の調査）。

| Claude Code | Codex 相当 | 要点 |
|---|---|---|
| CLAUDE.md | `AGENTS.md` | グローバル + プロジェクト階層（root→cwd 連結）・近い方が後勝ち・`project_doc_max_bytes` で制御 |
| skills（SKILL.md） | config.toml の `[skills]` | frontmatter の description で自動トリガ、per-skill enable/disable |
| hooks | `hooks.json` / inline `[hooks]` | PreToolUse / PostToolUse / SessionStart 等。**`type=command` のみ実行**（prompt / agent ハンドラは未実装） |
| MCP | `[mcp_servers]` | stdio / streamable HTTP、`enabled_tools`/`disabled_tools` の allow/denylist、`default_tools_approval_mode` |

### dotfiles 化ステータス

- **AGENTS.md / seed（model・effort・features）**: dotfiles 化済み（`dot_codex/`）。
- **skills / hooks / MCP の「実体」**: 未収録（フォローアップ）。実機の hooks / MCP 定義は
  マシン固有の絶対パス・SHA256・app バージョンを含み、そのまま追跡すると別マシンで有害・常時
  churn になる（config.toml 本体を管理外にしたのと同じ理由）。seed 方式に載せるには chezmoi
  tmpl 化によるパス抽象化の設計が別途必要。

## 領域別分担（Codex ⇔ Claude）

得手不得手は領域で分かれる（Issue #14 の deep-research。ベンチは短サイクルで順位が動くため
着手時に再確認する）。判定の正本は `task-delegation` スキルの「領域別の得手不得手」節。

- **Codex 優位（T2 委譲に寄せる）**: 自律ターミナル実行 / Web リサーチ / 音声入出力 / 画像生成（gpt-image 系）。
- **Claude 優位（司令塔側で扱う）**: ComputerUse（PC 操作）/ ブラウザエージェント操作 / 図表・ビジョン読解 / 対話・設計議論・ADR。
- **拮抗**: コーディング精度（SWE-Bench 系は未決着）→ 通常の Tier 判定に従う。

## モデル選択（GPT-5.6 系）

2026-07-09 に GPT-5.6 が登場し、Codex で `sol` / `terra` / `luna` の 3 モデルが使える。
**ChatGPT サブスク認証（`auth_mode = chatgpt`）でも 3 モデルすべて使える**ことを 2026-07-14 に
実挙動で確認した（Codex CLI v0.144.4・Codex.app build 26.707.72221）。

- **既定は `gpt-5.6-terra`**（バランス型・消費は sol の 1/2）。委譲パスの常用モデル。
- **`gpt-5.6-sol`**（最上位・消費は terra の 2 倍）は既定にせず、重い調査・実装・レビューだけ
  都度 `--model gpt-5.6-sol` で指定する。
- **`gpt-5.6-luna`**（最軽量・消費は sol の 1/5）は軽い機械的作業向け。
- モデル ID は **フル ID で指定する**。5.6 系にエイリアスは無い（プラグインのエイリアスは
  `spark`→`gpt-5.3-codex-spark` の 1 つだけ）。
- Codex プラグイン（`/codex:rescue` / `codex-rescue`）経由の effort は
  `none/minimal/low/medium/high/xhigh` の 6 段のみ。対話 UI の **`max` / `ultra` はプラグイン
  経由では使えない**。

### 履歴の訂正（重要）

リリース初日（2026-07-09）は「`gpt-5.6-sol` は ChatGPT アカウントでは非対応」という 400 エラーが
あった（GitHub Issue #31905、not planned クローズ）。これはロールアウト初日の挙動で、
**Codex.app を build 26.707.72221 に更新後は sol もサブスク認証で通る**。旧メモの「サブスクで
sol 不可」は現在は誤り。過去に ChatGPT 認証で 400 になった `gpt-5` / `gpt-5.3-codex` の記録は、
あくまでそれらのモデル固有の話であり、5.6 系には当てはまらない。

### モデル固定箇所の一覧（2026-07-14 時点）

| 場所 | 現在の pin | 追従方針 |
|---|---|---|
| `config.toml` / `config.seed.toml` の `model` | `gpt-5.6-terra`（更新済み） | 委譲パスの既定。ここで消費を調整 |
| self-review `scripts/codex-review.sh` | `-c model=`（default `gpt-5.5`、`CODEX_REVIEW_MODEL` で上書き可） | `--output-schema` 順守が要件。5.6 系が schema を守るか要検証してから bump |
| peer-review `scripts/codex-review.sh` | model 未指定 + `--ignore-user-config` | codex 組み込み既定に追従（＝バージョンで漂う）。決定論が要るなら `-c model=gpt-5.6-sol` を検討 |
| codex-imagegen | `gpt-image-2`（画像モデル） | テキストモデルとは別領域。対象外 |

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
- `~/.codex/AGENTS.md`（`dot_codex/AGENTS.md`）— Codex 側の委譲実行グローバル指針
- `~/.codex/config.seed.toml` — ポータブル設定の seed
