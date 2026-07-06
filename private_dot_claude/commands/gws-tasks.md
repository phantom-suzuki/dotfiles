Google Tasks を `gws` CLI で操作してください。`command gws` でバイナリを呼び出すこと（エイリアス回避）。

## API リソース

```bash
# タスクリスト
command gws tasks tasklists list
command gws tasks tasklists get --params '{"tasklist": "TASKLIST_ID"}'
command gws tasks tasklists insert --json '{"title": "New List"}'
command gws tasks tasklists delete --params '{"tasklist": "TASKLIST_ID"}'

# タスク
command gws tasks tasks list --params '{"tasklist": "TASKLIST_ID"}'
command gws tasks tasks get --params '{"tasklist": "TASKLIST_ID", "task": "TASK_ID"}'
command gws tasks tasks insert --params '{"tasklist": "TASKLIST_ID"}' --json '{"title": "Buy milk", "due": "2026-01-15T00:00:00Z"}'
command gws tasks tasks patch --params '{"tasklist": "TASKLIST_ID", "task": "TASK_ID"}' --json '{"status": "completed"}'
command gws tasks tasks delete --params '{"tasklist": "TASKLIST_ID", "task": "TASK_ID"}'
command gws tasks tasks move --params '{"tasklist": "TASKLIST_ID", "task": "TASK_ID", "parent": "PARENT_TASK_ID"}'
```

## セキュリティ

- タスクの作成・変更・削除は**実行前に必ずユーザーに確認**

## ユーザーのリクエスト

$ARGUMENTS
