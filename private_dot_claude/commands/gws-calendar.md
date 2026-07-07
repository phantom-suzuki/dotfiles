Google Calendar を `gws` CLI で操作してください。`command gws` でバイナリを呼び出すこと（エイリアス回避）。

## ヘルパーコマンド

```bash
# 予定一覧
command gws calendar +agenda                        # 今後の予定
command gws calendar +agenda --today                # 今日
command gws calendar +agenda --tomorrow             # 明日
command gws calendar +agenda --week --format table  # 今週
command gws calendar +agenda --days 3               # 3日間
command gws calendar +agenda --calendar 'Work'      # 特定カレンダー

# 予定作成
command gws calendar +insert --summary 'Meeting' --start '2026-01-01T10:00:00+09:00' --end '2026-01-01T11:00:00+09:00'
command gws calendar +insert --summary 'Review' --start ... --end ... --attendee alice@example.com --location 'Room A'
```

## API リソース

```bash
command gws calendar events list --params '{"calendarId": "primary", "timeMin": "2026-01-01T00:00:00Z", "maxResults": 10, "singleEvents": true, "orderBy": "startTime"}'
command gws calendar events get --params '{"calendarId": "primary", "eventId": "EVENT_ID"}'
command gws calendar events insert --params '{"calendarId": "primary"}' --json '{"summary": "...", "start": {"dateTime": "..."}, "end": {"dateTime": "..."}}'
command gws calendar events quickAdd --params '{"calendarId": "primary", "text": "Meeting tomorrow 3pm"}'
command gws calendar events delete --params '{"calendarId": "primary", "eventId": "EVENT_ID"}'
command gws calendar calendarList list
command gws calendar freebusy query --json '{"timeMin": "...", "timeMax": "...", "items": [{"id": "primary"}]}'
```

## セキュリティ

- 予定の作成・変更・削除は**実行前に必ずユーザーに確認**
- 時刻は RFC3339 形式 (例: `2026-01-01T10:00:00+09:00`)

## ユーザーのリクエスト

$ARGUMENTS
