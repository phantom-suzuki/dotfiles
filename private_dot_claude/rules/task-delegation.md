# Task Delegation Rules

実装タスクの委譲先判定（T1 Opus / T2 Codex / T3 Sonnet/Haiku）は **`task-delegation` スキル** に正本化されました。

詳細は以下を参照:

- スキル本体: `~/.claude/skills/task-delegation/SKILL.md`
  - 着手前必須チェック
  - Tier 定義と判断フロー
  - T1 / T2 / T3 の対象タスク一覧
  - Codex 呼び出しテンプレート
  - 安全制約・失敗時のフォールバック
  - アンチパターン

## 関連ルール

- `~/.claude/CLAUDE.md` の Task Delegation セクション（概要ポインタ）
- `~/.claude/rules/git-safety.md`（コミット判断の制約）

## 改訂ログ

- v1（初版）: 10 行未満ルール / レビュー対応は Opus 直接が暗黙
- v2（2026-04-28）: 10 行ルール撤廃、レビュー対応・ADR/コメント等のドキュメント文章化も T2 対象、スキル化
- v3（2026-05-14）: Codex 呼び出しを Bash `codex exec` 直叩きから OpenAI 公式 Codex Plugin (`/codex:rescue`) 経由に移行。stdin 待ちハング・引数渡し不安定を解消
