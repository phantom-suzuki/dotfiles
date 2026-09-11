---
name: db
description: MySQL の接続・クエリ実行・テーブル確認に使い、プロジェクトの接続プロファイルで実行して結果を表にまとめる。プロファイル設定（`.claude/db-profiles.json`）が無いプロジェクトや、MySQL 以外の DB には使わない。
---

# DB Query Skill

Execute MySQL queries interactively with structured markdown output.

## Input

ユーザーの依頼からプロファイル名と SQL を読み取ります。プロファイル名の省略時は `"default": true` を使い、SQL の省略時は対話モードに入ります。

## Procedure

### 1. Load connection profile

接続情報はプロジェクトの `.claude/db-profiles.json` をプロセス内で解析して取得します。このパスは既存の共有プロファイルの保存先です。ファイル全体や機密値をツール出力・ログに表示しません。

- ファイルがない場合は処理を止め、下記の Profile format を案内
- 指定プロファイルがない場合、または省略時に既定プロファイルがない場合はユーザーに選択を依頼

### 2. Resolve password

- `password` が `"FROM_SECRETS_MANAGER"` の場合、依頼や設定から secret name/ARN を特定。不明ならユーザーに確認
- `aws secretsmanager get-secret-value` の応答はプロセス内で受け取り、JSON の password を抽出。標準出力へ表示しない
- それ以外はプロファイルの password を使用

パスワードはプロセス内で `MYSQL_PWD` 環境変数に設定して mysql 子プロセスへ渡します。`-p`、コマンド文字列、出力、ログには値を含めません。以下のコマンド例は、その環境変数を設定済みの子プロセスで実行します。

### 3. Test connection

日本語を扱うため、mysql には常に `--default-character-set=utf8mb4` を指定します。

```bash
mysql -h <host> -P <port> -u <user> --default-character-set=utf8mb4 <database> -e "SELECT 1" 2>&1
```

- If connection fails, show the error and suggest troubleshooting:
  - Local: Is Docker running? `docker ps | grep mysql`
  - Remote: Is SSM tunnel active? Check the port with `lsof -i :<port>`

### 4. Execute query

#### Safety checks BEFORE execution

1. **Write operation detection** — Check if the query matches any write pattern (case-insensitive):
   `INSERT`, `UPDATE`, `DELETE`, `DROP`, `ALTER`, `CREATE`, `TRUNCATE`, `REPLACE`, `RENAME`, `GRANT`, `REVOKE`

   - If `readonly: true` on the profile → **REFUSE execution**:
     > This profile is read-only (`<profile_name>`, environment: `<env>`). Write operations are not allowed.
   - If `readonly: false` → **WARN** and ask for explicit confirmation:
     > ⚠️ This is a write operation on `<profile_name>` (`<env>`). Proceed? (yes/no)

2. **LIMIT check** — For `SELECT` queries without `LIMIT` (and not subqueries):
   - Automatically append `LIMIT 100`
   - Inform the user: `Auto-applied LIMIT 100. Specify an explicit LIMIT to override.`

#### Execute

```bash
mysql -h <host> -P <port> -u <user> --default-character-set=utf8mb4 <database> --column-names -B -e "<query>" 2>&1
```

- Use `--column-names -B` to obtain column names and tab-separated rows in one execution
- Measure execution time

### 5. Format output

#### Query results (SELECT, SHOW, DESCRIBE, EXPLAIN)

Use the column names and rows from step 4; do not rerun the query to format results.

Format as markdown table:

```markdown
**Profile**: <name> | **Database**: <database> | **Rows**: <count>

| col1 | col2 | col3 |
|------|------|------|
| val1 | val2 | val3 |

_<execution_time>s_
```

- Truncate cell values longer than 60 characters with `...`
- NULL values display as `NULL`

#### SHOW TABLES — Enhanced output

When the query is `SHOW TABLES` (or similar), also fetch row counts:

```sql
SELECT TABLE_NAME, TABLE_ROWS FROM information_schema.TABLES WHERE TABLE_SCHEMA = '<database>' ORDER BY TABLE_NAME;
```

Format:

```markdown
**Database**: <database> | **Tables**: <count>

| # | Table Name | Rows (approx) |
|---|------------|---------------|
| 1 | users      | ~150          |
| 2 | orders     | ~1,200        |
```

#### Write operations (INSERT, UPDATE, DELETE)

```markdown
**Profile**: <name> | **Database**: <database>

✅ Query executed successfully.
Affected rows: <count>

_<execution_time>s_
```

### 6. Interactive mode

If the user did not provide a query:

- After showing the result, ask the user for the next query
- Continue until the user says "exit", "quit", or "done"
- Each iteration: apply safety checks → execute → format output

## Profile format

`.claude/db-profiles.json` in the project root:

```json
{
  "local": {
    "host": "127.0.0.1",
    "port": 3306,
    "user": "root",
    "password": "root",
    "database": "myapp",
    "description": "Local Docker MySQL",
    "environment": "local",
    "readonly": false,
    "default": true
  },
  "staging": {
    "host": "127.0.0.1",
    "port": 13306,
    "user": "admin",
    "password": "FROM_SECRETS_MANAGER",
    "database": "myapp",
    "description": "Aurora MySQL staging (SSM tunnel on port 13306)",
    "environment": "staging",
    "readonly": true
  }
}
```
