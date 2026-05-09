# セルフレビュー サマリテンプレート

以下のテンプレートに基づいて最終サマリを生成する。
`{...}` 部分を実際の値に置換すること。

---

## Self-Review Summary

### 結果

| 項目 | 値 |
|------|---|
| 終了理由 | {convergence_reason: 収束完了 / 上限到達 / simple 早期終了} |
| 総イテレーション数 | {total_iterations} |
| Strategy | {strategy_used: simple / standard / deep} |
| 有効な opt-in | {opt_ins: --with-design / --with-gemini / --ultrareview / --simplify-via=codex（未指定なら「なし」）} |
| 対象ファイル数 | {file_count} |
| 対象 diff 行数 | {diff_lines} |

### 観点別件数

standard なら bug / security のみ、deep または `--with-design` 時は design も含める。

| 観点 | findings 数 | (auto-fix / judgment / info) |
|------|:---:|:---:|
| bug | {n} | {auto}/{judgment}/{info} |
| security | {n} | {auto}/{judgment}/{info} |
| design *(opt-in 時のみ)* | {n} | {auto}/{judgment}/{info} |

### イテレーション詳細

| # | Simplify 変更 | 起動レビュアー | 指摘数 (auto/judgment/info) | 修正数 |
|---|:---:|---|---|:---:|
| {N} | {simplify_changes} 件 | {reviewers_used} | {auto}/{judgment}/{info} | {fixes_applied} 件 |

### 修正サマリ

#### 自動修正 (auto-fix)

- [{file}:{line}] {title} — {description}

#### ユーザー判断 (judgment, 最大 3 件まで対話提示)

- [{file}:{line}] {title} — ユーザー回答: {user_decision}

#### info に格下げされた judgment（4 件目以降があれば）

- [{file}:{line}] {title} — {reason: 上限超過のため info 格下げ}

### 残存事項 (info)

今すぐの対応は不要だが、将来的に検討すべき事項:

- [{file}:{line}] {title} — {description}

### レビュアー使用状況

| レビュアー | 使用回数 | fallback 発生 | 失敗内容 |
|-----------|:-------:|:---:|---|
| Claude-p (`--bare`) | {count} | {Yes/No} | {timeout / schema-violation / -} |
| Codex (`--output-schema`) | {count} | {Yes/No} | {rate-limit / schema-violation / -} |
| claude ultrareview | {count} | {Yes/No} | {exit1 / -} |
| Gemini ({model}) | {count} | {Yes/No} | {429 / -} |
| Simplify ({internal/codex}) | {count} | - | - |
