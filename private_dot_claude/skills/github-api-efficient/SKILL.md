---
name: github-api-efficient
description: GitHub API / gh CLI を使う前に、最もレートリミット効率の良いメソッド選択・静的キャッシュ・事前budgetチェックを強制する規律スキル。`gh api` / `gh project item-list` / `gh issue list` / GraphQL での Issue・Project・PR の取得、一括操作、「GitHub から取得」「一覧取得」「棚卸し」等の依頼時、特に件数が多い・ループする・繰り返し取得する場面の前に必ず使用する。レートリミット枯渇（403/429）・再取得の無駄を構造的に防ぐ。
---

# GitHub API Efficient Skill

GitHub API（`gh` CLI / REST / GraphQL）を使う作業の前に、**3つの規律**を強制する:

1. **最安メソッドを選ぶ**（全件取得ではなくサーバー側フィルタ／最小フィールド）
2. **静的キャッシュを通す**（同じ取得を二度叩かない・再取得でデバッグしない）
3. **重い・ループする取得の前に budget を確認する**（`gh api rate_limit` は無料）

> このスキルは 2026-06-15 の実事故から正本化した。takeover 中に「現 Sprint の Issue を取得」で十分なところを `gh project item-list -L 4000` で全件（約3,200件）を取得し、さらに自分の Python パースのバグを直すたびに全件を再取得して GraphQL レートリミットを枯渇させた。失敗の核心は分量ではなく **①指示スコープ超過 ②再取得でのバグ修正 ③事前budget未確認**。

## いつ発動するか（必須）

GitHub API を叩く前、特に以下では必ずこのスキルの判断を通す:

- `gh project item-list` / `gh issue list` / `gh search` / `gh api graphql` で **複数件の取得**をする
- 取得結果を**ループで処理**する、または**繰り返し取得**する見込みがある
- 「棚卸し」「一覧」「全件」「集計」「Sprint の Issue」などスコープが広い依頼

単発の 1 リソース取得（`gh issue view 123`）や、自明な read 1 回ならこの規律は軽く流してよい。

## 規律1: 最安メソッドを選ぶ

取得の前に「**この問いに答える最小データは何か**」を必ず自問する。詳細な判断フローは
[reference/method-selection.md](reference/method-selection.md) を参照。要点:

- **指示が切ったスコープを越えない**。「現 Sprint」なら現 Sprint だけ。全件取得は安全ではなく、ただ高コスト
- **サーバー側でフィルタ**してから取る（`--search` / GraphQL の引数 / `gh issue list --label --milestone --assignee`）。クライアント側 `jq` フィルタのために全件ダンプしない
- **必要フィールドだけ**取る（`--json number,title` / GraphQL で要る node だけ・`first` は必要数）
- GraphQL connection は `first`/`last` 必須。`-L 4000` のような巨大ページングを安易に使わない
- REST GET の繰り返しは ETag 条件付き（304 はレート無料）。GraphQL に ETag は無い → キャッシュ＋最小取得が効く

## 規律2: 静的キャッシュを通す

**同じ取得を二度 API に投げない。** 重い取得結果はまずファイル化し、解析・整形はローカルで反復する。
パーサのバグ修正のために API を再実行しない（今回の事故の直接原因）。

ラッパー `scripts/gh-cache.sh` を read 系コマンドの前置に使う:

```bash
# 通常の gh をそのまま前置するだけ。TTL 内の再実行は API ゼロ消費でディスクから返る
~/.claude/skills/github-api-efficient/scripts/gh-cache.sh \
  api graphql -f query='{ ... }'

~/.claude/skills/github-api-efficient/scripts/gh-cache.sh \
  project item-list 35 --owner mationinc --format json > /tmp/board.json
```

- TTL 既定 300 秒。`GH_CACHE_TTL=60` 等で調整、`GH_CACHE_BYPASS=1` で強制取得（結果は再キャッシュ）
- write（`--method POST` 等・`mutation`・`issue create` 等）は**キャッシュせず素通し**で `gh` に渡る。安全に前置できる
- REST GET は ETag を保存し、TTL 切れ時は条件付きリクエストで再検証（304 ならレート無料）
- 取得結果を解析するなら **`> /tmp/xxx.json` に保存 → ローカルで `jq`/`python`** を反復する。`gh ... | python` の直結を、解析が失敗し得る場面で使わない

ラッパーを使わない場合でも、重い取得は必ず `> file` に保存してから解析する。

## 規律3: 重い取得の前に budget を確認

ループ・一括取得の前に残量を 1 度測り、`件数 × 推定コスト` が残量を超えるなら分割／延期する。

```bash
# rate_limit endpoint は消費ゼロ。これで事前ゲートする
gh api rate_limit --jq '{core:.resources.core.remaining, graphql:.resources.graphql.remaining, search:.resources.search.remaining}'
```

- REST core 既定 5,000 req/h、GraphQL 5,000 pt/h、Search 30 req/min（別バケット）
- `gh project item-list` / `gh issue list` は GraphQL バケットを消費する
- 残量が乏しい（例: GraphQL < 200）ときは重い取得を打ち切り、リセット時刻（`x-ratelimit-reset`）まで待つか、スコープを絞る
- 制限到達（403/429）時は即時 retry 禁止。`retry-after` 優先、無ければ reset まで待機 + 指数バックオフ

仕様の定数・バックオフ詳細は [reference/rate-limits.md](reference/rate-limits.md) を参照。

## 既存資産との関係（scrum-penguin）

scrum-penguin プラグインの `github-operator` エージェントが、scrum バッチ処理向けに同等の
レートリミット知識と観測ヘルパー `gh-with-budget.sh` を持つ。**接続層は両者とも素の `gh` CLI のみ**で
競合しない（MCP も独自 HTTP も無い）。本スキルは「main ループの ad-hoc な GitHub 作業」用の規律＋
キャッシュ層を担い、仕様知識は公式ドキュメントを正本に蒸留している。定数が変わったら両方を更新する。

## チェックリスト（GitHub API 作業の着手前）

- [ ] この取得に必要な**最小スコープ／最小フィールド**は何か即答できる
- [ ] サーバー側フィルタを使い、全件ダンプ＋クライアント側 filter にしていない
- [ ] 重い／ループ取得の前に `gh api rate_limit` で残量を確認した
- [ ] 取得結果は `> file` に保存し、解析はローカルで反復する（再取得しない）
- [ ] 繰り返し得る read は `gh-cache.sh` を前置した
