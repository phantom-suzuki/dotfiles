Google Docs を `gws` CLI で操作してください。`command gws` でバイナリを呼び出すこと（エイリアス回避）。

## ヘルパーコマンド

```bash
# テキスト追記
command gws docs +write --document <ID> --text 'Hello, world!'
```

## API リソース

```bash
# ドキュメント取得
command gws docs documents get --params '{"documentId": "DOC_ID"}'

# ドキュメント作成
command gws docs documents create --json '{"title": "New Document"}'

# バッチ更新（リッチフォーマット）
command gws docs documents batchUpdate --params '{"documentId": "DOC_ID"}' --json '{"requests": [{"insertText": {"location": {"index": 1}, "text": "Hello"}}]}'
```

## セキュリティ

- 書き込み操作 (`+write`, `batchUpdate`, `create`) は**実行前に必ずユーザーに確認**

## ユーザーのリクエスト

$ARGUMENTS
