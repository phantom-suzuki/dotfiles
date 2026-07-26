---
name: review-pr
description: 自分の PR についたレビューコメント（CodeRabbit / 人間レビュアー）と CI 失敗に対応する。コード修正 → コミット → review thread への返信と resolve までを行う。「レビュー対応」「レビューコメントに返信」「CodeRabbit の指摘を直して」「PR のコメントに対応」「review-pr」等の依頼時に使用。他者の PR をレビューする側の依頼では使わない（レビュアー側は pr-reviewer / peer-review スキルが担う）。
argument-hint: "[pr-number]"
---

# PR Review Response Skill

Respond to PR review comments, including CodeRabbit automated reviews and human reviewer feedback.

## 実行モードと承認ゲート

このスキルは AI（Claude Code のモデル）が自分で起動して実行できる。ユーザーが `/review-pr` と打って起動した場合も、同じ承認ゲートを通す。

**確認なしで進めてよい操作**:

- 読み取り（`gh pr checks` / `gh run view` / GraphQL でのスレッド取得）
- ローカルのコード修正
- 返信本文のドラフト作成

**ユーザー承認が必要な操作**（取り消しにくい、または外向き）:

- コミットと push（Step 6 のコミットと push）
- review thread への返信投稿と resolve（Step 7 の返信）
- 見送り項目の Issue 作成（Step 7 の返信）
- 失敗ジョブの再実行 `gh run rerun`（Step 2 の分類 ④）

**承認の取り方**: Step 5（コードを修正する）が終わった時点で、次の 2 つを 1 回だけ提示して承認を得る。承認が出たら Step 6（コミットと push）と Step 7（返信）はまとめて実行してよい。

1. スレッドごとの対応表（対応する / 見送る / 返信の要旨）
2. push 予定の差分要約（`git diff --stat` の出力）

指摘が 5 件を超えるとき、または方針判断が割れる指摘があるときは、その指摘だけ個別に確認する。

## Procedure

### 0. 対象 PR を特定する

引数 `$ARGUMENTS` に PR 番号があればそれを使う。無ければ現在のブランチの PR を取る。

```bash
gh pr view --json number,title,headRefName,baseRefName,state \
  --jq '{number,title,headRefName,baseRefName,state}'
```

- `state` が `MERGED` / `CLOSED` のときは、作業に入る前にユーザーへ確認する
- **シェル変数は Bash 呼び出し間で持続しない**。以降のコマンドは PR 番号とスレッド ID を**リテラルで埋めて**実行する。`PR=$(...)` を別の呼び出しで再利用してはならない

### 1. Check CI Status

```bash
gh pr checks <pr_number> --json name,state,bucket,link
```

- Do not use `--watch` — it blocks the session for a long time
- 待機が必要なときは `Monitor` ツールで `gh pr checks <pr_number>` の until ループを回す。フォアグラウンドの `sleep` は使えない
- ポーリングは**最大 5 回・間隔 60 秒**を上限とする。上限を超えたら「保留中」として Step 9（サマリ出力）に記録し、ユーザーに判断を仰ぐ
- If any check has failed, find the workflow run and fetch failure logs:
  ```bash
  gh run list --branch <branch> --limit 5
  gh run view <run-id> --log-failed --job <job-id>
  ```
  - `--log-failed` の出力は長い。失敗したジョブに絞り、必要なら末尾だけを抜粋する。巨大なレスポンスを受けた直後は tool call が不安定になる
- If all checks pass, skip to step 3（review thread を取得する）

### 2. Classify & Handle CI Failures

Classify each failure using the failed logs from step 1（CI の状態を確認する）:

| Category | Examples | Handling |
|----------|----------------------------------|-----------------------------------------------|
| ① Lint / format | ESLint, markdownlint, Prettier | Mechanically fixable — identify the fix and apply it |
| ② Test failure | Unit / integration test failure | Needs root-cause analysis — do not auto-fix |
| ③ Build / type error | Compile error, type check failure | Identify the fix and apply it |
| ④ Infra / flaky | Runner failure, network timeout | Rerun after user approval |

- **① and ③**: identify and apply the fix. Who executes the fix (yourself vs. delegate) follows `~/.claude/skills/task-delegation/SKILL.md` — this skill does not duplicate that decision table
- **②**: report the root cause and a proposed fix in the final summary; do not auto-fix
- **④**: `gh run rerun <run-id> --failed` を提案する。実行はユーザー承認後。**再実行は 1 回まで**とし、2 回目以降は原因調査へ切り替える
- 分類の根拠にした失敗ログの該当行を 1 行だけ引用し、Step 9（サマリ出力）に載せる
- Fixes from ① and ③ are committed and pushed together with review-comment fixes in step 6（コミットと push）

### 3. Fetch Review Threads (GraphQL API)

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      title
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 20) {
            nodes {
              body
              author { login }
              path
              line
              createdAt
            }
          }
        }
      }
    }
  }
}' -F owner={owner} -F repo={repo} -F pr=<pr_number> \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | {id, path: .comments.nodes[0].path, line: .comments.nodes[0].line,
           author: .comments.nodes[0].author.login, body: .comments.nodes[0].body}'
```

- **`-f` ではなく `-F` を使う**。`-f`（raw-field）は `{owner}` / `{repo}` を展開せず、リテラル文字列を GraphQL に渡して失敗する。`-F`（field）は現在のリポジトリから値を解決する
- `--jq` で未解決スレッドだけに絞る。100 スレッド分の生 JSON をそのまま受け取らない

**review thread に含まれないコメントもある**。次の 2 つを別途取得しないと指摘を取りこぼす。CodeRabbit の要約コメントはトップレベル側に出る。

```bash
# top-level comments on the PR itself
gh pr view <pr_number> --json comments --jq '.comments[] | {author: .author.login, body}'

# review states (CHANGES_REQUESTED etc.)
gh api repos/{owner}/{repo}/pulls/<pr_number>/reviews --jq '.[] | {user: .user.login, state, body}'
```

### 4. Classify Comments

**Skip** resolved threads (`isResolved: true`).

For unresolved threads, classify by source and severity:

| Priority | Source | Action |
|----------|--------------------------------------|-----------------|
| Required | Human reviewer comments | Fix code |
| Required | CodeRabbit Critical / Major | Fix code |
| Recommended | CodeRabbit Minor | Fix if in scope |
| Optional | CodeRabbit Suggestion / Refactor | Evaluate against design goals |

**CodeRabbit severity detection**: Check for emoji indicators in comment body:

- `🔴` or "Critical" → Critical
- `🟠` or "Major" → Major
- `🟡` or "Minor" → Minor
- `🛠️` or "Suggestion" → Suggestion

### 5. Fix Code

For each actionable comment:

1. Read the referenced file and line
2. Understand the feedback
3. Apply the fix
4. Verify official documentation for SDK/API-related suggestions before applying

修正が終わったら、「実行モードと承認ゲート」の手順でユーザー承認を取る。

### 6. Commit & Push

`/commit` と `/push` スキルは `disable-model-invocation` が付いており、AI からは起動できない。よって必要な手順をここに内製する。

```bash
git status --short
git diff
```

- **対象ファイルだけを stage する**。`git add -A` は使わない
- コミットメッセージは Conventional Commits に従う（例: `fix: address review feedback on <topic>`）。件名は英語 72 文字以内
- `Co-Authored-By` トレイラーを必ず付ける
- **コマンド文字列に日本語を書かない**。長い本文が必要なら `-m` を短く複数回に分けるか、本文をファイルに書いて `git commit -F <file>` を使う
- 保護ブランチ（`main` / `master` / `develop` / `release/*`）に居る場合は push せず、ユーザーへ確認する
- push は `git push origin <branch>`。force が必要なときだけ `--force-with-lease` を使う（`--force` は使わない）
- push は承認ゲートの対象。承認を得てから実行する
- Step 2（CI 失敗の分類）の修正と review 対応の修正は、同じファイルに触るなら 1 コミットにまとめ、別論点なら分割する
- After pushing, CI reruns automatically — no need to manually re-check unless the summary requires confirmed-green status

### 7. Reply to Review Threads (GraphQL API)

#### Reply language rules

- **CodeRabbit (bot) へは英語で返信** — CodeRabbit の解析精度が高くなるため
- **Human reviewer へは日本語で返信** — チームは全員日本語ネイティブ
- **全ての返信に日本語の要約を付記** — CodeRabbit への英語返信にも `---` 区切りで日本語要約を追記し、チームメンバーが読み直す際のコストを下げる

#### 返信本文はファイルに書き出す

**返信本文をコマンド文字列に書いてはならない**。まず Write ツールでセッションのスクラッチパッドにファイルとして書き出す（例: `<scratchpad>/reply-<n>.md`）。`/tmp` 直下は使わない。日本語を含む長文をコマンド引数に埋めると、tool call の引数が壊れる。

#### GraphQL mutations

**Reply to a thread:**

```bash
gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: $threadId
    body: $body
  }) {
    comment { id }
  }
}' -f threadId='<thread-id>' -F body=@<scratchpad>/reply-<n>.md \
  --jq '.data.addPullRequestReviewThreadReply.comment.id'
```

- `-F body=@<file>` はファイルの中身を値として読み込む。`-f` にこの機能はない
- `threadId` は ASCII のみなので `-f` のままでよい

**Resolve a thread:**

```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {
    threadId: $threadId
  }) {
    thread { isResolved }
  }
}' -f threadId='<thread-id>'
```

- 返信の投稿が成功したことを確認してから resolve する

#### Reply body by scenario

**Fixed items** (reply → resolve):

```
Fixed in <commit-hash>.

<brief description of the fix in English>

---
📝 <日本語の修正内容の要約>
```

**Deferred items** (create Issue → reply → resolve):

```bash
gh issue create --title "<short one-line title>" --label "enhancement" \
  --body-file <scratchpad>/issue-<n>.md
```

- Issue 本文もファイル経由で渡す。日本語をコマンド引数に置くのは `--title` の短い 1 行までに留める

```
Out of scope for the current PR. Tracked in #<issue-number>.

---
📝 本PRのスコープ外のため、#<issue-number> で追跡します。
```

**Human reviewer comments** (reply in Japanese → resolve):

```
<commit-hash> で修正しました。

<日本語の修正内容の説明>

---
📝 <日本語の修正内容の要約>
```

### 8. 未解決スレッドが残っていないか検証する

投稿と resolve が終わったら、step 3（review thread を取得する）と同じクエリを再実行し、未解決スレッドが 0 件であることを確認する。

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) { nodes { id isResolved } }
    }
  }
}' -F owner={owner} -F repo={repo} -F pr=<pr_number> \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[]
         | select(.isResolved == false) | .id]'
```

- 0 件でなければ、残ったスレッド ID を列挙して Step 9（サマリ出力）に載せる。黙って完了報告をしてはならない

### 9. Output Summary

After processing all threads, display a summary table:

```
## Review Response Summary

### CI Checks
- ✅ lint: passed
- ❌ test: failed (flaky — rerun proposed via `gh run rerun`)
- ❌ build: failed (type error) — fixed in <commit-hash>

### Addressed
- [file:line] <description> (commit: <hash>)

### Deferred
- [file:line] <description> — Reason: <reason> (Issue: #<number>)

### Skipped (already resolved)
- <count> threads

### Unresolved (残)
- <thread-id> — <理由 / 次の一手>
```

- The CI Checks section lists every check name, its result, its category from step 2（CI 失敗の分類）, and the action taken (fixed / reported / rerun proposed)
- `Unresolved (残)` は Step 8（未解決スレッドの検証）の結果を書く。0 件なら「なし」と明記する

## Best Practices

- **All threads must be resolved** — every review thread must end in a resolved state after processing
- Always reply in the original review thread, not as a top-level PR comment
- Include commit hashes in replies so reviewers can verify fixes
- Verify SDK/API suggestions against official documentation before applying
- **Out-of-scope items must have a tracking Issue** — always create an Issue before deferring, then resolve the thread with the Issue link
- **CI failures must not be silently ignored** — even when CodeRabbit and human reviewers raise no comments, a failing check (e.g. lint errors CodeRabbit did not flag) must be caught in step 1（CI の状態を確認する）and either fixed or reported in the summary

## AI 実行時の落とし穴

- **コマンド文字列に日本語を埋めない**。本文は必ずファイル経由で渡す（`-F body=@file` / `--body-file` / `git commit -F`）
- **`-f` は `{owner}` を展開しない**。テンプレート展開が必要な変数は `-F` を使う
- **シェル変数は Bash 呼び出し間で持続しない**。PR 番号とスレッド ID はリテラルで埋める
- **フォアグラウンドの `sleep` は使えない**。待機は `Monitor` ツールの until ループで、上限回数を決めて回す
- **`gh pr checks --watch` は使わない**。セッションが長時間ブロックされる
- **`/commit`・`/push`・`/pr` スキルは AI からは起動できない**。本スキル内の手順を使う
- **GraphQL の生 JSON をそのまま受け取らない**。`--jq` で絞る。巨大なレスポンスの直後は tool call が不安定になる
- **review thread だけを見ると取りこぼす**。トップレベルコメント（CodeRabbit の要約など）とレビュー状態も取得する

## 関連

- `~/.claude/rules/tool-call-hygiene.md` — コマンド引数の衛生（日本語の直書き禁止・巨大レスポンス回避）
- `~/.claude/rules/git-safety.md` — 保護ブランチ・force push・PR マージの制約
- `~/.claude/rules/commit-conventions.md` — Conventional Commits と `Co-Authored-By`
- `~/.claude/skills/review-dispatch/SKILL.md` — どのレビュースキルを使うかの分岐
- `~/.claude/skills/pr-reviewer/SKILL.md` — 他者の PR をレビューする側のフロー
