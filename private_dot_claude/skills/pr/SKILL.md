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
   - Follow Conventional Commits style: `<type>: <summary>`
   - Max 70 characters
   - Derive type from branch prefix (feature/ → feat, hotfix/ → fix, etc.)

5. **Generate PR body**:
   ```markdown
   ## Summary
   <1-3 bullet points summarizing the changes>

   ## Test Plan
   - [ ] <testing checklist items>

   ## Related Issues
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
