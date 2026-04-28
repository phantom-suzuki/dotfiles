# Drift Detection — エコシステム別の追従更新検知レシピ

bot PR のバージョン bump で「他に追従が必要な箇所」を決定論的に grep するためのレシピ集。

エコシステム判定後、対応する節を参照して検知ロジックを実行する。

## 共通フロー

1. PR メタから `ecosystem` / `package` / `from` / `to` を取得
2. このファイルから対応エコシステムのレシピを参照
3. レシピが指す **検索パターン**を `from` の version から構築
4. リポジトリ全体に grep（`rg` または `grep -rn`、`.git`/`node_modules`/`vendor` を除外）
5. PR 差分（`gh pr diff <PR> --name-only`）にヒットファイルが含まれていれば skip、含まれていなければドリフト候補
6. Claude が候補を読み、以下を除外:
   - コメント文中の歴史的記述（「以前は X だった」等）
   - サンプルコード / フィクスチャ
   - 別パッケージ / 別文脈の偶然一致
   - すでに `to` 値で書かれている箇所（grep の `from` ヒットだが実は別文脈）
7. 残った候補を「追従要」として出力

## エコシステム別レシピ

### docker（Dockerfile FROM bump）

例: `golang:1.24-bookworm` → `golang:1.26-bookworm`

| 検索対象 | パターン例（from = `1.24`） | 該当ファイル |
|---|---|---|
| Go module の go directive | `^go 1\.24(\.\d+)?$` | `**/go.mod` |
| Go toolchain directive | `^toolchain go1\.24` | `**/go.mod` |
| GitHub Actions setup-go の go-version | `go-version:\s*['"]?1\.24` | `.github/workflows/*.yml` |
| Reusable workflow の inputs default | `default:\s*['"]1\.24` | `.github/workflows/_*.yml` |
| Makefile / shell script のバージョンチェック | `1\.24` | `**/Makefile`, `**/*.sh` |
| ドキュメント（README / CLAUDE.md / ADR） | `Go 1\.24`, `golang 1\.24`, `1\.24-bookworm` | `**/*.md` |
| `.tool-versions` / `.go-version` / `asdf` | `^golang 1\.24` | リポジトリルート / `apps/**` |

注: ADR（Architecture Decision Record）は意思決定時点の記録のため**触らない方針**にすることが多い。Claude が判断時にスキップ候補へ。

### gomod（Go module bump）

例: `google.golang.org/grpc v1.77.0` → `v1.79.3`

| 検索対象 | パターン例 | 該当ファイル |
|---|---|---|
| go.sum エントリ | `from` の hash | `**/go.sum`（基本 `go mod tidy` で自動更新されるため checked か確認のみ） |
| vendor/ ディレクトリ | vendoring 使用時 | `vendor/**` |
| ドキュメント中のバージョン記述 | `grpc.*v1\.77` | `**/*.md` |
| 別 module の go.mod が同パッケージを require | 同 package を別 directory で参照 | `**/go.mod`（モノレポ時） |

### npm（npm/yarn package bump）

例: `react 19.0.0` → `19.1.0`

| 検索対象 | パターン例 | 該当ファイル |
|---|---|---|
| 別 workspace の package.json | `"react":\s*"\^?19\.0` | `**/package.json` |
| package-lock / yarn.lock | 自動更新だが Dependabot 設定で grouping されているか確認 | `**/package-lock.json`, `**/yarn.lock` |
| ドキュメント中のバージョン記述 | `React 19\.0` | `**/*.md` |
| Storybook / vitest 等 peer-dep が固定バージョンを要求 | peer-deps 互換性 | `**/package.json` の `peerDependencies` |
| TypeScript の types 定義 | `@types/<pkg>` の version | `**/package.json`（types バージョン乖離） |

### github-actions（Actions version bump）

例: `actions/setup-go@5` → `@6`

| 検索対象 | パターン例 | 該当ファイル |
|---|---|---|
| 他 workflow での同 action 使用 | `uses:\s*actions/setup-go@v?5` | `.github/workflows/*.yml` |
| Composite action の参照 | 同上 | `.github/actions/*/action.yml` |
| README で example として記載 | `actions/setup-go@v5` | `**/*.md` |
| **Major bump の breaking changes** | Node version / API 互換 | リリースノート要確認（→ release-notes.md） |

注: GHA は **すべての workflow** で同 action を使っている可能性が高いため、PR 差分に含まれない other workflows を必ずチェック。

## Renovate 固有の差分

Renovate は config 次第で挙動が変わる:

- **branch 名**: `renovate/<manager>-...`（manager 部分は config の `branchPrefix` 設定で変更可）
- **title**: `Update dependency X to Y` / `chore(deps): update X to Y` / config 次第
- **from が title に含まれない**: Dependabot と違い `from` を必ずしも明示しない
  - その場合は `gh pr diff <PR>` の変更行から `-` の行を抽出して `from` 推定:
    ```bash
    gh pr diff <PR> | grep -E "^-FROM golang" | head -1
    ```

## False positive 除去のヒント（Claude 判断材料）

候補をレポート対象に残すかの判断:

| ケース | 判定 | 理由 |
|---|---|---|
| ヒット箇所が `# 以前は X だった` のようなコメント | 除外 | 履歴記述は更新しない |
| ヒット箇所が ADR (`docs/adr/*.md`) | 除外推奨 | 意思決定時点の記録、別 ADR で更新するのが筋 |
| ヒット箇所がテストフィクスチャ / モックデータ | 除外 | テスト固有 version |
| ヒット箇所が `from` と同じだが別 package の文字列 | 除外 | 偶然一致（grep の前後文脈で確認） |
| ヒット箇所が `from` でかつ同 package | **追従候補** | 真陽性 |
| ヒット箇所が複数バージョン同時記載（`1.24 / 1.25 / 1.26`） | 個別判断 | サポートマトリクス系の記述で更新不要のことも |

## 出力フォーマット（findings JSON）

```json
[
  {
    "file": "apps/backend/go.mod",
    "line": 3,
    "current_value": "go 1.24.0",
    "suggested_value": "go 1.26.0",
    "severity": "high",
    "reason": "Dockerfile が 1.26 に bump されたため go directive も追従が必要"
  }
]
```

`severity`:
- `high`: ほぼ確実に追従要（ビルド/CI が壊れる、あるいは bump の意図と矛盾）
- `medium`: 確認推奨（更新しなくても動くがドキュメントとして整合性を欠く）
- `low`: 任意（コメント・ADR 等、touch しないことも妥当）

レポートには `high` + `medium` のみ出す。`low` は省略するか「参考」として最後に列挙。

## 拡張時のメンテナンス

新しいエコシステムを追加する場合は本ファイルに新節を追加し、`SKILL.md` の「サポートする bot author」「エコシステム判定」を併せて更新する。
