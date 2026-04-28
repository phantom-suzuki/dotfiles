# Release Notes — `--release-notes` 指定時のリリースノート取得・要約

bot PR の `from` から `to` の間に発生した変更を要約する手順。デフォルト OFF（ネット呼び出しを伴うため）。

## 共通フロー

1. PR メタから `ecosystem` / `package` / `from` / `to` を取得
2. エコシステム別の取得方法でリリースノート / changelog を取得
3. `from` から `to` の間の release のみフィルタ
4. **breaking changes** / **security fix** を抽出して強調
5. ハイライト + 詳細リンクをレポートに追加

## エコシステム別取得方法

### docker

Docker タグ自体には changelog がないため、image の **upstream リポジトリ**を特定:

| image | upstream repo |
|---|---|
| `golang` | `golang/go` |
| `node` | `nodejs/node` |
| `gcr.io/distroless/*` | `GoogleContainerTools/distroless` |
| `python` | `python/cpython` |
| その他 公式 image | Docker Hub の Description にリンク記載 |

取得:
```bash
gh release list --repo golang/go --limit 50 \
  --json tagName,publishedAt,name | \
  jq '[.[] | select(.tagName | contains("go1.25") or contains("go1.26"))]'
```

注: Go の場合は minor (`go1.25.0`, `go1.25.1`, ...) ごとに release があるため、`from` から `to` の間に含まれる patch 数が多くなる。

### gomod

```bash
# 1. パッケージのリポジトリ URL を取得
go list -m -json google.golang.org/grpc | jq -r .Origin.URL
# → https://github.com/grpc/grpc-go

# 2. Releases を取得
gh release list --repo grpc/grpc-go --limit 30 \
  --json tagName,publishedAt,body
```

代替: `go doc -all` や `pkg.go.dev/<package>?tab=versions` を直接見る。

### npm

```bash
# Method 1: npm registry から repository URL
npm view <pkg> repository.url
# → git+https://github.com/facebook/react.git

# Method 2: GitHub Releases
gh release list --repo facebook/react --limit 20 --json tagName,name,body

# Method 3: npm view changelog (一部 package のみ)
npm view <pkg> versions --json
```

### github-actions

```bash
# Action 名から repo を特定
# uses: actions/setup-go@v6  →  actions/setup-go
gh release view v6 --repo actions/setup-go --json tagName,name,body

# 全 release 一覧
gh release list --repo actions/setup-go --limit 10
```

GHA は major bump で **Node version 変更**が頻繁にあるため、特に注目:
- Node 16 → 20 移行
- Node 20 → 24 移行（2026 予定）

## 要約フォーマット

レポートの「Release Notes」セクションは以下構造:

```markdown
### 📋 Release Notes Summary

**<package>** `<from>` → `<to>`

#### ⚠️ Breaking Changes
- [release X.Y.Z] <breaking change の概要>

#### 🔒 Security Fixes
- [release X.Y.Z] CVE-YYYY-NNNNN: <概要>

#### ✨ Notable Changes
- [release X.Y.Z] <注目すべき変更>

詳細: <upstream changelog URL>
```

## breaking change の検出ヒント

リリースノート本文から以下キーワードを抽出:

- 英語: `breaking`, `BREAKING CHANGE`, `removed`, `deprecated`, `incompatible`
- 日本語: `破壊的変更`, `非互換`, `削除`, `廃止`
- セキュリティ: `CVE-`, `security`, `vulnerability`, `脆弱性`

## API 呼び出し失敗時の挙動

ネット呼び出しが失敗した場合（rate limit / repo 不明 / private repo）:

1. WARNING を出して **Release Notes セクションを省略**
2. レポート末尾に「リリースノート取得失敗: <理由>」を 1 行記載
3. ドリフト検知のレポートはそのまま継続（Release Notes は補助情報）

## キャッシュ

同一 PR で複数回スキルを実行する場合、リリースノート取得結果を `/tmp/dependabot-review-cache/<repo>-<from>-<to>.json` 等に保存して再利用してもよい。ただし TTL は短く（1 時間程度）。

## 注意事項

- **rate limit**: GitHub API は認証ありで 5,000 req/h。`gh` 経由なら通常問題ないが、複数 PR を連続スキャンする場合は注意
- **private repo**: 上流が private ならアクセス不可。Skip して継続
- **monorepo**: 同 repo に複数 package がある場合（例: `protobuf/grpc-go` のサブモジュール）、`tagName` フィルタで該当のみ抽出
