# GitHub API レートリミット仕様（蒸留）

> **正本**: GitHub 公式ドキュメント。値は GitHub 側で変わり得るため、異常時は公式を再確認する。
> - REST: <https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api>
> - GraphQL: <https://docs.github.com/en/graphql/overview/rate-limits-and-node-limits-for-the-graphql-api>
> - Secondary: <https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api>
> - 条件付きリクエスト: <https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests-if-appropriate>
>
> scrum-penguin プラグインにも並行コピー（`docs/plugin/github-rate-limits.md`）がある。定数を直したら両方更新する。

## 二層構造

GitHub のレートリミットは独立した二層:

- **Primary**: 時間枠クォータ。バケットごとに残量がリセットされる。レスポンスヘッダ `x-ratelimit-*` で観測可
- **Secondary**: 短時間の乱用防止。明示的な残量 API は無い。間隔・並列・content 作成数で抑制する

## Primary（主要値・認証ユーザー既定）

| バケット | 既定上限 | 備考 |
|---|---:|---|
| REST 認証ユーザー | 5,000 req/h | PAT / OAuth。`gh issue create` 等の REST |
| REST 未認証 | 60 req/h | IP 単位 |
| GraphQL 認証ユーザー | 5,000 pt/h | **`gh project item-list` / `gh issue list` はここを消費** |
| Search（REST） | 30 req/min | 別バケット。`gh search` |
| Actions の GITHUB_TOKEN | 1,000 req(pt)/h/repo | CI 実行時 |

- Enterprise Cloud のユーザー代理は REST 15,000 / GraphQL 10,000 に上がる
- **残量確認**: `gh api rate_limit`（このendpoint自体は消費ゼロ）。`x-ratelimit-remaining` / `x-ratelimit-reset`（epoch秒）/ `x-ratelimit-resource`

```bash
gh api rate_limit --jq '{core:.resources.core.remaining, graphql:.resources.graphql.remaining, search:.resources.search.remaining}'
```

## GraphQL のコストと node 制限

GraphQL は「リクエスト数」ではなく **point** で課金される。さらに Primary 残量があっても **node 制限**が先に当たることがある:

- connection には `first` / `last` が必須（1〜100）
- 1 call で要求できる総 node 数の上限がある（深い `first:100` の多段ネストで急増）
- レスポンスに `rateLimit { cost remaining nodeCount }` を含めれば、その call の実コストを観測できる

```graphql
query { rateLimit { cost remaining nodeCount } ...本体... }
```

→ **巨大ページング（`-L 4000` 等）や深いネストは、Primary 枯渇・node 制限・timeout のいずれかを引く。** 必要な分だけ `first` で取り、ページングは必要件数で止める。

## Secondary（共有枠・短時間制限）

| 制限 | 値 |
|---|---|
| 同時実行（REST+GraphQL 共通） | 100 requests |
| content 作成（Issue/Comment/PR/Review/Sub-issue 等） | 80 req/min・500 req/h |
| 単一 endpoint への集中（REST） | 約 900 pt/min |
| 単一 endpoint への集中（GraphQL） | 約 2,000 pt/min |
| CPU time | 90 sec / 60 sec window |

### Secondary 用ポイント（リクエスト種別）

| 種別 | ポイント |
|---|---:|
| GraphQL query（mutation なし） | 1 |
| GraphQL mutation を含む | 5 |
| REST GET / HEAD / OPTIONS（大半） | 1 |
| REST POST / PATCH / PUT / DELETE（大半） | 5 |

→ 状態取得は query（1pt）に寄せ、書き込みは mutation（5pt）でまとめる。read-only ループに mutation を混ぜない。

## 条件付きリクエスト（ETag）で REST を無料再検証

REST GET のレスポンスには `ETag` ヘッダが付く。次回 `If-None-Match: <etag>` を付けて投げ、変化が無ければ
**`304 Not Modified` が返り、これは Primary レートリミットを消費しない**。`scripts/gh-cache.sh` がこれを自動化する。

- ETag が効くのは **REST のみ**。GraphQL（`gh project item-list` 等）には ETag が無い → キャッシュ＋最小取得で抑える

## バックオフ（制限到達時）

| 状況 | 対応 |
|---|---|
| `403` / `429` で `retry-after` ヘッダあり | その秒数だけ待つ |
| `x-ratelimit-remaining: 0` | `x-ratelimit-reset`（epoch）まで待つ |
| 上記以外の二次制限 | 最低 1 分 + 指数バックオフ |

**即時 retry は禁止**（ban を誘発する）。バッチは 1 件ごとに最低 1 秒 + ジッターを入れ、同時実行は低並列に抑える。
