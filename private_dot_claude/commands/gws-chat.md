Google Chat を `gws` CLI で操作してください。`command gws` でバイナリを呼び出すこと（エイリアス回避）。

## ヘルパーコマンド

```bash
# メッセージ送信
command gws chat +send --space spaces/AAAA --text 'Hello!'
```

## API リソース

```bash
# スペース
command gws chat spaces list
command gws chat spaces get --params '{"name": "spaces/SPACE_ID"}'
command gws chat spaces create --json '{"displayName": "Team Chat", "spaceType": "SPACE"}'

# メッセージ
command gws chat spaces messages list --params '{"parent": "spaces/SPACE_ID"}'
command gws chat spaces messages get --params '{"name": "spaces/SPACE_ID/messages/MSG_ID"}'
command gws chat spaces messages create --params '{"parent": "spaces/SPACE_ID"}' --json '{"text": "Hello!"}'

# メンバー
command gws chat spaces members list --params '{"parent": "spaces/SPACE_ID"}'
```

## セキュリティ

- メッセージ送信は**実行前に必ずユーザーに確認**

## ユーザーのリクエスト

$ARGUMENTS
