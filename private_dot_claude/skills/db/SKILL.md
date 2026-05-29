---
name: db
description: MySQL データベースにクエリを実行する。DB操作、クエリ実行、テーブル確認を依頼されたときに使用。
---

# DB Query Skill

Execute MySQL queries interactively with structured markdown output.

## Arguments

- `$ARGUMENTS` — Optional: `[profile] ["query"]`
  - `/db` → default profile, interactive mode
  - `/db staging` → staging profile, interactive mode
  - `/db local "SELECT * FROM users LIMIT 10"` → execute query directly
  - `/db "SHOW TABLES"` → default profile, execute query directly

## Procedure

### 1. Load connection profile

Read the project-level profile config:

```bash
cat .claude/db-profiles.json
```

- If file not found, inform the user:
  > No `.claude/db-profiles.json` found in the current project. Create one with connection profiles. See `~/.claude/skills/db/SKILL.md` for the format.
- Parse `$ARGUMENTS`:
  - If first arg matches a profile name → use that profile
  - If first arg is a quoted string → treat as query, use `"default": true` profile
  - If no args → use default profile, enter interactive mode
- If no profile has `"default": true`, ask the user to choose

### 2. Resolve password

- If `password` is `"FROM_SECRETS_MANAGER"`:
  - Ask the user for the secret name/ARN, or attempt:
    ```bash
    aws secretsmanager get-secret-value --secret-id <inferred-secret-id> --query 'SecretString' --output text
    ```
  - Parse the JSON secret for the password field
- Otherwise, use the password value directly

### 3. Test connection

```bash
MYSQL_PWD='<password>' mysql -h <host> -P <port> -u <user> --default-character-set=utf8mb4 <database> -e "SELECT 1" 2>&1
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
MYSQL_PWD='<password>' mysql -h <host> -P <port> -u <user> --default-character-set=utf8mb4 <database> -N -B -e "<query>" 2>&1
```

- Use `-N -B` (no column names, tab-separated) for programmatic parsing
- For column names, run a separate query or use `--column-names`
- Measure execution time

### 5. Format output

#### Query results (SELECT, SHOW, DESCRIBE, EXPLAIN)

First, get column names:
```bash
MYSQL_PWD='<password>' mysql -h <host> -P <port> -u <user> --default-character-set=utf8mb4 <database> --column-names -B -e "<query>" 2>&1
```

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

If no query was provided in `$ARGUMENTS`:

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

## Rules

- **NEVER** pass passwords via `-p` flag — always use `MYSQL_PWD` environment variable (prevents exposure in `ps` output)
- **ALWAYS** use `--default-character-set=utf8mb4` for Japanese text support
- `readonly: true` profiles must NEVER execute write operations — no exceptions
- Auto-apply `LIMIT 100` to unbounded SELECT queries
- Truncate cell values at 60 characters
- Show execution time for every query
