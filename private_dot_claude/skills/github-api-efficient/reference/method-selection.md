# 最安メソッド選択ガイド

「この問いに答える最小データは何か」から逆算してメソッドを選ぶ。**取得してからフィルタ**ではなく、
**フィルタしてから取得**する。

## 判断フロー

```
何が欲しい？
├─ 単一リソースの詳細        → gh issue/pr view <n> --json <最小フィールド>
├─ 条件付きの Issue/PR 一覧   → サーバー側フィルタを最大限使う（下表）
├─ Project(Board) のフィールド → 現 Sprint 等で絞った GraphQL。全件 item-list は最後の手段
└─ 集計/横断                  → まずスコープを Sprint/Label/Milestone で絞る
```

## よくある取得の「高い vs 安い」

| 欲しいもの | ❌ 高い | ✅ 安い |
|---|---|---|
| 自分の OPEN Issue | `gh project item-list -L 4000` を `jq` で filter | `gh search issues "repo:o/r is:open assignee:@me"`（Search バケット） |
| 現 Sprint の Issue | Board 全件取得→client filter | Iteration を GraphQL で 1 度引き、現 Sprint の iterationId で `items(first:N)` を絞る |
| ラベル別 Issue | 全件→filter | `gh issue list --label X --milestone Y --json number,title` |
| 1 Issue の Project フィールド | Board 全件 | `gh api graphql` で `node(id:issueId){ ... projectItems(first:5){...fieldValueByName...} }` |
| PR の状態 | 全 PR list | `gh pr view <n> --json state,reviewDecision,statusCheckRollup` |

## サーバー側フィルタの引き出し

- `gh issue list`: `--label` `--milestone` `--assignee` `--state` `--search` `--json <fields>` `--limit`
- `gh search issues/prs`: GitHub 検索構文をフルに使う（`repo:` `is:` `label:` `assignee:` `milestone:` `created:`）。**Search は別バケット（30/min）**なので core/graphql を温存できる
- GraphQL: connection を `first: <必要数>` で絞り、欲しい node だけ書く。`fieldValueByName(name:"Sprint")` のように単一フィールドを名指しで引く

## ⚠ 実測: 全件 item-list は GraphQL 予算の約半分を1回で消費する

2026-06-15 計測（Project #35、約2,300 items、`gh project item-list 35 -L 4000`）:

- **1回のフルボード取得 ≈ 約2,400 GraphQL points**（5,000pt/h 予算の約半分）
- → **2回で枯渇寸前、3回で完全枯渇**。当初の事故（3回再取得）が枯渇したのは必然
- さらに**枯渇寸前の状態で取得すると `item-list` が部分的・不完全な結果を返す**（件数が実際より少なく見え、誤った判断を招く）。残量が乏しいときは取得自体を延期する

対策: フルボードは**1回だけ**取得して `> file` にキャッシュし、以降の集計・絞り込みはローカルで行う（`gh-cache.sh` のHITならAPIゼロ）。Sprint やラベルで絞れるなら全件取得を避ける。

## スコープを越えない（最重要）

指示・スキルが切ったスコープより広く取らない。

- 「現 Sprint」と言われたら現 Sprint の iterationId だけ。全 Sprint・全件を取らない
- 「この Epic 配下」なら sub-issues を辿る。リポ全件を舐めない
- 全件が**本当に**必要なときだけ全件取得し、その場合は事前 budget 確認＋ページング件数を `log` 的に明示する

## 取得後は保存してローカル反復

重い取得は必ず `> /tmp/xxx.json` に保存し、`jq` / `python` の試行錯誤はそのファイルに対して行う。
**解析スクリプトのバグを直すために API を再実行しない**（2026-06-15 事故の直接原因）。

```bash
gh-cache.sh project item-list 35 --owner mationinc --format json > /tmp/board.json
# 以降、/tmp/board.json に対して jq/python を何度でも回す（API 消費ゼロ）
jq '...' /tmp/board.json
python3 analyze.py < /tmp/board.json
```

## 現 Sprint だけを安く引く例（Project #35）

Board 全件ではなく、Iteration 設定を 1 度引いて現 Sprint を特定し、必要なら絞った items を取る:

```bash
# 1) iteration 一覧（軽量・1 query）
gh-cache.sh api graphql -f query='
{ organization(login:"mationinc"){ projectV2(number:35){
    field(name:"Sprint"){ ... on ProjectV2IterationField {
      configuration { iterations { id title startDate duration } } } } } } }'
# 今日 ∈ [startDate, startDate+duration) の iteration が現 Sprint
```

`.scrum/.metacache.json` に project_id / field_ids / iteration_ids がキャッシュ済みなら、それを使って
API 往復をさらに減らせる（field-list の再取得を避ける）。
