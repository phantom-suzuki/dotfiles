# peer-review 最終サマリテンプレート

作業完了時にユーザーに表示するサマリのテンプレート。

---

## peer-review 完了 — PR #{N}

### 投稿結果

| 項目 | 値 |
|------|---|
| PR URL | {PR URL} |
| 判定 | {approve / comment / request-changes} |
| 投稿時刻 | {ISO8601} |
| コメント本文 | {文字数} 文字 |

### 指摘サマリ

| 分類 | 件数 |
|------|:---:|
| must-fix | {N} |
| should-fix | {N} |
| question | {N} |
| nit | {N} |
| praise | {N} |

### レビュアー使用状況

| レビュアー | 実行 | 備考 |
|-----------|:---:|------|
| L1 Claude (Opus) | ✓ | - |
| L2 Gemini ({pro \| flash}) | {✓ \| - skipped} | {フォールバック有無} |
| L3 Codex (optional) | {✓ \| - skipped} | {--with-codex 時のみ} |

### 主な指摘（must-fix のみ）

- **M1**: {タイトル}
- **M2**: {タイトル}

### 次に期待される作成者アクション

- {返信 / 修正コミット / Issue 起票 / ADR 更新}

### 後続フォローアップ

- 作成者返信が来たら、必要に応じて追加コメントを検討
- must-fix が全て解消されたら `gh pr review {N} --approve` で最終 approve
- 関連する後続 Issue の起票: {Issue 候補リスト}
