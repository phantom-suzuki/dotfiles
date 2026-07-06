Gmail を `gws` CLI で操作してください。`command gws` でバイナリを呼び出すこと（エイリアス回避）。

## ヘルパーコマンド

```bash
# メール送信
command gws gmail +send --to <EMAIL> --subject <SUBJECT> --body <TEXT>

# 未読メール一覧（トリアージ）
command gws gmail +triage
command gws gmail +triage --max 5 --query 'from:boss'
command gws gmail +triage --labels --format table
```

## API リソース

```bash
command gws gmail users getProfile --params '{"userId": "me"}'
command gws gmail users messages list --params '{"userId": "me", "q": "is:unread"}'
command gws gmail users messages get --params '{"userId": "me", "id": "MSG_ID"}'
command gws gmail users messages send --params '{"userId": "me"}' --json '{"raw": "BASE64_ENCODED"}'
command gws gmail users messages modify --params '{"userId": "me", "id": "MSG_ID"}' --json '{"addLabelIds": ["LABEL_ID"]}'
command gws gmail users labels list --params '{"userId": "me"}'
command gws gmail users drafts list --params '{"userId": "me"}'
command gws gmail users threads list --params '{"userId": "me"}'
```

## スキーマ確認

```bash
command gws schema gmail.users.messages.list
command gws gmail --help
```

## セキュリティ

- メール送信 (`+send`, `messages.send`) は**実行前に必ずユーザーに確認**
- `modify`, `delete` も確認必須

## ユーザーのリクエスト

$ARGUMENTS
