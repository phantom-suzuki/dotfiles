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

### パターン B — Issue 連携並列（team-lead 事前 worktree + Agent dispatch）

複数ブランチで作業しつつ、API 境界の擦り合わせや共通設計判断が頻繁に必要な場合、または tmux 起動を避けたい場合。

#### 手順

1. **team-lead が事前に worktree を作成**:
   ```bash
   git worktree add -b feature/<branch-1> /path/to/worktree-1
   git worktree add -b feature/<branch-2> /path/to/worktree-2
   ```
2. `TeamCreate` → `Agent`（`team_name` 付き、`isolation` パラメータは指定しない）で teammate spawn
3. **teammate prompt に worktree path を明示し、最初の操作を `cd <path>` に固定**:
   ```
   ## 実行環境
   作業 worktree: <absolute path>
   最初に `cd <path>` してから `pwd` / `git branch --show-current` / `git worktree list` で確認すること。
   ```

#### 特性

- 永続 feature branch を扱える（branch 名は team-lead が制御）
- `SendMessage` / 共有 TaskList で teammate 間連携可
- tmux 不要

#### 例

- 設計判断は同一だが各 Issue で別ブランチが必要な場合
- API 境界の擦り合わせが頻発する複数モジュール同時実装
- tmux トラブル回避を優先したい場合の永続 feature branch 並列

## Teammate prompt 設計指針（パターン B / S 共通）

`Agent` ツールで teammate を spawn する際、prompt に以下 3 要素を必ず含める:

### 1. 実行環境の明示

- worktree path（パターン B の場合は absolute path、パターン S なら親 cwd 共有を明示）
- 最初の操作: `cd <path>` → `pwd` / `git branch --show-current` / `git worktree list` で確認

### 2. 事前相談プロトコル（独断禁止）

teammate prompt に以下を必ず含める:

> 以下に該当する場合は **着手前に SendMessage で team-lead に相談** すること（独断禁止）:
> - 指示された branch 名 / worktree path / ファイル名と異なる方針を採りたい場合
> - 指示されたスコープを変更したい場合（タスクを増減）
> - 設計判断が前提と食い違う事実を発見した場合（既存実装との衝突、リソース不足など）
> - 複数の妥当な実装案があり、選択が任意でない場合
>
> 「相談 = 着手停止」程度で OK。team-lead が即応する。NACK 時のみ方針変更。

### 3. 完了報告フォーマット

teammate に最終報告で以下を必須項目として求める:

- worktree path / branch / commits（SHA + 件名）
- AC ステータス表（実装系 + リポジトリ衛生系）
- リポジトリ衛生チェック結果（`task-delegation` skill のチェック節を参照）
- 未対応項目 / 申し送り
- 次の依頼事項（ある場合）

### 実証例（2026-04-28 wp-platform-phase-a session）

**好例**: edge-domain は ADR 番号衝突を着手前に発見・相談 → 30秒 timeout 提案 → 手戻りゼロで完了

**反例**: composer-env は branch 名 / worktree path を独断変更 → 完了報告で発覚 → main worktree HEAD 想定外 + 事後 rename / migration が必要に

差は「相談プロトコルを踏むか独断か」だけ。両者とも reasoning は妥当だった。事前相談プロトコルの徹底で teammate の方針ドリフトを防止できる。

## 起動コマンド早見表

| パターン | 起動 | 後片付け |
|---|---|---|
| S | `TeamCreate` + `Agent`（`team_name` 付き、`isolation` なし） | `shutdown_request` → `TeamDelete` |
| A | `wta <branch>` または `wti <issue#>` | `wtm`（merge + cleanup）または `wtr`（削除） |
| B | `git worktree add` ×N → `TeamCreate` + `Agent`（`team_name` 付き、prompt で path 固定） | `shutdown_request` → `TeamDelete`（worktree は merge 後 `git worktree remove`）|

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
- **`isolation: "worktree"` パラメータに頼ってブランチ分離を Agent ツール任せにする** ← 環境によって自動 worktree 作成が起きない（実証済、2026-04-28 wp-platform セッション）。team-lead が明示的に `git worktree add` してから teammate に path を渡す方法（パターン B 改）が確実

## 関連

- `~/.claude/CLAUDE.md` の Parallel Work セクション
- 既存 worktree 確認: `wtl` または `git worktree list`
- worktree shell functions: `wta` / `wti` / `wtl` / `wtm` / `wtr` / `wtprune`
