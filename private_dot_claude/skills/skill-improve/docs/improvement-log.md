# Skill Improve — 改善ログ

self-improving loop で反映/却下した改善の記録。生の会話は貼らず抽象化した要約のみ（このファイルは public リポへ push されうる）。

## 2026-06-04 session 481ab187

- signal: skill-improve 自身の signal 抽出が、スキル注入本文・ドキュメント言及・話題への言及まで拾い、parse 失敗を過大カウント（実エラー 0 件を 12 件と誤検出）
  - 原因: Step 2 にノイズ除外がない
  - 対応: **accept** — Step 2 のユーザー発言抽出からスキル注入/meta を除外、parse 失敗を「カウント=signal」から実エラー裏取りに格下げ
- signal: codex の存在確認を Bash に書きフックにブロックされた
  - 原因: tool-call-hygiene に codex の Bash 参照禁止が未記載
  - 対応: **accept** — tool-call-hygiene に項目「codex を Bash コマンド文字列に書かない」を追加
- signal: 新規ファイルの個別 chezmoi apply が親ディレクトリ未作成で stat 失敗
  - 原因: CLAUDE.md の chezmoi 手順に注意なし
  - 対応: **accept** — CLAUDE.md「新しいファイルの追加」に落とし穴の注記を追加
- signal: 完了報告が冗長と指摘された
  - 原因: 完了報告の簡潔さ指針が弱い
  - 対応: **accept** — feedback memory「完了報告は簡潔に」を作成
