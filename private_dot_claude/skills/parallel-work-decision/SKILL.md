---
name: parallel-work-decision
description: 並列作業を依頼されたとき worktree × Agent Teams のパターン S/B を判定する。「並列で」「同時に」「複数 Issue を同時進行」「ブランチ分けて」「複数タスク並行」等の依頼時に使用。
---

# Parallel Work Decision Skill

並列作業の依頼を受けたとき、worktree × Agent Teams の組み合わせパターンを判定し、起動プランを提示する。判定をスキップしてツール呼び出しに入るのは禁止。

## 原則: Agent Teams × git worktree を default にする

ユーザーが tmux を能動運用していないため、`wta`/`wti` ベースの tmux 並列（旧パターン A）は実用性が低い。並列作業はメインセッションから `Agent Teams` で teammate を dispatch し、各 teammate を `git worktree` 上で動かす **パターン S / B** を default とする。

旧パターン A（`wta`/`wti`）は **明示的なオプトイン時のみ** 使用する（後述「オプション: tmux 並列」節参照）。

## 判定フロー

```
並列作業の依頼
  ↓
ブランチ分離が必要か？
  No  → パターン S（同一ブランチ × Agent Teams）
  Yes → パターン B（worktree × Agent Teams）
```

連携の有無は **パターン B 内で機能を使うかどうか** の問題（`SendMessage` / 共有 `TaskList` を使うか否か）。連携が稀薄でもパターン B でよい — 連携機能を使わなければいいだけ。

## 2 パターン

### パターン S — 同一ブランチ並列（Agent Teams のみ）

同一 feature branch 上で複数サブタスクを並列化する場合。

- 手段: `TeamCreate` → `Agent` ツール（`team_name` 付き、`isolation` なし）で teammate spawn
- 全 teammate が同一 cwd を共有する。**異なる `git checkout` / `git switch` は禁止**（ブランチ切替が互いの作業を破壊）
- 例: API 実装とテスト作成を同時進行、フロントとバックを同時に

### パターン B — Issue 別ブランチ並列（team-lead 事前 worktree + Agent dispatch）

複数 Issue / 複数ブランチで作業する場合。連携の有無を問わず default。

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
- 連携が必要なら `SendMessage` / 共有 TaskList、不要なら使わなくてよい
- tmux 不要、メインセッションから集約管理可能
- 各 worktree で独立に PR 作成・マージできる

#### 例

- 独立した複数 Issue の並列処理（連携不要でも採用）
- API 境界の擦り合わせが頻発する複数モジュール同時実装（連携あり）
- 設計判断は同一だが各 Issue で別ブランチが必要な場合

## オプション: tmux 並列（旧パターン A、`wta`/`wti`）

以下のいずれかに **明示的に該当する場合のみ** 採用する:

- ユーザーが「tmux で進めたい」と明示した
- 各 worktree で長期的に作業を回したい（数日にわたる継続作業）
- 別 Claude セッションで IDE / エディタとの併用を想定する

それ以外では **採用しない**。判定理由を「ユーザーが明示的に tmux 並列を要求した」と text で記載してから起動する。

起動: `wta <branch>` または `wti <issue#>` → 別 tmux window + 独立 Claude セッション。

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
| B | `git worktree add` ×N → `TeamCreate` + `Agent`（`team_name` 付き、prompt で path 固定） | `shutdown_request` → `TeamDelete`（worktree は merge 後 `git worktree remove`） |
| tmux 並列（オプション） | `wta <branch>` または `wti <issue#>` | `wtm`（merge + cleanup）または `wtr`（削除） |

## チェックリスト出力テンプレート

並列作業の依頼を受けたら、以下を text で明示してから起動コマンドを実行する:

```
## 並列作業判定
- ブランチ分離: Yes / No
- パターン: S / B / tmux 並列（オプション）
- 起動方法: （具体的なコマンドまたはツール呼び出し）
- 理由: （ブランチ分離 Yes/No の判定根拠。tmux 並列を選んだ場合はユーザーの明示的指示を引用）
```

## アンチパターン

- **「並列だから Agent Teams で」** ← パターン判定をスキップした起動。S/B のどちらかを必ず明示する
- **同一ディレクトリで teammate ごとにブランチ切替** ← パターン S なのに別ブランチに行こうとしている。worktree 化が必要
- **`isolation: "worktree"` パラメータに頼ってブランチ分離を Agent ツール任せにする** ← 環境によって自動 worktree 作成が起きない（実証済、2026-04-28 wp-platform セッション）。team-lead が明示的に `git worktree add` してから teammate に path を渡す方法（パターン B）が確実
- **ユーザー指示なしに `wta`/`wti` で tmux 並列を案内する** ← tmux 運用が定着していない環境では実用性が低い。Agent Teams × worktree（パターン B）が default

## 関連

- `~/.claude/CLAUDE.md` の Parallel Work セクション
- 既存 worktree 確認: `wtl` または `git worktree list`
- worktree shell functions: `wta` / `wti` / `wtl` / `wtm` / `wtr` / `wtprune`（オプション利用時のみ）
