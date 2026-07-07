Google Drive を `gws` CLI で操作してください。`command gws` でバイナリを呼び出すこと（エイリアス回避）。

## ヘルパーコマンド

```bash
# ファイルアップロード
command gws drive +upload ./file.pdf
command gws drive +upload ./file.pdf --parent FOLDER_ID
command gws drive +upload ./data.csv --name 'Sales Data.csv'
```

## API リソース

```bash
# ファイル操作
command gws drive files list --params '{"pageSize": 10}'
command gws drive files list --params '{"q": "mimeType=\"application/vnd.google-apps.folder\"", "pageSize": 20}'
command gws drive files get --params '{"fileId": "FILE_ID"}'
command gws drive files create --json '{"name": "New Folder", "mimeType": "application/vnd.google-apps.folder"}'
command gws drive files copy --params '{"fileId": "FILE_ID"}' --json '{"name": "Copy of file"}'
command gws drive files update --params '{"fileId": "FILE_ID"}' --json '{"name": "Renamed"}'
command gws drive files delete --params '{"fileId": "FILE_ID"}'
command gws drive files export --params '{"fileId": "FILE_ID", "mimeType": "application/pdf"}' -o output.pdf

# 権限
command gws drive permissions list --params '{"fileId": "FILE_ID"}'
command gws drive permissions create --params '{"fileId": "FILE_ID"}' --json '{"role": "reader", "type": "user", "emailAddress": "user@example.com"}'

# 共有ドライブ
command gws drive drives list
command gws drive drives get --params '{"driveId": "DRIVE_ID"}'

# ダウンロード
command gws drive files get --params '{"fileId": "FILE_ID", "alt": "media"}' -o downloaded_file
```

## セキュリティ

- ファイルの作成・アップロード・削除・権限変更は**実行前に必ずユーザーに確認**

## ユーザーのリクエスト

$ARGUMENTS
