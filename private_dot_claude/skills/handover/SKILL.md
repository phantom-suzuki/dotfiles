---
name: handover
description: セッションの作業内容を引き継ぎ用にまとめる。セッション終了時や作業の区切りで使用。
disable-model-invocation: true
---

# Session Handover Skill

現在のセッションで行った作業内容を引き継ぎ用にまとめ、`~/.claude/projects/<project-key>/handover.md` に保存する。

## 保存先

保存先は `~/.claude/projects/<project-key>/handover.md`。

`<project-key>` は、現在の作業ディレクトリの絶対パス中の `/` を `-` に置換した文字列（先頭の `-` を含む。Claude Code 内部のプロジェクトキー形式）。

```bash
# 例: /Users/alice/work/my-app -> -Users-alice-work-my-app
PROJECT_KEY=$(pwd | sed 's|/|-|g')
OUTPUT_PATH="$HOME/.claude/projects/${PROJECT_KEY}/handover.md"
```

この配置のメリット:
- リポジトリを汚さない（`.gitignore` 不要）
- git worktree ごとに自動的に分離される（パスが異なるため）
- Auto Memory と同じ場所に同居する

## Procedure

1. 今回のセッションで行った作業を振り返る
2. 以下のテンプレートに従って `~/.claude/projects/<project-key>/handover.md` を作成（既存ファイルがある場合は上書き）
3. 保存完了を報告する
4. 次のアクションを案内する:
   - セッションを終了して再開する場合: `/exit` (または `Ctrl+D`) → `claude "/takeover"` で新セッション開始
   - 同じターミナルで続ける場合: `/clear` → `/takeover` でコンテキストをリセットして再開

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
<!-- 次のセッションで最初にやるべきことをリストで。対応する GitHub Issue がある項目は Issue 番号（例: #123）を併記する -->
```

## Rules

- 実際の作業内容に基づいて正確に記述すること
- 推測や曖昧な情報は含めない
- 次のセッションの自分（Claude）が読んですぐ作業を再開できるレベルの具体性で書く
- ファイルパスは省略せず正確に記述する
- `git diff` や `git status` を確認して変更ファイルを正確に把握する
- Next Steps の各項目は、対応する GitHub Issue があれば Issue 番号を併記する。`/takeover` が次回セッションで Next Steps と Sprint Board の実体を突き合わせ、整合チェック・ネクストアクションのランク付けに使う
