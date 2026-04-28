# Report Template — PR コメント投稿用テンプレート

`/dependabot-review` が投稿するレポートコメントの構造とテンプレート。

## 固定マーカー

upsert のための識別子。コメント本文の **先頭行** に必ずこの行を含める:

```
<!-- dependabot-review:report -->
```

更新時は同マーカー付きの既存コメントを検索して `PATCH`、なければ新規投稿。

## 全体構造

```markdown
<!-- dependabot-review:report -->
## 🤖 dependabot-review レポート

**対象 PR**: #<番号> — `<title>`
**エコシステム**: <docker | gomod | npm | github-actions>
**Bump**: `<package>` `<from>` → `<to>`
**実行日時**: <YYYY-MM-DD HH:MM JST>

---

### {{ ドリフト検知セクション }}

{{ Release Notes セクション (--release-notes 指定時のみ) }}

---

### 📌 推奨アクション

{{ アクション提案 }}

---

<sub>🛠 `/dependabot-review` スキルにより生成。`<!-- dependabot-review:report -->` マーカーで upsert されます。</sub>
```

## ドリフト検知セクション

検知結果に応じて 3 パターン:

### パターン A: ドリフト検出あり

```markdown
### 🔍 ドリフト検知結果

**結論**: 追従更新が必要な箇所が **<件数> 件** 検出されました。

| Severity | File | Line | Current | Suggested | Reason |
|---|---|---:|---|---|---|
| 🔴 high | `apps/backend/go.mod` | 3 | `go 1.24.0` | `go 1.26.0` | Dockerfile bump に追従が必要 |
| 🟡 medium | `apps/backend/Makefile` | 4 | `# Go 1.24+` | `# Go 1.26+` | コメント記述の整合性 |

#### 検知に含めなかった候補（参考）
- `docs/adr/002-technology-stack.md`: ADR は意思決定時点の記録のため対象外
```

### パターン B: ドリフト検出なし

```markdown
### 🔍 ドリフト検知結果

**結論**: 追従更新が必要な箇所は検出されませんでした ✅

調査範囲: <調査したパターン数> パターン / <調査ファイル数> ファイル
```

### パターン C: 抽出失敗（title から bump 情報が取れなかった等）

```markdown
### 🔍 ドリフト検知結果

⚠️ PR title から bump 情報を抽出できなかったため、ドリフト検知をスキップしました。

`{{ title }}` から `package`/`from`/`to` を判定できません。手動で確認してください。
```

## Release Notes セクション（任意）

`--release-notes` 指定時のみ追加。詳細は [release-notes.md](release-notes.md) 参照。

```markdown
### 📋 Release Notes Summary

**<package>** `<from>` → `<to>`

#### ⚠️ Breaking Changes
- [release X.Y.Z] <概要>

#### 🔒 Security Fixes
- [CVE-YYYY-NNNNN](URL) <概要>（release Z.Z.Z で修正）

#### ✨ Notable Changes
- [release X.Y.Z] <概要>

詳細: <upstream changelog URL>
```

取得失敗時:

```markdown
### 📋 Release Notes Summary

⚠️ リリースノート取得に失敗しました: <理由>
手動で <upstream URL> を参照してください。
```

## 推奨アクションセクション

検知結果に応じて分岐:

### A. ドリフト検出あり（高 severity 含む）

```markdown
### 📌 推奨アクション

1. **追従 PR を作成**: 検知された <件数> 箇所をまとめて修正する PR を作成することを推奨します
   - ブランチ案: `feature/dependabot-followup-{{ PR# }}`
   - コミットメッセージ案: `chore(deps): sync version references for #{{ PR# }}`
   - マージ順: 元 PR #{{ PR# }} を先にマージ → 本追従 PR をマージ

スキル実行中であれば、続けて「追従 PR を作成しますか？」と確認されます。
```

### B. ドリフト検出あり（medium 以下のみ）

```markdown
### 📌 推奨アクション

検出された箇所はいずれも `medium` 以下です。元 PR を **そのままマージしても直ちにビルドが壊れることはありません**。
ドキュメント整合性のために任意で追従更新を検討してください。
```

### C. ドリフト検出なし

```markdown
### 📌 推奨アクション

ドリフトは検出されませんでした。元 PR の通常レビュー（テスト結果・breaking changes 確認）に進んでください。
```

## upsert ロジック（参考実装）

```bash
REPO="<owner/repo>"
PR=<番号>
MARKER="<!-- dependabot-review:report -->"
BODY=$(cat /tmp/report.md)  # 上記テンプレートを埋めた本文

existing=$(gh api repos/$REPO/issues/$PR/comments --paginate \
  --jq ".[] | select(.body | startswith(\"$MARKER\")) | .id" | head -1)

if [ -n "$existing" ]; then
  echo "Updating existing comment $existing"
  gh api repos/$REPO/issues/comments/$existing \
    --method PATCH \
    -f body="$BODY"
else
  echo "Creating new comment"
  gh pr comment "$PR" --repo "$REPO" --body "$BODY"
fi
```

## サブコマンド: 追従 PR 作成時の本文テンプレ

追従 PR の **PR 本文**には以下を含める:

```markdown
## 概要

[#{{ 元PR# }}]({{ 元PR URL }}) のバージョン bump に伴う追従更新。

`/dependabot-review` で検出されたドリフトを修正します。

## 変更内容

| File | Change |
|---|---|
| `apps/backend/go.mod` | `go 1.24.0` → `go 1.26.0` |
| `apps/backend/Makefile` | コメント `Go 1.24+` → `Go 1.26+` |

## マージ順

1. 先に元 PR [#{{ 元PR# }}]({{ URL }}) をマージ
2. その後本 PR をマージ（main の Dockerfile が新バージョンを使うため、追従が main 上で整合性を担保）

## 関連

- 元 PR: #{{ 元PR# }}
- 検知元スキル: `/dependabot-review`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## 元 PR への追加コメント（追従 PR 作成後）

追従 PR を作成したら、元 PR にも 1 行コメントを追加:

```markdown
<!-- dependabot-review:followup-link -->
🔗 追従 PR を作成しました: #{{ 追従PR# }}
```

これも upsert 対象（マーカーは別、`followup-link`）。
