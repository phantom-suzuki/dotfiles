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
- config 全体の優先順位（概略）: `CLI/--config` が最優先、次いで profile / project スコープ、
  その下に user（`~/.codex/config.toml`）、最後に defaults。公式ドキュメントは完全な全順序を明示
  しておらず、profile と project の上下も確定ではない（2026-07 再検証）。上書きが効かないときは
  `--config` 明示で回避する。project スコープは provider / auth / notification / profile 選択 /
  telemetry 等のマシンローカルなキーを上書きできない点に注意。

## Codex 拡張機構（skills / hooks / MCP）

Codex は Claude Code の拡張機構に 1:1 対応する仕組みを公式に持つ（Issue #14 の調査）。

| Claude Code | Codex 相当 | 要点 |
|---|---|---|
| CLAUDE.md | `AGENTS.md` | グローバル + プロジェクト階層（root→cwd 連結）・近い方が後勝ち・`project_doc_max_bytes` で制御 |
| skills（SKILL.md） | 実体は `.agents/skills`（repo / `$HOME/.agents/skills` / `/etc/codex/skills` / 同梱）。config.toml は `[[skills.config]]` で enable/disable のみ | frontmatter の description で自動トリガ。※ config.toml の `[skills]` で SKILL.md 本体を管理するわけではない |
| hooks | `hooks.json` / inline `[hooks]` | SessionStart / PreToolUse / PermissionRequest / PostToolUse / PreCompact / PostCompact / UserPromptSubmit / SubagentStart / SubagentStop / Stop の 10 イベント。**`type=command` のみ実行**（prompt / agent は parse されるが skip） |
| MCP | `[mcp_servers]` | stdio / streamable HTTP、`enabled_tools`/`disabled_tools` の allow/denylist、`default_tools_approval_mode` |

### dotfiles 化ステータス（Issue #14 で更新）

- **AGENTS.md / seed（model・effort・features）**: dotfiles 化済み（`dot_codex/`）。
- **hooks**: dotfiles 化済み（`dot_codex/hooks/` の `block-codex-direct.py` / `cleanup.sh` /
  `notify.py` と `dot_codex/hooks.json.tmpl`）。`hooks.json` のマシン固有な絶対パスは
  `{{ .chezmoi.homeDir }}` で抽象化し、レンダリング結果が実機の `hooks.json` と一致することを検証済み。
- **skills**: 未収録（意図的）。実機の `$HOME/.agents/skills` は Claude 側 skills と大半が重複し、
  `private_dot_claude/skills/` で既に版管理済み。二重管理・churn を避けるため seed に載せない。
  Codex 固有の独自スキルを作る場合のみ、その時点で `dot_agents/skills/` 等への収録を検討する。
- **MCP**: config.toml 本体は管理外（`node_repl` は Codex.app 生成の絶対パス・SHA256・app バージョン
  を含みマシン固有）。ポータブルに移植したいサーバー（chrome-devtools / playwright）だけを
  `config.seed.toml` のコメントサンプルとして残し、新マシンで config.toml へ手で反映する。

## 領域別分担（Codex ⇔ Claude）

得手不得手は領域で分かれる（Issue #14 の deep-research。ベンチは短サイクルで順位が動くため
着手時に再確認する）。判定の正本は `task-delegation` スキルの「領域別の得手不得手」節。

- **Codex 優位（T2 委譲に寄せる）**: 自律ターミナル実行 / Web リサーチ / 音声入出力 / 画像生成（gpt-image 系）。
- **Claude 優位（司令塔側で扱う）**: ComputerUse（PC 操作）/ ブラウザエージェント操作 / 図表・ビジョン読解 / 対話・設計議論・ADR。
- **拮抗**: コーディング精度（SWE-Bench 系は未決着）→ 通常の Tier 判定に従う。

### 2026-07 再検証メモ（Issue #14）

領域別の**優劣の向きはおおむね維持**。ただし主語となるモデル世代が更新され、一部で差が縮小した:

- **モデル世代の更新**: 比較の主語は「Opus 4.8 / GPT-5.5」ではなく「Fable 5 / Mythos 5（Claude 側、6/9）
  ⇔ GPT-5.6 Sol/Terra/Luna（OpenAI 側、7/9）」で考える。分担表はモデル非依存で書いてあるため骨子は不変。
- **差の縮小（要注意）**: 自律ターミナル実行・Web リサーチの Codex/GPT 優位は継続だが差が縮小（Terminal-Bench
  で Claude 側が 83 台へ上昇）。拮抗に近づいた可能性があり、委譲の費用対効果は着手時に再確認する。
- **ブラウザエージェント**: 旧「Claude 明確優位」は scaffold 込み評価が主流化して判定困難になった。
  base モデル単体の優劣は断定しない。
- **音声入出力**: GPT が成熟で優位だが、Fable 5 に native 音声出力の主張あり（SEO ブログ発、一次情報未確認）。
  音声を重視する委譲判断の前に Anthropic 公式で裏取りする。
- **数値の性質**: 領域別スコアの多くは vendor 自己申告 + SEO ブログ再掲で確定順位ではない。「向き」として扱う。

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
