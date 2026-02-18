---
name: review-pr
description: PR のレビューコメントに対応する。レビュー対応やレビューコメントへの返信を依頼されたときに使用。
disable-model-invocation: true
argument-hint: "[pr-number]"
---

# PR Review Response Skill

Respond to PR review comments, including CodeRabbit automated reviews and human reviewer feedback.

## Procedure

### 1. Fetch Review Threads (GraphQL API)

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
}' -f owner='{owner}' -f repo='{repo}' -F pr={pr_number}
```

- Derive owner/repo from `gh repo view --json owner,name`
- PR number from `$ARGUMENTS` or current branch's PR: `gh pr view --json number`

### 2. Classify Comments

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

### 3. Fix Code

For each actionable comment:
1. Read the referenced file and line
2. Understand the feedback
3. Apply the fix
4. Verify official documentation for SDK/API-related suggestions before applying

### 4. Commit & Push

Follow the `/commit` and `/push` skill workflows:
- Stage specific files only
- Use `fix: address review feedback` or similar Conventional Commits message
- Include Co-Authored-By trailer
- Push to the current branch

### 5. Reply to Review Threads (GraphQL API)

**For fixed items** — reply with the fix description and commit hash:

```bash
gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: $threadId
    body: $body
  }) {
    comment { id }
  }
}' -f threadId='<thread-id>' -f body='Fixed in <commit-hash>.

<brief description of the fix>'
```

**For deferred items** — reply with the reason and optionally create an Issue:

```bash
gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: $threadId
    body: $body
  }) {
    comment { id }
  }
}' -f threadId='<thread-id>' -f body='Thank you for the suggestion.

This is out of scope for the current PR. Tracked in #<issue-number>.'
```

Create a tracking Issue when deferring non-trivial suggestions:
```bash
gh issue create --title "<title>" --label "enhancement" --body "<body>"
```

### 6. Output Summary

After processing all threads, display a summary table:

```
## Review Response Summary

### Addressed
- [file:line] <description> (commit: <hash>)

### Deferred
- [file:line] <description> — Reason: <reason> (Issue: #<number>)

### Skipped (already resolved)
- <count> threads
```

## Best Practices

- Always reply in the original review thread, not as a top-level PR comment
- Include commit hashes in replies so reviewers can verify fixes
- Verify SDK/API suggestions against official documentation before applying
- Keep scope awareness — defer out-of-scope suggestions to Issues
