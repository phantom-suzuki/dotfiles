---
description: >-
  CodeRabbit に PR を正式 APPROVED させてマージゲートを埋めるための正しいハンドリングスキル。
  `@coderabbitai review` は所見コメントを返すだけで承認しない。正式な GitHub APPROVED を得るには
  `@coderabbitai approve`（top-level PR コメント・request_changes_workflow: true 前提）が必要。
  sticky な CHANGES_REQUESTED の dismiss、push 後の自動 DISMISS への再 approve も扱う。
  「CodeRabbit に approve させたい」「CHANGES_REQUESTED が外れない」「review 依頼したのに承認が出ない」
  「マージゲートを CodeRabbit で埋めたい」「CodeRabbit が承認してくれない」等の依頼時に使用。
argument-hint: "[PR番号]"
---

# CodeRabbit Approve Handling Skill

CodeRabbit に PR を**正式 APPROVED** させ、`reviewDecision == APPROVED` のマージゲートを埋めるための正本手順。

## 前提知識（なぜ `review` では承認されないか）

CodeRabbit のチャットコマンドは効果が分かれる。**`review` 系はレビュー所見をコメントで返すだけで、GitHub の formal な APPROVED レビューイベントは提出しない。**

| コマンド | 効果 | 配置制約 |
|---|---|---|
| `@coderabbitai review` | 増分レビュー（新規変更のみ）。所見をコメントで返す。**Approve しない** | top-level / thread 返信 両可 |
| `@coderabbitai full review` | 全体再レビュー。同上。**Approve しない** | 両可 |
| `@coderabbitai resolve` | CodeRabbit コメントを全 resolved にするだけ | 両可 |
| **`@coderabbitai approve`** | **スレッド解決 + 正式 GitHub APPROVED レビューを提出** | **top-level PR コメント必須**（thread 返信では無効） |
| `@coderabbitai pause` / `resume` | 自動レビューの停止 / 再開 | 両可 |
| `@coderabbitai summary` | PR 説明欄のサマリ更新 | top-level |
| `@coderabbitai configuration` | 現在のリポジトリ設定を表示 | top-level |

### `request_changes_workflow` 依存（最重要）

`@coderabbitai approve` が機能するのは **`reviews.request_changes_workflow: true`** が設定されている場合のみ。

- **デフォルトは `false`**。false の場合 CodeRabbit は一切 Approve せず（どれだけ綺麗でも）、承認は人間レビュアーに委ねられる。`@coderabbitai approve` を送っても「approval is disabled」と返すだけ。
- `true` の場合のみ: CodeRabbit はレビューで指摘があれば `CHANGES_REQUESTED` を提出し、全コメント解決後に `approve` で正式 APPROVED を出せる。

確認コマンド:

```bash
grep -n "request_changes_workflow" .coderabbit.yaml .coderabbit.yml 2>/dev/null
# 出力が無い、または false → approve は機能しない。設定変更が先。
# .coderabbit.yaml が存在する時点で Organization GUI 設定は無視され本ファイルが唯一の SoT。
```

## 標準手順

PR 番号を `$1`（引数）または `gh pr view --json number` から取得。owner/repo は `gh repo view --json owner,name`。

### Step 1: 前提と現状の確認

```bash
PR=<番号>
# 1. request_changes_workflow が true か
grep -n "request_changes_workflow" .coderabbit.yaml 2>/dev/null
# 2. 現在の判定・マージ可否・HEAD
gh pr view $PR --json reviewDecision,mergeable,headRefOid \
  --jq '"review: \(.reviewDecision)  mergeable: \(.mergeable)  head: \(.headRefOid[0:7])"'
# 3. 未解決レビュースレッド数
gh api graphql -f query='query($o:String!,$r:String!,$p:Int!){repository(owner:$o,name:$r){pullRequest(number:$p){reviewThreads(first:100){nodes{isResolved}}}}}' \
  -f o=<owner> -f r=<repo> -F p=$PR \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)]|length'
```

- `request_changes_workflow` が無効 → ここで停止。approve は機能しない旨を伝える。
- 未解決スレッドがある → Step 2 へ。無ければ Step 3 へ。

### Step 2: 指摘を修正（未解決スレッドがある場合）

`/review-pr` スキルの手順で各スレッドを修正・push・返信・resolve する。CodeRabbit への返信は英語＋日本語要約。
**push すると直前の APPROVED は自動 DISMISS される**点に注意（Step 3 を push 後に必ず実行）。

### Step 3: 正式 APPROVED を取得

```bash
gh pr comment $PR --body "@coderabbitai approve"
```

- **必ず top-level PR コメント**で送る（review thread 返信では無効）。
- 投稿後、CodeRabbit が残スレッドを解決し formal APPROVED を提出する（通常 20秒〜数分）。

### Step 4: 検証

```bash
# APPROVED になるまで監視（背景実行推奨。foreground sleep はハーネスでブロックされる場合あり）
for i in $(seq 1 12); do
  dec=$(gh pr view $PR --json reviewDecision --jq '.reviewDecision')
  [ "$dec" = "APPROVED" ] && { echo "APPROVED"; break; }
  sleep 20
done
gh api repos/<owner>/<repo>/pulls/$PR/reviews --jq '.[] | "[\(.user.login)] \(.state)"' | tail -3
```

`reviewDecision == APPROVED` かつ `mergeable == MERGEABLE` でゲート充足。**マージ実行はユーザーの明示指示後**（git-safety）。

## フォールバック・エッジケース

### A. sticky な CHANGES_REQUESTED が外れない

コミットで指摘を直しスレッドを全 resolved にしても、CodeRabbit が過去に提出した `CHANGES_REQUESTED` レビューが残り `reviewDecision` が変わらないことがある（`@coderabbitai review` は既レビュー済みコミットを再評価しないため判定を更新しない）。

対処の優先順:
1. スレッドが全 `isResolved=true` か確認（指摘が実際に解消済みかの裏取り）。
2. 解消済みなら **まず `@coderabbitai approve`** を試す（最もクリーン）。
3. それでも CHANGES_REQUESTED が残る場合、陳腐化レビューを **API で dismiss**:
   ```bash
   RID=$(gh api repos/<owner>/<repo>/pulls/$PR/reviews --jq '.[]|select(.state=="CHANGES_REQUESTED")|.id' | head -1)
   gh api -X PUT repos/<owner>/<repo>/pulls/$PR/reviews/$RID/dismissals \
     -f message="指摘は解消済み・スレッド resolved 済みのため陳腐化レビューを dismiss" -f event=DISMISS
   ```
   dismiss すると `CHANGES_REQUESTED → REVIEW_REQUIRED` に落ちる。その後 `@coderabbitai approve` で正式承認を取得。

### B. push したら APPROVED が消えた

新規 push は直前の CodeRabbit APPROVED を自動 DISMISS する（GitHub の仕様 + CodeRabbit 挙動）。**push 後は再度 `@coderabbitai approve` を送る**。

### C. Rate Limit で skip された

コメントに記載の解除時刻まで待ってから再実行する。解除前の催促は再 skip されるだけ。

## アンチパターン

- ❌ `@coderabbitai review` / `full review` で formal APPROVED を期待する（所見コメントしか返らない）
- ❌ `@coderabbitai approve` を**レビュースレッド返信**で送る（top-level 必須・無効になる）
- ❌ `request_changes_workflow` 無効のまま approve を待つ（永遠に承認されない。設定確認が先）
- ❌ push 後に再 approve せず APPROVED 継続を期待する（push で DISMISS 済み）
- ❌ マージゲート充足とマージ実行を混同する（gate クリア ≠ マージ許可。マージは明示指示後）

## 関連

- `/review-pr` — レビュー指摘への修正・返信・resolve の手順（Step 2 の本体）
- メモリ `feedback_coderabbit_merge_workflow` — 本リポジトリの merge gate 運用（承認1件必須・sticky review 罠）
- 出典: [CodeRabbit Commands](https://docs.coderabbit.ai/guides/commands) / [Configure CodeRabbit](https://docs.coderabbit.ai/configure-coderabbit/) / [Request Changes Workflow](https://docs.coderabbit.ai/changelog/request-changes-workflow)
