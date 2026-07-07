Google Sheets を `gws` CLI で操作してください。`command gws` でバイナリを呼び出すこと（エイリアス回避）。

## ヘルパーコマンド

```bash
# スプレッドシート読み取り
command gws sheets +read --spreadsheet <ID> --range 'Sheet1!A1:D10'
command gws sheets +read --spreadsheet <ID> --range Sheet1

# 行追加
command gws sheets +append --spreadsheet <ID> --values 'Alice,100,true'
command gws sheets +append --spreadsheet <ID> --json-values '[["a","b"],["c","d"]]'
```

## API リソース

```bash
# スプレッドシート操作
command gws sheets spreadsheets get --params '{"spreadsheetId": "ID"}'
command gws sheets spreadsheets create --json '{"properties": {"title": "New Sheet"}}'

# 値の読み書き
command gws sheets spreadsheets values get --params '{"spreadsheetId": "ID", "range": "Sheet1!A1:D10"}'
command gws sheets spreadsheets values update --params '{"spreadsheetId": "ID", "range": "Sheet1!A1", "valueInputOption": "USER_ENTERED"}' --json '{"values": [["a","b"],["c","d"]]}'
command gws sheets spreadsheets values append --params '{"spreadsheetId": "ID", "range": "Sheet1", "valueInputOption": "USER_ENTERED"}' --json '{"values": [["new","row"]]}'

# バッチ操作
command gws sheets spreadsheets batchUpdate --params '{"spreadsheetId": "ID"}' --json '{"requests": [...]}'
```

## セキュリティ

- 書き込み操作 (`+append`, `values update`, `batchUpdate`) は**実行前に必ずユーザーに確認**

## ユーザーのリクエスト

$ARGUMENTS
