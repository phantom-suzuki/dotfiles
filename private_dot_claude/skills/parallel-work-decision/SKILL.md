---
name: parallel-work-decision
description: 並列作業を依頼されたとき worktree × Agent Teams のパターン S/A/B を判定する。「並列で」「同時に」「複数 Issue を同時進行」「ブランチ分けて」「複数タスク並行」等の依頼時に使用。
---

# Parallel Work Decision Skill

並列作業の依頼を受けたとき、worktree × Agent Teams の組み合わせパターンを判定し、起動プランを提示する。判定をスキップしてツール呼び出しに入るのは禁止。

## 判定フロー

```
並列作業の依頼
  ↓
Q1: ブランチ分離が必要か？
  No  → パターン S（同一ブランチ並列）
  Yes ↓
  ↓
Q2: Issue 間連携が必要か？
  No  → パターン A（Issue 独立並列、wta ベース）
  Yes → パターン B（連携並列、isolation:worktree）
```

## 3 パターン

### パターン S — 同一ブランチ並列（Agent Teams のみ）

同一 feature branch 上で複数サブタスクを並列化する場合。

- 手段: `TeamCreate` → `Agent` ツール（`team_name` 付き、`isolation` なし）で teammate spawn
- 全 teammate が同一 cwd を共有する。**異なる `git checkout` / `git switch` は禁止**（ブランチ切替が互いの作業を破壊）
- 例: API 実装とテスト作成を同時進行、フロントとバックを同時に

### パターン A — Issue 独立並列（`wta` ベース）

複数 Issue を並行処理し、Issue 間連携が稀薄な場合。

- 手段: 各 Issue で `wta <branch>` または `wti <issue#>` を実行
  - 各 worktree に独立した tmux window + Claude セッションが起動
  - リポジトリに executable な `.worktree-init` があれば自動実行
- 各セッション内で必要に応じて Agent Teams を立ち上げる（パターン S 入れ子）
- 連携は git レベルのみ（PR / merge）
- 例: 設計上独立したインフラ層別 Issue（エッジ層 と Composer 層）の並行処理

### パターン B — Issue 連携並列（単一セッション + `isolation: "worktree"`）

複数ブランチで作業しつつ、API 境界の擦り合わせや共通設計判断が頻繁に必要な場合。

- 手段: 1 セッションで `TeamCreate` → `Agent` ツール `isolation: "worktree"` 付きで spawn
- teammate ごとに一時 worktree が自動作成される
- `SendMessage` / 共有 TaskList で teammate 間連携可
- 注意: 一時 worktree（変更なしなら自動削除）。**永続 feature branch には不向き**
- 例: 同一機能の複数モジュール同時実装で API 境界の調整が頻発するケース

## 起動コマンド早見表

| パターン | 起動 | 後片付け |
|---|---|---|
| S | `TeamCreate` + `Agent`（`team_name` 付き） | `shutdown_request` → `TeamDelete` |
| A | `wta <branch>` または `wti <issue#>` | `wtm`（merge + cleanup）または `wtr`（削除） |
| B | `TeamCreate` + `Agent`（`isolation: "worktree"`） | `shutdown_request` → `TeamDelete`（worktree 自動削除） |

## チェックリスト出力テンプレート

並列作業の依頼を受けたら、以下を text で明示してから起動コマンドを実行する:

```
## 並列作業判定
- ブランチ分離: Yes / No
- Issue 間連携: Yes / No / 該当なし
- パターン: S / A / B
- 起動方法: （具体的なコマンドまたはツール呼び出し）
- 理由: （Q1 / Q2 の判定根拠）
```

## アンチパターン

- **「並列だから Agent Teams で」** ← パターン判定をスキップした起動。S/A/B のどれかを必ず明示する
- **同一ディレクトリで teammate ごとにブランチ切替** ← パターン S なのに別ブランチに行こうとしている。worktree 化が必要
- **永続 feature branch を `isolation: "worktree"` で扱う** ← 一時 worktree なので変更なしで消える。`wta` ベースに切替

## 関連

- `~/.claude/CLAUDE.md` の Parallel Work セクション
- 既存 worktree 確認: `wtl` または `git worktree list`
- worktree shell functions: `wta` / `wti` / `wtl` / `wtm` / `wtr` / `wtprune`
