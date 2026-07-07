Google Workspace CLI (`gws`) を使って、ユーザーのリクエストを実行してください。

## 重要: バイナリパス

`gws` は zsh で git エイリアスと競合する可能性があります。
Bash ツールでは以下のようにフルパスで実行してください:

```bash
command gws <args>
```

## 認証

```bash
command gws auth status    # 認証状態確認
command gws auth login     # OAuth ログイン（初回 or 期限切れ時）
command gws auth login -s drive,gmail,calendar,sheets,docs,tasks,chat  # スコープ指定
```

## CLI 構文

```bash
command gws <service> <resource> [sub-resource] <method> [flags]
```

### グローバルフラグ

| Flag | Description |
|------|-------------|
| `--params '{"key":"val"}'` | URL/クエリパラメータ |
| `--json '{"key":"val"}'` | リクエストボディ |
| `--format <json\|table\|yaml\|csv>` | 出力形式 (デフォルト: json) |
| `--dry-run` | API呼び出しなしで検証 |
| `--upload <PATH>` | ファイルアップロード |
| `-o, --output <PATH>` | バイナリレスポンス保存先 |
| `--page-all` | 自動ページネーション (NDJSON) |
| `--page-limit <N>` | 最大ページ数 (デフォルト: 10) |

## 対応サービスと主要ヘルパーコマンド

### Gmail
```bash
command gws gmail +send --to <EMAIL> --subject <SUBJECT> --body <TEXT>
command gws gmail +triage                          # 未読メール一覧
command gws gmail +triage --max 5 --query 'from:boss'
command gws gmail users messages list --params '{"userId": "me", "q": "is:unread"}'
```

### Calendar
```bash
command gws calendar +agenda                       # 今後の予定一覧
command gws calendar +agenda --today               # 今日の予定
command gws calendar +agenda --week --format table  # 今週の予定
command gws calendar +insert --summary 'Meeting' --start '2026-01-01T10:00:00+09:00' --end '2026-01-01T11:00:00+09:00'
```

### Drive
```bash
command gws drive files list --params '{"pageSize": 10}'
command gws drive +upload ./file.pdf
command gws drive +upload ./file.pdf --parent FOLDER_ID
command gws drive files get --params '{"fileId": "ID"}'
```

### Sheets
```bash
command gws sheets +read --spreadsheet <ID> --range 'Sheet1!A1:D10'
command gws sheets +append --spreadsheet <ID> --values 'Alice,100,true'
command gws sheets +append --spreadsheet <ID> --json-values '[["a","b"],["c","d"]]'
```

### Docs
```bash
command gws docs documents get --params '{"documentId": "ID"}'
command gws docs documents create --json '{"title": "New Doc"}'
command gws docs +write --document <ID> --text 'Hello, world!'
```

### Tasks
```bash
command gws tasks tasklists list
command gws tasks tasks list --params '{"tasklist": "TASKLIST_ID"}'
command gws tasks tasks insert --params '{"tasklist": "TASKLIST_ID"}' --json '{"title": "New task"}'
```

### Chat
```bash
command gws chat spaces list
command gws chat +send --space spaces/AAAA --text 'Hello!'
```

### Workflow (クロスサービス)
```bash
command gws workflow +standup-report    # 今日のミーティング + 未完了タスク
command gws workflow +meeting-prep      # 次のミーティングの準備情報
command gws workflow +weekly-digest     # 週間サマリー
command gws workflow +email-to-task     # メールをタスクに変換
```

## コマンド探索

```bash
command gws <service> --help                        # リソース一覧
command gws schema <service>.<resource>.<method>    # メソッドの詳細スキーマ
```

## セキュリティルール

- **書き込み/削除コマンドは実行前に必ずユーザーに確認**
- トークンやAPIキーを出力に含めない
- 破壊的操作には `--dry-run` を先に実行して確認

## ユーザーのリクエスト

$ARGUMENTS
