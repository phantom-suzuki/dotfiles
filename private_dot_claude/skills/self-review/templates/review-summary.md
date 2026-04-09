# セルフレビュー サマリテンプレート

以下のテンプレートに基づいて最終サマリを生成する。
`{...}` 部分を実際の値に置換すること。

---

## Self-Review Summary

### 結果

| 項目 | 値 |
|------|---|
| 終了理由 | {convergence_reason: 収束完了 / 上限到達} |
| 総イテレーション数 | {total_iterations} |
| Strategy | {strategy_used} |
| 対象ファイル数 | {file_count} |
| 対象 diff 行数 | {diff_lines} |

### イテレーション詳細

| # | Simplify 変更 | レビュアー | 指摘数 (auto/judgment/info) | 修正数 |
|---|:---:|---|---|:---:|
| {N} | {simplify_changes} 件 | {reviewer_name} | {auto}/{judgment}/{info} | {fixes_applied} 件 |

### 修正サマリ

#### 自動修正 (auto-fix)

- [{file}:{line}] {title} — {description}

#### ユーザー判断 (judgment)

- [{file}:{line}] {title} — ユーザー回答: {user_decision}

### 残存事項 (info)

今すぐの対応は不要だが、将来的に検討すべき事項:

- [{file}:{line}] {title} — {description}

### レビュアー使用状況

| レビュアー | 使用回数 | フォールバック発生 |
|-----------|:-------:|:---:|
| Claude-p (Sonnet) | {count} | {fallback: Yes/No} |
| Codex CLI | {count} | {fallback: Yes/No} |
| Gemini CLI ({model}) | {count} | {fallback: Yes/No} |
| Simplify | {count} | - |
