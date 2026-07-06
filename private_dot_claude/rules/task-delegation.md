# Task Delegation Rules

実装タスクの委譲先判定（役割ベース: T1 司令塔 / T2 外部 CLI 委譲 = Codex / T3 実行サブエージェント）は **`task-delegation` スキル** に正本化されました。委譲マトリクスの実体（司令塔が Opus か Fable か、実行役が Codex か impl-sonnet / impl-opus か）は config dir によって変わります。判断の詳細はすべてスキル本体を参照してください。

詳細は以下を参照:

- スキル本体: `~/.claude/skills/task-delegation/SKILL.md`
  - config dir による委譲体系の分岐（標準 `~/.claude` / Fable パイロット `~/.claude-fable`）
  - 着手前必須チェック
  - 役割ベースの Tier 定義と判断フロー
  - T1 / T2 / T3 の対象タスク一覧
  - Codex 呼び出しテンプレート・実行サブエージェント委譲のコツ
  - 安全制約・失敗時のフォールバック
  - アンチパターン

## 関連ルール

- `~/.claude/CLAUDE.md` の Task Delegation セクション（概要ポインタ）
- `~/.claude/rules/git-safety.md`（コミット判断の制約）

## 改訂ログ

- v1（初版）: 10 行未満ルール / レビュー対応は Opus 直接が暗黙
- v2（2026-04-28）: 10 行ルール撤廃、レビュー対応・ADR/コメント等のドキュメント文章化も T2 対象、スキル化
- v3（2026-05-14）: Codex 呼び出しを Bash `codex exec` 直叩きから OpenAI 公式 Codex Plugin (`/codex:rescue`) 経由に移行。stdin 待ちハング・引数渡し不安定を解消
- v4（2026-07-06）: 委譲マトリクスを役割ベース（T1 司令塔 / T2 外部 CLI 委譲 = Codex / T3 実行サブエージェント）に一般化。特定モデル名を主語にせず、司令塔のモデルは可変（標準は Opus、Fable パイロットは Fable）とした。Codex 未導入環境では T2 を skip し T3 実行サブエージェント（impl-sonnet / impl-opus）へフォールバックする分岐を明記。正本をスキルへ統合し、Codex 委譲体系と Fable パイロット委譲体系の競合を解消（Issue #24）
