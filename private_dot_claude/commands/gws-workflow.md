Google Workspace のクロスサービスワークフローを `gws` CLI で実行してください。`command gws` でバイナリを呼び出すこと（エイリアス回避）。

## ワークフローコマンド

```bash
# スタンドアップレポート: 今日のミーティング + 未完了タスクのサマリー
command gws workflow +standup-report

# ミーティング準備: 次のミーティングのアジェンダ、参加者、関連ドキュメント
command gws workflow +meeting-prep

# 週間ダイジェスト: 今週のミーティング + 未読メール数
command gws workflow +weekly-digest

# メール→タスク変換: Gmail メッセージを Google Tasks に変換
command gws workflow +email-to-task

# ファイルアナウンス: Drive ファイルを Chat スペースで共有
command gws workflow +file-announce
```

## 組み合わせ例

```bash
# 朝のルーティン
command gws workflow +standup-report
command gws gmail +triage --max 10 --format table

# ミーティング前
command gws workflow +meeting-prep
command gws calendar +agenda --today --format table

# 週初め
command gws workflow +weekly-digest
command gws calendar +agenda --week --format table
```

## ユーザーのリクエスト

$ARGUMENTS
