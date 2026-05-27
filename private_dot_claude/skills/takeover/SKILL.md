---
name: takeover
description: HANDOVER.md を読んで前回セッションの作業を再開する。セッション開始時に使用。
disable-model-invocation: true
---

# Session Resume Skill

前回セッションで作成された引き継ぎ情報を `~/.claude/projects/<project-key>/handover.md` から読み込み、作業を再開する。

## 引き継ぎファイルの場所

読込元は `~/.claude/projects/<project-key>/handover.md`。

`<project-key>` は、現在の作業ディレクトリの絶対パス中の `/` を `-` に置換した文字列（先頭の `-` を含む。Claude Code 内部のプロジェクトキー形式）。

```bash
# 例: /Users/alice/work/my-app -> -Users-alice-work-my-app
PROJECT_KEY=$(pwd | sed 's|/|-|g')
HANDOVER_PATH="$HOME/.claude/projects/${PROJECT_KEY}/handover.md"
```

## Procedure

1. 以下の4分岐で引き継ぎファイルを判定する
   - (a) 新パスのみ存在 → 新パスを読んで再開する。
   - (b) カレントディレクトリの `HANDOVER.md` のみ存在（新パスは無い）→ 内容を新パスへ移行保存し、カレントの `HANDOVER.md` は削除してから新パスを読んで再開する。
   - (c) 両方存在:
     - 内容が同一 → カレントの `HANDOVER.md` を削除（クリーンアップ）し、新パスで再開する。
     - 内容に差分あり → 両ファイルを読んで差分を抽出・整理し、どう統合するか/どちらを採用するかの方法をユーザーに提案する。ユーザー承認後に新パスへ確定保存し、カレントの `HANDOVER.md` を削除してから新パスを読んで再開する。
   - (d) どちらも存在しない → その旨をユーザーに伝えて終了する。
2. 内容を要約して現状を提示する:
   - 前回の作業概要 (Summary)
   - 現在の状態 (Current State)
   - 未完了の作業 (In Progress / Incomplete)
   - 未解決の問題 (Issues / Concerns)
3. "Next Steps" セクションに基づいて作業方針を提示し、ユーザーに確認してから作業を開始する
