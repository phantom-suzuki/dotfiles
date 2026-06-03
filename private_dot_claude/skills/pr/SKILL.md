---
name: pr
description: Pull Request を作成する。PR作成を依頼されたときに使用。
disable-model-invocation: true
argument-hint: "[options]"
---

# PR Creation Skill

Create a Pull Request with auto-detected base branch and generated description.

## Procedure

1. **Check current state**:
   ```bash
   git status
   git branch --show-current
   git log --oneline -10
   ```
   - If there are uncommitted changes, suggest committing first
   - If there are unpushed commits, push them before creating the PR

2. **Detect base branch**:
   - Check branching strategy: `git branch -a | grep -E '(^|\s|/)develop$'`
   - **GitFlow**:
     | Current Branch | Base Branch |
     |----------------|-------------|
     | feature/* | develop |
     | hotfix/* | main |
     | release/* | main |
   - **GitHub Flow**: Always use `main` (or `master` if main doesn't exist)

3. **Gather commit information**:
   ```bash
   git log <base>..HEAD --oneline
   git diff <base>...HEAD --stat
   ```

4. **Generate PR title**:
   - Japanese, max 70 characters
   - Derive context from branch prefix and commit history

5. **Generate PR body** (Japanese):
   ```markdown
   ## 概要
   <1-3 bullet points summarizing the changes>

   ## テスト計画
   - [ ] <testing checklist items>

   ## 関連 Issue
   closes #<issue-number> (if applicable)
   ```

6. **Create PR**:
   ```bash
   gh pr create --base <base-branch> --title "<title>" --body "$(cat <<'EOF'
   <body content>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

7. **Show result**: Display the created PR URL.

## Options

Arguments in `$ARGUMENTS` are passed as additional `gh pr create` flags:
- `--draft` — create as draft PR
- `--reviewer <user>` — request review
- `--label <label>` — add labels
- `--assignee @me` — self-assign

## PR Merge Policy

**PR のマージはユーザーの明示的な指示がある場合にのみ実行する。**

「PR を作成してマージまで」等の曖昧な表現では、PR 作成までを行い、マージ前にユーザーに確認すること。

**Do not proactively ask whether to merge right after creating the PR.** Creating a PR and merging it are separate steps. After PR creation, just report the PR URL and stop — wait for the user to explicitly request a merge. Only then run the Merge Prerequisite Gate below.

### Merge Prerequisite Gate

When the user explicitly asks to merge a PR, verify all four items below **before** running `gh pr merge`. Check each automatically via `gh` where possible. If any item is unmet, hold the merge and present the unmet items with reasons, then ask for the user's decision.

**1. CI passing**

```bash
gh pr checks <PR>
```

All checks must be `pass`. If any check is `fail` or `pending`, hold the merge.

**2. Self-review completed**

Confirm the self-review skill has been run on this branch (from session history, or ask the user to self-attest). If it has not been run, prompt the user to run self-review first.

**3. No unresolved change requests**

```bash
gh pr view <PR> --json reviews,comments
```

Check for `CHANGES_REQUESTED` from human reviewers or bots (especially `coderabbitai`), and for unresolved review comments. In repos where CodeRabbit is active (`coderabbitai` reviews exist), verify that all CodeRabbit findings have been addressed.

> Note: `--json reviews,comments` does not expose review-thread resolved/unresolved state, so this is an approximation. For a strict check of unresolved threads, use `gh api graphql` and inspect `reviewThreads.isResolved`.

**4. Branch-protection Approved requirement satisfied**

```bash
gh pr view <PR> --json reviewDecision
# supplement if more detail is needed (gh auto-substitutes {owner}/{repo} only;
# substitute the branch name yourself, e.g. via a shell variable):
gh api "repos/{owner}/{repo}/branches/$BRANCH/protection"
```

Use `reviewDecision` (`APPROVED` / `REVIEW_REQUIRED` / `CHANGES_REQUESTED`) as the primary signal. **Only if** branch protection requires Approved reviews must the required number of approvals be present. If branch protection does NOT require approvals, the absence of an Approved review is not a merge blocker.

---

Even after all four gate items pass, executing `gh pr merge` still requires the user's explicit instruction (per `git-safety.md`). Never silently skip the gate. If the user says "merge" while gate items are unmet, present the unmet items and ask for their decision before proceeding.
