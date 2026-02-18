---
name: handover
description: セッションの作業内容を引き継ぎ用にまとめる
disable-model-invocation: true
---

# Session Handover Skill

現在のセッションで行った作業内容を引き継ぎ用にまとめ、プロジェクトルートの `HANDOVER.md` に保存する。

## Procedure

1. 今回のセッションで行った作業を振り返る
2. 以下のテンプレートに従って `HANDOVER.md` を作成（既存ファイルがある場合は上書き）
3. 保存完了を報告する
4. 次のアクションを案内する:
   - セッションを終了して再開する場合: `/exit` (または `Ctrl+D`) → `claude "/resume"` で新セッション開始
   - 同じターミナルで続ける場合: `/clear` → `/resume` でコンテキストをリセットして再開

## Template

```markdown
# Session Handover

> Created: {現在の日時 YYYY-MM-DD HH:MM}

## Summary
<!-- セッション全体の要約を1-3行で -->

## What Was Done
<!-- 完了したタスクをリストで -->
-

## Current State
<!-- 作業の現在の状態。ビルド/テストの成否、動作状況など -->

## In Progress / Incomplete
<!-- 未完了のタスク、途中の作業があればリストで。なければ「なし」 -->

## Key Decisions
<!-- 重要な設計判断、方針決定をリストで -->

## Files Modified
<!-- 変更・作成・削除したファイルのパスをリストで -->

## Issues / Concerns
<!-- 未解決の問題、注意事項、懸念点。なければ「なし」 -->

## Next Steps
<!-- 次のセッションで最初にやるべきことをリストで -->
```

## Rules

- 実際の作業内容に基づいて正確に記述すること
- 推測や曖昧な情報は含めない
- 次のセッションの自分（Claude）が読んですぐ作業を再開できるレベルの具体性で書く
- ファイルパスは省略せず正確に記述する
- `git diff` や `git status` を確認して変更ファイルを正確に把握する
