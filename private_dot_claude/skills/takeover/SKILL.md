---
name: takeover
description: handover.md と Sprint Board の実体を突き合わせ、ネクストアクション候補を優先度順に提示して前回セッションを再開する。セッション開始時に使用。
disable-model-invocation: true
---

# Session Resume Skill

前回セッションの引き継ぎ（`~/.claude/projects/<project-key>/handover.md`）と、プロジェクトの Sprint Board 実体を突き合わせ、**今セッションのネクストアクション候補を優先度順に提示**して作業を再開する。ユーザーが白紙から「次どれをやるか」を考えなくて済むようにするのが目的。

## 引き継ぎファイルの場所

読込元は `~/.claude/projects/<project-key>/handover.md`。

`<project-key>` は、現在の作業ディレクトリの絶対パス中の `/` を `-` に置換した文字列（先頭の `-` を含む。Claude Code 内部のプロジェクトキー形式）。

```bash
# 例: /Users/alice/work/my-app -> -Users-alice-work-my-app
PROJECT_KEY=$(pwd | sed 's|/|-|g')
HANDOVER_PATH="$HOME/.claude/projects/${PROJECT_KEY}/handover.md"
```

## Procedure

### Step 1: 引き継ぎファイルの判定・読み込み

以下の4分岐で引き継ぎファイルを判定する。

- (a) 新パスのみ存在 → 新パスを読んで再開する。
- (b) カレントディレクトリの `HANDOVER.md` のみ存在（新パスは無い）→ 内容を新パスへ移行保存し、カレントの `HANDOVER.md` は削除してから新パスを読んで再開する。
- (c) 両方存在:
  - 内容が同一 → カレントの `HANDOVER.md` を削除（クリーンアップ）し、新パスで再開する。
  - 内容に差分あり → 両ファイルを読んで差分を抽出・整理し、どう統合するか/どちらを採用するかの方法をユーザーに提案する。ユーザー承認後に新パスへ確定保存し、カレントの `HANDOVER.md` を削除してから新パスを読んで再開する。
- (d) どちらも存在しない → handover が無い旨を伝え、Step 2 以降（Board 起点のネクストアクション提示）のみ実施する。Board も無ければその旨を伝えて終了。

handover を読んだら、内部的に以下を把握しておく（この時点ではまだ要約提示しない）:
- Summary / Current State
- In Progress / Incomplete（= 前回の続きの最有力候補）
- Next Steps（前回の自分が想定したネクストアクション）
- Issues / Concerns（着手前に解消すべき確認事項の候補）
- handover が言及している Issue 番号

### Step 2: Sprint Board の実体確認（scrum 運用 repo の場合のみ）

カレントが GitHub repo で、Sprint Board 運用がある場合に実施する。**無い場合は Step 2〜3 を飛ばし、handover の Next Steps だけでネクストアクションを構成する。**

Board の有無・Project 番号の判定材料（上から優先）:
1. このプロジェクトの memory（`reference_*_sprint_board.md` 等に Project 番号・project_id・Iteration field id が記録されていることが多い）
2. `.scrum/.metacache.json`（`project_id` / `field_ids` / `iteration_ids`）
3. `.scrum/config.md`

> **机上記述は信用しない**（[[feedback-config-vs-github-reality]]）。config.md / handover / memory の Sprint 番号・Iteration マッピングは計画書であって実体と一致する保証はない。Project 番号など「場所」の特定には使ってよいが、**現 Sprint の判定は必ず GraphQL で実体確認する**。

現 Sprint の実体確認（[[feedback-sprint-iteration-lookup]]）:

```bash
gh api graphql -f query='
{
  organization(login: "<ORG>") {
    projectV2(number: <PROJECT_NUMBER>) {
      field(name: "<ITERATION_FIELD_NAME>") {   # 実名は "Sprint" のこともある。memory/metacache で確認
        ... on ProjectV2IterationField {
          configuration { iterations { id title startDate duration } }
        }
      }
    }
  }
}'
```

`今日の日付 ∈ [startDate, startDate + duration)` を満たす iteration が現 Sprint。duration は 7 日固定ではなく 14 日もあり得る。

現 Sprint の Issue を取得し、各 Issue の **Status / Priority / Issue Type / SP / Assignee** を把握する（`gh project item-list` または GraphQL）。ユーザー自身の GitHub ログイン名は `gh api user --jq .login` で取得し、「ユーザー Assign 分」を区別できるようにする（ただし下記ランク付けで Assign は唯一の軸ではない）。

### Step 3: 整合チェック（handover × Board）

handover の Next Steps / In Progress / Issues と、Board 実態を突き合わせ、**一致とズレを明示**する。典型的なズレ:

- handover「着手済み / In Progress」と書いてあるのに Board Status が Todo のまま
- handover の Sprint 表記と GraphQL 実体の現 Sprint がずれている
- Next Steps の項目に対応する Issue が Board 上で別 Sprint / Closed になっている
- 依存先 Issue が未完で、Next Steps の項目がまだ着手できない

ズレは「着手前に解消すべき確認事項」として候補リストとは分けて提示する（事実報告に徹し、勝手に Board を更新しない）。

### Step 4: ネクストアクション候補を優先度順に提示

着手候補を **3〜5 件**に絞り、優先度順に番号付きで提示する。各候補に**根拠を1行**添える。ランク基準（上ほど優先）:

1. **In Progress のタスク** — 前回の続き。最優先で再開対象。
2. **handover の Next Steps にあり、Board 上 Todo かつ着手可能**（依存解消済み）なもの。
3. **現 Sprint の高 Priority（P0/P1）で未着手・着手可能**なもの（handover 未言及でも拾う）。
4. それ以下の現 Sprint タスク。

提示フォーマット例:

```
## 現状（実体確認済み）
- 現 Sprint: Sprint-N（実体 start〜end、GraphQL 確認済み）
- 前回の焦点: <handover Summary を1行>

## 整合チェック（handover × Board）
- ⚠ <ズレ・要確認事項があれば>
- ✓ <一致している点>

## ネクストアクション候補（優先度順）
1. #123 <タイトル> — 根拠: In Progress、前回の続き
2. #456 <タイトル> — 根拠: P1・依存解消済・現 Sprint
3. ...

→ 着手する番号を選んでください（別タスク・別方針の指示でも可）。
```

選択を受けたら着手する。

## 制約（必守）

- **スクラムイベントを自発提案しない**（[[feedback-no-scrum-event-suggestion]]）。retrospective / sprint-planning / daily-standup / backlog-refinement / sprint-review を候補や Next Steps に含めない。Sprint 期限・Sprint Goal 遅延等のリスクを観測しても「ユーザー判断に委ねる」事実報告に止め、「実施推奨」等の能動的提案文言を付けない。
- **Board を勝手に更新しない**。整合チェックで見つけたズレ（Status 不整合等）は提示するだけで、ユーザーの指示があってから更新する。
- **現 Sprint は必ず実体確認**（[[feedback-sprint-iteration-lookup]] / [[feedback-config-vs-github-reality]]）。handover / config.md の Sprint 表記を現 Sprint 判定の根拠にしない。
- 候補は実装・調査・レビュー対応など**手を動かすタスク**に限定する。
- 推測で候補を埋めない。Board が取得できない・handover が無い場合は、取れた情報の範囲で正直に提示する。
