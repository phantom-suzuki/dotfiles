---
name: resume
description: HANDOVER.md を読んで前回セッションの作業を再開する
disable-model-invocation: true
---

# Session Resume Skill

前回セッションで作成された `HANDOVER.md` を読み込み、作業を再開する。

## Procedure

1. カレントディレクトリの `HANDOVER.md` を Read で読み込む
   - ファイルが存在しない場合は、その旨を伝えて終了する
2. 内容を要約して現状を提示する:
   - 前回の作業概要 (Summary)
   - 現在の状態 (Current State)
   - 未完了の作業 (In Progress / Incomplete)
   - 未解決の問題 (Issues / Concerns)
3. "Next Steps" セクションに基づいて作業方針を提示し、ユーザーに確認してから作業を開始する
