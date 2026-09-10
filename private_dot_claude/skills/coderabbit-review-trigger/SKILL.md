---
description: >-
  CodeRabbit のレビューを PR にトリガーし、トリガー後に「レビューが起動したか / rate limit で
  制限中か / 結果が投稿されたか」を監視・判定するスキル。`@coderabbitai review` / `full review`
  はコメントを投げても rate limit（Fair Usage Limits）で silent に skip されることがあり、
  投げっぱなしだと起動したか分からない。しかも制限中でも「Full review finished」と併記されるため
  完了と誤読しやすい。本スキルはトリガー → 応答コメントの監視 → 状態判定 →（制限中なら解除目安の
  算出）まで行う。approve は扱わない（coderabbit-approve へ）。「CodeRabbit にレビューさせて」
  「CodeRabbit をトリガー」「full review 依頼」「レビュー回して」「CodeRabbit 起動したか確認」
  「rate limit 中か見て」「CodeRabbit の反応を監視」等の依頼時に使用。
argument-hint: "[PR番号] [--mode full|incremental]"
---

# CodeRabbit Review Trigger + Startup Monitor

CodeRabbit に**レビューをトリガー**し、その直後に **起動したか / 制限中か / 結果が出たか** を確認するための正本手順。トリガー系コマンド（`review` / `full review`）は投稿しても rate limit で無言のまま skip されることがあり、「投げたのに起動したか分からない」を防ぐのが本スキルの目的。

## なぜトリガーだけでは不十分か

CodeRabbit は Fair Usage Limits（adaptive limit）を持ち、短期間に多くのレビューを回すと制限される。制限中は次のように振る舞うため、**トリガーの投稿成功 ≠ レビュー起動**である。

- 制限中に `@coderabbitai full review` を投げると、応答コメントに「**Full review finished**」と書かれつつ同じコメント内で「**You're currently rate limited … available in N minutes**」が併記される。「finished」だけ読むと完了と誤読するが、**実レビュー結果（walkthrough / actionable comments）は投稿されていない**。
- そもそも受領時はまず 👀 リアクションだけ付き、本文コメントが遅れて出ることもある。

したがって、トリガー後は必ず応答コメントを取得し、**rate limit 表現を最優先で判定**する必要がある。

## coderabbit-approve との棲み分け

| スキル | 役割 |
|---|---|
| **本スキル（coderabbit-review-trigger）** | レビューを**トリガー**し、**起動 / 制限中 / 結果投稿**を監視・判定する |
| `coderabbit-approve` | 正式 GitHub APPROVED を取得しマージゲートを埋める（`@coderabbitai approve`・`request_changes_workflow` 依存） |

本スキルは approve しない。レビュー結果が出て指摘対応が済んだあと、承認が要る場合は `coderabbit-approve` へ渡す。

## 標準手順

PR 番号を引数で受ける。owner/repo は未指定なら `gh repo view` から解決する。

### Step 1: トリガー + 監視（1 コマンド）

同梱スクリプトがトリガー投稿と応答監視をまとめて行う。

```bash
bash ~/.claude/skills/coderabbit-review-trigger/scripts/trigger-and-watch.sh <PR> \
  [--repo owner/repo] [--mode full|incremental] [--poll 秒] [--max 回数]
```

- `--mode full`（既定）= 全体再レビュー（`@coderabbitai full review`）。`incremental` = 増分レビュー（`@coderabbitai review`）。
- 既定は 30 秒間隔 × 8 回 = 最大約 4 分監視する。CodeRabbit の応答が遅いリポジトリでは `--max` を増やす。
- **長時間 sleep はハーネスでブロックされることがある**。監視窓を長く取りたいときは、この呼び出し自体を**バックグラウンド実行**する（Bash の `run_in_background`）。

スクリプトは最終行に `STATE=...` を出す。意味は次のとおり。

| STATE | 意味 | 次アクション |
|---|---|---|
| `POSTED` | walkthrough / actionable comments 等の結果が投稿された | 指摘を確認。承認が要れば `coderabbit-approve` へ |
| `REVIEWING` | レビュー実行中の応答を確認 | 少し置いて `--no-trigger` で再確認 |
| `RATE_LIMITED` | 制限中。実レビューは未実施 | `RETRY_AFTER` の目安まで待って再トリガー（Step 2） |
| `OTHER` | CodeRabbit 応答はあるが分類外 | 本文を目視確認 |
| `NO_RESPONSE` | 監視窓内に新規応答なし | `--poll`/`--max` を増やすか、後刻 `--no-trigger` で確認 |

### Step 2: rate limit 解除後の再トリガー

`RATE_LIMITED` のとき、スクリプトは `RETRY_AFTER: 約 N 分後（目安 <UTC 時刻>）` を出す。**解除前に催促しても再び skip されるだけ**なので、目安時刻まで待ってから再実行する。

```bash
# 解除目安を過ぎたら、トリガーせず監視のみで実状態を確認 → まだ結果が無ければ再トリガー
bash .../trigger-and-watch.sh <PR> --no-trigger        # 現状だけ確認
bash .../trigger-and-watch.sh <PR> --mode full         # 再トリガー + 監視
```

待機を自動化するなら、解除目安まで空けて再実行する形をバックグラウンドに置く（`run_in_background` で「解除時刻付近に起動 → `--no-trigger` で確認 → 未完なら再トリガー」）。数十分規模の待機を前面で回さない。

### Step 3: 状態確認だけしたいとき（トリガーしない）

既にトリガー済みで「今どうなっているか」だけ見たい場合は `--no-trigger` を使う。無駄な再トリガーで rate limit を消費しない。

```bash
bash .../trigger-and-watch.sh <PR> --no-trigger
```

## 判定の要点（スクリプトの内部ロジック）

- **rate limit を最優先で判定**する。「Full review finished」と rate limit が併記されるため、finished 語を先に見ると誤判定する。
- 最新の CodeRabbit コメントは全ページを `--slurp` で束ねて `created_at` でソートして取る。**この gh では `--slurp` と `--jq` は併用できない**ため、`--slurp` の出力をパイプで jq に渡す。
- コメント本文には制御文字が混じることがある。生テキストを別 jq に食わせると `U+0000-001F` で parse error になるため、`jq -c` で valid JSON 化してから `.body` を再取得する。
- baseline（トリガー前の最新 CodeRabbit コメント時刻）より後の応答だけを「今回の応答」とみなし、古いコメントで誤判定しない。

## アンチパターン

- ❌ `@coderabbitai full review` を投げて完了扱いにする（rate limit で silent skip されうる。応答監視が必須）
- ❌ 「Full review finished」だけ見て結果が出たと判断する（rate limit 併記時は結果未投稿）
- ❌ rate limit 解除前に催促を繰り返す（再 skip されるだけ。目安時刻まで待つ）
- ❌ 本スキルで approve まで期待する（approve は `coderabbit-approve`）
- ❌ 数十分の解除待ちを前面 `sleep` で回す（ハーネスでブロックされうる。バックグラウンドに置く）

## 関連

- `coderabbit-approve` — 正式 APPROVED 取得・マージゲート充足（本スキルの後段）
- `review-doc` / `peer-review` / `self-review` — レビュー本体の観点別スキル
- メモリ `feedback_coderabbit_merge_workflow` — 本組織の CodeRabbit 運用（承認1件必須・rate limit は解除時刻を待つ）
- 出典: [CodeRabbit Commands](https://docs.coderabbit.ai/guides/commands) / [Fair Usage Limits](https://docs.coderabbit.ai/management/plans#fair-usage-limits-policy)
